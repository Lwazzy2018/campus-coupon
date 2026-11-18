import 'package:intl/intl.dart';

/// Maps to ERD table EVENTS
class CampusEvent {
  final int id;
  final String title, description, location, category, status;
  final DateTime date;
  final String startTime;
  final String? endTime, imageUrl;
  final int points;
  final bool rsvpd; // true if the signed-in student has an active RSVP

  CampusEvent.fromMap(Map<String, dynamic> m)
      : id = m['event_id'] as int,
        title = m['title'] as String,
        description = (m['description'] ?? '') as String,
        location = m['location'] as String,
        category = (m['category'] ?? 'Other') as String,
        status = m['status'] as String,
        date = DateTime.parse(m['event_date'] as String),
        startTime = (m['start_time'] as String).substring(0, 5),
        endTime = (m['end_time'] as String?)?.substring(0, 5),
        imageUrl = m['image_url'] as String?,
        points = (m['points_reward'] ?? 0) as int,
        // RLS only returns the current student's own rsvp rows in the embed
        rsvpd = ((m['rsvp'] as List?) ?? const [])
            .any((r) => (r as Map)['status'] == 'registered');

  String get dateLabel => DateFormat('d MMMM yyyy').format(date);
  String get timeLabel => endTime == null ? startTime : '$startTime - $endTime';
}

/// Maps to table COUPONS (catalogue shown in the wallet)
class Coupon {
  final int id, cost;
  final String title, category, location, terms;
  final DateTime validUntil;
  final String? imageUrl;

  Coupon.fromMap(Map<String, dynamic> m)
      : id = m['coupon_id'] as int,
        cost = m['points_cost'] as int,
        title = m['title'] as String,
        category = m['category'] as String,
        location = m['location'] as String,
        terms = (m['terms'] ?? '') as String,
        validUntil = DateTime.parse(m['valid_until'] as String),
        imageUrl = m['image_url'] as String?;

  String get validLabel => DateFormat('d MMMM yyyy').format(validUntil);
}

/// Maps to ERD table STUDENTS
class StudentProfile {
  final String id, name, email, studentNumber;
  final String? course, phone;
  final String? avatarUrl; // profile picture (08_profile_photo.sql)

  StudentProfile.fromMap(Map<String, dynamic> m)
      : id = m['student_id'] as String,
        name = m['name'] as String,
        email = m['email'] as String,
        studentNumber = m['student_number'] as String,
        course = m['course'] as String?,
        phone = m['phone'] as String?,
        avatarUrl = m['avatar_url'] as String?;

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

/// Maps to ERD table REWARD_TRANSACTIONS
class RewardTxn {
  final int points;
  final String type, description;
  final DateTime createdAt;

  RewardTxn.fromMap(Map<String, dynamic> m)
      : points = m['points'] as int,
        type = m['txn_type'] as String,
        description = m['description'] as String,
        createdAt = DateTime.parse(m['created_at'] as String).toLocal();
}

class HomeStats {
  final int upcomingEvents, myRsvps, attended, pointsRedeemed, balance;
  HomeStats.fromMap(Map<String, dynamic> m)
      : upcomingEvents = m['upcoming_events'] as int,
        myRsvps = m['my_rsvps'] as int,
        attended = m['events_attended'] as int,
        pointsRedeemed = m['points_redeemed'] as int,
        balance = (m['balance'] ?? 0) as int;
}

class ActivityItem {
  final String title, detail;
  final DateTime createdAt;
  ActivityItem.fromMap(Map<String, dynamic> m)
      : title = m['title'] as String,
        detail = m['detail'] as String,
        createdAt = DateTime.parse(m['created_at'] as String).toLocal();
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
  if (d.inHours < 24) return '${d.inHours} hours ago';
  return '${d.inDays} days ago';
}
