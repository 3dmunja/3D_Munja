import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/trip.dart';
import '../services/storage_service.dart';
import '../services/advanced_ride_analytics_service.dart';
import '../Services/munja_pro_service.dart';
import 'munja_pro_screen.dart';
import '../widgets/munja_card.dart';
import '../widgets/section_title.dart';

class RideAnalyticsScreen extends StatefulWidget {
  const RideAnalyticsScreen({super.key});

  @override
  State<RideAnalyticsScreen> createState() => _RideAnalyticsScreenState();
}

class _RideAnalyticsScreenState extends State<RideAnalyticsScreen> {
  bool loading = true;
  List<Trip> trips = [];
  AdvancedAnalyticsResult? advancedAnalytics;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    await MunjaProService.instance.initialize();

    final loaded = await StorageService.loadTrips();

    final analytics =
        const AdvancedRideAnalyticsService().analyze(
      loaded,
    );

    if (!mounted) return;

    setState(() {
      trips = loaded;
      advancedAnalytics = analytics;
      loading = false;
    });
  }

  double get totalKm {
    return trips.fold(0.0, (sum, t) => sum + t.distanceM / 1000);
  }

  int get totalRides => trips.length;

  bool get isProAnalytics =>
      MunjaProService.instance.hasFeature(
        MunjaProFeature.advancedAnalytics,
      );


  Duration get totalDuration {
    return trips.fold(Duration.zero, (sum, t) => sum + t.duration);
  }

  double get avgSpeedKmh {
    final hours = totalDuration.inSeconds / 3600;
    if (hours <= 0) return 0;
    return totalKm / hours;
  }

  double get longestRideKm {
    if (trips.isEmpty) return 0;

    return trips.map((t) => t.distanceM / 1000).reduce((a, b) => a > b ? a : b);
  }

  int get totalCalories {
    return trips.fold(0, (sum, t) {
      final km = t.distanceM / 1000;
      final hours = t.duration.inSeconds / 3600;
      final speed = hours <= 0 ? 0 : km / hours;

      final met = speed < 16
          ? 4.0
          : speed < 20
          ? 6.8
          : speed < 25
          ? 8.0
          : 10.0;

      return sum + (met * 75 * hours).round();
    });
  }

  double get co2SavedKg => totalKm * 0.12;

  int get streakDays {
    if (trips.isEmpty) return 0;

    final rideDays = trips
        .map((t) => DateTime.fromMillisecondsSinceEpoch(t.startedAtMs))
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final todayRaw = DateTime.now();
    final today = DateTime(todayRaw.year, todayRaw.month, todayRaw.day);

    int streak = 0;

    for (int i = 0; i < 365; i++) {
      final day = today.subtract(Duration(days: i));

      if (rideDays.contains(day)) {
        streak++;
      } else {
        if (i == 0) continue;
        break;
      }
    }

    return streak;
  }

  List<_MonthStat> get monthlyStats {
    final now = DateTime.now();

    final months = List.generate(6, (i) {
      return DateTime(now.year, now.month - (5 - i), 1);
    });

    return months.map((monthStart) {
      final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);

      final monthTrips = trips.where((t) {
        final d = DateTime.fromMillisecondsSinceEpoch(t.startedAtMs);
        return !d.isBefore(monthStart) && d.isBefore(nextMonth);
      }).toList();

      final km = monthTrips.fold<double>(
        0,
        (sum, t) => sum + t.distanceM / 1000,
      );

      return _MonthStat(
        label:
            '${monthStart.month.toString().padLeft(2, '0')}/${monthStart.year.toString().substring(2)}',
        km: km,
      );
    }).toList();
  }

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _dateText(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  String _streakText() {
    if (streakDays == 0) {
      return AppText.t('startAutoRideBody');
    }

    return '$streakDays ${AppText.t('days')}';
  }

  Future<void> _openMunjaPro() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MunjaProScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    // Re-read the entitlement after returning from the Pro screen.
    // This makes Local Test Pro and later real Apple/Google purchases
    // unlock Advanced Analytics immediately without restarting the app.
    await MunjaProService.instance.refresh();

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return ValueListenableBuilder<MunjaProState>(
      valueListenable: MunjaProService.instance.state,
      builder: (
        context,
        proState,
        _,
      ) {
        final isPro = proState.hasActivePro &&
            MunjaProService.instance.hasFeature(
              MunjaProFeature.advancedAnalytics,
            );

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: SafeArea(
            child: RefreshIndicator(
          onRefresh: _loadTrips,
          color: MunjaColors.mint,
          backgroundColor: const Color(0xFF07110E),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 300),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: MunjaColors.mint.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: MunjaColors.mint.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      isPro
                          ? 'MUNJA PRO ANALYTICS'
                          : 'MUNJA ANALYTICS',
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Text(
                AppText.t('analytics'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                AppText.t('personalRideIntelligence'),
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 22),

              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: MunjaColors.panel,
                  borderRadius: BorderRadius.circular(34),
                  border: Border.all(color: MunjaColors.mint.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: MunjaColors.mint.withOpacity(0.14),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppText.t('distance'),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          totalKm.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 64,
                            height: 0.92,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'km',
                            style: TextStyle(
                              color: MunjaColors.mint,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _AnalyticsMetric(
                      icon: Icons.directions_bike_rounded,
                      label: AppText.t('rides'),
                      value: '$totalRides',
                      unit: '',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AnalyticsMetric(
                      icon: Icons.timer_rounded,
                      label: AppText.t('time'),
                      value: _durationText(totalDuration),
                      unit: '',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _AnalyticsMetric(
                      icon: Icons.speed_rounded,
                      label: AppText.t('avgSpeed'),
                      value: avgSpeedKmh.toStringAsFixed(1),
                      unit: 'km/h',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AnalyticsMetric(
                      icon: Icons.route_rounded,
                      label: AppText.t('longest'),
                      value: longestRideKm.toStringAsFixed(1),
                      unit: 'km',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _AnalyticsMetric(
                      icon: Icons.local_fire_department_rounded,
                      label: AppText.t('calories'),
                      value: '$totalCalories',
                      unit: 'kcal',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _AnalyticsMetric(
                      icon: Icons.eco_rounded,
                      label: AppText.t('co2Saved'),
                      value: co2SavedKg.toStringAsFixed(1),
                      unit: 'kg',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              MunjaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: AppText.t('monthlyProgress'),
                      subtitle: AppText.t('lastSixMonthsRiding'),
                    ),
                    const SizedBox(height: 18),
                    _MonthlyBarChart(stats: monthlyStats),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              MunjaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: AppText.t('streak'),
                      subtitle: AppText.t('consistencyCreatesResults'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            color: MunjaColors.mint.withOpacity(0.13),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: MunjaColors.mint.withOpacity(0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.bolt_rounded,
                            color: MunjaColors.mint,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _streakText(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              if (isPro &&
                  advancedAnalytics != null) ...[
                _ProAnalyticsPanel(
                  analytics: advancedAnalytics!,
                ),
                const SizedBox(height: 16),
              ] else ...[
                _ProAnalyticsLockedCard(
                  onTap: _openMunjaPro,
                ),
                const SizedBox(height: 16),
              ],

              MunjaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: AppText.t('recentRides'),
                      subtitle: AppText.t('latestSavedTrips'),
                    ),
                    const SizedBox(height: 14),
                    if (trips.isEmpty)
                      Text(
                        AppText.t('noRidesSavedYet'),
                        style: const TextStyle(color: MunjaColors.textSoft),
                      )
                    else
                      ...trips
                          .take(6)
                          .map(
                            (trip) => _RecentRideTile(
                              trip: trip,
                              dateText: _dateText(trip.startedAtMs),
                            ),
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
          ),
        );
      },
    );
  }
}

class _ProAnalyticsPanel extends StatelessWidget {
  const _ProAnalyticsPanel({
    required this.analytics,
  });

  final AdvancedAnalyticsResult analytics;

  String _change(double? value) {
    if (value == null) {
      return 'NEW';
    }

    final prefix = value >= 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final week = analytics.weekComparison;
    final month = analytics.monthComparison;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_graph_rounded,
                color: MunjaColors.mint,
                size: 21,
              ),
              SizedBox(width: 8),
              Text(
                'ADVANCED ANALYTICS',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              Spacer(),
              Icon(
                Icons.verified_rounded,
                color: MunjaColors.mint,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ProTrendMetric(
                  label: 'THIS WEEK',
                  value:
                      '${week.currentDistanceKm.toStringAsFixed(1)} km',
                  change:
                      _change(week.distanceChangePercent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProTrendMetric(
                  label: 'THIS MONTH',
                  value:
                      '${month.currentDistanceKm.toStringAsFixed(1)} km',
                  change:
                      _change(month.distanceChangePercent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ProTrendMetric(
                  label: 'PACE TREND',
                  value:
                      '${month.currentAverageSpeedKmh.toStringAsFixed(1)} km/h',
                  change:
                      _change(month.speedChangePercent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProTrendMetric(
                  label: 'CONSISTENCY',
                  value:
                      '${analytics.consistencyScore}/100',
                  change:
                      '${week.currentRideCount} RIDES',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.055),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.auto_awesome_rounded,
                  color: MunjaColors.mint,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        analytics.insightTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        analytics.insightBody,
                        style: const TextStyle(
                          color: MunjaColors.textSoft,
                          fontSize: 11,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'BEST MONTH',
                style: TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                ),
              ),
              const Spacer(),
              Text(
                '${analytics.bestMonthLabel} · '
                '${analytics.bestMonthDistanceKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProTrendMetric extends StatelessWidget {
  const _ProTrendMetric({
    required this.label,
    required this.value,
    required this.change,
  });

  final String label;
  final String value;
  final String change;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            change,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProAnalyticsLockedCard extends StatelessWidget {
  const _ProAnalyticsLockedCard({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: MunjaColors.panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: MunjaColors.mint,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ADVANCED ANALYTICS',
                      style: TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Weekly trends, monthly comparison and personal insights',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'UNLOCK WITH MUNJA PRO',
                      style: TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: MunjaColors.mint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthStat {
  final String label;
  final double km;

  const _MonthStat({required this.label, required this.km});
}

class _MonthlyBarChart extends StatelessWidget {
  final List<_MonthStat> stats;

  const _MonthlyBarChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    final maxKm = stats.isEmpty
        ? 1.0
        : stats.map((e) => e.km).reduce((a, b) => a > b ? a : b);

    final safeMax = maxKm <= 0 ? 1.0 : maxKm;

    return SizedBox(
      height: 190,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: stats.map((item) {
          final ratio = item.km <= 0
              ? 0.05
              : (item.km / safeMax).clamp(0.05, 1.0);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    item.km.toStringAsFixed(1),
                    style: const TextStyle(
                      color: MunjaColors.textSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    height: 126 * ratio,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          MunjaColors.mintStrong,
                          MunjaColors.mint.withOpacity(0.75),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AnalyticsMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const _AnalyticsMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 21),
          const Spacer(),
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
                    fontSize: 22,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentRideTile extends StatelessWidget {
  final Trip trip;
  final String dateText;

  const _RecentRideTile({required this.trip, required this.dateText});

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final km = trip.distanceM / 1000;
    final hours = trip.duration.inSeconds / 3600;
    final avg = hours <= 0 ? 0 : km / hours;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panelSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.directions_bike_rounded,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${km.toStringAsFixed(2)} km',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$dateText · ${_durationText(trip.duration)} · ${avg.toStringAsFixed(1)} km/h',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        ],
      ),
    );
  }
}
