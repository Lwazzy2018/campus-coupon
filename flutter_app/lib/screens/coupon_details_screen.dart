import 'package:flutter/material.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';
import 'redeem_success_screen.dart';

/// Figma: "Redeem Coupons" - coupon photo, title, cost, Valid until, Location,
/// Terms & Conditions, "Redeem Coupons" button.
/// Use case: Redeem coupon <<include>> Validate coupon balance (FR-017, FR-018).
class CouponDetailsScreen extends StatefulWidget {
  const CouponDetailsScreen({super.key, required this.coupon, required this.balance});
  final Coupon coupon;
  final int balance;
  @override
  State<CouponDetailsScreen> createState() => _CouponDetailsScreenState();
}

class _CouponDetailsScreenState extends State<CouponDetailsScreen> {
  bool _busy = false;

  Future<void> _redeem() async {
    final c = widget.coupon;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Redeem coupon?'),
        content: Text('${c.cost} points will be deducted for "${c.title}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Redeem')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final result = await CampusService.instance.redeem(c.id);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RedeemSuccessScreen(code: result.code, couponTitle: c.title)),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.coupon;
    final enough = widget.balance >= c.cost;
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'Redeem Coupon'),
      bottomNavigationBar: const CCBottomNav(popToShell: true),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 190,
            child: CCImage(c.imageUrl, icon: c.category == 'Food' ? Icons.restaurant_rounded : Icons.card_giftcard_rounded),
          ),
        ),
        const SizedBox(height: 14),
        Align(alignment: Alignment.centerLeft, child: CCPill(c.category)),
        const SizedBox(height: 6),
        Text(c.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: CC.navy)),
        Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Text('${c.cost}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: CC.points)),
        ),
        const SizedBox(height: 12),
        _row(Icons.calendar_month_outlined, 'Valid until', c.validLabel),
        _row(Icons.place_outlined, 'Location', c.location.toUpperCase()),
        _row(Icons.description_outlined, 'Terms & Conditions', c.terms),
        const SizedBox(height: 4),
        if (!enough)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CC.redSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0x33B02319)),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, color: CC.cutRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text('You need ${c.cost - widget.balance} more points to redeem this coupon.',
                    style: const TextStyle(color: CC.cutRed, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: _busy || !enough ? null : _redeem,
            child: _busy
                ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: CC.white))
                : const Text('Redeem Coupons'),
          ),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 32, color: CC.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 15, color: CC.black)),
              Text(value, style: const TextStyle(fontSize: 15, color: CC.black)),
            ]),
          ),
        ]),
      );
}