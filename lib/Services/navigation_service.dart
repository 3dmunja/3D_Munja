import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../Models/navigation_instruction.dart';
import '../Models/route_result.dart';

class NavigationService {
  NavigationService._();

  static final NavigationService instance =
      NavigationService._();

  static const double defaultOffRouteThresholdMeters = 45;
  static const double arrivalThresholdMeters = 25;

  final ValueNotifier<NavigationState?> state =
      ValueNotifier<NavigationState?>(null);

  List<RoutePoint> _routePoints = const <RoutePoint>[];
  List<double> _cumulativeDistances = const <double>[];
  List<RouteNavigationStep> _navigationSteps =
      const <RouteNavigationStep>[];
  List<_RouteTurn> _turns = const <_RouteTurn>[];

  double _totalDistanceMeters = 0;
  int _routeDurationSeconds = 0;

  bool get hasRoute => _routePoints.length >= 2;

  /// Returns a visual steering angle for the 3D Munja cockpit.
  ///
  /// Negative values steer left and positive values steer right.
  /// The value is based primarily on the real route bearing change and
  /// falls back to the maneuver type if bearing information is unavailable.
  ///
  /// The steering effect intentionally starts becoming stronger as the rider
  /// approaches the maneuver, so the 3D bike does not sit at a large steering
  /// angle hundreds of meters before the turn.
  double steeringAngleForInstruction(
    NavigationInstruction? instruction, {
    double maxAngleDegrees = 18.0,
    double fullSteeringDistanceMeters = 32.0,
    double steeringPreviewDistanceMeters = 140.0,
  }) {
    if (instruction == null || maxAngleDegrees <= 0) {
      return 0.0;
    }

    switch (instruction.maneuver) {
      case NavigationManeuver.start:
      case NavigationManeuver.continueStraight:
      case NavigationManeuver.arrive:
      case NavigationManeuver.offRoute:
        return 0.0;

      case NavigationManeuver.uTurn:
        final bearingDelta = _bearingDeltaForInstruction(
          instruction,
        );

        final direction = bearingDelta == null
            ? 1.0
            : (bearingDelta >= 0 ? 1.0 : -1.0);

        return direction * maxAngleDegrees;

      case NavigationManeuver.slightLeft:
      case NavigationManeuver.left:
      case NavigationManeuver.sharpLeft:
      case NavigationManeuver.slightRight:
      case NavigationManeuver.right:
      case NavigationManeuver.sharpRight:
        break;
    }

    final bearingDelta = _bearingDeltaForInstruction(
      instruction,
    );

    final baseAngle = bearingDelta == null
        ? _fallbackSteeringForManeuver(
            instruction.maneuver,
            maxAngleDegrees,
          )
        : _steeringFromBearingDelta(
            bearingDelta,
            maxAngleDegrees,
          );

    final distance =
        instruction.distanceToInstructionMeters;

    final distanceFactor = _steeringDistanceFactor(
      distanceMeters: distance,
      fullSteeringDistanceMeters:
          fullSteeringDistanceMeters,
      previewDistanceMeters:
          steeringPreviewDistanceMeters,
    );

    final steering = baseAngle * distanceFactor;

    return steering.clamp(
      -maxAngleDegrees,
      maxAngleDegrees,
    );
  }

  /// Convenience getter for the current navigation state.
  double get currentSteeringAngleDegrees {
    return steeringAngleForInstruction(
      state.value?.currentInstruction,
    );
  }

  double? _bearingDeltaForInstruction(
    NavigationInstruction instruction,
  ) {
    final before = instruction.bearingBefore;
    final after = instruction.bearingAfter;

    if (before == null || after == null) {
      return null;
    }

    if (!before.isFinite || !after.isFinite) {
      return null;
    }

    return _normalizedAngleDifference(
      after - before,
    );
  }

  double _steeringFromBearingDelta(
    double bearingDelta,
    double maxAngleDegrees,
  ) {
    final absoluteDelta = bearingDelta.abs();

    if (absoluteDelta < 1) {
      return 0.0;
    }

    // Real road turns can be anywhere from a few degrees to almost 180°.
    // Map 30°..120° progressively into the available visual steering range.
    final normalized =
        ((absoluteDelta - 18.0) / (120.0 - 18.0))
            .clamp(0.18, 1.0);

    final angle = maxAngleDegrees * normalized;

    return bearingDelta < 0 ? -angle : angle;
  }

  double _fallbackSteeringForManeuver(
    NavigationManeuver maneuver,
    double maxAngleDegrees,
  ) {
    switch (maneuver) {
      case NavigationManeuver.slightLeft:
        return -maxAngleDegrees * 0.38;
      case NavigationManeuver.left:
        return -maxAngleDegrees * 0.68;
      case NavigationManeuver.sharpLeft:
        return -maxAngleDegrees;
      case NavigationManeuver.slightRight:
        return maxAngleDegrees * 0.38;
      case NavigationManeuver.right:
        return maxAngleDegrees * 0.68;
      case NavigationManeuver.sharpRight:
        return maxAngleDegrees;
      case NavigationManeuver.uTurn:
        return maxAngleDegrees;
      case NavigationManeuver.start:
      case NavigationManeuver.continueStraight:
      case NavigationManeuver.arrive:
      case NavigationManeuver.offRoute:
        return 0.0;
    }
  }

  double _steeringDistanceFactor({
    required double distanceMeters,
    required double fullSteeringDistanceMeters,
    required double previewDistanceMeters,
  }) {
    if (!distanceMeters.isFinite) {
      return 0.0;
    }

    if (distanceMeters <= fullSteeringDistanceMeters) {
      return 1.0;
    }

    if (distanceMeters >= previewDistanceMeters) {
      return 0.0;
    }

    final range =
        previewDistanceMeters -
        fullSteeringDistanceMeters;

    if (range <= 0) {
      return 1.0;
    }

    final progress =
        (previewDistanceMeters - distanceMeters) /
        range;

    // Smoothstep keeps the steering calm at long distance and avoids
    // sudden jumps when crossing the preview threshold.
    final clamped = progress.clamp(0.0, 1.0);

    return clamped * clamped * (3 - 2 * clamped);
  }

  void setRoute({
    required List<RoutePoint> points,
    required double totalDistanceMeters,
    required int totalDurationSeconds,
    List<RouteNavigationStep> navigationSteps =
        const <RouteNavigationStep>[],
  }) {
    if (points.length < 2) {
      clear();
      return;
    }

    _routePoints = List<RoutePoint>.unmodifiable(points);
    _totalDistanceMeters = totalDistanceMeters;
    _routeDurationSeconds = totalDurationSeconds;
    _cumulativeDistances =
        _buildCumulativeDistances(_routePoints);

    _navigationSteps =
        List<RouteNavigationStep>.unmodifiable(
      navigationSteps,
    );

    // Prefer Google's authoritative turn-by-turn maneuvers whenever they
    // are available. The old geometry detector remains as a safe fallback
    // for older stored routes that do not yet contain navigationSteps.
    final googleTurns =
        _buildTurnsFromNavigationSteps(
      _navigationSteps,
    );

    _turns = googleTurns.isNotEmpty
        ? googleTurns
        : _buildTurns(_routePoints);

    debugPrint(
      'NAVIGATION ROUTE READY: '
      'points=${_routePoints.length}, '
      'googleSteps=${_navigationSteps.length}, '
      'turns=${_turns.length}, '
      'source=${googleTurns.isNotEmpty ? 'google' : 'geometry'}, '
      'distance=${_totalDistanceMeters.toStringAsFixed(0)}m',
    );
  }

  void clear() {
    _routePoints = const <RoutePoint>[];
    _cumulativeDistances = const <double>[];
    _navigationSteps = const <RouteNavigationStep>[];
    _turns = const <_RouteTurn>[];
    _totalDistanceMeters = 0;
    _routeDurationSeconds = 0;
    state.value = null;
  }

  NavigationState? updatePosition({
    required double latitude,
    required double longitude,
    double offRouteThresholdMeters =
        defaultOffRouteThresholdMeters,
  }) {
    if (!hasRoute) {
      return null;
    }

    final current = RoutePoint(
      latitude: latitude,
      longitude: longitude,
    );

    final nearest = _findNearestRoutePoint(current);
    final nearestIndex = nearest.index;
    final distanceFromRoute = nearest.distanceMeters;

    final remainingDistance =
        _remainingDistanceFromIndex(nearestIndex);

    final progress = _totalDistanceMeters <= 0
        ? 0.0
        : (1 - (remainingDistance / _totalDistanceMeters))
            .clamp(0.0, 1.0);

    final remainingDuration =
        (_routeDurationSeconds * (1 - progress))
            .round()
            .clamp(0, _routeDurationSeconds);

    final destination = _routePoints.last;
    final distanceToDestination =
        _distanceMeters(current, destination);

    final isOffRoute =
        distanceFromRoute > offRouteThresholdMeters;

    late final NavigationInstruction instruction;

    if (distanceToDestination <= arrivalThresholdMeters) {
      instruction = NavigationInstruction(
        maneuver: NavigationManeuver.arrive,
        title: 'Du er fremme',
        distanceToInstructionMeters: distanceToDestination,
        remainingDistanceMeters: distanceToDestination,
        remainingDurationSeconds: 0,
        routePointIndex: _routePoints.length - 1,
      );
    } else if (isOffRoute) {
      instruction = NavigationInstruction(
        maneuver: NavigationManeuver.offRoute,
        title: 'Du er kørt fra ruten',
        distanceToInstructionMeters: distanceFromRoute,
        remainingDistanceMeters: remainingDistance,
        remainingDurationSeconds: remainingDuration,
        routePointIndex: nearestIndex,
      );
    } else {
      instruction = _nextInstruction(
        currentPosition: current,
        nearestRoutePointIndex: nearestIndex,
        remainingDistanceMeters: remainingDistance,
        remainingDurationSeconds: remainingDuration,
      );
    }

    final nextState = NavigationState(
      currentInstruction: instruction,
      nearestRoutePointIndex: nearestIndex,
      distanceFromRouteMeters: distanceFromRoute,
      isOffRoute: isOffRoute,
      progress: progress,
    );

    state.value = nextState;
    return nextState;
  }

  NavigationInstruction _nextInstruction({
    required RoutePoint currentPosition,
    required int nearestRoutePointIndex,
    required double remainingDistanceMeters,
    required int remainingDurationSeconds,
  }) {
    _RouteTurn? nextTurn;

    for (final turn in _turns) {
      if (turn.routePointIndex > nearestRoutePointIndex + 1) {
        nextTurn = turn;
        break;
      }
    }

    if (nextTurn == null) {
      final destination = _routePoints.last;
      final distanceToDestination =
          _distanceMeters(currentPosition, destination);

      return NavigationInstruction(
        maneuver: NavigationManeuver.continueStraight,
        title: 'Fortsæt mod destinationen',
        distanceToInstructionMeters: distanceToDestination,
        remainingDistanceMeters: remainingDistanceMeters,
        remainingDurationSeconds: remainingDurationSeconds,
        routePointIndex: _routePoints.length - 1,
      );
    }

    final distanceToTurn = _distanceAlongRoute(
      nearestRoutePointIndex,
      nextTurn.routePointIndex,
    );

    return NavigationInstruction(
      maneuver: nextTurn.maneuver,
      title: nextTurn.title.trim().isNotEmpty
          ? nextTurn.title
          : _titleForManeuver(nextTurn.maneuver),
      distanceToInstructionMeters: distanceToTurn,
      remainingDistanceMeters: remainingDistanceMeters,
      remainingDurationSeconds: remainingDurationSeconds,
      routePointIndex: nextTurn.routePointIndex,
      bearingBefore: nextTurn.bearingBefore,
      bearingAfter: nextTurn.bearingAfter,
    );
  }

  List<_RouteTurn> _buildTurnsFromNavigationSteps(
    List<RouteNavigationStep> steps,
  ) {
    if (steps.isEmpty || _routePoints.length < 2) {
      return const <_RouteTurn>[];
    }

    final turns = <_RouteTurn>[];

    for (final step in steps) {
      final maneuver =
          _navigationManeuverFromGoogleStep(step);

      if (maneuver == null ||
          maneuver == NavigationManeuver.start ||
          maneuver ==
              NavigationManeuver.continueStraight ||
          maneuver == NavigationManeuver.arrive) {
        continue;
      }

      final anchor =
          step.endPoint ?? step.startPoint;

      if (anchor == null) {
        continue;
      }

      final nearest =
          _findNearestRoutePoint(anchor);

      final routePointIndex =
          nearest.index.clamp(
        1,
        _routePoints.length - 2,
      );

      final bearingBefore =
          _bearingBeforeRouteIndex(
        routePointIndex,
      );

      final bearingAfter =
          _bearingAfterRouteIndex(
        routePointIndex,
      );

      final absoluteAngle =
          _normalizedAngleDifference(
        bearingAfter - bearingBefore,
      ).abs();

      // Do not allow duplicate Google steps pointing at almost the same
      // geometry location. Keep the first authoritative instruction.
      if (turns.isNotEmpty &&
          (routePointIndex -
                      turns.last.routePointIndex)
                  .abs() <=
              1 &&
          maneuver == turns.last.maneuver) {
        continue;
      }

      turns.add(
        _RouteTurn(
          routePointIndex: routePointIndex,
          maneuver: maneuver,
          bearingBefore: bearingBefore,
          bearingAfter: bearingAfter,
          absoluteAngle: absoluteAngle,
          title: _titleForGoogleStep(
            step,
            maneuver,
          ),
        ),
      );
    }

    turns.sort(
      (a, b) => a.routePointIndex.compareTo(
        b.routePointIndex,
      ),
    );

    return List<_RouteTurn>.unmodifiable(
      turns,
    );
  }

  NavigationManeuver? _navigationManeuverFromGoogleStep(
    RouteNavigationStep step,
  ) {
    switch (step.maneuver) {
      case RouteNavigationManeuver.start:
        return NavigationManeuver.start;

      case RouteNavigationManeuver.straight:
      case RouteNavigationManeuver.merge:
      case RouteNavigationManeuver.ferry:
        return NavigationManeuver.continueStraight;

      case RouteNavigationManeuver.slightLeft:
      case RouteNavigationManeuver.rampLeft:
      case RouteNavigationManeuver.roundaboutLeft:
        return NavigationManeuver.slightLeft;

      case RouteNavigationManeuver.left:
        return NavigationManeuver.left;

      case RouteNavigationManeuver.sharpLeft:
        return NavigationManeuver.sharpLeft;

      case RouteNavigationManeuver.slightRight:
      case RouteNavigationManeuver.rampRight:
      case RouteNavigationManeuver.roundaboutRight:
        return NavigationManeuver.slightRight;

      case RouteNavigationManeuver.right:
        return NavigationManeuver.right;

      case RouteNavigationManeuver.sharpRight:
        return NavigationManeuver.sharpRight;

      case RouteNavigationManeuver.uTurnLeft:
      case RouteNavigationManeuver.uTurnRight:
        return NavigationManeuver.uTurn;

      case RouteNavigationManeuver.destination:
        return NavigationManeuver.arrive;

      case RouteNavigationManeuver.unknown:
        return null;
    }
  }

  String _titleForGoogleStep(
    RouteNavigationStep step,
    NavigationManeuver maneuver,
  ) {
    final googleInstruction =
        step.instruction.trim();

    if (googleInstruction.isNotEmpty) {
      return googleInstruction;
    }

    return _titleForManeuver(maneuver);
  }

  double _bearingBeforeRouteIndex(int index) {
    final fromIndex =
        (index - 2).clamp(0, _routePoints.length - 1);
    final toIndex =
        index.clamp(0, _routePoints.length - 1);

    if (fromIndex == toIndex) {
      return 0.0;
    }

    return _bearingDegrees(
      _routePoints[fromIndex],
      _routePoints[toIndex],
    );
  }

  double _bearingAfterRouteIndex(int index) {
    final fromIndex =
        index.clamp(0, _routePoints.length - 1);
    final toIndex =
        (index + 2).clamp(0, _routePoints.length - 1);

    if (fromIndex == toIndex) {
      return 0.0;
    }

    return _bearingDegrees(
      _routePoints[fromIndex],
      _routePoints[toIndex],
    );
  }

  List<_RouteTurn> _buildTurns(List<RoutePoint> points) {
    if (points.length < 5) {
      return const <_RouteTurn>[];
    }

    final turns = <_RouteTurn>[];
    const window = 2;

    for (
      var index = window;
      index < points.length - window;
      index++
    ) {
      final before = points[index - window];
      final current = points[index];
      final after = points[index + window];

      final bearingBefore = _bearingDegrees(before, current);
      final bearingAfter = _bearingDegrees(current, after);
      final angle = _normalizedAngleDifference(
        bearingAfter - bearingBefore,
      );
      final absoluteAngle = angle.abs();

      if (absoluteAngle < 28) {
        continue;
      }

      final maneuver = _maneuverForAngle(angle);

      if (turns.isNotEmpty &&
          index - turns.last.routePointIndex < 6) {
        if (absoluteAngle > turns.last.absoluteAngle) {
          turns[turns.length - 1] = _RouteTurn(
            routePointIndex: index,
            maneuver: maneuver,
            bearingBefore: bearingBefore,
            bearingAfter: bearingAfter,
            absoluteAngle: absoluteAngle,
            title: '',
          );
        }

        continue;
      }

      turns.add(
        _RouteTurn(
          routePointIndex: index,
          maneuver: maneuver,
          bearingBefore: bearingBefore,
          bearingAfter: bearingAfter,
          absoluteAngle: absoluteAngle,
          title: '',
        ),
      );
    }

    return List<_RouteTurn>.unmodifiable(turns);
  }

  NavigationManeuver _maneuverForAngle(double angle) {
    final absoluteAngle = angle.abs();
    final isRight = angle > 0;

    if (absoluteAngle >= 150) {
      return NavigationManeuver.uTurn;
    }

    if (absoluteAngle >= 105) {
      return isRight
          ? NavigationManeuver.sharpRight
          : NavigationManeuver.sharpLeft;
    }

    if (absoluteAngle >= 55) {
      return isRight
          ? NavigationManeuver.right
          : NavigationManeuver.left;
    }

    return isRight
        ? NavigationManeuver.slightRight
        : NavigationManeuver.slightLeft;
  }

  String _titleForManeuver(
    NavigationManeuver maneuver,
  ) {
    switch (maneuver) {
      case NavigationManeuver.start:
        return 'Start turen';
      case NavigationManeuver.continueStraight:
        return 'Fortsæt ligeud';
      case NavigationManeuver.slightLeft:
        return 'Hold let til venstre';
      case NavigationManeuver.left:
        return 'Drej til venstre';
      case NavigationManeuver.sharpLeft:
        return 'Skarpt til venstre';
      case NavigationManeuver.slightRight:
        return 'Hold let til højre';
      case NavigationManeuver.right:
        return 'Drej til højre';
      case NavigationManeuver.sharpRight:
        return 'Skarpt til højre';
      case NavigationManeuver.uTurn:
        return 'Vend om';
      case NavigationManeuver.arrive:
        return 'Du er fremme';
      case NavigationManeuver.offRoute:
        return 'Du er kørt fra ruten';
    }
  }

  _NearestRoutePoint _findNearestRoutePoint(
    RoutePoint current,
  ) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;

    for (
      var index = 0;
      index < _routePoints.length;
      index++
    ) {
      final distance = _distanceMeters(
        current,
        _routePoints[index],
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = index;
      }
    }

    return _NearestRoutePoint(
      index: nearestIndex,
      distanceMeters: nearestDistance,
    );
  }

  List<double> _buildCumulativeDistances(
    List<RoutePoint> points,
  ) {
    final distances = <double>[0];
    var total = 0.0;

    for (
      var index = 1;
      index < points.length;
      index++
    ) {
      total += _distanceMeters(
        points[index - 1],
        points[index],
      );

      distances.add(total);
    }

    return List<double>.unmodifiable(distances);
  }

  double _remainingDistanceFromIndex(int index) {
    if (_cumulativeDistances.isEmpty) {
      return 0;
    }

    final routeGeometryDistance =
        _cumulativeDistances.last;

    if (routeGeometryDistance <= 0) {
      return 0;
    }

    final remainingGeometry =
        routeGeometryDistance -
            _cumulativeDistances[index];

    return remainingGeometry *
        (_totalDistanceMeters / routeGeometryDistance);
  }

  double _distanceAlongRoute(
    int fromIndex,
    int toIndex,
  ) {
    if (_cumulativeDistances.isEmpty ||
        fromIndex >= toIndex) {
      return 0;
    }

    final geometryDistance =
        _cumulativeDistances[toIndex] -
            _cumulativeDistances[fromIndex];

    final totalGeometry =
        _cumulativeDistances.last;

    if (totalGeometry <= 0) {
      return geometryDistance;
    }

    return geometryDistance *
        (_totalDistanceMeters / totalGeometry);
  }

  double _distanceMeters(
    RoutePoint a,
    RoutePoint b,
  ) {
    const earthRadiusMeters = 6371000.0;

    final lat1 = _degreesToRadians(a.latitude);
    final lat2 = _degreesToRadians(b.latitude);
    final deltaLat =
        _degreesToRadians(b.latitude - a.latitude);
    final deltaLng =
        _degreesToRadians(b.longitude - a.longitude);

    final sinLat = math.sin(deltaLat / 2);
    final sinLng = math.sin(deltaLng / 2);

    final haversine =
        sinLat * sinLat +
            math.cos(lat1) *
                math.cos(lat2) *
                sinLng *
                sinLng;

    final centralAngle = 2 *
        math.atan2(
          math.sqrt(haversine),
          math.sqrt(1 - haversine),
        );

    return earthRadiusMeters * centralAngle;
  }

  double _bearingDegrees(
    RoutePoint from,
    RoutePoint to,
  ) {
    final lat1 = _degreesToRadians(from.latitude);
    final lat2 = _degreesToRadians(to.latitude);
    final deltaLongitude = _degreesToRadians(
      to.longitude - from.longitude,
    );

    final y = math.sin(deltaLongitude) *
        math.cos(lat2);

    final x = math.cos(lat1) *
            math.sin(lat2) -
        math.sin(lat1) *
            math.cos(lat2) *
            math.cos(deltaLongitude);

    final bearing =
        math.atan2(y, x) * 180 / math.pi;

    return (bearing + 360) % 360;
  }

  double _normalizedAngleDifference(
    double angle,
  ) {
    var normalized = angle;

    while (normalized > 180) {
      normalized -= 360;
    }

    while (normalized < -180) {
      normalized += 360;
    }

    return normalized;
  }

  double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}

class _RouteTurn {
  const _RouteTurn({
    required this.routePointIndex,
    required this.maneuver,
    required this.bearingBefore,
    required this.bearingAfter,
    required this.absoluteAngle,
    required this.title,
  });

  final int routePointIndex;
  final NavigationManeuver maneuver;
  final double bearingBefore;
  final double bearingAfter;
  final double absoluteAngle;
  final String title;
}

class _NearestRoutePoint {
  const _NearestRoutePoint({
    required this.index,
    required this.distanceMeters,
  });

  final int index;
  final double distanceMeters;
}
