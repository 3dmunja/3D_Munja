import 'dart:math';

import '../models/trip.dart';
import '../Core/localization/app_text.dart';

enum RideAnalysisTier { free, pro }

class RideAnalysisResult {
  const RideAnalysisResult({
    required this.title,
    required this.summary,
    required this.recommendation,
    required this.consistencyScore,
    required this.isAboveUsualDistance,
    required this.isAboveUsualSpeed,
    required this.isLongerThanUsual,
  });

  final String title;
  final String summary;
  final String recommendation;
  final int consistencyScore;
  final bool isAboveUsualDistance;
  final bool isAboveUsualSpeed;
  final bool isLongerThanUsual;
}

class AiRideAnalysisService {
  const AiRideAnalysisService();

  String _t(
    String key, [
    Map<String, String> values = const <String, String>{},
  ]) {
    var text = AppText.t(key);

    for (final entry in values.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }

    return text;
  }

  RideAnalysisResult analyze({
    required Trip trip,
    required List<Trip> history,
    required RideAnalysisTier tier,
  }) {
    final distanceKm = trip.distanceM / 1000;
    final durationHours = trip.duration.inSeconds / 3600;
    final averageSpeedKmh = durationHours <= 0
        ? 0.0
        : distanceKm / durationHours;

    final previousTrips = history
        .where(
          (candidate) =>
              candidate.startedAtMs != trip.startedAtMs ||
              candidate.endedAtMs != trip.endedAtMs,
        )
        .toList(growable: false);

    final historicalDistances = previousTrips
        .map((item) => item.distanceM / 1000)
        .where((value) => value.isFinite && value > 0)
        .toList(growable: false);

    final historicalSpeeds = previousTrips
        .map((item) {
          final hours = item.duration.inSeconds / 3600;
          if (hours <= 0) {
            return 0.0;
          }
          return (item.distanceM / 1000) / hours;
        })
        .where((value) => value.isFinite && value > 0)
        .toList(growable: false);

    final averageHistoricDistance = _average(historicalDistances);
    final averageHistoricSpeed = _average(historicalSpeeds);

    final isAboveUsualDistance =
        averageHistoricDistance > 0 &&
        distanceKm >= averageHistoricDistance * 1.10;

    final isLongerThanUsual =
        averageHistoricDistance > 0 &&
        distanceKm >= averageHistoricDistance * 1.25;

    final isAboveUsualSpeed =
        averageHistoricSpeed > 0 &&
        averageSpeedKmh >= averageHistoricSpeed * 1.08;

    final consistencyScore = _consistencyScore(
      trip: trip,
      averageSpeedKmh: averageSpeedKmh,
    );

    if (tier == RideAnalysisTier.free) {
      return RideAnalysisResult(
        title: _freeTitle(
          distanceKm: distanceKm,
          averageSpeedKmh: averageSpeedKmh,
        ),
        summary: _freeSummary(
          distanceKm: distanceKm,
          averageSpeedKmh: averageSpeedKmh,
          duration: trip.duration,
        ),
        recommendation: _freeRecommendation(
          distanceKm: distanceKm,
          averageSpeedKmh: averageSpeedKmh,
        ),
        consistencyScore: consistencyScore,
        isAboveUsualDistance: false,
        isAboveUsualSpeed: false,
        isLongerThanUsual: false,
      );
    }

    return RideAnalysisResult(
      title: _proTitle(
        isAboveUsualDistance: isAboveUsualDistance,
        isAboveUsualSpeed: isAboveUsualSpeed,
        consistencyScore: consistencyScore,
      ),
      summary: _proSummary(
        distanceKm: distanceKm,
        averageSpeedKmh: averageSpeedKmh,
        averageHistoricDistance: averageHistoricDistance,
        averageHistoricSpeed: averageHistoricSpeed,
        isAboveUsualDistance: isAboveUsualDistance,
        isAboveUsualSpeed: isAboveUsualSpeed,
        consistencyScore: consistencyScore,
      ),
      recommendation: _proRecommendation(
        isLongerThanUsual: isLongerThanUsual,
        isAboveUsualSpeed: isAboveUsualSpeed,
        consistencyScore: consistencyScore,
        hardBrakes: trip.hardBrakes,
      ),
      consistencyScore: consistencyScore,
      isAboveUsualDistance: isAboveUsualDistance,
      isAboveUsualSpeed: isAboveUsualSpeed,
      isLongerThanUsual: isLongerThanUsual,
    );
  }

  double _average(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }

    final total = values.fold<double>(0, (sum, value) => sum + value);

    return total / values.length;
  }

  int _consistencyScore({required Trip trip, required double averageSpeedKmh}) {
    var score = 70;

    if (trip.duration.inMinutes >= 20) {
      score += 8;
    }

    if (trip.distanceM >= 5000) {
      score += 8;
    }

    if (averageSpeedKmh >= 15) {
      score += 6;
    }

    score -= min(trip.hardBrakes * 3, 18);

    return score.clamp(35, 100);
  }

  String _freeTitle({
    required double distanceKm,
    required double averageSpeedKmh,
  }) {
    if (distanceKm >= 25) {
      return _t('rideAnalysisStrongEndurance');
    }

    if (averageSpeedKmh >= 22) {
      return _t('rideAnalysisFastRide');
    }

    if (distanceKm >= 8) {
      return _t('rideAnalysisSolidRide');
    }

    return _t('rideAnalysisRideComplete');
  }

  String _freeSummary({
    required double distanceKm,
    required double averageSpeedKmh,
    required Duration duration,
  }) {
    final minutes = duration.inMinutes;

    return _t('rideAnalysisFreeSummary', {
      'distance': distanceKm.toStringAsFixed(1),
      'minutes': '$minutes',
      'speed': averageSpeedKmh.toStringAsFixed(1),
    });
  }

  String _freeRecommendation({
    required double distanceKm,
    required double averageSpeedKmh,
  }) {
    if (distanceKm < 5) {
      return _t('rideAnalysisAddSteadyKilometres');
    }

    if (averageSpeedKmh < 14) {
      return _t('rideAnalysisSmoothSustainablePace');
    }

    return _t('rideAnalysisBuildConsistency');
  }

  String _proTitle({
    required bool isAboveUsualDistance,
    required bool isAboveUsualSpeed,
    required int consistencyScore,
  }) {
    if (isAboveUsualDistance && isAboveUsualSpeed) {
      return _t('rideAnalysisAboveNormalPerformance');
    }

    if (isAboveUsualSpeed) {
      return _t('rideAnalysisFasterThanUsual');
    }

    if (isAboveUsualDistance) {
      return _t('rideAnalysisLongerThanUsual');
    }

    if (consistencyScore >= 85) {
      return _t('rideAnalysisVeryConsistent');
    }

    return _t('rideAnalysisPersonalAnalysis');
  }

  String _proSummary({
    required double distanceKm,
    required double averageSpeedKmh,
    required double averageHistoricDistance,
    required double averageHistoricSpeed,
    required bool isAboveUsualDistance,
    required bool isAboveUsualSpeed,
    required int consistencyScore,
  }) {
    final parts = <String>[
      _t('rideAnalysisProBaseSummary', {
        'distance': distanceKm.toStringAsFixed(1),
        'speed': averageSpeedKmh.toStringAsFixed(1),
      }),
    ];

    if (averageHistoricDistance > 0) {
      final distanceDelta = ((distanceKm / averageHistoricDistance) - 1) * 100;

      parts.add(
        _t(
          distanceDelta >= 0
              ? 'rideAnalysisDistanceAbove'
              : 'rideAnalysisDistanceBelow',
          {'percent': distanceDelta.abs().toStringAsFixed(0)},
        ),
      );
    }

    if (averageHistoricSpeed > 0) {
      final speedDelta = ((averageSpeedKmh / averageHistoricSpeed) - 1) * 100;

      parts.add(
        _t(
          speedDelta >= 0 ? 'rideAnalysisSpeedAbove' : 'rideAnalysisSpeedBelow',
          {'percent': speedDelta.abs().toStringAsFixed(0)},
        ),
      );
    }

    parts.add(
      _t('rideAnalysisConsistencyScore', {'score': '$consistencyScore'}),
    );

    if (isAboveUsualDistance && isAboveUsualSpeed) {
      parts.add(_t('rideAnalysisExtendedDistanceAndPace'));
    }

    return parts.join(' ');
  }

  String _proRecommendation({
    required bool isLongerThanUsual,
    required bool isAboveUsualSpeed,
    required int consistencyScore,
    required int hardBrakes,
  }) {
    if (hardBrakes >= 4) {
      return _t('rideAnalysisSmootherBraking');
    }

    if (isLongerThanUsual && isAboveUsualSpeed) {
      return _t('rideAnalysisRecoverySession');
    }

    if (consistencyScore < 70) {
      return _t('rideAnalysisStartEasier');
    }

    if (isAboveUsualSpeed) {
      return _t('rideAnalysisPaceProgressing');
    }

    return _t('rideAnalysisAddDistance');
  }
}
