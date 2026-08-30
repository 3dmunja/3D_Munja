import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../Models/navigation_arrow.dart';
import '../Models/route_result.dart';

class NavigationArrowService {
  NavigationArrowService._();

  static final NavigationArrowService instance =
      NavigationArrowService._();

  final ValueNotifier<List<NavigationArrow>> arrows =
      ValueNotifier<List<NavigationArrow>>(
    const <NavigationArrow>[],
  );

  List<RoutePoint> _routePoints = const <RoutePoint>[];
  List<double> _cumulativeDistances = const <double>[];
  List<NavigationArrow> _baseArrows = const <NavigationArrow>[];

  double _totalGeometryDistanceMeters = 0;

  bool get hasRoute => _routePoints.length >= 2;

  /// Loads the route and creates a lightweight set of possible arrow
  /// positions. Only a small group in front of the rider is published
  /// by [updateProgress].
  void setRoute({
    required List<RoutePoint> points,
    double spacingMeters = 140,
    int maxArrowCount = 48,
  }) {
    if (points.length < 2) {
      clear();
      return;
    }

    _routePoints = List<RoutePoint>.unmodifiable(points);
    _cumulativeDistances =
        _buildCumulativeDistances(_routePoints);

    _totalGeometryDistanceMeters =
        _cumulativeDistances.isEmpty
            ? 0
            : _cumulativeDistances.last;

    final intelligentSpacing = _resolveBaseSpacing(
      requestedSpacingMeters: spacingMeters,
      routeDistanceMeters: _totalGeometryDistanceMeters,
    );

    _baseArrows = _generateArrows(
      spacingMeters: intelligentSpacing,
      maxArrowCount: maxArrowCount.clamp(12, 64),
    );

    // Do not show every arrow before the first GPS update.
    arrows.value = _baseArrows
        .take(12)
        .toList(growable: false);

    debugPrint(
      'NAVIGATION ARROWS READY: '
      'base=${_baseArrows.length}, '
      'spacing=${intelligentSpacing.toStringAsFixed(0)}m',
    );
  }

  void clear() {
    _routePoints = const <RoutePoint>[];
    _cumulativeDistances = const <double>[];
    _baseArrows = const <NavigationArrow>[];
    _totalGeometryDistanceMeters = 0;
    arrows.value = const <NavigationArrow>[];
  }

  /// Publishes only arrows ahead of the rider.
  ///
  /// Passed arrows are removed completely. The first upcoming arrow is
  /// the single active mint arrow. Remaining arrows are neutral.
  List<NavigationArrow> updateProgress({
    required double latitude,
    required double longitude,
    int? activeRoutePointIndex,
    double passedToleranceMeters = 18,
    double activeAheadDistanceMeters = 220,
    double visibleAheadDistanceMeters = 1800,
    int maxVisibleArrows = 14,
  }) {
    if (!hasRoute || _baseArrows.isEmpty) {
      arrows.value = const <NavigationArrow>[];
      return arrows.value;
    }

    final current = RoutePoint(
      latitude: latitude,
      longitude: longitude,
    );

    final nearest = _findNearestRoutePoint(current);
    final progressDistance =
        _cumulativeDistances[nearest.index];

    final activeIndex =
        activeRoutePointIndex ?? nearest.index;

    final visibleLimit =
        maxVisibleArrows.clamp(6, 18);

    final upcoming = _baseArrows.where((arrow) {
      final distanceAhead =
          arrow.distanceAlongRouteMeters -
              progressDistance;

      final isPassed =
          distanceAhead < -passedToleranceMeters;

      final isBehindNavigationIndex =
          arrow.routePointIndex <
              activeIndex - 2;

      return !isPassed &&
          !isBehindNavigationIndex &&
          distanceAhead >= 0 &&
          distanceAhead <=
              visibleAheadDistanceMeters;
    }).toList(growable: false)
      ..sort(
        (a, b) => a.distanceAlongRouteMeters
            .compareTo(b.distanceAlongRouteMeters),
      );

    if (upcoming.isEmpty) {
      arrows.value = const <NavigationArrow>[];
      return arrows.value;
    }

    final selected = _selectVisibleArrows(
      upcoming: upcoming,
      progressDistance: progressDistance,
      maxVisibleArrows: visibleLimit,
    );

    final firstUpcomingId = selected.first.id;

    final updated = selected.map((arrow) {
      final distanceAhead =
          arrow.distanceAlongRouteMeters -
              progressDistance;

      final isFirst = arrow.id == firstUpcomingId;

      final isActive = isFirst ||
          distanceAhead <= activeAheadDistanceMeters &&
              arrow.type != NavigationArrowType.route;

      return arrow.copyWith(
        isPassed: false,
        isActive: isActive,
        type: isActive
            ? NavigationArrowType.next
            : arrow.type,
        scale: isActive ? 1.20 : 0.82,
      );
    }).toList(growable: false);

    arrows.value =
        List<NavigationArrow>.unmodifiable(updated);

    return arrows.value;
  }

  List<NavigationArrow> _selectVisibleArrows({
    required List<NavigationArrow> upcoming,
    required double progressDistance,
    required int maxVisibleArrows,
  }) {
    if (upcoming.length <= maxVisibleArrows) {
      return upcoming;
    }

    final selected = <NavigationArrow>[];
    var lastAcceptedDistance =
        double.negativeInfinity;

    for (final arrow in upcoming) {
      final distanceAhead =
          arrow.distanceAlongRouteMeters -
              progressDistance;

      final minimumGap =
          _minimumVisibleGapForDistance(distanceAhead);

      final isImportantTurn =
          arrow.type != NavigationArrowType.route;

      final farEnough =
          arrow.distanceAlongRouteMeters -
                  lastAcceptedDistance >=
              minimumGap;

      if (selected.isEmpty ||
          isImportantTurn ||
          farEnough) {
        selected.add(arrow);
        lastAcceptedDistance =
            arrow.distanceAlongRouteMeters;
      }

      if (selected.length >= maxVisibleArrows) {
        break;
      }
    }

    return selected;
  }

  double _minimumVisibleGapForDistance(
    double distanceAheadMeters,
  ) {
    if (distanceAheadMeters <= 300) {
      return 90;
    }

    if (distanceAheadMeters <= 800) {
      return 130;
    }

    return 190;
  }

  double _resolveBaseSpacing({
    required double requestedSpacingMeters,
    required double routeDistanceMeters,
  }) {
    final requested =
        requestedSpacingMeters.clamp(90.0, 240.0);

    if (routeDistanceMeters <= 2500) {
      return math.max(requested, 105);
    }

    if (routeDistanceMeters <= 8000) {
      return math.max(requested, 135);
    }

    if (routeDistanceMeters <= 20000) {
      return math.max(requested, 175);
    }

    return math.max(requested, 220);
  }

  List<NavigationArrow> _generateArrows({
    required double spacingMeters,
    required int maxArrowCount,
  }) {
    if (_totalGeometryDistanceMeters <= 0) {
      return const <NavigationArrow>[];
    }

    final estimatedCount =
        (_totalGeometryDistanceMeters /
                spacingMeters)
            .floor();

    final actualSpacing =
        estimatedCount > maxArrowCount
            ? _totalGeometryDistanceMeters /
                maxArrowCount
            : spacingMeters;

    final generated = <NavigationArrow>[];

    var targetDistance = actualSpacing;
    var arrowIndex = 0;

    while (targetDistance <
            _totalGeometryDistanceMeters &&
        generated.length < maxArrowCount) {
      final sample =
          _sampleRouteAtDistance(targetDistance);

      final turnType =
          _arrowTypeForPoint(sample.routePointIndex);

      generated.add(
        NavigationArrow(
          id: 'route_arrow_$arrowIndex',
          latitude: sample.point.latitude,
          longitude: sample.point.longitude,
          headingDegrees: sample.headingDegrees,
          distanceAlongRouteMeters:
              targetDistance,
          routePointIndex:
              sample.routePointIndex,
          type: turnType,
          isPassed: false,
          isActive: false,
          scale: turnType ==
                  NavigationArrowType.route
              ? 0.82
              : 1.0,
        ),
      );

      targetDistance += actualSpacing;
      arrowIndex++;
    }

    return List<NavigationArrow>.unmodifiable(
      generated,
    );
  }

  NavigationArrowType _arrowTypeForPoint(
    int routePointIndex,
  ) {
    const lookBack = 3;
    const lookAhead = 3;

    if (routePointIndex < lookBack ||
        routePointIndex >=
            _routePoints.length - lookAhead) {
      return NavigationArrowType.route;
    }

    final before =
        _routePoints[routePointIndex - lookBack];

    final current =
        _routePoints[routePointIndex];

    final after =
        _routePoints[routePointIndex + lookAhead];

    final bearingBefore =
        _bearingDegrees(before, current);

    final bearingAfter =
        _bearingDegrees(current, after);

    final angle = _normalizedAngleDifference(
      bearingAfter - bearingBefore,
    );

    final absoluteAngle = angle.abs();
    final isRight = angle > 0;

    if (absoluteAngle < 34) {
      return NavigationArrowType.route;
    }

    if (absoluteAngle >= 150) {
      return NavigationArrowType.uTurn;
    }

    if (absoluteAngle >= 105) {
      return isRight
          ? NavigationArrowType.sharpRight
          : NavigationArrowType.sharpLeft;
    }

    if (absoluteAngle >= 58) {
      return isRight
          ? NavigationArrowType.turnRight
          : NavigationArrowType.turnLeft;
    }

    return isRight
        ? NavigationArrowType.slightRight
        : NavigationArrowType.slightLeft;
  }

  _RouteSample _sampleRouteAtDistance(
    double targetDistanceMeters,
  ) {
    var segmentIndex = 1;

    while (segmentIndex <
            _cumulativeDistances.length &&
        _cumulativeDistances[segmentIndex] <
            targetDistanceMeters) {
      segmentIndex++;
    }

    if (segmentIndex >= _routePoints.length) {
      final lastIndex = _routePoints.length - 1;

      return _RouteSample(
        point: _routePoints[lastIndex],
        headingDegrees: _bearingDegrees(
          _routePoints[lastIndex - 1],
          _routePoints[lastIndex],
        ),
        routePointIndex: lastIndex,
      );
    }

    final previousIndex = segmentIndex - 1;

    final segmentStart =
        _cumulativeDistances[previousIndex];

    final segmentEnd =
        _cumulativeDistances[segmentIndex];

    final segmentLength =
        segmentEnd - segmentStart;

    final fraction = segmentLength <= 0
        ? 0.0
        : ((targetDistanceMeters -
                    segmentStart) /
                segmentLength)
            .clamp(0.0, 1.0);

    final from = _routePoints[previousIndex];
    final to = _routePoints[segmentIndex];

    final point = RoutePoint(
      latitude: from.latitude +
          (to.latitude - from.latitude) *
              fraction,
      longitude: from.longitude +
          (to.longitude - from.longitude) *
              fraction,
    );

    return _RouteSample(
      point: point,
      headingDegrees:
          _bearingDegrees(from, to),
      routePointIndex: segmentIndex,
    );
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

  double _distanceMeters(
    RoutePoint a,
    RoutePoint b,
  ) {
    const earthRadiusMeters = 6371000.0;

    final lat1 =
        _degreesToRadians(a.latitude);

    final lat2 =
        _degreesToRadians(b.latitude);

    final deltaLat =
        _degreesToRadians(
      b.latitude - a.latitude,
    );

    final deltaLng =
        _degreesToRadians(
      b.longitude - a.longitude,
    );

    final sinLat =
        math.sin(deltaLat / 2);

    final sinLng =
        math.sin(deltaLng / 2);

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

    return earthRadiusMeters *
        centralAngle;
  }

  double _bearingDegrees(
    RoutePoint from,
    RoutePoint to,
  ) {
    final lat1 =
        _degreesToRadians(from.latitude);

    final lat2 =
        _degreesToRadians(to.latitude);

    final deltaLongitude =
        _degreesToRadians(
      to.longitude - from.longitude,
    );

    final y =
        math.sin(deltaLongitude) *
            math.cos(lat2);

    final x =
        math.cos(lat1) *
                math.sin(lat2) -
            math.sin(lat1) *
                math.cos(lat2) *
                math.cos(deltaLongitude);

    final bearing =
        math.atan2(y, x) *
            180 /
            math.pi;

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

  double _degreesToRadians(
    double degrees,
  ) {
    return degrees *
        math.pi /
        180;
  }
}

class _RouteSample {
  const _RouteSample({
    required this.point,
    required this.headingDegrees,
    required this.routePointIndex,
  });

  final RoutePoint point;
  final double headingDegrees;
  final int routePointIndex;
}

class _NearestRoutePoint {
  const _NearestRoutePoint({
    required this.index,
    required this.distanceMeters,
  });

  final int index;
  final double distanceMeters;
}
