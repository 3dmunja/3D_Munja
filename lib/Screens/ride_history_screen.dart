import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/trip.dart';
import '../services/storage_service.dart';

import 'ride_summary_screen.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  bool loading = true;
  List<Trip> trips = [];

  static const double bottomWheelSafePadding = 360;

  String t(String key) => AppText.t(key);

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final loaded = await StorageService.loadTrips();

    if (!mounted) return;

    setState(() {
      trips = loaded;
      loading = false;
    });
  }

  Future<void> _deleteTrip(Trip trip) async {
    final updated = trips
        .where(
          (t) =>
              t.startedAtMs != trip.startedAtMs ||
              t.endedAtMs != trip.endedAtMs,
        )
        .toList();

    await StorageService.saveTrips(updated);

    if (!mounted) return;

    setState(() {
      trips = updated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('rideDeleted')),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  Future<void> _openTrip(Trip trip) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RideSummaryScreen(trip: trip)));

    await _loadTrips();
  }

  double get totalKm {
    return trips.fold<double>(0, (sum, trip) => sum + (trip.distanceM / 1000));
  }

  Duration get totalDuration {
    return trips.fold<Duration>(
      Duration.zero,
      (sum, trip) => sum + trip.duration,
    );
  }

  double get averageKm {
    if (trips.isEmpty) return 0;
    return totalKm / trips.length;
  }

  int get streakDays {
    if (trips.isEmpty) return 0;

    final days = trips
        .map((trip) {
          final d = DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);
          return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
        })
        .toSet()
        .length;

    return days.clamp(0, 999);
  }

  String _dateText(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  String _groupTitle(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);
    final rideDay = DateTime(d.year, d.month, d.day);
    final diff = today.difference(rideDay).inDays;

    if (diff == 0) return t('today');
    if (diff == 1) return t('yesterday');
    if (diff < 7) return t('thisWeek');

    return '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  Map<String, List<Trip>> _groupTrips() {
    final groups = <String, List<Trip>>{};

    for (final trip in trips) {
      final key = _groupTitle(trip.startedAtMs);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(trip);
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _loadTrips,
          color: MunjaColors.mint,
          backgroundColor: MunjaColors.panel,
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: MunjaColors.mint),
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    18,
                    20,
                    bottomWheelSafePadding,
                  ),
                  children: [
                    _Header(
                      title: t('rides'),
                      onBack: () => Navigator.of(context).maybePop(),
                    ),

                    const SizedBox(height: 18),

                    _HeroSummaryCard(
                      title: t('rideHistoryTitle'),
                      subtitle: t('rideHistorySubtitle'),
                      totalKm: totalKm,
                      totalRides: trips.length,
                      totalDuration: totalDuration,
                      averageKm: averageKm,
                      streakDays: streakDays,
                    ),

                    const SizedBox(height: 16),

                    if (trips.isEmpty)
                      _EmptyState(
                        title: t('noRidesSavedYet'),
                        subtitle: t('startRideFromWheelHint'),
                      )
                    else
                      ..._groupTrips().entries.expand(
                        (entry) => [
                          _GroupHeader(title: entry.key),
                          ...entry.value.map(
                            (trip) => _RideTile(
                              trip: trip,
                              dateText: _dateText(trip.startedAtMs),
                              durationText: _durationText(trip.duration),
                              routeLabel: t('route'),
                              scoreLabel: t('score'),
                              onTap: () => _openTrip(trip),
                              onDelete: () => _deleteTrip(trip),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _Header({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _BackButton(onTap: onBack),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MUNJA RIDES',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.panel.withOpacity(0.86),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _HeroSummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final double totalKm;
  final int totalRides;
  final Duration totalDuration;
  final double averageKm;
  final int streakDays;

  const _HeroSummaryCard({
    required this.title,
    required this.subtitle,
    required this.totalKm,
    required this.totalRides,
    required this.totalDuration,
    required this.averageKm,
    required this.streakDays,
  });

  @override
  Widget build(BuildContext context) {
    final hours = totalDuration.inHours;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _premiumDecoration(glow: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: AppText.t('distance'),
                  value: totalKm.toStringAsFixed(1),
                  unit: 'km',
                  icon: Icons.route_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryMetric(
                  label: AppText.t('rides'),
                  value: '$totalRides',
                  unit: '',
                  icon: Icons.directions_bike_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SmallMetric(
                  icon: Icons.timer_rounded,
                  label: AppText.t('time'),
                  value: '${hours}h',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SmallMetric(
                  icon: Icons.timeline_rounded,
                  label: AppText.t('avg'),
                  value: '${averageKm.toStringAsFixed(1)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SmallMetric(
                  icon: Icons.local_fire_department_rounded,
                  label: AppText.t('streak'),
                  value: '$streakDays',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.17),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 23),
          const Spacer(),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 5),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SmallMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String title;

  const _GroupHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: MunjaColors.mint,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: _premiumDecoration(),
      child: Column(
        children: [
          Icon(
            Icons.route_rounded,
            color: MunjaColors.mint.withOpacity(0.7),
            size: 42,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RideTile extends StatelessWidget {
  final Trip trip;
  final String dateText;
  final String durationText;
  final String routeLabel;
  final String scoreLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _RideTile({
    required this.trip,
    required this.dateText,
    required this.durationText,
    required this.routeLabel,
    required this.scoreLabel,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final km = trip.distanceM / 1000;
    final hours = trip.duration.inSeconds / 3600;
    final avg = hours <= 0 ? 0 : km / hours;
    final score = _rideScore(km, trip.duration);
    final hasRoute = trip.path.length >= 2;

    return Dismissible(
      key: ValueKey('${trip.startedAtMs}_${trip.endedAtMs}'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: MunjaColors.danger.withOpacity(0.18),
          borderRadius: BorderRadius.circular(26),
        ),
        child: const Icon(Icons.delete_rounded, color: MunjaColors.danger),
      ),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: _premiumDecoration(),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: MunjaColors.mint.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: MunjaColors.mint.withOpacity(0.22),
                    ),
                  ),
                  child: Icon(
                    hasRoute
                        ? Icons.route_rounded
                        : Icons.directions_bike_rounded,
                    color: MunjaColors.mint,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${km.toStringAsFixed(2)} km',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$dateText · $durationText · ${avg.toStringAsFixed(1)} km/t',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MunjaColors.textSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          _MiniTag(
                            icon: Icons.speed_rounded,
                            text: '${avg.toStringAsFixed(1)} km/t',
                          ),
                          _MiniTag(
                            icon: Icons.bolt_rounded,
                            text: '$scoreLabel $score',
                          ),
                          if (hasRoute)
                            _MiniTag(icon: Icons.map_rounded, text: routeLabel),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _rideScore(double km, Duration duration) {
    final minutes = duration.inMinutes.clamp(1, 999);
    final base = (km * 5).round();
    final timeBonus = (minutes / 4).round();
    return (base + timeBonus).clamp(10, 100);
  }
}

class _MiniTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MiniTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 13),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _premiumDecoration({bool glow = false}) {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.86),
    borderRadius: BorderRadius.circular(28),
    border: Border.all(color: Colors.white.withOpacity(0.075)),
    boxShadow: glow
        ? [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(0.13),
              blurRadius: 34,
              spreadRadius: 1,
              offset: const Offset(0, 14),
            ),
          ]
        : null,
  );
}
