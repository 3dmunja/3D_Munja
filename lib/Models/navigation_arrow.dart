enum NavigationArrowType {
  route,
  next,
  turnLeft,
  turnRight,
  slightLeft,
  slightRight,
  sharpLeft,
  sharpRight,
  uTurn,
  destination,
}

class NavigationArrow {
  const NavigationArrow({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.headingDegrees,
    required this.distanceAlongRouteMeters,
    required this.routePointIndex,
    required this.type,
    required this.isPassed,
    required this.isActive,
    required this.scale,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double headingDegrees;
  final double distanceAlongRouteMeters;
  final int routePointIndex;
  final NavigationArrowType type;
  final bool isPassed;
  final bool isActive;
  final double scale;

  NavigationArrow copyWith({
    String? id,
    double? latitude,
    double? longitude,
    double? headingDegrees,
    double? distanceAlongRouteMeters,
    int? routePointIndex,
    NavigationArrowType? type,
    bool? isPassed,
    bool? isActive,
    double? scale,
  }) {
    return NavigationArrow(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      headingDegrees: headingDegrees ?? this.headingDegrees,
      distanceAlongRouteMeters:
          distanceAlongRouteMeters ?? this.distanceAlongRouteMeters,
      routePointIndex: routePointIndex ?? this.routePointIndex,
      type: type ?? this.type,
      isPassed: isPassed ?? this.isPassed,
      isActive: isActive ?? this.isActive,
      scale: scale ?? this.scale,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'headingDegrees': headingDegrees,
      'distanceAlongRouteMeters': distanceAlongRouteMeters,
      'routePointIndex': routePointIndex,
      'type': type.name,
      'isPassed': isPassed,
      'isActive': isActive,
      'scale': scale,
    };
  }

  factory NavigationArrow.fromJson(Map<String, dynamic> json) {
    return NavigationArrow(
      id: json['id'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      headingDegrees:
          (json['headingDegrees'] as num?)?.toDouble() ?? 0,
      distanceAlongRouteMeters:
          (json['distanceAlongRouteMeters'] as num?)?.toDouble() ?? 0,
      routePointIndex:
          (json['routePointIndex'] as num?)?.toInt() ?? 0,
      type: NavigationArrowType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => NavigationArrowType.route,
      ),
      isPassed: json['isPassed'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? false,
      scale: (json['scale'] as num?)?.toDouble() ?? 1,
    );
  }

  @override
  String toString() {
    return 'NavigationArrow('
        'id: $id, '
        'type: ${type.name}, '
        'heading: ${headingDegrees.toStringAsFixed(1)}, '
        'distance: ${distanceAlongRouteMeters.toStringAsFixed(1)}, '
        'passed: $isPassed, '
        'active: $isActive'
        ')';
  }
}
