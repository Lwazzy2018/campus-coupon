import 'package:flutter/material.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';
import 'coupon_details_screen.dart';

/// Figma: "Coupons or Wallet" - My Points Balance + All/Food/Retail + coupon cards.
/// Sequence Diagram 1, step 20 (View the Coupon Wallet). FR-015.
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  String _category = 'All';
  late Future<(int, List<Coupon>)> _data;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = () async {
      final s = CampusService.instance;
      final balance = await s.walletBalance();
      final coupons = await s.coupons(category: _category);
      return (balance, coupons);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'Coupons'),
      bottomNavigationBar: const CCBottomNav(),
      body: FutureBuilder<(int, List<Coupon>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.hasError) return CCErrorView(friendlyError(snap.error!), onRetry: () => setState(_reload));
          if (!snap.hasData) return const CCLoading();
          final (balance, coupons) = snap.data!;
          final ready = coupons.where((c) => c.cost <= balance).length;
          return RefreshIndicator(
            color: CC.navy,
            onRefresh: () async => setState(_reload),
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
              // "My Points Balance" box from the design
              CCTile(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('My Points Balance', style: TextStyle(fontSize: 18, color: CC.black)),
                      const SizedBox(height: 4),
                      Row(children: [
                        const CCCoin(size: 44),
                        const SizedBox(width: 8),
                        Text('$balance',
                            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: CC.navy)),
                      ]),
                      const Text('Use at the CUT Welkom cafeteria', style: TextStyle(fontSize: 11, color: CC.muted)),
                    ]),
                  ),
                  if (ready > 0)
                    CCPill('$ready ready', background: CC.greenSoft, color: CC.greenText, icon: Icons.card_giftcard_rounded),
                ]),
              ),
              const SizedBox(height: 14),
              CCFilterChips(
                options: const ['All', 'Food', 'Retail'],
                selected: _category,
                onSelected: (c) => setState(() {
                  _category = c;
                  _reload();
                }),
              ),
              const SizedBox(height: 14),
              if (coupons.isEmpty)
                const CCEmptyState(
                  icon: Icons.local_activity_outlined,
                  title: 'No coupons available right now',
                  message: 'The cafeteria adds new meals regularly.',
                ),
              for (final c in coupons)
                CCListCard(
                  imageSize: 96,
                  image: CCImage(c.imageUrl, icon: c.category == 'Food' ? Icons.restaurant_rounded : Icons.card_giftcard_rounded),
                  onTap: () async {
                    await Navigator.push(context,
                        MaterialPageRoute(builder: (_) => CouponDetailsScreen(coupon: c, balance: balance)));
                    if (mounted) setState(_reload);
                  },
                  children: [
                    Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: CC.navy)),
                    Text('${c.cost}',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: CC.points, height: 1.2)),
                    Row(children: [
                      const Icon(Icons.calendar_month_outlined, size: 20, color: CC.navy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Valid until\n${c.validLabel}', style: const TextStyle(fontSize: 12, color: CC.black)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    balance >= c.cost
                        ? const CCPill('Redeem now', background: CC.greenSoft, color: CC.greenText, icon: Icons.check_rounded)
                        : CCPill('${c.cost - balance} pts to go'),
                  ],
                ),
            ]),
          );
        },
      ),
    );
  }
}