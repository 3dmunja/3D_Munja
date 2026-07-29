import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/ride_coach_recommendation.dart';
import '../models/trip.dart';
import '../services/storage_service.dart';
import '../widgets/munja_card.dart';
import '../widgets/section_title.dart';

class SmartRideCoachScreen extends StatefulWidget {
  const SmartRideCoachScreen({super.key});

  @override
  State<SmartRideCoachScreen> createState() => _SmartRideCoachScreenState();
}

class _SmartRideCoachScreenState extends State<SmartRideCoachScreen> {
  bool loading = true;

  List<Trip> trips = [];
  late RideCoachRecommendation recommendation;

  @override
  void initState() {
    super.initState();
    _loadCoach();
  }

  Future<void> _loadCoach() async {
    final loadedTrips = await StorageService.loadTrips();

    if (!mounted) return;

    setState(() {
      trips = loadedTrips;
      recommendation = RideCoachRecommendation.fromTrips(loadedTrips);
      loading = false;
    });
  }

  String _lastRideText() {
    if (trips.isEmpty) return AppText.t('noRidesSavedYet');

    final sorted = [...trips]
      ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));

    final last = DateTime.fromMillisecondsSinceEpoch(sorted.first.startedAtMs);
    final now = DateTime.now();

    final days = now.difference(last).inDays;

    if (days == 0) return AppText.t('today');
    if (days == 1) return AppText.t('yesterday');
    return '$days ${AppText.t('daysAgo')}';
  }

  double _weeklyKm() {
    final now = DateTime.now();

    return trips
        .where((trip) {
          final d = DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);
          return now.difference(d).inDays <= 7;
        })
        .fold<double>(0, (sum, trip) => sum + trip.distanceM / 1000);
  }

  double _totalKm() {
    return trips.fold<double>(0, (sum, trip) => sum + trip.distanceM / 1000);
  }

  Duration _totalDuration() {
    return trips.fold<Duration>(
      Duration.zero,
      (sum, trip) => sum + trip.duration,
    );
  }

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);

    if (h <= 0) return '${m}m';
    return '${h}h ${m}m';
  }

  Future<void> _activateRecommendation() async {
    await _loadCoach();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MunjaColors.panel,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 180),
        content: Text(
          AppText.t('coachRecommendationActivated'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final weeklyKm = _weeklyKm();
    final totalKm = _totalKm();
    final totalDuration = _totalDuration();

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadCoach,
          color: MunjaColors.mint,
          backgroundColor: const Color(0xFF07110E),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 300),
            children: [
              const _TopBar(),

              const SizedBox(height: 18),

              Text(
                AppText.t('aiRideCoach'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                AppText.t('personalRideIntelligence'),
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 22),

              _CoachHeroCard(recommendation: recommendation),

              const SizedBox(height: 18),

              Row(
                children: [
                  Expanded(
                    child: _CoachMetric(
                      icon: Icons.bolt_rounded,
                      label: AppText.t('readiness'),
                      value: '${recommendation.readinessScore}',
                      unit: '%',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CoachMetric(
                      icon: Icons.monitor_heart_rounded,
                      label: AppText.t('fatigue'),
                      value: '${recommendation.fatigueScore}',
                      unit: '%',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _CoachMetric(
                      icon: Icons.repeat_rounded,
                      label: AppText.t('consistency'),
                      value: '${recommendation.consistencyScore}',
                      unit: '%',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _CoachMetric(
                      icon: Icons.route_rounded,
                      label: AppText.t('thisWeek'),
                      value: weeklyKm.toStringAsFixed(1),
                      unit: 'km',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 18),

              _CoachSummaryStrip(
                rides: trips.length,
                totalKm: totalKm,
                totalDuration: totalDuration,
                lastRide: _lastRideText(),
                durationText: _durationText,
              ),

              const SizedBox(height: 18),

              MunjaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: AppText.t('todayPlan'),
                      subtitle: AppText.t('recommendedRecentHistory'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _PlanTile(
                            icon: Icons.directions_bike_rounded,
                            label: AppText.t('rideType'),
                            value: recommendation.rideTypeText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PlanTile(
                            icon: Icons.route_rounded,
                            label: AppText.t('distance'),
                            value:
                                '${recommendation.suggestedDistanceKm.toStringAsFixed(1)} km',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _PlanTile(
                            icon: Icons.timer_rounded,
                            label: AppText.t('duration'),
                            value: recommendation.durationText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PlanTile(
                            icon: Icons.history_rounded,
                            label: AppText.t('lastRide'),
                            value: _lastRideText(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              MunjaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: AppText.t('coachIntelligence'),
                      subtitle: AppText.t('whatMunjaNotices'),
                    ),
                    const SizedBox(height: 14),
                    _InsightRow(
                      icon: Icons.psychology_rounded,
                      title: AppText.t('adaptiveRecommendation'),
                      message: AppText.t('adaptiveRecommendationBody'),
                    ),
                    const SizedBox(height: 12),
                    _InsightRow(
                      icon: Icons.shield_rounded,
                      title: AppText.t('safetyLayer'),
                      message: AppText.t('safetyLayerBody'),
                    ),
                    const SizedBox(height: 12),
                    _InsightRow(
                      icon: Icons.auto_graph_rounded,
                      title: AppText.t('performanceTrend'),
                      message: AppText.t('performanceTrendBody'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              MunjaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle(
                      title: AppText.t('coachTips'),
                      subtitle: AppText.t('smallActionsBetterRide'),
                    ),
                    const SizedBox(height: 14),
                    ...recommendation.tips.map(
                      (tip) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TipRow(tip: tip),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _activateRecommendation,
                  icon: const Icon(Icons.navigation_rounded),
                  label: Text(
                    AppText.t('useRecommendation'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: MunjaColors.mint.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: MunjaColors.mint.withOpacity(0.08),
                blurRadius: 18,
              ),
            ],
          ),
          child: const Text(
            'Munja AI',
            style: TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            AppText.t('wheelNavigation'),
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _CoachHeroCard extends StatelessWidget {
  final RideCoachRecommendation recommendation;

  const _CoachHeroCard({required this.recommendation});

  @override
  Widget build(BuildContext context) {
    final progress = (recommendation.readinessScore / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.92),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.12),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MiniLabel(
            icon: Icons.auto_awesome_rounded,
            label: recommendation.rideTypeText,
          ),
          const SizedBox(height: 12),
          Text(
            recommendation.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              height: 0.98,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.9,
            ),
          ),
          const SizedBox(height: 11),
          Text(
            recommendation.message,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Text(
                AppText.t('readiness'),
                style: const TextStyle(
                  color: Colors.white54,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${recommendation.readinessScore}%',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 11,
              backgroundColor: Colors.white10,
              color: MunjaColors.mint,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: MunjaColors.mint, size: 17),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: MunjaColors.mint,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _CoachMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const _CoachMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 102,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.9),
        borderRadius: BorderRadius.circular(28),
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

class _CoachSummaryStrip extends StatelessWidget {
  final int rides;
  final double totalKm;
  final Duration totalDuration;
  final String lastRide;
  final String Function(Duration) durationText;

  const _CoachSummaryStrip({
    required this.rides,
    required this.totalKm,
    required this.totalDuration,
    required this.lastRide,
    required this.durationText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(label: AppText.t('rides'), value: '$rides'),
          ),
          Expanded(
            child: _SummaryItem(
              label: AppText.t('total'),
              value: '${totalKm.toStringAsFixed(1)} km',
            ),
          ),
          Expanded(
            child: _SummaryItem(
              label: AppText.t('time'),
              value: durationText(totalDuration),
            ),
          ),
          Expanded(
            child: _SummaryItem(label: AppText.t('last'), value: lastRide),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _PlanTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PlanTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: MunjaColors.panelSoft.withOpacity(0.86),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 19),
          const Spacer(),
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

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _InsightRow({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: MunjaColors.mint.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: MunjaColors.mint, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 13,
                  height: 1.38,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  final String tip;

  const _TipRow({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.check_circle_rounded,
          color: MunjaColors.mint,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tip,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
