import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

/// Every call to Supabase lives here. Screens never talk to Supabase directly.
/// Each method is labelled with the Sequence Diagram 1 step it implements.
class CampusService {
  CampusService._();
  static final instance = CampusService._();

  SupabaseClient get _db => Supabase.instance.client;
  String? get userId => _db.auth.currentUser?.id;

  // ---------------- Authentication (Seq 1: steps 1-8) ----------------

  /// Steps 1-3: Register account -> send registration data -> user created.
  /// The database trigger handle_new_user() creates the STUDENTS + WALLET rows.
  Future<void> register({
    required String fullName,
    required String studentNumber,
    required String course,
    required String email,
    required String password,
  }) async {
    await _db.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {
        'role': 'student',
        'full_name': fullName.trim(),
        'student_number': studentNumber.trim(),
        'course': course,
      },
    );
  }

  /// Steps 5-7: Login(credentials) -> authenticate user -> success.
  /// Accepts "Student Number or Email" exactly like the Login screen.
  Future<void> login(String identifier, String password) async {
    final email = await _db.rpc('login_email', params: {'identifier': identifier}) as String?;
    if (email == null) {
      throw const AuthException('No student found with that student number');
    }
    await _db.auth.signInWithPassword(email: email, password: password);
    final role = await _db.rpc('current_app_role') as String?;
    if (role != 'student') {
      await _db.auth.signOut();
      throw const AuthException('This app is for students. Administrators use the web portal.');
    }
  }

  Future<void> sendPasswordReset(String email) =>
      _db.auth.resetPasswordForEmail(email.trim().toLowerCase());

  Future<void> changePassword(String newPassword) =>
      _db.auth.updateUser(UserAttributes(password: newPassword));

  Future<void> logout() => _db.auth.signOut();

  // ---------------- Home dashboard ----------------

  Future<HomeStats> homeStats() async {
    final rows = await _db.rpc('student_home_stats') as List<dynamic>;
    return HomeStats.fromMap(rows.first as Map<String, dynamic>);
  }

  Future<List<ActivityItem>> recentActivity({int limit = 3}) async {
    final rows = await _db
        .from('audit_log')
        .select('title, detail, created_at')
        .eq('student_id', userId!)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(ActivityItem.fromMap).toList();
  }

  // ---------------- Events (Seq 1: steps 9-12) ----------------

  /// Steps 9-12: View upcoming events -> retrieve events -> event data.
  Future<List<CampusEvent>> upcomingEvents({String? category, String? search}) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    var q = _db
        .from('events')
        .select('*, rsvp(status)')
        .eq('status', 'published')
        .gte('event_date', today);
    if (category != null && category != 'All') q = q.eq('category', category);
    if (search != null && search.trim().isNotEmpty) q = q.ilike('title', '%${search.trim()}%');
    final rows = await q.order('event_date', ascending: true);
    return rows.map(CampusEvent.fromMap).toList();
  }

  Future<CampusEvent> event(int id) async {
    final row = await _db.from('events').select('*, rsvp(status)').eq('event_id', id).single();
    return CampusEvent.fromMap(row);
  }

  // ---------------- RSVP (Seq 1: steps 13-16) ----------------

  /// Steps 13-15: RSVP to selected event -> send RSVP request(event ID) -> RSVP saved.
  /// rsvp_to_event() enforces <<include>> Validate RSVP (published, not past, no duplicates).
  Future<void> rsvp(int eventId) => _db.rpc('rsvp_to_event', params: {'p_event_id': eventId});

  Future<void> cancelRsvp(int eventId) => _db.rpc('cancel_rsvp', params: {'p_event_id': eventId});

  // ---------------- Wallet & coupons (Seq 1: steps 17-20) ----------------

  Future<int> walletBalance() async {
    final row = await _db.from('wallet').select('balance').eq('student_id', userId!).single();
    return row['balance'] as int;
  }

  Future<List<Coupon>> coupons({String? category}) async {
    // Only what staff marked Available (Meals / Coupons page) and not past its valid-until date
    final today = DateTime.now().toIso8601String().substring(0, 10);
    var q = _db.from('coupons').select().eq('is_active', true).gte('valid_until', today);
    if (category != null && category != 'All') q = q.eq('category', category);
    final rows = await q.order('points_cost', ascending: false);
    return rows.map(Coupon.fromMap).toList();
  }

  /// Redeem coupon <<include>> Validate coupon balance. Returns the redemption code.
  Future<({String code, int newBalance})> redeem(int couponId) async {
    final rows = await _db.rpc('redeem_coupon', params: {'p_coupon_id': couponId}) as List<dynamic>;
    final r = rows.first as Map<String, dynamic>;
    return (code: r['redemption_code'] as String, newBalance: r['new_balance'] as int);
  }

  /// FR-016: reward and redemption history
  Future<List<RewardTxn>> transactions() async {
    final rows = await _db
        .from('reward_transactions')
        .select('points, txn_type, description, created_at')
        .eq('student_id', userId!)
        .order('created_at', ascending: false);
    return rows.map(RewardTxn.fromMap).toList();
  }

  // ---------------- Profile ----------------

  Future<StudentProfile> profile() async {
    final row = await _db.from('students').select().eq('student_id', userId!).single();
    return StudentProfile.fromMap(row);
  }

  Future<void> updateProfile({required String name, String? course, String? phone}) =>
      _db.from('students').update({'name': name, 'course': course, 'phone': phone}).eq('student_id', userId!);

  // ---------------- Profile picture (Supabase Storage) ----------------
  // Photos live in the public "event-media" bucket under avatars/<user id>/.
  // RLS (08_profile_photo.sql) lets a student write only in their own folder.

  /// Uploads the photo, saves its link on the student row and returns the link.
  Future<String> uploadAvatar(Uint8List bytes, String fileName) async {
    final uid = userId!;
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'jpg';
    final safeExt = const ['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext) ? ext : 'jpg';
    // New name every time so phones/browsers don't show the old cached photo.
    final path = 'avatars/$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
    final bucket = _db.storage.from('event-media');
    await bucket.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: 'image/${safeExt == 'jpg' ? 'jpeg' : safeExt}', upsert: true),
    );
    final url = bucket.getPublicUrl(path);
    await _db.from('students').update({'avatar_url': url}).eq('student_id', uid);
    await _removeOldAvatars(keep: path.split('/').last);
    return url;
  }

  /// Removes the photo and goes back to the initials.
  Future<void> removeAvatar() async {
    await _db.from('students').update({'avatar_url': null}).eq('student_id', userId!);
    await _removeOldAvatars();
  }

  Future<void> _removeOldAvatars({String? keep}) async {
    try {
      final folder = 'avatars/${userId!}';
      final bucket = _db.storage.from('event-media');
      final files = await bucket.list(path: folder);
      final old = files.where((f) => f.name != keep).map((f) => '$folder/${f.name}').toList();
      if (old.isNotEmpty) await bucket.remove(old);
    } catch (_) {
      // Tidying old photos is optional; never fail the upload because of it.
    }
  }
}

/// Turns Supabase errors into the short messages shown in SnackBars (FR-021).
String friendlyError(Object e) {
  if (e is AuthException) {
    if (e.message.contains('Database error saving new user')) {
      return 'Registration failed: check your student number (9 digits) and that it is not already registered.';
    }
    if (e.message.contains('Invalid login credentials')) return 'Incorrect student number/email or password.';
    return e.message;
  }
  if (e is PostgrestException) return e.message;
  if (e is StorageException) {
    if (e.message.toLowerCase().contains('row-level security') || e.statusCode == '403') {
      return 'Photo upload not allowed yet. Ask the admin to run 08_profile_photo.sql in Supabase.';
    }
    return 'Photo upload failed: ${e.message}';
  }
  return 'Something went wrong. Check your internet connection and try again.';
}
