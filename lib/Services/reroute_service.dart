import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Models/active_ride_plan.dart';
import '../Models/reroute_result.dart';
import '../Services/active_ride_plan_service.dart';
import '../Services/route_service.dart';

class RerouteService {
  RerouteService._();

  static final RerouteService instance = RerouteService._();

  static const Duration confirmationDelay =
      Duration(seconds: 3);

  static const Duration rerouteCooldown =
      Duration(seconds: 12);

  static const double defaultOffRouteThresholdMeters = 38;

  final ValueNotifier<RerouteStatus> status =
      ValueNotifier<RerouteStatus>(
    RerouteStatus.idle,
  );

  final ValueNotifier<RerouteResult?> lastResult =
      ValueNotifier<RerouteResult?>(null);

  Timer? _confirmationTimer;

  DateTime? _lastRerouteAt;

  bool _rerouting = false;
  bool _offRouteCandidate = false;

  double? _candidateLatitude;
  double? _candidateLongitude;

  bool get isRerouting => _rerouting;

  bool get isWaitingForConfirmation {
    return status.value ==
        RerouteStatus.waitingForConfirmation;
  }

  bool get isInCooldown {
    final last = _lastRerouteAt;

    if (last == null) {
      return false;
    }

    return DateTime.now().difference(last) <
        rerouteCooldown;
  }

  Duration get remainingCooldown {
    final last = _lastRerouteAt;

    if (last == null) {
      return Duration.zero;
    }

    final elapsed = DateTime.now().difference(last);
    final remaining = rerouteCooldown - elapsed;

    if (remaining.isNegative) {
      return Duration.zero;
    }

    return remaining;
  }

  void handleNavigationState({
    required bool isOffRoute,
    required double distanceFromRouteMeters,
    required double latitude,
    required double longitude,
    double offRouteThresholdMeters =
        defaultOffRouteThresholdMeters,
  }) {
    if (!isOffRoute ||
        distanceFromRouteMeters <
            offRouteThresholdMeters) {
      cancelPendingConfirmation();
      return;
    }

    if (_rerouting || isInCooldown) {
      return;
    }

    // Always retain the newest GPS point. When the confirmation timer
    // expires, rerouting starts from the rider's latest known position.
    _candidateLatitude = latitude;
    _candidateLongitude = longitude;

    if (_offRouteCandidate) {
      return;
    }

    _offRouteCandidate = true;
    status.value =
        RerouteStatus.waitingForConfirmation;

    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(
      confirmationDelay,
      () async {
        final candidateLatitude =
            _candidateLatitude;
        final candidateLongitude =
            _candidateLongitude;

        if (!_offRouteCandidate ||
            candidateLatitude == null ||
            candidateLongitude == null) {
          return;
        }

        await rerouteFromCurrentPosition(
          originLatitude: candidateLatitude,
          originLongitude: candidateLongitude,
        );
      },
    );
  }

  void cancelPendingConfirmation() {
    _confirmationTimer?.cancel();
    _confirmationTimer = null;

    _offRouteCandidate = false;
    _candidateLatitude = null;
    _candidateLongitude = null;

    if (!_rerouting &&
        status.value ==
            RerouteStatus.waitingForConfirmation) {
      status.value = RerouteStatus.idle;
    }
  }

  Future<RerouteResult?> rerouteFromCurrentPosition({
    required double originLatitude,
    required double originLongitude,
  }) async {
    if (_rerouting) {
      return null;
    }

    final plan = ActiveRidePlanService.instance.current;

    if (plan == null ||
        !plan.hasDestinationCoordinates) {
      final now = DateTime.now();

      final result = RerouteResult(
        status: RerouteStatus.failed,
        startedAt: now,
        finishedAt: now,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude:
            plan?.destinationLatitude ?? 0,
        destinationLongitude:
            plan?.destinationLongitude ?? 0,
        message:
            'Der findes ingen aktiv destination.',
        error: 'Missing destination coordinates.',
      );

      lastResult.value = result;
      status.value = RerouteStatus.failed;

      return result;
    }

    if (isInCooldown) {
      cancelPendingConfirmation();
      status.value = RerouteStatus.cooldown;

      Future<void>.delayed(
        remainingCooldown,
        () {
          if (!_rerouting &&
              status.value == RerouteStatus.cooldown) {
            status.value = RerouteStatus.idle;
          }
        },
      );

      return null;
    }

    final destinationLatitude =
        plan.destinationLatitude!;
    final destinationLongitude =
        plan.destinationLongitude!;

    _confirmationTimer?.cancel();
    _confirmationTimer = null;
    _offRouteCandidate = false;

    _rerouting = true;
    status.value = RerouteStatus.rerouting;

    final startedAt = DateTime.now();

    try {
      debugPrint(
        'REROUTE START: '
        'origin=$originLatitude,$originLongitude '
        'destination='
        '$destinationLatitude,$destinationLongitude',
      );

      final route =
          await RouteService.instance.calculateBicycleRoute(
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
      );

      // Publish the rerouted start, polyline, distance and ETA in one
      // notifier update. This avoids configuring navigation with a mixed
      // old/new route between two separate saves.
      await ActiveRidePlanService.instance.applyReroutedRoute(
        startLatitude: originLatitude,
        startLongitude: originLongitude,
        routeDistanceMeters: route.distanceMeters,
        routeDurationSeconds: route.durationSeconds,
        encodedPolyline: route.encodedPolyline,
        navigationSteps: route.navigationSteps,
      );

      final finishedAt = DateTime.now();

      final result = RerouteResult(
        status: RerouteStatus.success,
        startedAt: startedAt,
        finishedAt: finishedAt,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
        routeDistanceMeters: route.distanceMeters,
        routeDurationSeconds: route.durationSeconds,
        encodedPolyline: route.encodedPolyline,
        message: 'Ny cykelrute er beregnet.',
      );

      _lastRerouteAt = finishedAt;
      lastResult.value = result;
      status.value = RerouteStatus.success;

      debugPrint(
        'REROUTE SUCCESS: '
        '$result, '
        'googleSteps=${route.navigationSteps.length}',
      );

      return result;
    } on RouteServiceException catch (error, stackTrace) {
      debugPrint('REROUTE ROUTE SERVICE ERROR: $error');
      debugPrint('$stackTrace');

      final finishedAt = DateTime.now();

      final result = RerouteResult(
        status: RerouteStatus.failed,
        startedAt: startedAt,
        finishedAt: finishedAt,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
        message: 'Kunne ikke genberegne ruten.',
        error: error.toString(),
      );

      lastResult.value = result;
      status.value = RerouteStatus.failed;

      return result;
    } catch (error, stackTrace) {
      debugPrint('REROUTE ERROR: $error');
      debugPrint('$stackTrace');

      final finishedAt = DateTime.now();

      final result = RerouteResult(
        status: RerouteStatus.failed,
        startedAt: startedAt,
        finishedAt: finishedAt,
        originLatitude: originLatitude,
        originLongitude: originLongitude,
        destinationLatitude: destinationLatitude,
        destinationLongitude: destinationLongitude,
        message: 'Der opstod en fejl under genberegningen.',
        error: error.toString(),
      );

      lastResult.value = result;
      status.value = RerouteStatus.failed;

      return result;
    } finally {
      _rerouting = false;
      _candidateLatitude = null;
      _candidateLongitude = null;

      if (status.value == RerouteStatus.success ||
          status.value == RerouteStatus.failed) {
        Future<void>.delayed(
          const Duration(seconds: 3),
          () {
            if (!_rerouting) {
              status.value = RerouteStatus.idle;
            }
          },
        );
      }
    }
  }

  void reset() {
    _confirmationTimer?.cancel();
    _confirmationTimer = null;

    _lastRerouteAt = null;
    _candidateLatitude = null;
    _candidateLongitude = null;

    _rerouting = false;
    _offRouteCandidate = false;

    lastResult.value = null;
    status.value = RerouteStatus.idle;
  }

  void dispose() {
    _confirmationTimer?.cancel();
    status.dispose();
    lastResult.dispose();
  }
}
