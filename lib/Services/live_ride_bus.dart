import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/live_ride_state.dart';

class LiveRideBus {
  LiveRideBus._();

  static final LiveRideBus instance = LiveRideBus._();

  static const String _storageKey = 'munja_live_ride_state';

  final ValueNotifier<LiveRideState> state = ValueNotifier<LiveRideState>(
    LiveRideState.initial(),
  );

  final StreamController<LiveRideState> _streamController =
      StreamController<LiveRideState>.broadcast();

  Timer? _persistDebounce;
  Future<void>? _initializeFuture;
  bool _initialized = false;

  Stream<LiveRideState> get stream => _streamController.stream;

  int get debugInstanceId => identityHashCode(this);
  int get debugNotifierId => identityHashCode(state);

  Future<void> initialize() {
    if (_initialized) {
      return Future<void>.value();
    }

    final inFlight = _initializeFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _initialize();
    _initializeFuture = future;
    return future;
  }

  Future<void> _initialize() async {
    try {
      await restore();
      _initialized = true;

      debugPrint(
        'LiveRideBus initialized: '
        'bus=$debugInstanceId notifier=$debugNotifierId '
        'active=${state.value.isActive}',
      );
    } finally {
      _initializeFuture = null;
    }
  }

  void update(LiveRideState newState) {
    state.value = newState;

    if (!_streamController.isClosed) {
      _streamController.add(newState);
    }

    _persistDebounced();

    debugPrint(
      'LiveRideBus updated: '
      'bus=$debugInstanceId notifier=$debugNotifierId '
      'active=${newState.isActive} '
      'paused=${newState.isPaused} '
      'speed=${newState.speedKmh.toStringAsFixed(1)} '
      'distance=${newState.distanceKm.toStringAsFixed(2)}',
    );
  }

  void patch({
    bool? isActive,
    bool? isPaused,
    double? speedKmh,
    double? averageSpeedKmh,
    double? maxSpeedKmh,
    double? distanceKm,
    Duration? duration,
    int? calories,
    double? gpsAccuracy,
    double? altitude,
    DateTime? startedAt,
    DateTime? lastUpdate,
    List<LatLng>? path,
  }) {
    final current = state.value;

    update(
      current.copyWith(
        isActive: isActive,
        isPaused: isPaused,
        speedKmh: speedKmh,
        averageSpeedKmh: averageSpeedKmh,
        maxSpeedKmh: maxSpeedKmh,
        distanceKm: distanceKm,
        duration: duration,
        calories: calories,
        gpsAccuracy: gpsAccuracy,
        altitude: altitude,
        startedAt: startedAt,
        lastUpdate: lastUpdate,
        path: path,
      ),
    );
  }

  void start({DateTime? startedAt}) {
    final now = DateTime.now();

    update(
      LiveRideState.initial().copyWith(
        isActive: true,
        isPaused: false,
        startedAt: startedAt ?? now,
        lastUpdate: now,
        duration: Duration.zero,
      ),
    );
  }

  void pause() {
    patch(isPaused: true, lastUpdate: DateTime.now());
  }

  void resume() {
    patch(isPaused: false, lastUpdate: DateTime.now());
  }

  Future<void> stop() async {
    await reset();
  }

  Future<void> reset() async {
    _persistDebounce?.cancel();

    state.value = LiveRideState.initial();

    if (!_streamController.isClosed) {
      _streamController.add(state.value);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(_storageKey, jsonEncode(state.value.toJson()));
    } catch (e) {
      debugPrint('LiveRideBus persist error: $e');
    }
  }

  void _persistDebounced() {
    _persistDebounce?.cancel();

    _persistDebounce = Timer(const Duration(milliseconds: 600), persist);
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);

      if (raw == null) {
        _publishInitialState(
          reason: 'no persisted ride state',
        );
        return;
      }

      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_storageKey);
        _publishInitialState(
          reason: 'invalid persisted ride state',
        );
        return;
      }

      final restored = LiveRideState.fromJson(decoded);

      // IMPORTANT:
      // A persisted LiveRideState is only a snapshot from the previous app
      // process. It must NOT automatically reactivate Home navigation after
      // an app restart.
      //
      // Previously an unfinished/stale snapshot with isActive=true was
      // restored directly. Home correctly trusted LiveRideBus and therefore
      // showed Google Maps + cockpit view even though the rider had not
      // started a new ride.
      //
      // For now Munja uses a strict rule:
      //   - a fresh app process always starts with NO active ride;
      //   - only start() may transition LiveRideBus to isActive=true.
      //
      // This deliberately favors a correct Home state over automatic
      // crash-recovery of an interrupted ride. Proper crash recovery can be
      // added later with an explicit resumable-session token.
      if (restored.isActive || restored.isPaused) {
        debugPrint(
          'LiveRideBus discarded stale active snapshot: '
          'active=${restored.isActive} '
          'paused=${restored.isPaused} '
          'distance=${restored.distanceKm.toStringAsFixed(3)} '
          'path=${restored.path.length}',
        );
      }

      await prefs.remove(_storageKey);

      _publishInitialState(
        reason: 'startup restore sanitized',
      );
    } catch (e, stackTrace) {
      debugPrint('LiveRideBus restore error: $e');
      debugPrint('$stackTrace');

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_storageKey);
      } catch (_) {
        // Best effort cleanup only.
      }

      _publishInitialState(
        reason: 'restore error fallback',
      );
    }
  }

  void _publishInitialState({
    required String reason,
  }) {
    final initial = LiveRideState.initial();

    state.value = initial;

    if (!_streamController.isClosed) {
      _streamController.add(initial);
    }

    debugPrint(
      'LiveRideBus startup state reset: '
      'reason=$reason '
      'bus=$debugInstanceId notifier=$debugNotifierId '
      'active=${initial.isActive}',
    );
  }

  bool get isActive => state.value.isActive;

  bool get isPaused => state.value.isPaused;

  double get speed => state.value.speedKmh;

  double get distance => state.value.distanceKm;

  Duration get duration => state.value.duration;

  List<LatLng> get path => state.value.path;

  Future<void> dispose() async {
    _persistDebounce?.cancel();
    await _streamController.close();
  }
}
