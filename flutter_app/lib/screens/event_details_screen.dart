import 'package:flutter/material.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';

/// Figma: "Event Details" - poster, title, description, Date/Time box, RSVP button
/// (white CUT look).
/// Sequence Diagram 1, steps 13-16 (RSVP -> RSVP saved -> show confirmation).
class EventDetailsScreen extends StatefulWidget {
  const EventDetailsScreen({super.key, required this.eventId});
  final int eventId;
  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  late Future<CampusEvent> _event;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _event = CampusService.instance.event(widget.eventId);
  }

  Future<void> _toggleRsvp(CampusEvent e) async {
    setState(() => _busy = true);
    try {
      if (e.rsvpd) {
        await CampusService.instance.cancelRsvp(e.id);
        if (mounted) showMessage(context, 'RSVP cancelled');
      } else {
        await CampusService.instance.rsvp(e.id);
        // Step 16: Show RSVP confirmation
        if (mounted) {
          showMessage(context,
              "You're going to ${e.title}! Attend to earn ${e.points} points once the organiser confirms attendance.");
        }
      }
      if (mounted) {
        setState(() {
          _event = CampusService.instance.event(widget.eventId);
        });
      }
    } catch (err) {
      if (mounted) showMessage(context, friendlyError(err), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'Event Details'),
      bottomNavigationBar: const CCBottomNav(popToShell: true),
      body: FutureBuilder<CampusEvent>(
        future: _event,
        builder: (context, snap) {
          if (snap.hasError) return CCErrorView(friendlyError(snap.error!));
          if (!snap.hasData) return const CCLoading();
          final e = snap.data!;
          final open = e.status == 'published';
          return ListView(children: [
            SizedBox(height: 220, child: CCImage(e.imageUrl, showLogo: true)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CUT STUDENT EVENT',
                    style: TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w700, color: CC.muted)),
                const SizedBox(height: 2),
                Text(e.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: CC.navy)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  CCPill('+${e.points} points', background: CC.navy, color: CC.white),
                  CCPill(daysUntilLabel(e.date)),
                  CCPill(e.category),
                  if (e.rsvpd)
                    const CCPill("You're going", background: CC.greenSoft, color: CC.greenText, icon: Icons.check_rounded),
                ]),
                const SizedBox(height: 14),
                Text(e.description, style: const TextStyle(fontSize: 16, height: 1.45, color: CC.labelBlue)),
                const SizedBox(height: 16),
                CCCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(children: [
                    _infoRow(Icons.calendar_month_outlined, 'Date', e.dateLabel),
                    const Divider(height: 1, color: CC.border),
                    _infoRow(Icons.schedule_rounded, 'Time', e.timeLabel),
                    const Divider(height: 1, color: CC.border),
                    _infoRow(Icons.place_outlined, 'Location', e.location),
                  ]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 60,
                  width: double.infinity,
                  child: ElevatedButton(
                    // navy button with the red "RSVP" from the design; green once you're going
                    style: ElevatedButton.styleFrom(
                      backgroundColor: e.rsvpd ? CC.approve : CC.navy,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _busy || !open ? null : () => _toggleRsvp(e),
                    child: _busy
                        ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: CC.white))
                        : Text(
                            !open
                                ? 'RSVP CLOSED'
                                : e.rsvpd
                                    ? "RSVP'D  ✓  (tap to cancel)"
                                    : 'RSVP',
                            style: TextStyle(
                              fontSize: e.rsvpd || !open ? 18.0 : 30.0,
                              fontWeight: FontWeight.w900,
                              letterSpacing: e.rsvpd || !open ? 0.0 : 2.0,
                              color: !open ? CC.black : (e.rsvpd ? CC.white : CC.rsvpRed),
                            ),
                          ),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, size: 28, color: CC.navy),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: CC.black)),
              Text(value, style: const TextStyle(fontSize: 13, color: CC.black)),
            ]),
          ),
        ]),
      );
}