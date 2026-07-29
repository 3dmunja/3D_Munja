import '../models/home_ai_state.dart';
import '../models/trip.dart';

class HomeAIEngine {
  HomeAIEngine._();

  static final HomeAIEngine instance = HomeAIEngine._();

  HomeAIState generate({
    required List<Trip> trips,
    required bool isRideActive,
  }) {
    if (isRideActive) {
      return const HomeAIState(
        mood: HomeAIMood.ready,
        title: 'Ride in progress',
        message:
            'Munja is actively tracking your ride and monitoring performance.',
        primaryActionLabel: 'Open live ride',
        secondaryActionLabel: 'View map',
        readinessScore: 100,
        fatigueScore: 0,
        suggestedDistanceKm: 0,
        showCoachCard: false,
        showRoutePlannerCard: false,
        showRecoveryHint: false,
        showChallengeHint: false,
        chips: ['Live tracking', 'GPS active', 'Ride recording'],
      );
    }

    if (trips.isEmpty) {
      return const HomeAIState(
        mood: HomeAIMood.ready,
        title: 'Welcome to Munja',
        message:
            'Start your first ride and Munja will begin learning your cycling style.',
        primaryActionLabel: 'Start first ride',
        secondaryActionLabel: 'Explore routes',
        readinessScore: 72,
        fatigueScore: 14,
        suggestedDistanceKm: 3.0,
        showCoachCard: true,
        showRoutePlannerCard: true,
        showRecoveryHint: false,
        showChallengeHint: false,
        chips: ['Beginner friendly', 'Easy routes', 'Smart tracking'],
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

    final weeklyTrips = sorted.where((trip) {
      final d = DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);
      return now.difference(d).inDays <= 7;
    }).toList();

    final weeklyKm = weeklyTrips.fold<double>(
      0,
      (sum, t) => sum + t.distanceM / 1000,
    );

    final totalKm = sorted.fold<double>(
      0,
      (sum, t) => sum + t.distanceM / 1000,
    );

    final averageKm = totalKm / sorted.length;

    final consistency = _consistencyScore(sorted);

    final fatigue = _fatigueScore(
      weeklyKm: weeklyKm,
      weeklyRideCount: weeklyTrips.length,
      daysSinceLastRide: daysSinceLastRide,
    );

    final readiness = (100 - fatigue + (consistency * 0.25))
        .clamp(0, 100)
        .round();

    final currentHour = now.hour;

    final eveningRide = currentHour >= 17 && currentHour <= 22;
    final morningRide = currentHour >= 5 && currentHour <= 10;

    if (fatigue >= 72) {
      return HomeAIState(
        mood: HomeAIMood.recovery,
        title: 'Recovery ride recommended',
        message:
            'You have pushed hard recently. Munja suggests a short relaxed recovery ride.',
        primaryActionLabel: 'Recovery ride',
        secondaryActionLabel: 'Easy route',
        readinessScore: readiness,
        fatigueScore: fatigue,
        suggestedDistanceKm: 2.5,
        showCoachCard: true,
        showRoutePlannerCard: true,
        showRecoveryHint: true,
        showChallengeHint: false,
        chips: const ['Low intensity', 'Recovery', 'Relaxed pace'],
      );
    }

    if (daysSinceLastRide >= 5) {
      return HomeAIState(
        mood: HomeAIMood.comeback,
        title: 'Let’s get moving again',
        message:
            'It has been a few days since your last ride. Start smooth and rebuild momentum.',
        primaryActionLabel: 'Easy comeback ride',
        secondaryActionLabel: 'Scenic route',
        readinessScore: readiness,
        fatigueScore: fatigue,
        suggestedDistanceKm: averageKm.clamp(3.0, 7.0),
        showCoachCard: true,
        showRoutePlannerCard: true,
        showRecoveryHint: false,
        showChallengeHint: false,
        chips: const ['Easy start', 'Comfort ride', 'Consistency'],
      );
    }

    if (readiness >= 84 && weeklyKm < 25) {
      return HomeAIState(
        mood: HomeAIMood.challenge,
        title: 'Challenge ride ready',
        message:
            'Your readiness is high today. This is a strong day for a longer or harder ride.',
        primaryActionLabel: 'Start challenge ride',
        secondaryActionLabel: 'Generate hard route',
        readinessScore: readiness,
        fatigueScore: fatigue,
        suggestedDistanceKm: (averageKm * 1.45).clamp(8.0, 18.0),
        showCoachCard: true,
        showRoutePlannerCard: true,
        showRecoveryHint: false,
        showChallengeHint: true,
        chips: const ['High readiness', 'Performance day', 'Push harder'],
      );
    }

    if (eveningRide) {
      return HomeAIState(
        mood: HomeAIMood.ready,
        title: 'Evening fitness ride',
        message:
            'Your recent activity suggests this is a good time for a moderate workout ride.',
        primaryActionLabel: 'Start fitness ride',
        secondaryActionLabel: 'Fitness route',
        readinessScore: readiness,
        fatigueScore: fatigue,
        suggestedDistanceKm: (averageKm * 1.1).clamp(5.0, 12.0),
        showCoachCard: true,
        showRoutePlannerCard: true,
        showRecoveryHint: false,
        showChallengeHint: false,
        chips: const ['Workout', 'Tempo pace', 'Evening ride'],
      );
    }

    if (morningRide) {
      return HomeAIState(
        mood: HomeAIMood.scenic,
        title: 'Morning scenic ride',
        message:
            'A lighter scenic ride matches your current rhythm and recovery level.',
        primaryActionLabel: 'Start scenic ride',
        secondaryActionLabel: 'Find scenic route',
        readinessScore: readiness,
        fatigueScore: fatigue,
        suggestedDistanceKm: averageKm.clamp(4.0, 9.0),
        showCoachCard: true,
        showRoutePlannerCard: true,
        showRecoveryHint: false,
        showChallengeHint: false,
        chips: const ['Morning energy', 'Scenic', 'Balanced'],
      );
    }

    return HomeAIState(
      mood: HomeAIMood.ready,
      title: 'Ready for today’s ride',
      message:
          'Munja recommends a balanced ride based on your recent activity.',
      primaryActionLabel: 'Start ride',
      secondaryActionLabel: 'Plan route',
      readinessScore: readiness,
      fatigueScore: fatigue,
      suggestedDistanceKm: averageKm.clamp(5.0, 10.0),
      showCoachCard: true,
      showRoutePlannerCard: true,
      showRecoveryHint: false,
      showChallengeHint: false,
      chips: const ['Balanced', 'Smart recommendation', 'Ride ready'],
    );
  }

  int _consistencyScore(List<Trip> trips) {
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

  int _fatigueScore({
    required double weeklyKm,
    required int weeklyRideCount,
    required int daysSinceLastRide,
  }) {
    int fatigue = 0;

    fatigue += (weeklyKm * 2.2).round();
    fatigue += weeklyRideCount * 8;

    if (daysSinceLastRide == 0) fatigue += 18;
    if (daysSinceLastRide == 1) fatigue += 8;
    if (daysSinceLastRide >= 3) fatigue -= 14;

    return fatigue.clamp(0, 100);
  }
}
