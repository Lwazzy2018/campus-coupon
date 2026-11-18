import 'package:flutter/material.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';
import 'transactions_screen.dart';

/// Home ("Welcome Screen"): greeting, points card with progress to the next
/// reward, four tiles (navy feature tile for Upcoming events) and Recent activity.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeData {
  _HomeData(this.stats, this.activity, this.profile, this.events, this.coupons, this.txns);
  final HomeStats stats;
  final List<ActivityItem> activity;
  final StudentProfile profile;
  final List<CampusEvent> events;
  final List<Coupon> coupons;
  final List<RewardTxn> txns;
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<_HomeData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_HomeData> _load() async {
    final s = CampusService.instance;
    final results = await Future.wait<dynamic>([
      s.homeStats(),
      s.recentActivity(),
      s.profile(),
      s.upcomingEvents(),
      s.coupons(),
      s.transactions(),
    ]);
    return _HomeData(
      results[0] as HomeStats,
      results[1] as List<ActivityItem>,
      results[2] as StudentProfile,
      results[3] as List<CampusEvent>,
      results[4] as List<Coupon>,
      results[5] as List<RewardTxn>,
    );
  }

  void _reload() => setState(() {
        _data = _load();
      });

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _openHistory() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => const TransactionsScreen()));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context),
      bottomNavigationBar: const CCBottomNav(),
      body: FutureBuilder<_HomeData>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return CCErrorView(friendlyError(snap.error!), onRetry: _reload);
          if (!snap.hasData) return const CCLoading();
          final d = snap.data!;
          return RefreshIndicator(
            color: CC.navy,
            onRefresh: () async => _reload(),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              _greetingRow(d.profile),
              const SizedBox(height: 14),
              _pointsCard(d),
              const SizedBox(height: 12),
              _tiles(d),
              CCSectionHeader('Recent activity', action: 'See all', onAction: _openHistory),
              _activity(d.activity),
            ]),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------- Greeting
  Widget _greetingRow(StudentProfile p) => Row(children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: CC.navy,
          // Profile photo when there is one; initials underneath as the fallback.
          foregroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
          onForegroundImageError: p.avatarUrl != null ? (_, __) {} : null,
          child: Text(p.initials, style: const TextStyle(color: CC.white, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_greeting 👋', style: const TextStyle(color: CC.muted, fontSize: 13)),
            Text(p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: CC.navy, fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
        ),
        // History shortcut
        InkWell(
          onTap: _openHistory,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: CC.border),
            ),
            child: const Icon(Icons.receipt_long_outlined, color: CC.navy, size: 22),
          ),
        ),
      ]);

  // ---------------------------------------------------------------- Points card
  Widget _pointsCard(_HomeData d) {
    final balance = d.stats.balance;
    final costs = d.coupons.map((c) => c.cost).toList()..sort();
    final ready = costs.where((c) => c <= balance).length;
    final above = costs.where((c) => c > balance).toList();
    final nextCost = above.isEmpty ? null : above.first;
    final nextTitle = nextCost == null ? null : d.coupons.firstWhere((c) => c.cost == nextCost).title;
    final double progress = nextCost == null ? 1.0 : (balance / nextCost).clamp(0.0, 1.0).toDouble();

    return CCCard(
      padding: const EdgeInsets.all(16),
      child: Stack(clipBehavior: Clip.none, children: [
        // soft decorative ring
        Positioned(
          right: -46,
          top: -56,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: CC.tileBg, width: 14),
            ),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('CAMPUS COUPON POINTS',
              style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: CC.muted)),
          const SizedBox(height: 6),
          Row(children: [
            const CCCoin(size: 46),
            const SizedBox(width: 10),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: balance.toDouble()),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text('${v.round()}',
                    style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: CC.navy, height: 1.1)),
              ),
            ),
            if (ready > 0)
              CCPill('$ready reward${ready == 1 ? '' : 's'} ready',
                  background: CC.greenSoft, color: CC.greenText, icon: Icons.card_giftcard_rounded),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: const Color(0xFFEEF1F6),
              valueColor: const AlwaysStoppedAnimation<Color>(CC.navy),
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            nextCost == null
                ? TextSpan(text: d.coupons.isEmpty ? 'Attend events to earn points.' : 'You can redeem every reward!')
                : TextSpan(children: [
                    TextSpan(text: '${nextCost - balance} more points for '),
                    TextSpan(text: nextTitle, style: const TextStyle(fontWeight: FontWeight.w800, color: CC.navy)),
                  ]),
            style: const TextStyle(fontSize: 12, color: CC.muted),
          ),
        ]),
      ]),
    );
  }

  // ---------------------------------------------------------------- Four tiles
  Widget _tiles(_HomeData d) {
    final s = d.stats;
    final earned = d.txns.where((t) => t.type == 'earn').fold<int>(0, (a, t) => a + t.points);
    final meals = d.txns.where((t) => t.type == 'redeem').length - d.txns.where((t) => t.type == 'refund').length;
    final next = d.events.isEmpty ? null : d.events.first.title;

    return Column(children: [
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _FeatureTile(
              icon: Icons.calendar_month_rounded,
              value: s.upcomingEvents,
              label: 'Upcoming events',
              caption: next == null ? 'Check back soon' : 'Next: $next →',
              onTap: () => currentTab.value = 2,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.groups_rounded,
              color: CC.navy,
              value: s.myRsvps,
              label: 'My RSVPs',
              caption: s.myRsvps == 0 ? 'RSVP to an event' : 'Events you are going to',
              onTap: () => currentTab.value = 2,
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: _StatTile(
              icon: Icons.verified_rounded,
              color: CC.approve,
              captionColor: CC.greenText,
              value: s.attended,
              label: 'Events attended',
              caption: '$earned pts earned',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatTile(
              icon: Icons.restaurant_rounded,
              color: CC.cutRed,
              value: s.pointsRedeemed,
              label: 'Points spent',
              caption: '${meals < 0 ? 0 : meals} meal${meals == 1 ? '' : 's'} enjoyed',
              onTap: () => currentTab.value = 1,
            ),
          ),
        ]),
      ),
    ]);
  }

  // ---------------------------------------------------------------- Recent activity
  Widget _activity(List<ActivityItem> items) {
    if (items.isEmpty) {
      return const CCCard(
        child: CCEmptyState(
          icon: Icons.bolt_rounded,
          title: 'No activity yet',
          message: 'RSVP to an event to get started!',
        ),
      );
    }
    return CCCard(
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < items.length; i++) ...[
          ListTile(
            leading: _activityIcon(items[i].title),
            title: Text(items[i].title,
                style: const TextStyle(fontWeight: FontWeight.w800, color: CC.navy, fontSize: 14)),
            subtitle: Text(items[i].detail,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: CC.muted, fontSize: 12)),
            trailing: Text(timeAgo(items[i].createdAt), style: const TextStyle(color: CC.muted, fontSize: 11)),
          ),
          if (i < items.length - 1) const Divider(height: 1, color: CC.border),
        ],
      ]),
    );
  }

  Widget _activityIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('refund')) return const CCIconBox(Icons.undo_rounded, color: CC.greenText, background: CC.greenSoft, size: 36);
    if (t.contains('redeem') || t.contains('used')) {
      return const CCIconBox(Icons.restaurant_rounded, color: CC.cutRed, background: CC.redSoft, size: 36);
    }
    if (t.contains('approved') || t.contains('attend') || t.contains('earned')) {
      return const CCIconBox(Icons.verified_rounded, color: CC.greenText, background: CC.greenSoft, size: 36);
    }
    return const CCIconBox(Icons.notifications_none_rounded, size: 36);
  }
}

/// Navy -> CUT blue tile that stands out ("Upcoming events").
class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.value, required this.label, required this.caption, this.onTap});
  final IconData icon;
  final int value;
  final String label;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: CC.featureGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x33003261), blurRadius: 18, offset: Offset(0, 8))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(children: [
              Positioned(
                right: -22,
                top: -22,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x1AFFFFFF), width: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CCIconBox(icon, color: CC.white, background: const Color(0x26FFFFFF), size: 36),
                  const SizedBox(height: 8),
                  Text('$value',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: CC.white, height: 1)),
                  const SizedBox(height: 2),
                  Text(label,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF))),
                  const SizedBox(height: 6),
                  Text(caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: CC.cutGold)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

/// White tile with a coloured top edge.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.caption,
    this.captionColor,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color? captionColor;
  final int value;
  final String label;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: CC.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: CC.border),
          boxShadow: const [BoxShadow(color: Color(0x0F003261), blurRadius: 12, offset: Offset(0, 4))],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(height: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    CCIconBox(icon, color: color, background: const Color(0xFFF4F6FA), size: 36),
                    const SizedBox(height: 8),
                    Text('$value',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: CC.navy, height: 1)),
                    const SizedBox(height: 2),
                    Text(label,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: CC.bodyText)),
                    const SizedBox(height: 6),
                    Text(caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: captionColor ?? color)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      );
}
