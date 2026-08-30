import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Models/active_ride_plan.dart';
import '../Models/route_result.dart';

class ActiveRidePlanService {
  ActiveRidePlanService._();

  static final ActiveRidePlanService instance =
      ActiveRidePlanService._();

  static const String _storageKey = 'munja_active_ride_plan';

  final ValueNotifier<ActiveRidePlan?> notifier =
      ValueNotifier<ActiveRidePlan?>(null);

  bool _initialized = false;
  bool _busy = false;

  ActiveRidePlan? get current => notifier.value;

  bool get hasPlan => current != null;

  bool get isInitialized => _initialized;

  bool get isBusy => _busy;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _busy = true;

    try {
      final preferences = await SharedPreferences.getInstance();
      final rawJson = preferences.getString(_storageKey);

      if (rawJson == null || rawJson.trim().isEmpty) {
        notifier.value = null;
        _initialized = true;
        return;
      }

      final decoded = jsonDecode(rawJson);

      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          'ACTIVE RIDE PLAN: Stored value was not a JSON object.',
        );

        await preferences.remove(_storageKey);
        notifier.value = null;
        _initialized = true;
        return;
      }

      final plan = ActiveRidePlan.fromJson(decoded);

      if (plan.id.trim().isEmpty) {
        debugPrint(
          'ACTIVE RIDE PLAN: Stored plan had no valid id.',
        );

        await preferences.remove(_storageKey);
        notifier.value = null;
        _initialized = true;
        return;
      }

      notifier.value = plan;

      debugPrint(
        'ACTIVE RIDE PLAN RESTORED: $plan',
      );

      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint(
        'ACTIVE RIDE PLAN INITIALIZE ERROR: $error',
      );
      debugPrint('$stackTrace');

      notifier.value = null;
      _initialized = true;
    } finally {
      _busy = false;
    }
  }

  Future<void> save(ActiveRidePlan plan) async {
    _busy = true;

    try {
      final normalizedPlan = plan.copyWith(
        updatedAt: DateTime.now(),
      );

      final preferences = await SharedPreferences.getInstance();

      await preferences.setString(
        _storageKey,
        jsonEncode(normalizedPlan.toJson()),
      );

      notifier.value = normalizedPlan;

      debugPrint(
        'ACTIVE RIDE PLAN SAVED: $normalizedPlan',
      );
    } catch (error, stackTrace) {
      debugPrint('ACTIVE RIDE PLAN SAVE ERROR: $error');
      debugPrint('$stackTrace');

      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<ActiveRidePlan> createAndSave({
    required ActiveRideMode mode,
    required ActiveRideBikeType bikeType,
    required double distanceKm,
    String destination = '',
    String? destinationPlaceId,
    double? destinationLatitude,
    double? destinationLongitude,
  }) async {
    final plan = ActiveRidePlan.create(
      mode: mode,
      bikeType: bikeType,
      distanceKm: distanceKm,
      destination: destination,
      destinationPlaceId: destinationPlaceId,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
    );

    await save(plan);

    return notifier.value ?? plan;
  }

  Future<void> updateStartPosition({
    required double latitude,
    required double longitude,
  }) async {
    final plan = current;

    if (plan == null) {
      return;
    }

    await save(
      plan.copyWith(
        startLatitude: latitude,
        startLongitude: longitude,
      ),
    );
  }

  Future<void> updateCalculatedRoute({
    required double routeDistanceMeters,
    required int routeDurationSeconds,
    required String encodedPolyline,
    List<RouteNavigationStep> navigationSteps =
        const <RouteNavigationStep>[],
  }) async {
    final plan = current;

    if (plan == null) {
      return;
    }

    if (routeDistanceMeters <= 0 ||
        routeDurationSeconds <= 0 ||
        encodedPolyline.trim().isEmpty) {
      throw ArgumentError(
        'Calculated route must contain distance, duration and polyline.',
      );
    }

    await save(
      plan.copyWith(
        routeDistanceMeters: routeDistanceMeters,
        routeDurationSeconds: routeDurationSeconds,
        encodedPolyline: encodedPolyline,
        navigationSteps: navigationSteps,
        isReady: true,
      ),
    );

    debugPrint(
      'ACTIVE RIDE ROUTE UPDATED: '
      'distance=${routeDistanceMeters.toStringAsFixed(0)}m, '
      'duration=${routeDurationSeconds}s, '
      'googleSteps=${navigationSteps.length}',
    );
  }

  /// Stores one complete RouteResult, including the exact Google
  /// navigation steps belonging to that route.
  ///
  /// Prefer this helper when a route has just been calculated. It prevents the
  /// polyline from being persisted while turn-by-turn steps accidentally come
  /// from another candidate/request.
  Future<void> updateCalculatedRouteFromResult(
    RouteResult result,
  ) {
    return updateCalculatedRoute(
      routeDistanceMeters: result.distanceMeters,
      routeDurationSeconds: result.durationSeconds,
      encodedPolyline: result.encodedPolyline,
      navigationSteps: result.navigationSteps,
    );
  }

  /// Atomically replaces the active route after a successful reroute.
  ///
  /// Updating start position and calculated route in one save prevents
  /// listeners from briefly receiving the new start with the old polyline.
  Future<void> applyReroutedRoute({
    required double startLatitude,
    required double startLongitude,
    required double routeDistanceMeters,
    required int routeDurationSeconds,
    required String encodedPolyline,
    List<RouteNavigationStep> navigationSteps =
        const <RouteNavigationStep>[],
  }) async {
    final plan = current;

    if (plan == null) {
      return;
    }

    await save(
      plan.copyWith(
        startLatitude: startLatitude,
        startLongitude: startLongitude,
        routeDistanceMeters: routeDistanceMeters,
        routeDurationSeconds: routeDurationSeconds,
        encodedPolyline: encodedPolyline,
        navigationSteps: navigationSteps,
        isReady: true,
      ),
    );

    debugPrint(
      'ACTIVE RIDE REROUTE APPLIED: '
      'distance=${routeDistanceMeters.toStringAsFixed(0)}m, '
      'duration=${routeDurationSeconds}s, '
      'googleSteps=${navigationSteps.length}',
    );
  }

  Future<void> markNotReady() async {
    final plan = current;

    if (plan == null) {
      return;
    }

    await save(
      plan.copyWith(isReady: false),
    );
  }

  Future<void> markReady() async {
    final plan = current;

    if (plan == null) {
      return;
    }

    await save(
      plan.copyWith(isReady: true),
    );
  }

  Future<void> clearCalculatedRoute() async {
    final plan = current;

    if (plan == null) {
      return;
    }

    await save(
      plan.copyWith(
        clearCalculatedRoute: true,
      ),
    );
  }

  Future<void> clear() async {
    _busy = true;

    try {
      final preferences = await SharedPreferences.getInstance();

      await preferences.remove(_storageKey);

      notifier.value = null;

      debugPrint('ACTIVE RIDE PLAN CLEARED');
    } catch (error, stackTrace) {
      debugPrint('ACTIVE RIDE PLAN CLEAR ERROR: $error');
      debugPrint('$stackTrace');

      rethrow;
    } finally {
      _busy = false;
    }
  }

  void replaceInMemory(ActiveRidePlan? plan) {
    notifier.value = plan;
  }

  void dispose() {
    notifier.dispose();
  }
}
