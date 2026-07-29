import '../models/trip.dart';

enum RideCoachMood { recovery, easy, balanced, fitness, challenge }

extension RideCoachMoodX on RideCoachMood {
  String get title {
    switch (this) {
      case RideCoachMood.recovery:
        return 'Recovery';
      case RideCoachMood.easy:
        return 'Easy Ride';
      case RideCoachMood.balanced:
        return 'Balanced';
      case RideCoachMood.fitness:
        return 'Fitness';
      case RideCoachMood.challenge:
        return 'Challenge';
    }
  }

  String get emoji {
    switch (this) {
      case RideCoachMood.recovery:
        return '🧘';
      case RideCoachMood.easy:
        return '🌿';
      case RideCoachMood.balanced:
        return '⚖️';
      case RideCoachMood.fitness:
        return '⚡';
      case RideCoachMood.challenge:
        return '🔥';
    }
  }
}

class RideCoachRecommendation {
  final RideCoachMood mood;
  final int readinessScore;
  final int fatigueScore;
  final int consistencyScore;
  final double suggestedDistanceKm;
  final Duration suggestedDuration;
  final String title;
  final String message;
  final List<String> tips;

  const RideCoachRecommendation({
    required this.mood,
    required this.readinessScore,
    required this.fatigueScore,
    required this.consistencyScore,
    required this.suggestedDistanceKm,
    required this.suggestedDuration,
    required this.title,
    required this.message,
    required this.tips,
  });

  String get durationText {
    final h = suggestedDuration.inHours;
    final m = suggestedDuration.inMinutes.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get rideTypeText => '${mood.emoji} ${mood.title}';

  factory RideCoachRecommendation.fromTrips(List<Trip> trips) {
    if (trips.isEmpty) {
      return const RideCoachRecommendation(
        mood: RideCoachMood.easy,
        readinessScore: 72,
        fatigueScore: 18,
        consistencyScore: 0,
        suggestedDistanceKm: 3.5,
        suggestedDuration: Duration(minutes: 15),
        title: 'Start with an easy ride',
        message:
            'Munja does not have ride history yet. Start simple and build your rhythm.',
        tips: [
          'Keep the first ride short.',
          'Focus on comfort, not speed.',
          'Try an easy scenic route.',
        ],
      );
    }

    final sorted = [...trips]
      ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));

    final now = DateTime.now();

    final lastRide = sorted.first;
    final lastRideDate = DateTime.fromMillisecondsSinceEpoch(
      lastRide.startedAtMs,
    );

    final daysSinceLastRide = now.difference(lastRideDate).inDays;

    final last7Days = sorted.where((trip) {
      final date = DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);
      return now.difference(date).inDays <= 7;
    }).toList();

    final weeklyKm = last7Days.fold<double>(
      0,
      (sum, trip) => sum + trip.distanceM / 1000,
    );

    final totalKm = sorted.fold<double>(
      0,
      (sum, trip) => sum + trip.distanceM / 1000,
    );

    final avgRideKm = totalKm / sorted.length;

    final consistency = _calculateConsistency(sorted);
    final fatigue = _calculateFatigue(
      weeklyKm: weeklyKm,
      daysSinceLastRide: daysSinceLastRide,
      rideCount7d: last7Days.length,
    );

    final readiness = (100 - fatigue + (consistency * 0.28))
        .clamp(0, 100)
        .round();

    if (fatigue >= 72) {
      return RideCoachRecommendation(
        mood: RideCoachMood.recovery,
        readinessScore: readiness,
        fatigueScore: fatigue,
        consistencyScore: consistency,
        suggestedDistanceKm: 2.5,
        suggestedDuration: const Duration(minutes: 12),
        title: 'Recovery ride recommended',
        message:
            'You have been riding hard lately. A short relaxed ride is the best move today.',
        tips: const [
          'Keep speed low.',
          'Avoid long climbs.',
          'Stop if your legs feel heavy.',
        ],
      );
    }

    if (daysSinceLastRide >= 5) {
      return RideCoachRecommendation(
        mood: RideCoachMood.easy,
        readinessScore: readiness,
        fatigueScore: fatigue,
        consistencyScore: consistency,
        suggestedDistanceKm: avgRideKm.clamp(3.0, 7.0),
        suggestedDuration: const Duration(minutes: 20),
        title: 'Ease back into it',
        message:
            'It has been a few days since your last ride. Start smooth and rebuild rhythm.',
        tips: const [
          'Choose an easy route.',
          'Warm up slowly.',
          'Focus on consistency.',
        ],
      );
    }

    if (readiness >= 82 && weeklyKm < 25) {
      return RideCoachRecommendation(
        mood: RideCoachMood.challenge,
        readinessScore: readiness,
        fatigueScore: fatigue,
        consistencyScore: consistency,
        suggestedDistanceKm: (avgRideKm * 1.45).clamp(8.0, 18.0),
        suggestedDuration: const Duration(minutes: 45),
        title: 'You are ready for a challenge',
        message:
            'Your readiness looks strong. Today is a good day to push distance or pace.',
        tips: const [
          'Pick a challenge route.',
          'Keep a steady tempo.',
          'Hydrate before the ride.',
        ],
      );
    }

    if (readiness >= 68) {
      return RideCoachRecommendation(
        mood: RideCoachMood.fitness,
        readinessScore: readiness,
        fatigueScore: fatigue,
        consistencyScore: consistency,
        suggestedDistanceKm: (avgRideKm * 1.15).clamp(5.0, 12.0),
        suggestedDuration: const Duration(minutes: 30),
        title: 'Fitness ride looks ideal',
        message:
            'You are in a good zone today. A moderate ride will improve fitness without overdoing it.',
        tips: const [
          'Ride at a steady pace.',
          'Add one faster segment.',
          'Cool down for 5 minutes.',
        ],
      );
    }

    return RideCoachRecommendation(
      mood: RideCoachMood.balanced,
      readinessScore: readiness,
      fatigueScore: fatigue,
      consistencyScore: consistency,
      suggestedDistanceKm: avgRideKm.clamp(4.0, 9.0),
      suggestedDuration: const Duration(minutes: 25),
      title: 'Balanced ride recommended',
      message:
          'A normal ride is the best fit today. Keep it enjoyable and consistent.',
      tips: const [
        'Choose a familiar route.',
        'Do not chase top speed.',
        'Finish with energy left.',
      ],
    );
  }

  static int _calculateConsistency(List<Trip> trips) {
    final now = DateTime.now();

    final rideDays = trips
        .map((trip) => DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs))
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    int activeDays = 0;

    for (int i = 0; i < 14; i++) {
      final day = now.subtract(Duration(days: i));
      final normalized = DateTime(day.year, day.month, day.day);

      if (rideDays.contains(normalized)) {
        activeDays++;
      }
    }

    return ((activeDays / 14) * 100).round().clamp(0, 100);
  }

  static int _calculateFatigue({
    required double weeklyKm,
    required int daysSinceLastRide,
    required int rideCount7d,
  }) {
    int fatigue = 0;

    fatigue += (weeklyKm * 2.2).round();
    fatigue += rideCount7d * 8;

    if (daysSinceLastRide == 0) fatigue += 18;
    if (daysSinceLastRide == 1) fatigue += 8;
    if (daysSinceLastRide >= 3) fatigue -= 14;

    return fatigue.clamp(0, 100);
  }
}
