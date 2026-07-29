enum HomeAIMood { ready, recovery, comeback, challenge, commute, scenic }

extension HomeAIMoodX on HomeAIMood {
  String get title {
    switch (this) {
      case HomeAIMood.ready:
        return 'Ready to ride';
      case HomeAIMood.recovery:
        return 'Recovery mode';
      case HomeAIMood.comeback:
        return 'Time to move again';
      case HomeAIMood.challenge:
        return 'Challenge ready';
      case HomeAIMood.commute:
        return 'Commute ready';
      case HomeAIMood.scenic:
        return 'Scenic ride';
    }
  }

  String get emoji {
    switch (this) {
      case HomeAIMood.ready:
        return '⚡';
      case HomeAIMood.recovery:
        return '🧘';
      case HomeAIMood.comeback:
        return '🌱';
      case HomeAIMood.challenge:
        return '🔥';
      case HomeAIMood.commute:
        return '🏙️';
      case HomeAIMood.scenic:
        return '🌿';
    }
  }
}

class HomeAIState {
  final HomeAIMood mood;
  final String title;
  final String message;
  final String primaryActionLabel;
  final String secondaryActionLabel;
  final int readinessScore;
  final int fatigueScore;
  final double suggestedDistanceKm;
  final bool showCoachCard;
  final bool showRoutePlannerCard;
  final bool showRecoveryHint;
  final bool showChallengeHint;
  final List<String> chips;

  const HomeAIState({
    required this.mood,
    required this.title,
    required this.message,
    required this.primaryActionLabel,
    required this.secondaryActionLabel,
    required this.readinessScore,
    required this.fatigueScore,
    required this.suggestedDistanceKm,
    required this.showCoachCard,
    required this.showRoutePlannerCard,
    required this.showRecoveryHint,
    required this.showChallengeHint,
    required this.chips,
  });

  factory HomeAIState.initial() {
    return const HomeAIState(
      mood: HomeAIMood.ready,
      title: 'Ready when you are',
      message: 'Start a ride or let Munja suggest a smart route.',
      primaryActionLabel: 'Start ride',
      secondaryActionLabel: 'Plan route',
      readinessScore: 72,
      fatigueScore: 18,
      suggestedDistanceKm: 3.5,
      showCoachCard: true,
      showRoutePlannerCard: true,
      showRecoveryHint: false,
      showChallengeHint: false,
      chips: ['Easy start', 'Smart route', 'Coach ready'],
    );
  }

  HomeAIState copyWith({
    HomeAIMood? mood,
    String? title,
    String? message,
    String? primaryActionLabel,
    String? secondaryActionLabel,
    int? readinessScore,
    int? fatigueScore,
    double? suggestedDistanceKm,
    bool? showCoachCard,
    bool? showRoutePlannerCard,
    bool? showRecoveryHint,
    bool? showChallengeHint,
    List<String>? chips,
  }) {
    return HomeAIState(
      mood: mood ?? this.mood,
      title: title ?? this.title,
      message: message ?? this.message,
      primaryActionLabel: primaryActionLabel ?? this.primaryActionLabel,
      secondaryActionLabel: secondaryActionLabel ?? this.secondaryActionLabel,
      readinessScore: readinessScore ?? this.readinessScore,
      fatigueScore: fatigueScore ?? this.fatigueScore,
      suggestedDistanceKm: suggestedDistanceKm ?? this.suggestedDistanceKm,
      showCoachCard: showCoachCard ?? this.showCoachCard,
      showRoutePlannerCard: showRoutePlannerCard ?? this.showRoutePlannerCard,
      showRecoveryHint: showRecoveryHint ?? this.showRecoveryHint,
      showChallengeHint: showChallengeHint ?? this.showChallengeHint,
      chips: chips ?? this.chips,
    );
  }
}
