import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';

/// Use case "View transaction history" (FR-016). No Figma screen exists for it,
/// so it uses the same light boxes as "Recent Activity"; opened from Home.
class TransactionsScreen extends StatelessWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'Transaction History'),
      bottomNavigationBar: const CCBottomNav(popToShell: true),
      body: FutureBuilder<List<RewardTxn>>(
        future: CampusService.instance.transactions(),
        builder: (context, snap) {
          if (snap.hasError) return CCErrorView(friendlyError(snap.error!));
          if (!snap.hasData) return const CCLoading();
          final txns = snap.data!;
          if (txns.isEmpty) {
            return const CCEmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No points earned or redeemed yet',
              message: 'Attend an event to earn your first points.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            itemCount: txns.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final t = txns[i];
              final positive = t.points > 0;
              return CCTile(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(t.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: CC.navy)),
                      const SizedBox(height: 2),
                      Text(DateFormat('d MMM yyyy, HH:mm').format(t.createdAt),
                          style: const TextStyle(fontSize: 12, color: CC.labelBlue)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text('${positive ? '+' : ''}${t.points}',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, color: positive ? CC.greenText : CC.points)),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}
