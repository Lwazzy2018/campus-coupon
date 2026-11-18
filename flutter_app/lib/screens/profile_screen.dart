import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';

/// Figma: "Profile" - initials avatar, name, Student chip, Student Number,
/// Course, Email, Phone number, Personal Information, Change Password.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<StudentProfile> _profile;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _profile = CampusService.instance.profile();
  }

  void _reload() {
    setState(() {
      _profile = CampusService.instance.profile();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'My Profile'),
      bottomNavigationBar: const CCBottomNav(),
      body: FutureBuilder<StudentProfile>(
        future: _profile,
        builder: (context, snap) {
          if (snap.hasError) return CCErrorView(friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData) return const CCLoading();
          final p = snap.data!;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
            // Photo (or initials) with the navy camera badge (Figma "Profile").
            // Tap the photo or the badge to change it.
            Center(
              child: SizedBox(
                width: 140,
                height: 140,
                child: Stack(children: [
                  GestureDetector(
                    onTap: _uploading ? null : () => _photoOptions(p),
                    child: Container(
                      width: 140,
                      height: 140,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: CC.tileBg,
                        shape: BoxShape.circle,
                        border: Border.all(color: CC.border),
                      ),
                      child: ClipOval(
                        child: SizedBox(
                          width: 140,
                          height: 140,
                          child: Stack(fit: StackFit.expand, children: [
                            if (p.avatarUrl != null)
                              Image.network(
                                p.avatarUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _initials(p),
                              )
                            else
                              _initials(p),
                            if (_uploading)
                              Container(
                                color: const Color(0x99003261),
                                alignment: Alignment.center,
                                child: const SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: CircularProgressIndicator(color: CC.white, strokeWidth: 3),
                                ),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    bottom: 8,
                    child: Material(
                      color: CC.navy,
                      shape: const CircleBorder(side: BorderSide(color: CC.white, width: 3)),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _uploading ? null : () => _photoOptions(p),
                        child: const SizedBox(
                          width: 46,
                          height: 46,
                          child: Icon(Icons.photo_camera_outlined, color: CC.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(p.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: CC.navy)),
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 6, bottom: 20),
                padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 3),
                decoration: BoxDecoration(
                  color: CC.tileBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: CC.border),
                ),
                child: const Text('Student', style: TextStyle(fontSize: 22, color: CC.black)),
              ),
            ),
            _info(Icons.badge_outlined, 'Student Number', p.studentNumber),
            _info(Icons.school_outlined, 'Course', p.course ?? '-'),
            _info(Icons.mail_outline_rounded, 'Email', p.email),
            _info(Icons.phone_outlined, 'Phone number', p.phone ?? 'Not set'),
            const SizedBox(height: 6),
            _action(Icons.manage_accounts_outlined, 'Personal Information', () async {
              final changed = await Navigator.push<bool>(
                  context, MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p)));
              if (changed == true) _reload();
            }),
            _action(Icons.lock_outline_rounded, 'Change Password', () => _changePassword(context)),
          ]);
        },
      ),
    );
  }

  Widget _initials(StudentProfile p) => Center(
        child: Text(p.initials, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: CC.navy)),
      );

  /// Bottom sheet: Choose from gallery / Take a photo / Remove photo.
  Future<void> _photoOptions(StudentProfile p) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: CC.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: CC.border, borderRadius: BorderRadius.circular(2))),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Text('Profile picture', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: CC.navy)),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: CC.navy),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(sheet, 'gallery'),
          ),
          if (!kIsWeb) // the browser has no camera option; it opens the file picker instead
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: CC.navy),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, 'camera'),
            ),
          if (p.avatarUrl != null)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: CC.cutRed),
              title: const Text('Remove photo', style: TextStyle(color: CC.cutRed)),
              onTap: () => Navigator.pop(sheet, 'remove'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;

    try {
      if (choice == 'remove') {
        setState(() => _uploading = true);
        await CampusService.instance.removeAvatar();
        if (mounted) showMessage(context, 'Profile picture removed');
      } else {
        final file = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 600, // small and quick to upload
          maxHeight: 600,
          imageQuality: 80,
        );
        if (file == null || !mounted) return; // cancelled
        setState(() => _uploading = true);
        final bytes = await file.readAsBytes();
        if (bytes.lengthInBytes > 5 * 1024 * 1024) {
          if (mounted) showMessage(context, 'That photo is too big. Choose one under 5 MB.', error: true);
          return;
        }
        await CampusService.instance.uploadAvatar(bytes, file.name);
        if (mounted) showMessage(context, 'Profile picture updated');
      }
      _reload();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _info(IconData icon, String label, String value) => CCTile(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Icon(icon, color: CC.navy, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: CC.labelBlue, fontWeight: FontWeight.w600, fontSize: 15)),
              Text(value, style: const TextStyle(color: CC.labelBlue, fontWeight: FontWeight.w600, fontSize: 15)),
            ]),
          ),
        ]),
      );

  Widget _action(IconData icon, String label, VoidCallback onTap) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        onTap: onTap,
        leading: Icon(icon, color: CC.navy, size: 28),
        title: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: CC.black)),
        trailing: const Icon(Icons.chevron_right_rounded, color: CC.muted),
      );

  Future<void> _changePassword(BuildContext context) async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Change Password'),
        content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(hintText: 'New password (8+ characters)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dCtx, ctrl.text), child: const Text('Save')),
        ],
      ),
    );
    if (pw == null || !context.mounted) return;
    if (pw.length < 8) {
      showMessage(context, 'Password must be at least 8 characters', error: true);
      return;
    }
    try {
      await CampusService.instance.changePassword(pw);
      if (context.mounted) showMessage(context, 'Password updated');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}

/// "Personal Information" - edit name, course, phone (student number & email are locked by RLS).
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});
  final StudentProfile profile;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _course = TextEditingController(text: widget.profile.course ?? '');
  late final _phone = TextEditingController(text: widget.profile.phone ?? '');
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().length < 3) {
      showMessage(context, 'Enter your full name', error: true);
      return;
    }
    if (_phone.text.trim().isNotEmpty && !RegExp(r'^0\d{9}$').hasMatch(_phone.text.trim())) {
      showMessage(context, 'Phone number must be 10 digits starting with 0', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await CampusService.instance.updateProfile(
        name: _name.text.trim(),
        course: _course.text.trim().isEmpty ? null : _course.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: CC.white,
        appBar: ccAppBar(context, title: 'Personal Information'),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          CCField(controller: _name, hint: 'Full Name', icon: Icons.person),
          CCField(controller: _course, hint: 'Course', icon: Icons.account_balance),
          CCField(controller: _phone, hint: 'Phone number', icon: Icons.phone, keyboardType: TextInputType.phone),
          ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Save Changes')),
        ]),
      );
}
