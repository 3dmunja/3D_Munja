import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/trip.dart';
import '../services/crystal_reward_service.dart';
import '../services/storage_service.dart';
import '../services/ai_ride_analysis_service.dart';
import '../Services/munja_pro_service.dart';

class RideSummaryScreen extends StatefulWidget {
  final Trip trip;

  const RideSummaryScreen({super.key, required this.trip});

  @override
  State<RideSummaryScreen> createState() => _RideSummaryScreenState();
}

class _RideSummaryScreenState extends State<RideSummaryScreen> {
  static const double bottomWheelSafePadding = 360;

  /// Ride rewards are written just after a completed ride is persisted.
  /// The summary screen can open before Firestore has finished that write,
  /// so we give the backend a short window before showing an error.
  static const int _crystalRewardLoadAttempts = 3;

  CrystalRewardClaim? _rideRewardClaim;
  CrystalRewardClaim? _firstRideRewardClaim;
  bool _loadingCrystalRewards = true;
  Object? _crystalRewardError;

  RideAnalysisResult? _rideAnalysis;
  bool _loadingRideAnalysis = true;

  Trip get trip => widget.trip;

  String t(String key) => AppText.t(key);

  double get distanceKm => trip.distanceM / 1000;

  double get avgSpeedKmh {
    final hours = trip.duration.inSeconds / 3600;
    if (hours <= 0) return 0;
    return distanceKm / hours;
  }

  int get rideScore {
    final minutes = trip.duration.inMinutes.clamp(1, 999);
    final base = (distanceKm * 5).round();
    final timeBonus = (minutes / 4).round();
    final speedBonus = (avgSpeedKmh / 2).round();

    return (base + timeBonus + speedBonus).clamp(10, 100);
  }

  int get xp {
    return (distanceKm * 18 + rideScore * 1.7).round().clamp(20, 9999);
  }


  String get _rideRewardId =>
      '${trip.startedAtMs}_${trip.endedAtMs}';

  int get _rideCompletedCrystals =>
      _rideRewardClaim?.amount ?? 0;

  int get _firstRideBonusCrystals =>
      _firstRideRewardClaim?.amount ?? 0;

  int get _totalEarnedCrystals =>
      _rideCompletedCrystals + _firstRideBonusCrystals;

  bool get _hasAnyCrystalReward =>
      _totalEarnedCrystals > 0;

  @override
  void initState() {
    super.initState();
    _loadCrystalRewards();
    _loadRideAnalysis();
  }

  Future<void> _loadRideAnalysis() async {
    try {
      await MunjaProService.instance.initialize();

      final history = await StorageService.loadTrips();

      final isPro =
          MunjaProService.instance.hasFeature(
        MunjaProFeature.aiRideAnalysis,
      );

      final result = const AiRideAnalysisService().analyze(
        trip: trip,
        history: history,
        tier: isPro
            ? RideAnalysisTier.pro
            : RideAnalysisTier.free,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _rideAnalysis = result;
        _loadingRideAnalysis = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'RIDE SUMMARY AI ANALYSIS ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _rideAnalysis = null;
        _loadingRideAnalysis = false;
      });
    }
  }

  Future<void> _loadCrystalRewards() async {
    final uid = StorageService.currentUserId?.trim();

    if (mounted) {
      setState(() {
        _loadingCrystalRewards = true;
        _crystalRewardError = null;
      });
    }

    if (uid == null || uid.isEmpty) {
      if (!mounted) return;

      setState(() {
        _rideRewardClaim = null;
        _firstRideRewardClaim = null;
        _loadingCrystalRewards = false;
        _crystalRewardError = null;
      });

      return;
    }

    final rideId = _rideRewardId;
    final rewardService = CrystalRewardService.instance;

    Object? lastError;

    for (var attempt = 1;
        attempt <= _crystalRewardLoadAttempts;
        attempt++) {
      try {
        // First try to read rewards that were already granted by the central
        // completed-ride pipeline.
        var rideClaim =
            await rewardService.getRideCompletedClaim(
          uid: uid,
          rideId: rideId,
        );

        var firstRideClaim =
            await rewardService.getClaim(
          uid: uid,
          rewardId: 'first_ride',
        );

        // Self-healing fallback:
        //
        // If Ride Summary opened before the central ride reward side effect
        // finished (or that side effect was interrupted), safely request the
        // reward here. CrystalRewardService uses the reward document ID as an
        // idempotency key, so this can NEVER credit the same ride twice.
        if (rideClaim == null) {
          final rideResult =
              await rewardService.grantRideCompletedReward(
            uid: uid,
            rideId: rideId,
            amount: 2,
            distanceKm: distanceKm,
          );

          debugPrint(
            'RIDE SUMMARY CRYSTAL REPAIR: '
            'ride=$rideId '
            'status=${rideResult.status} '
            'amount=${rideResult.amount} '
            'balance=${rideResult.newBalance}',
          );

          rideClaim =
              await rewardService.getRideCompletedClaim(
            uid: uid,
            rideId: rideId,
          );
        }

        // First Ride Bonus uses one global reward ID (`first_ride`), so calling
        // this again is also safe. If another ride already owns the bonus,
        // CrystalRewardService simply returns alreadyClaimed.
        if (firstRideClaim == null) {
          final firstRideResult =
              await rewardService.grantFirstRideReward(
            uid: uid,
            rideId: rideId,
            amount: 20,
          );

          debugPrint(
            'RIDE SUMMARY FIRST RIDE REPAIR: '
            'ride=$rideId '
            'status=${firstRideResult.status} '
            'amount=${firstRideResult.amount} '
            'balance=${firstRideResult.newBalance}',
          );

          firstRideClaim =
              await rewardService.getClaim(
            uid: uid,
            rewardId: 'first_ride',
          );
        }

        final firstRideBelongsToThisTrip =
            firstRideClaim != null &&
            firstRideClaim.sourceId == rideId;

        if (!mounted) return;

        setState(() {
          _rideRewardClaim = rideClaim;
          _firstRideRewardClaim =
              firstRideBelongsToThisTrip
                  ? firstRideClaim
                  : null;
          _loadingCrystalRewards = false;
          _crystalRewardError = null;
        });

        debugPrint(
          'RIDE SUMMARY CRYSTALS LOADED: '
          'ride=$rideId '
          'rideReward=${rideClaim?.amount ?? 0} '
          'firstRide=${firstRideBelongsToThisTrip ? firstRideClaim?.amount ?? 0 : 0}',
        );

        return;
      } catch (error, stackTrace) {
        lastError = error;

        debugPrint(
          'RIDE SUMMARY CRYSTAL REWARD LOAD ERROR '
          'attempt=$attempt/$_crystalRewardLoadAttempts: $error',
        );
        debugPrint('$stackTrace');

        if (attempt < _crystalRewardLoadAttempts) {
          await Future<void>.delayed(
            Duration(
              milliseconds: 350 * attempt,
            ),
          );
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _rideRewardClaim = null;
      _firstRideRewardClaim = null;
      _loadingCrystalRewards = false;
      _crystalRewardError =
          lastError ?? StateError('Crystal rewards unavailable.');
    });
  }

  int get calories {
    const riderWeightKg = 75.0;
    final hours = trip.duration.inSeconds / 3600;

    final met = avgSpeedKmh < 16
        ? 4.0
        : avgSpeedKmh < 20
        ? 6.8
        : avgSpeedKmh < 25
        ? 8.0
        : 10.0;

    return (met * riderWeightKg * hours).round();
  }

  String get rideLabel {
    if (distanceKm >= 30) return t('longRide');
    if (distanceKm >= 15) return t('strongRide');
    if (distanceKm >= 5) return t('dailyRide');
    return t('quickRide');
  }

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }

    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _dateText() {
    final d = DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);

    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  List<String> get achievements {
    final items = <String>[];

    if (distanceKm >= 1) items.add(t('firstKilometer'));
    if (distanceKm >= 5) items.add(t('fiveKmRide'));
    if (distanceKm >= 10) items.add(t('tenKmStrong'));
    if (avgSpeedKmh >= 20) items.add(t('fastPace'));
    if (trip.duration.inMinutes >= 30) items.add(t('enduranceRide'));
    if (trip.path.length >= 10) items.add(t('routeRecorded'));

    if (items.isEmpty) items.add(t('rideCompleted'));

    return items;
  }

  LatLngBounds? _boundsFromPoints(List<LatLng> points) {
    if (points.isEmpty) return null;

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = trip.latLngPath;
    final hasRoute = points.length >= 2;
    final start = points.isNotEmpty
        ? points.first
        : const LatLng(55.6761, 12.5683);

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            20,
            18,
            20,
            bottomWheelSafePadding,
          ),
          children: [
            _Header(
              title: t('rideSaved'),
              dateText: _dateText(),
              savedLabel: t('saved'),
              onClose: () => Navigator.of(context).maybePop(),
            ),

            const SizedBox(height: 18),

            _ScoreHeroCard(
              rideLabel: rideLabel,
              rideScoreLabel: t('rideScore'),
              distanceKm: distanceKm,
              score: rideScore,
              durationLabel: t('time'),
              durationText: _durationText(trip.duration),
              avgLabel: t('avg'),
              avgSpeedKmh: avgSpeedKmh,
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _PremiumMetric(
                    icon: Icons.local_fire_department_rounded,
                    label: t('calories'),
                    value: '$calories',
                    unit: 'kcal',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PremiumMetric(
                    icon: Icons.bolt_rounded,
                    label: 'XP',
                    value: '$xp',
                    unit: '',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: _CrystalRewardMetric(
                    label: t('mCrystals'),
                    loading: _loadingCrystalRewards,
                    hasError: _crystalRewardError != null,
                    totalEarned: _totalEarnedCrystals,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PremiumMetric(
                    icon: Icons.route_rounded,
                    label: t('routePoints'),
                    value: '${trip.path.length}',
                    unit: '',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _CrystalRewardsCard(
              loading: _loadingCrystalRewards,
              hasError: _crystalRewardError != null,
              rideCompletedAmount: _rideCompletedCrystals,
              firstRideBonusAmount: _firstRideBonusCrystals,
              totalEarned: _totalEarnedCrystals,
              hasAnyReward: _hasAnyCrystalReward,
              onRetry: _loadCrystalRewards,
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: t('route'),
              subtitle: hasRoute ? t('routeSavedSubtitle') : t('noRouteSaved'),
              child: hasRoute
                  ? _RouteMap(
                      points: points,
                      start: start,
                      bounds: _boundsFromPoints(points),
                    )
                  : const _NoRouteState(),
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: t('achievements'),
              subtitle: t('achievementsSubtitle'),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: achievements
                    .map((item) => _AchievementChip(label: item))
                    .toList(),
              ),
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: AppText.t('rideSummaryAiAnalysis'),
              subtitle: MunjaProService.instance.hasFeature(
                MunjaProFeature.aiRideAnalysis,
              )
                  ? AppText.t('rideSummaryAiProSubtitle')
                  : AppText.t('rideSummaryAiFreeSubtitle'),
              child: _RideAnalysisCard(
                loading: _loadingRideAnalysis,
                result: _rideAnalysis,
                isPro:
                    MunjaProService.instance.hasFeature(
                  MunjaProFeature.aiRideAnalysis,
                ),
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.check_rounded),
                label: Text(
                  t('done'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideAnalysisCard extends StatelessWidget {
  const _RideAnalysisCard({
    required this.loading,
    required this.result,
    required this.isPro,
  });

  final bool loading;
  final RideAnalysisResult? result;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MunjaColors.mint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppText.t('rideSummaryAnalyzing'),
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final analysis = result;

    if (analysis == null) {
      return Text(
        AppText.t('rideSummaryAnalysisUnavailable'),
        style: const TextStyle(
          color: MunjaColors.textSoft,
          fontSize: 12,
          height: 1.4,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: MunjaColors.mint,
                size: 21,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    isPro
                        ? AppText.t('rideSummaryProAnalysis')
                        : AppText.t('rideSummaryRideRecap'),
                    style: const TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    analysis.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            if (isPro)
              const Icon(
                Icons.verified_rounded,
                color: MunjaColors.mint,
                size: 20,
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          analysis.summary,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _AnalysisMetric(
                label: AppText.t('rideSummaryConsistency'),
                value: '${analysis.consistencyScore}/100',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AnalysisMetric(
                label: AppText.t('rideSummaryTrend'),
                value: analysis.isAboveUsualSpeed
                    ? AppText.t('rideSummaryFaster')
                    : analysis.isAboveUsualDistance
                        ? AppText.t('rideSummaryLonger')
                        : AppText.t('rideSummarySteady'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.055),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: MunjaColors.mint,
                size: 19,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  analysis.recommendation,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 11.5,
                    height: 1.45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnalysisMetric extends StatelessWidget {
  const _AnalysisMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
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
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMap extends StatefulWidget {
  final List<LatLng> points;
  final LatLng start;
  final LatLngBounds? bounds;

  const _RouteMap({
    required this.points,
    required this.start,
    required this.bounds,
  });

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<_RouteMap> {
  GoogleMapController? controller;

  Future<void> _fitRoute() async {
    final bounds = widget.bounds;
    final mapController = controller;

    if (bounds == null || mapController == null) return;

    await Future<void>.delayed(const Duration(milliseconds: 350));

    try {
      await mapController.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 56),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: SizedBox(
        height: 300,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: widget.start, zoom: 14),
          zoomControlsEnabled: false,
          myLocationButtonEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: false,
          onMapCreated: (mapController) {
            controller = mapController;
            _fitRoute();
          },
          markers: {
            Marker(
              markerId: const MarkerId('start'),
              position: widget.points.first,
              infoWindow: InfoWindow(title: AppText.t('start')),
            ),
            Marker(
              markerId: const MarkerId('finish'),
              position: widget.points.last,
              infoWindow: InfoWindow(title: AppText.t('finish')),
            ),
          },
          polylines: {
            Polyline(
              polylineId: const PolylineId('summary_route'),
              points: widget.points,
              width: 6,
              color: MunjaColors.mint,
            ),
          },
        ),
      ),
    );
  }
}

class _NoRouteState extends StatelessWidget {
  const _NoRouteState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          const Icon(Icons.route_rounded, color: MunjaColors.mint, size: 34),
          const SizedBox(height: 12),
          Text(
            AppText.t('noRouteSaved'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            AppText.t('noRouteSavedSubtitle'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
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

class _Header extends StatelessWidget {
  final String title;
  final String dateText;
  final String savedLabel;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.dateText,
    required this.savedLabel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CloseButton(onTap: onClose),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppText.t('rideSummaryHeader'),
                style: const TextStyle(
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
              const SizedBox(height: 6),
              Text(
                dateText,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: MunjaColors.mint.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MunjaColors.mint.withOpacity(0.32)),
          ),
          child: Text(
            savedLabel.toUpperCase(),
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CloseButton({required this.onTap});

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
          child: const Icon(Icons.close_rounded, color: Colors.white),
        ),
      ),
    );
  }
}

class _ScoreHeroCard extends StatelessWidget {
  final String rideLabel;
  final String rideScoreLabel;
  final int score;
  final double distanceKm;
  final String durationLabel;
  final String durationText;
  final String avgLabel;
  final double avgSpeedKmh;

  const _ScoreHeroCard({
    required this.rideLabel,
    required this.rideScoreLabel,
    required this.score,
    required this.distanceKm,
    required this.durationLabel,
    required this.durationText,
    required this.avgLabel,
    required this.avgSpeedKmh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _premiumDecoration(glow: true),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: MunjaColors.mint,
                size: 24,
              ),
              const SizedBox(width: 10),
              Text(
                rideLabel.toUpperCase(),
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                rideScoreLabel.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        distanceKm.toStringAsFixed(2),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 62,
                          height: 0.92,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
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
              ),
              _ScoreCircle(score: score),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroMiniMetric(
                  label: durationLabel,
                  value: durationText,
                  icon: Icons.timer_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMiniMetric(
                  label: avgLabel,
                  value: '${avgSpeedKmh.toStringAsFixed(1)} ${AppText.t('speedUnitShort')}',
                  icon: Icons.speed_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreCircle extends StatelessWidget {
  final int score;

  const _ScoreCircle({required this.score});

  @override
  Widget build(BuildContext context) {
    final progress = (score / 100).clamp(0.0, 1.0);

    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            strokeWidth: 8,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: const AlwaysStoppedAnimation<Color>(MunjaColors.mint),
          ),
          Text(
            '$score',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _HeroMiniMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 74,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint, size: 19),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 4),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const _PremiumMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(15),
      decoration: _premiumDecoration(),
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
                    fontSize: 24,
                    height: 0.96,
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
                      color: MunjaColors.mint,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CrystalRewardMetric extends StatelessWidget {
  const _CrystalRewardMetric({
    required this.label,
    required this.loading,
    required this.hasError,
    required this.totalEarned,
  });

  final String label;
  final bool loading;
  final bool hasError;
  final int totalEarned;

  @override
  Widget build(BuildContext context) {
    final value = loading
        ? '...'
        : hasError
            ? '—'
            : '+$totalEarned';

    return Container(
      height: 104,
      padding: const EdgeInsets.all(15),
      decoration: _premiumDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.diamond_rounded,
            color: MunjaColors.mint,
            size: 21,
          ),
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
                    fontSize: 24,
                    height: 0.96,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ),
              if (!loading && !hasError && totalEarned > 0) ...[
                const SizedBox(width: 4),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text(
                    '◆',
                    style: TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _CrystalRewardsCard extends StatelessWidget {
  const _CrystalRewardsCard({
    required this.loading,
    required this.hasError,
    required this.rideCompletedAmount,
    required this.firstRideBonusAmount,
    required this.totalEarned,
    required this.hasAnyReward,
    required this.onRetry,
  });

  final bool loading;
  final bool hasError;
  final int rideCompletedAmount;
  final int firstRideBonusAmount;
  final int totalEarned;
  final bool hasAnyReward;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.86),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.07),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.11),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.diamond_rounded,
                  color: MunjaColors.mint,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppText.t('rideRewards'),
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Munja Crystals',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MunjaColors.mint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 17),
          if (loading)
            Text(
              AppText.t('loadingEarnedRewards'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            )
          else if (hasError)
            _RewardErrorState(onRetry: onRetry)
          else if (!hasAnyReward)
            Text(
              AppText.t('noCrystalRewardRide'),
              style: TextStyle(
                color: Colors.white.withOpacity(0.52),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            )
          else ...[
            if (rideCompletedAmount > 0)
              _RewardLine(
                icon: Icons.check_circle_rounded,
                label: AppText.t('rideCompletedReward'),
                amount: rideCompletedAmount,
              ),
            if (rideCompletedAmount > 0 && firstRideBonusAmount > 0)
              const SizedBox(height: 10),
            if (firstRideBonusAmount > 0)
              _RewardLine(
                icon: Icons.emoji_events_rounded,
                label: AppText.t('firstRideBonus'),
                amount: firstRideBonusAmount,
              ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.09),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: MunjaColors.mint.withOpacity(0.19),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    AppText.t('totalEarned'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.58),
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '+$totalEarned ◆',
                    style: const TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewardLine extends StatelessWidget {
  const _RewardLine({
    required this.icon,
    required this.label,
    required this.amount,
  });

  final IconData icon;
  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '+$amount ◆',
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RewardErrorState extends StatelessWidget {
  const _RewardErrorState({
    required this.onRetry,
  });

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Colors.orangeAccent,
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            AppText.t('crystalRewardsLoadFailed'),
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: () => onRetry(),
          child: Text(
            AppText.t('retry'),
            style: const TextStyle(
              color: MunjaColors.mint,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _premiumDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _CoachInsight extends StatelessWidget {
  final double distanceKm;
  final double avgSpeedKmh;
  final int rideScore;

  const _CoachInsight({
    required this.distanceKm,
    required this.avgSpeedKmh,
    required this.rideScore,
  });

  @override
  Widget build(BuildContext context) {
    String message;

    if (distanceKm < 1) {
      message = AppText.t('coachShortRide');
    } else if (rideScore >= 80) {
      message = AppText.t('coachStrongRide');
    } else if (avgSpeedKmh >= 20) {
      message = AppText.t('coachFastRide');
    } else {
      message = AppText.t('coachCalmRide');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.26)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AchievementChip extends StatelessWidget {
  final String label;

  const _AchievementChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            color: MunjaColors.mint,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
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
    borderRadius: BorderRadius.circular(30),
    border: Border.all(color: Colors.white.withOpacity(0.075)),
    boxShadow: glow
        ? [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(0.15),
              blurRadius: 38,
              spreadRadius: 1,
              offset: const Offset(0, 16),
            ),
          ]
        : null,
  );
}
