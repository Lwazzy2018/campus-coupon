import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/campus_service.dart';
import '../theme.dart';
import '../widgets/cc_widgets.dart';
import 'event_details_screen.dart';

/// Figma: "Recent Events" - Events list with search + All/Career/Other chips.
/// Sequence Diagram 1, steps 9-12.
class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _category = 'All';
  String _search = '';
  Timer? _debounce;
  late Future<List<CampusEvent>> _events;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  // Block body on purpose: a setState callback must not return a Future.
  void _reload() {
    _events = CampusService.instance.upcomingEvents(category: _category, search: _search);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CC.white,
      appBar: ccAppBar(context, title: 'Events'),
      bottomNavigationBar: const CCBottomNav(),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Search Events',
              hintStyle: const TextStyle(fontSize: 17, color: CC.muted, fontWeight: FontWeight.w500),
              prefixIcon: const Icon(Icons.search_rounded, size: 26, color: CC.muted),
              filled: true,
              fillColor: CC.tileBg,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: CC.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: const BorderSide(color: CC.navy, width: 1.5),
              ),
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                setState(() {
                  _search = v;
                  _reload();
                });
              });
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: CCFilterChips(
              options: const ['All', 'Career', 'Other'],
              selected: _category,
              onSelected: (c) => setState(() {
                _category = c;
                _reload();
              }),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<List<CampusEvent>>(
              future: _events,
              builder: (context, snap) {
                if (snap.hasError) {
                  return CCErrorView(friendlyError(snap.error!), onRetry: () => setState(_reload));
                }
                if (!snap.hasData) return const CCLoading();
                final events = snap.data!;
                return RefreshIndicator(
                  color: CC.navy,
                  onRefresh: () async => setState(_reload),
                  child: events.isEmpty
                      ? ListView(children: const [
                          CCEmptyState(
                            icon: Icons.event_busy_rounded,
                            title: 'No upcoming events found',
                            message: 'Try another search or category.',
                          ),
                        ])
                      : ListView(children: [
                          for (final e in events)
                            CCListCard(
                              image: CCImage(e.imageUrl, showLogo: true),
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => EventDetailsScreen(eventId: e.id)));
                                if (mounted) setState(_reload); // RSVP status may have changed
                              },
                              children: [
                                Text(e.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: CC.navy)),
                                const SizedBox(height: 8),
                                _line(Icons.calendar_month_outlined, e.dateLabel),
                                const SizedBox(height: 6),
                                _line(Icons.schedule_rounded, e.timeLabel),
                                const SizedBox(height: 8),
                                Wrap(spacing: 6, runSpacing: 4, children: [
                                  CCPill('+${e.points} pts'),
                                  if (e.rsvpd)
                                    const CCPill('Going',
                                        background: CC.greenSoft, color: CC.greenText, icon: Icons.check_rounded),
                                ]),
                              ],
                            ),
                        ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String text) => Row(children: [
        Icon(icon, size: 20, color: CC.navy),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: CC.black)),
        ),
      ]);
}
