import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme.dart';
import '../widgets/cc_widgets.dart';

/// Figma: "Coupons Redeemed" - green tick, "Coupon Redeemed!", QR code,
/// Redemption Code (e.g. CC2026-7843-2219), Done.
/// Cafeteria staff find this code in the portal and approve or reject it.
class RedeemSuccessScreen extends StatelessWidget {
  const RedeemSuccessScreen({super.key, required this.code, required this.couponTitle});
  final String code;
  final String couponTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'Redeem Coupon'),
      bottomNavigationBar: const CCBottomNav(popToShell: true),
      body: ListView(padding: const EdgeInsets.fromLTRB(24, 18, 24, 24), children: [
        // Tick that pops in
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Curves.elasticOut,
            builder: (_, t, child) => Transform.scale(scale: t, child: child),
            child: Container(
              width: 110,
              height: 110,
              decoration: const BoxDecoration(color: CC.success, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: CC.white, size: 70),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text('Coupon Redeemed!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: CC.navy)),
        Text('Your $couponTitle coupon has been successfully redeemed. Show this at the CUT Welkom cafeteria.',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: CC.textBlue)),
        const SizedBox(height: 22),
        CCTile(
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            Container(
              color: CC.white,
              padding: const EdgeInsets.all(10),
              child: QrImageView(
                data: code,
                size: 160,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: CC.navy),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: CC.navy),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Redemption Code', style: TextStyle(fontSize: 17, color: CC.textBlue)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Flexible(
                child: SelectableText(code,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: CC.navy)),
              ),
              IconButton(
                tooltip: 'Copy code',
                icon: const Icon(Icons.copy_rounded, color: CC.navy, size: 20),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) showMessage(context, 'Code copied');
                },
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 60,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.of(context).popUntil((r) => r.isFirst);
              currentTab.value = 1; // back to the wallet
            },
            child: const Text('Done', style: TextStyle(fontSize: 30)),
          ),
        ),
      ]),
    );
  }
}