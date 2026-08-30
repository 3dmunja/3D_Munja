import 'route_result.dart';

enum ActiveRideMode {
  destination,
  roundTrip,
  suggestedRoute,
  freeRide,
}

enum ActiveRideBikeType {
  mtb,
  road,
  family,
  nature,
  quietRoads,
}

class ActiveRidePlan {
  const ActiveRidePlan({
    required this.id,
    required this.mode,
    required this.bikeType,
    required this.distanceKm,
    required this.createdAt,
    required this.updatedAt,
    this.destination = '',
    this.destinationPlaceId,
    this.destinationLatitude,
    this.destinationLongitude,
    this.startLatitude,
    this.startLongitude,
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.encodedPolyline,
    this.navigationSteps = const <RouteNavigationStep>[],
    this.isReady = true,
  });

  final String id;
  final ActiveRideMode mode;
  final ActiveRideBikeType bikeType;
  final double distanceKm;

  final String destination;
  final String? destinationPlaceId;
  final double? destinationLatitude;
  final double? destinationLongitude;

  final double? startLatitude;
  final double? startLongitude;

  final double? routeDistanceMeters;
  final int? routeDurationSeconds;
  final String? encodedPolyline;
  final List<RouteNavigationStep> navigationSteps;

  final bool isReady;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasDestination {
    return destination.trim().isNotEmpty;
  }

  bool get hasDestinationCoordinates {
    return destinationLatitude != null &&
        destinationLongitude != null;
  }

  bool get hasStartCoordinates {
    return startLatitude != null && startLongitude != null;
  }

  bool get hasCalculatedRoute {
    return encodedPolyline != null &&
        encodedPolyline!.trim().isNotEmpty &&
        routeDistanceMeters != null &&
        routeDurationSeconds != null;
  }

  bool get hasNavigationSteps => navigationSteps.isNotEmpty;

  bool get isFreeRide {
    return mode == ActiveRideMode.freeRide;
  }

  bool get isRoundTrip {
    return mode == ActiveRideMode.roundTrip;
  }

  bool get isSuggestedRoute {
    return mode == ActiveRideMode.suggestedRoute;
  }

  bool get isDestinationRide {
    return mode == ActiveRideMode.destination;
  }

  String get modeLabel {
    switch (mode) {
      case ActiveRideMode.destination:
        return 'Destination';
      case ActiveRideMode.roundTrip:
        return 'Rundtur';
      case ActiveRideMode.suggestedRoute:
        return 'Ruteforslag';
      case ActiveRideMode.freeRide:
        return 'Fri tur';
    }
  }

  String get bikeTypeLabel {
    switch (bikeType) {
      case ActiveRideBikeType.mtb:
        return 'MTB';
      case ActiveRideBikeType.road:
        return 'Road';
      case ActiveRideBikeType.family:
        return 'Family';
      case ActiveRideBikeType.nature:
        return 'Nature';
      case ActiveRideBikeType.quietRoads:
        return 'Quiet roads';
    }
  }

  String get displayTitle {
    if (hasDestination) {
      return destination;
    }

    return modeLabel;
  }

  String get distanceLabel {
    if (routeDistanceMeters != null) {
      return '${(routeDistanceMeters! / 1000).toStringAsFixed(1)} km';
    }

    return '${distanceKm.toStringAsFixed(0)} km';
  }

  Duration? get routeDuration {
    final seconds = routeDurationSeconds;

    if (seconds == null) {
      return null;
    }

    return Duration(seconds: seconds);
  }

  ActiveRidePlan copyWith({
    String? id,
    ActiveRideMode? mode,
    ActiveRideBikeType? bikeType,
    double? distanceKm,
    String? destination,
    String? destinationPlaceId,
    double? destinationLatitude,
    double? destinationLongitude,
    double? startLatitude,
    double? startLongitude,
    double? routeDistanceMeters,
    int? routeDurationSeconds,
    String? encodedPolyline,
    List<RouteNavigationStep>? navigationSteps,
    bool? isReady,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDestinationPlaceId = false,
    bool clearDestinationCoordinates = false,
    bool clearStartCoordinates = false,
    bool clearCalculatedRoute = false,
  }) {
    return ActiveRidePlan(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      bikeType: bikeType ?? this.bikeType,
      distanceKm: distanceKm ?? this.distanceKm,
      destination: destination ?? this.destination,
      destinationPlaceId: clearDestinationPlaceId
          ? null
          : destinationPlaceId ?? this.destinationPlaceId,
      destinationLatitude: clearDestinationCoordinates
          ? null
          : destinationLatitude ?? this.destinationLatitude,
      destinationLongitude: clearDestinationCoordinates
          ? null
          : destinationLongitude ?? this.destinationLongitude,
      startLatitude: clearStartCoordinates
          ? null
          : startLatitude ?? this.startLatitude,
      startLongitude: clearStartCoordinates
          ? null
          : startLongitude ?? this.startLongitude,
      routeDistanceMeters: clearCalculatedRoute
          ? null
          : routeDistanceMeters ?? this.routeDistanceMeters,
      routeDurationSeconds: clearCalculatedRoute
          ? null
          : routeDurationSeconds ?? this.routeDurationSeconds,
      encodedPolyline: clearCalculatedRoute
          ? null
          : encodedPolyline ?? this.encodedPolyline,
      navigationSteps: clearCalculatedRoute
          ? const <RouteNavigationStep>[]
          : navigationSteps ?? this.navigationSteps,
      isReady: isReady ?? this.isReady,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'mode': mode.name,
      'bikeType': bikeType.name,
      'distanceKm': distanceKm,
      'destination': destination,
      'destinationPlaceId': destinationPlaceId,
      'destinationLatitude': destinationLatitude,
      'destinationLongitude': destinationLongitude,
      'startLatitude': startLatitude,
      'startLongitude': startLongitude,
      'routeDistanceMeters': routeDistanceMeters,
      'routeDurationSeconds': routeDurationSeconds,
      'encodedPolyline': encodedPolyline,
      'navigationSteps': navigationSteps
          .map((step) => step.toJson())
          .toList(growable: false),
      'isReady': isReady,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ActiveRidePlan.fromJson(Map<String, dynamic> json) {
    return ActiveRidePlan(
      id: json['id'] as String? ?? '',
      mode: _activeRideModeFromName(
        json['mode'] as String?,
      ),
      bikeType: _activeRideBikeTypeFromName(
        json['bikeType'] as String?,
      ),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      destination: json['destination'] as String? ?? '',
      destinationPlaceId:
          json['destinationPlaceId'] as String?,
      destinationLatitude:
          (json['destinationLatitude'] as num?)?.toDouble(),
      destinationLongitude:
          (json['destinationLongitude'] as num?)?.toDouble(),
      startLatitude:
          (json['startLatitude'] as num?)?.toDouble(),
      startLongitude:
          (json['startLongitude'] as num?)?.toDouble(),
      routeDistanceMeters:
          (json['routeDistanceMeters'] as num?)?.toDouble(),
      routeDurationSeconds:
          (json['routeDurationSeconds'] as num?)?.toInt(),
      encodedPolyline: json['encodedPolyline'] as String?,
      navigationSteps:
          (json['navigationSteps'] as List<dynamic>? ??
                  const <dynamic>[])
              .whereType<Map>()
              .map(
                (item) => RouteNavigationStep.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false),
      isReady: json['isReady'] as bool? ?? true,
      createdAt: DateTime.tryParse(
            json['createdAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
            json['updatedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }

  static ActiveRidePlan create({
    required ActiveRideMode mode,
    required ActiveRideBikeType bikeType,
    required double distanceKm,
    String destination = '',
    String? destinationPlaceId,
    double? destinationLatitude,
    double? destinationLongitude,
  }) {
    final now = DateTime.now();

    return ActiveRidePlan(
      id: now.microsecondsSinceEpoch.toString(),
      mode: mode,
      bikeType: bikeType,
      distanceKm: distanceKm,
      destination: destination,
      destinationPlaceId: destinationPlaceId,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  String toString() {
    return 'ActiveRidePlan('
        'id: $id, '
        'mode: ${mode.name}, '
        'bikeType: ${bikeType.name}, '
        'distanceKm: $distanceKm, '
        'destination: $destination, '
        'destinationLatitude: $destinationLatitude, '
        'destinationLongitude: $destinationLongitude, '
        'hasCalculatedRoute: $hasCalculatedRoute, '
        'navigationSteps: ${navigationSteps.length}'
        ')';
  }
}

ActiveRideMode _activeRideModeFromName(String? value) {
  for (final mode in ActiveRideMode.values) {
    if (mode.name == value) {
      return mode;
    }
  }

  return ActiveRideMode.freeRide;
}

ActiveRideBikeType _activeRideBikeTypeFromName(String? value) {
  for (final type in ActiveRideBikeType.values) {
    if (type.name == value) {
      return type;
    }
  }

  return ActiveRideBikeType.nature;
}
