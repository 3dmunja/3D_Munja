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

  Stream<LiveRideState> get stream => _streamController.stream;

  Future<void> initialize() async {
    await restore();
  }

  void update(LiveRideState newState) {
    state.value = newState;

    if (!_streamController.isClosed) {
      _streamController.add(newState);
    }

    _persistDebounced();

    debugPrint(
      'LiveRideBus updated: '
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

      if (raw == null) return;

      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) return;

      final restored = LiveRideState.fromJson(decoded);

      state.value = restored;

      if (!_streamController.isClosed) {
        _streamController.add(restored);
      }

      debugPrint('LiveRideBus restored');
    } catch (e) {
      debugPrint('LiveRideBus restore error: $e');
    }
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
