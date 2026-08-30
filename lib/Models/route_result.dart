class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
      };

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

enum RouteNavigationManeuver {
  start,
  straight,
  slightLeft,
  left,
  sharpLeft,
  slightRight,
  right,
  sharpRight,
  uTurnLeft,
  uTurnRight,
  rampLeft,
  rampRight,
  merge,
  ferry,
  roundaboutLeft,
  roundaboutRight,
  destination,
  unknown;

  static RouteNavigationManeuver fromGoogleValue(
    String value,
  ) {
    switch (value.trim().toUpperCase()) {
      case 'DEPART':
        return RouteNavigationManeuver.start;
      case 'STRAIGHT':
        return RouteNavigationManeuver.straight;
      case 'TURN_SLIGHT_LEFT':
        return RouteNavigationManeuver.slightLeft;
      case 'TURN_LEFT':
        return RouteNavigationManeuver.left;
      case 'TURN_SHARP_LEFT':
        return RouteNavigationManeuver.sharpLeft;
      case 'TURN_SLIGHT_RIGHT':
        return RouteNavigationManeuver.slightRight;
      case 'TURN_RIGHT':
        return RouteNavigationManeuver.right;
      case 'TURN_SHARP_RIGHT':
        return RouteNavigationManeuver.sharpRight;
      case 'UTURN_LEFT':
        return RouteNavigationManeuver.uTurnLeft;
      case 'UTURN_RIGHT':
        return RouteNavigationManeuver.uTurnRight;
      case 'RAMP_LEFT':
        return RouteNavigationManeuver.rampLeft;
      case 'RAMP_RIGHT':
        return RouteNavigationManeuver.rampRight;
      case 'MERGE':
        return RouteNavigationManeuver.merge;
      case 'FERRY':
      case 'FERRY_TRAIN':
        return RouteNavigationManeuver.ferry;
      case 'ROUNDABOUT_LEFT':
        return RouteNavigationManeuver.roundaboutLeft;
      case 'ROUNDABOUT_RIGHT':
        return RouteNavigationManeuver.roundaboutRight;
      case 'DESTINATION':
        return RouteNavigationManeuver.destination;
      default:
        return RouteNavigationManeuver.unknown;
    }
  }

  bool get isLeft {
    return this == RouteNavigationManeuver.slightLeft ||
        this == RouteNavigationManeuver.left ||
        this == RouteNavigationManeuver.sharpLeft ||
        this == RouteNavigationManeuver.uTurnLeft ||
        this == RouteNavigationManeuver.rampLeft ||
        this == RouteNavigationManeuver.roundaboutLeft;
  }

  bool get isRight {
    return this == RouteNavigationManeuver.slightRight ||
        this == RouteNavigationManeuver.right ||
        this == RouteNavigationManeuver.sharpRight ||
        this == RouteNavigationManeuver.uTurnRight ||
        this == RouteNavigationManeuver.rampRight ||
        this == RouteNavigationManeuver.roundaboutRight;
  }

  String get googleValue {
    switch (this) {
      case RouteNavigationManeuver.start:
        return 'DEPART';
      case RouteNavigationManeuver.straight:
        return 'STRAIGHT';
      case RouteNavigationManeuver.slightLeft:
        return 'TURN_SLIGHT_LEFT';
      case RouteNavigationManeuver.left:
        return 'TURN_LEFT';
      case RouteNavigationManeuver.sharpLeft:
        return 'TURN_SHARP_LEFT';
      case RouteNavigationManeuver.slightRight:
        return 'TURN_SLIGHT_RIGHT';
      case RouteNavigationManeuver.right:
        return 'TURN_RIGHT';
      case RouteNavigationManeuver.sharpRight:
        return 'TURN_SHARP_RIGHT';
      case RouteNavigationManeuver.uTurnLeft:
        return 'UTURN_LEFT';
      case RouteNavigationManeuver.uTurnRight:
        return 'UTURN_RIGHT';
      case RouteNavigationManeuver.rampLeft:
        return 'RAMP_LEFT';
      case RouteNavigationManeuver.rampRight:
        return 'RAMP_RIGHT';
      case RouteNavigationManeuver.merge:
        return 'MERGE';
      case RouteNavigationManeuver.ferry:
        return 'FERRY';
      case RouteNavigationManeuver.roundaboutLeft:
        return 'ROUNDABOUT_LEFT';
      case RouteNavigationManeuver.roundaboutRight:
        return 'ROUNDABOUT_RIGHT';
      case RouteNavigationManeuver.destination:
        return 'DESTINATION';
      case RouteNavigationManeuver.unknown:
        return 'UNKNOWN';
    }
  }
}

class RouteNavigationStep {
  const RouteNavigationStep({
    required this.index,
    required this.maneuver,
    required this.rawManeuver,
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.startLatitude,
    required this.startLongitude,
    required this.endLatitude,
    required this.endLongitude,
    required this.encodedPolyline,
  });

  final int index;
  final RouteNavigationManeuver maneuver;
  final String rawManeuver;
  final String instruction;
  final double distanceMeters;
  final int durationSeconds;
  final double? startLatitude;
  final double? startLongitude;
  final double? endLatitude;
  final double? endLongitude;
  final String encodedPolyline;

  bool get hasStart =>
      startLatitude != null && startLongitude != null;

  bool get hasEnd =>
      endLatitude != null && endLongitude != null;

  bool get hasPolyline => encodedPolyline.trim().isNotEmpty;
  bool get isLeft => maneuver.isLeft;
  bool get isRight => maneuver.isRight;

  RoutePoint? get startPoint {
    if (!hasStart) {
      return null;
    }

    return RoutePoint(
      latitude: startLatitude!,
      longitude: startLongitude!,
    );
  }

  RoutePoint? get endPoint {
    if (!hasEnd) {
      return null;
    }

    return RoutePoint(
      latitude: endLatitude!,
      longitude: endLongitude!,
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        'maneuver': maneuver.googleValue,
        'rawManeuver': rawManeuver,
        'instruction': instruction,
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'startLatitude': startLatitude,
        'startLongitude': startLongitude,
        'endLatitude': endLatitude,
        'endLongitude': endLongitude,
        'encodedPolyline': encodedPolyline,
      };

  factory RouteNavigationStep.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawManeuver =
        json['rawManeuver'] as String? ??
        json['maneuver'] as String? ??
        '';

    return RouteNavigationStep(
      index: (json['index'] as num?)?.toInt() ?? 0,
      maneuver: RouteNavigationManeuver.fromGoogleValue(
        json['maneuver'] as String? ?? rawManeuver,
      ),
      rawManeuver: rawManeuver,
      instruction: json['instruction'] as String? ?? '',
      distanceMeters:
          (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      durationSeconds:
          (json['durationSeconds'] as num?)?.toInt() ?? 0,
      startLatitude:
          (json['startLatitude'] as num?)?.toDouble(),
      startLongitude:
          (json['startLongitude'] as num?)?.toDouble(),
      endLatitude:
          (json['endLatitude'] as num?)?.toDouble(),
      endLongitude:
          (json['endLongitude'] as num?)?.toDouble(),
      encodedPolyline:
          json['encodedPolyline'] as String? ?? '',
    );
  }

  @override
  String toString() {
    return 'RouteNavigationStep('
        'index: $index, '
        'maneuver: $maneuver, '
        'distanceMeters: $distanceMeters, '
        'instruction: $instruction'
        ')';
  }
}

class RouteResult {
  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.encodedPolyline,
    required this.points,
    this.navigationSteps =
        const <RouteNavigationStep>[],
  });

  final double distanceMeters;
  final int durationSeconds;
  final String encodedPolyline;
  final List<RoutePoint> points;
  final List<RouteNavigationStep> navigationSteps;

  double get distanceKm => distanceMeters / 1000;

  Duration get duration =>
      Duration(seconds: durationSeconds);

  String get distanceLabel =>
      '${distanceKm.toStringAsFixed(1)} km';

  String get durationLabel {
    final totalMinutes =
        (durationSeconds / 60).ceil();

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

  bool get hasPolyline =>
      encodedPolyline.trim().isNotEmpty &&
      points.length >= 2;

  bool get hasNavigationSteps =>
      navigationSteps.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'encodedPolyline': encodedPolyline,
        'points': points
            .map((point) => point.toJson())
            .toList(),
        'navigationSteps': navigationSteps
            .map((step) => step.toJson())
            .toList(),
      };

  factory RouteResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawPoints =
        json['points'] as List<dynamic>? ??
        const <dynamic>[];

    final rawNavigationSteps =
        json['navigationSteps'] as List<dynamic>? ??
        const <dynamic>[];

    return RouteResult(
      distanceMeters:
          (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      durationSeconds:
          (json['durationSeconds'] as num?)?.toInt() ?? 0,
      encodedPolyline:
          json['encodedPolyline'] as String? ?? '',
      points: rawPoints
          .whereType<Map>()
          .map(
            (item) => RoutePoint.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      navigationSteps: rawNavigationSteps
          .whereType<Map>()
          .map(
            (item) => RouteNavigationStep.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }

  RouteResult copyWith({
    double? distanceMeters,
    int? durationSeconds,
    String? encodedPolyline,
    List<RoutePoint>? points,
    List<RouteNavigationStep>? navigationSteps,
  }) {
    return RouteResult(
      distanceMeters:
          distanceMeters ?? this.distanceMeters,
      durationSeconds:
          durationSeconds ?? this.durationSeconds,
      encodedPolyline:
          encodedPolyline ?? this.encodedPolyline,
      points: points ?? this.points,
      navigationSteps:
          navigationSteps ?? this.navigationSteps,
    );
  }

  @override
  String toString() {
    return 'RouteResult('
        'distanceMeters: $distanceMeters, '
        'durationSeconds: $durationSeconds, '
        'points: ${points.length}, '
        'navigationSteps: ${navigationSteps.length}'
        ')';
  }
}
