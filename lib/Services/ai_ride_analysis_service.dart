import 'dart:math';

import '../models/trip.dart';

enum RideAnalysisTier {
  free,
  pro,
}

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

  RideAnalysisResult analyze({
    required Trip trip,
    required List<Trip> history,
    required RideAnalysisTier tier,
  }) {
    final distanceKm = trip.distanceM / 1000;
    final durationHours = trip.duration.inSeconds / 3600;
    final averageSpeedKmh =
        durationHours <= 0 ? 0.0 : distanceKm / durationHours;

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

    final averageHistoricDistance =
        _average(historicalDistances);
    final averageHistoricSpeed =
        _average(historicalSpeeds);

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

    final total = values.fold<double>(
      0,
      (sum, value) => sum + value,
    );

    return total / values.length;
  }

  int _consistencyScore({
    required Trip trip,
    required double averageSpeedKmh,
  }) {
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
      return 'Strong endurance ride';
    }

    if (averageSpeedKmh >= 22) {
      return 'Fast ride';
    }

    if (distanceKm >= 8) {
      return 'Solid ride';
    }

    return 'Ride complete';
  }

  String _freeSummary({
    required double distanceKm,
    required double averageSpeedKmh,
    required Duration duration,
  }) {
    final minutes = duration.inMinutes;

    return 'You completed ${distanceKm.toStringAsFixed(1)} km '
        'in $minutes min with an average speed of '
        '${averageSpeedKmh.toStringAsFixed(1)} km/h.';
  }

  String _freeRecommendation({
    required double distanceKm,
    required double averageSpeedKmh,
  }) {
    if (distanceKm < 5) {
      return 'For the next ride, try adding a few more steady kilometres.';
    }

    if (averageSpeedKmh < 14) {
      return 'Focus on a smooth, sustainable pace rather than short speed bursts.';
    }

    return 'Keep building consistency and add distance gradually.';
  }

  String _proTitle({
    required bool isAboveUsualDistance,
    required bool isAboveUsualSpeed,
    required int consistencyScore,
  }) {
    if (isAboveUsualDistance && isAboveUsualSpeed) {
      return 'Above your normal performance';
    }

    if (isAboveUsualSpeed) {
      return 'Faster than your usual pace';
    }

    if (isAboveUsualDistance) {
      return 'Longer than your usual ride';
    }

    if (consistencyScore >= 85) {
      return 'Very consistent ride';
    }

    return 'Personal ride analysis';
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
      'This ride was ${distanceKm.toStringAsFixed(1)} km at '
          '${averageSpeedKmh.toStringAsFixed(1)} km/h.',
    ];

    if (averageHistoricDistance > 0) {
      final distanceDelta =
          ((distanceKm / averageHistoricDistance) - 1) * 100;

      parts.add(
        'Distance was ${distanceDelta.abs().toStringAsFixed(0)}% '
        '${distanceDelta >= 0 ? 'above' : 'below'} your recent average.',
      );
    }

    if (averageHistoricSpeed > 0) {
      final speedDelta =
          ((averageSpeedKmh / averageHistoricSpeed) - 1) * 100;

      parts.add(
        'Average speed was ${speedDelta.abs().toStringAsFixed(0)}% '
        '${speedDelta >= 0 ? 'above' : 'below'} your usual pace.',
      );
    }

    parts.add(
      'Ride consistency score: $consistencyScore/100.',
    );

    if (isAboveUsualDistance && isAboveUsualSpeed) {
      parts.add(
        'You extended both distance and pace in the same session.',
      );
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
      return 'Next ride, focus on smoother speed control and earlier braking.';
    }

    if (isLongerThanUsual && isAboveUsualSpeed) {
      return 'Use the next ride as a lighter recovery session to balance the training load.';
    }

    if (consistencyScore < 70) {
      return 'Try starting slightly easier and hold a steadier pace through the middle of the ride.';
    }

    if (isAboveUsualSpeed) {
      return 'Your pace is progressing. Keep the next ride controlled and repeat the same effort.';
    }

    return 'Build on this ride by adding 5–10% distance while keeping the same smooth pace.';
  }
}
