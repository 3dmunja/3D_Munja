enum NavigationManeuver {
  start,
  continueStraight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurn,
  arrive,
  offRoute,
}

class NavigationInstruction {
  const NavigationInstruction({
    required this.maneuver,
    required this.title,
    required this.distanceToInstructionMeters,
    required this.remainingDistanceMeters,
    required this.remainingDurationSeconds,
    required this.routePointIndex,
    this.bearingBefore,
    this.bearingAfter,
    this.streetName,
  });

  final NavigationManeuver maneuver;
  final String title;
  final double distanceToInstructionMeters;
  final double remainingDistanceMeters;
  final int remainingDurationSeconds;
  final int routePointIndex;
  final double? bearingBefore;
  final double? bearingAfter;
  final String? streetName;

  bool get isArrival => maneuver == NavigationManeuver.arrive;
  bool get isOffRoute => maneuver == NavigationManeuver.offRoute;

  String get distanceToInstructionLabel =>
      _distanceLabel(distanceToInstructionMeters);

  String get remainingDistanceLabel =>
      _distanceLabel(remainingDistanceMeters);

  String get remainingDurationLabel {
    final totalMinutes = (remainingDurationSeconds / 60).ceil();

    if (totalMinutes <= 1) {
      return '< 1 min';
    }

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes.remainder(60);

    if (hours > 0 && minutes > 0) {
      return '${hours} t ${minutes} min';
    }

    if (hours > 0) {
      return '${hours} t';
    }

    return '$minutes min';
  }

  String get iconName {
    switch (maneuver) {
      case NavigationManeuver.start:
        return 'start';
      case NavigationManeuver.continueStraight:
        return 'straight';
      case NavigationManeuver.slightLeft:
        return 'slight_left';
      case NavigationManeuver.left:
        return 'left';
      case NavigationManeuver.sharpLeft:
        return 'sharp_left';
      case NavigationManeuver.slightRight:
        return 'slight_right';
      case NavigationManeuver.right:
        return 'right';
      case NavigationManeuver.sharpRight:
        return 'sharp_right';
      case NavigationManeuver.uTurn:
        return 'u_turn';
      case NavigationManeuver.arrive:
        return 'arrive';
      case NavigationManeuver.offRoute:
        return 'off_route';
    }
  }

  NavigationInstruction copyWith({
    NavigationManeuver? maneuver,
    String? title,
    double? distanceToInstructionMeters,
    double? remainingDistanceMeters,
    int? remainingDurationSeconds,
    int? routePointIndex,
    double? bearingBefore,
    double? bearingAfter,
    String? streetName,
    bool clearStreetName = false,
  }) {
    return NavigationInstruction(
      maneuver: maneuver ?? this.maneuver,
      title: title ?? this.title,
      distanceToInstructionMeters:
          distanceToInstructionMeters ?? this.distanceToInstructionMeters,
      remainingDistanceMeters:
          remainingDistanceMeters ?? this.remainingDistanceMeters,
      remainingDurationSeconds:
          remainingDurationSeconds ?? this.remainingDurationSeconds,
      routePointIndex: routePointIndex ?? this.routePointIndex,
      bearingBefore: bearingBefore ?? this.bearingBefore,
      bearingAfter: bearingAfter ?? this.bearingAfter,
      streetName: clearStreetName ? null : streetName ?? this.streetName,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'maneuver': maneuver.name,
      'title': title,
      'distanceToInstructionMeters': distanceToInstructionMeters,
      'remainingDistanceMeters': remainingDistanceMeters,
      'remainingDurationSeconds': remainingDurationSeconds,
      'routePointIndex': routePointIndex,
      'bearingBefore': bearingBefore,
      'bearingAfter': bearingAfter,
      'streetName': streetName,
    };
  }

  factory NavigationInstruction.fromJson(Map<String, dynamic> json) {
    return NavigationInstruction(
      maneuver: NavigationManeuver.values.firstWhere(
        (value) => value.name == json['maneuver'],
        orElse: () => NavigationManeuver.continueStraight,
      ),
      title: json['title'] as String? ?? 'Fortsæt',
      distanceToInstructionMeters:
          (json['distanceToInstructionMeters'] as num?)?.toDouble() ?? 0,
      remainingDistanceMeters:
          (json['remainingDistanceMeters'] as num?)?.toDouble() ?? 0,
      remainingDurationSeconds:
          (json['remainingDurationSeconds'] as num?)?.toInt() ?? 0,
      routePointIndex:
          (json['routePointIndex'] as num?)?.toInt() ?? 0,
      bearingBefore:
          (json['bearingBefore'] as num?)?.toDouble(),
      bearingAfter:
          (json['bearingAfter'] as num?)?.toDouble(),
      streetName: json['streetName'] as String?,
    );
  }

  static String _distanceLabel(double meters) {
    if (meters < 0) {
      return '0 m';
    }

    if (meters < 1000) {
      final rounded = meters < 100
          ? (meters / 10).round() * 10
          : (meters / 50).round() * 50;

      return '$rounded m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}

class NavigationState {
  const NavigationState({
    required this.currentInstruction,
    required this.nearestRoutePointIndex,
    required this.distanceFromRouteMeters,
    required this.isOffRoute,
    required this.progress,
  });

  final NavigationInstruction currentInstruction;
  final int nearestRoutePointIndex;
  final double distanceFromRouteMeters;
  final bool isOffRoute;
  final double progress;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'currentInstruction': currentInstruction.toJson(),
      'nearestRoutePointIndex': nearestRoutePointIndex,
      'distanceFromRouteMeters': distanceFromRouteMeters,
      'isOffRoute': isOffRoute,
      'progress': progress,
    };
  }
}
