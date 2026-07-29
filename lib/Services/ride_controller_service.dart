import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/live_ride_state.dart';
import '../models/trip.dart';
import 'live_ride_bus.dart';
import 'storage_service.dart';

class RideControllerService {
  RideControllerService._();

  static final RideControllerService instance = RideControllerService._();

  final ValueNotifier<bool> isRideActive = ValueNotifier(false);
  final ValueNotifier<double> speedKmh = ValueNotifier(0);
  final ValueNotifier<double> distanceKm = ValueNotifier(0);
  final ValueNotifier<double> averageSpeedKmh = ValueNotifier(0);
  final ValueNotifier<double> maxSpeedKmh = ValueNotifier(0);
  final ValueNotifier<Duration> rideDuration = ValueNotifier(Duration.zero);
  final ValueNotifier<List<LatLng>> ridePath = ValueNotifier([]);

  StreamSubscription<Position>? _positionSub;
  Timer? _durationTimer;

  DateTime? _rideStart;
  Position? _lastPosition;

  double _totalMeters = 0;
  double _speedTotal = 0;
  int _speedSamples = 0;

  Future<void> initialize() async {
    await LiveRideBus.instance.initialize();
    await _restoreRideState();
  }

  Future<void> startRide() async {
    if (isRideActive.value) return;

    final permission = await _ensurePermission();
    if (!permission) {
      debugPrint('Location permission denied');
      return;
    }

    _rideStart ??= DateTime.now();
    isRideActive.value = true;

    await WakelockPlus.enable();

    _startDurationTicker();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    await _positionSub?.cancel();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onPositionUpdate);

    _publishState();
    await _saveRideState();

    debugPrint('Ride started');
  }

  Future<Trip?> stopRide() async {
    if (!isRideActive.value) return null;

    final completedTrip = _buildCompletedTrip();

    isRideActive.value = false;

    await _positionSub?.cancel();
    _positionSub = null;

    _durationTimer?.cancel();
    _durationTimer = null;

    speedKmh.value = 0;

    await WakelockPlus.disable();

    _publishState(isActiveOverride: false, speedOverride: 0);

    if (completedTrip != null) {
      await _saveCompletedTrip(completedTrip);
    }

    await _saveRideHistory();
    await _clearLiveRide();

    debugPrint('Ride stopped');

    return completedTrip;
  }

  void _onPositionUpdate(Position position) {
    final rawSpeed = position.speed < 0 ? 0.0 : position.speed;
    final currentSpeed = (rawSpeed * 3.6).clamp(0.0, 120.0);

    speedKmh.value = currentSpeed;
    maxSpeedKmh.value = max(maxSpeedKmh.value, currentSpeed);

    final point = LatLng(position.latitude, position.longitude);

    if (ridePath.value.isEmpty) {
      ridePath.value = [point];
    }

    if (_lastPosition != null) {
      final meters = Geolocator.distanceBetween(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      if (meters >= 1 && meters <= 150) {
        _totalMeters += meters;
        distanceKm.value = _totalMeters / 1000;

        ridePath.value = [...ridePath.value, point];
      }
    }

    _lastPosition = position;

    if (currentSpeed > 0.5) {
      _speedTotal += currentSpeed;
      _speedSamples++;
    }

    _updateAverageSpeed();

    _publishState(
      gpsAccuracy: position.accuracy,
      altitude: position.altitude,
      lastUpdate: position.timestamp,
    );

    _saveRideState();
  }

  void _startDurationTicker() {
    _durationTimer?.cancel();

    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_rideStart == null) return;

      rideDuration.value = DateTime.now().difference(_rideStart!);

      _updateAverageSpeed();
      _publishState();
      _saveRideState();
    });
  }

  void _updateAverageSpeed() {
    if (_speedSamples > 0) {
      averageSpeedKmh.value = _speedTotal / _speedSamples;
      return;
    }

    final hours = rideDuration.value.inSeconds / 3600;
    if (hours > 0) {
      averageSpeedKmh.value = distanceKm.value / hours;
    }
  }

  int _estimateCalories() {
    const riderWeightKg = 75.0;

    final met = averageSpeedKmh.value < 16
        ? 4.0
        : averageSpeedKmh.value < 20
        ? 6.8
        : averageSpeedKmh.value < 25
        ? 8.0
        : 10.0;

    final hours = rideDuration.value.inSeconds / 3600;
    return (met * riderWeightKg * hours).round();
  }

  Trip? _buildCompletedTrip() {
    if (_rideStart == null) return null;
    if (rideDuration.value.inSeconds < 3) return null;

    return Trip(
      startedAtMs: _rideStart!.millisecondsSinceEpoch,
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
      distanceM: distanceKm.value * 1000,
      brakes: 0,
      hardBrakes: 0,
      path: ridePath.value
          .map((p) => <double>[p.latitude, p.longitude])
          .toList(),
      source: 'software',
    );
  }

  Future<void> _saveCompletedTrip(Trip trip) async {
    final trips = await StorageService.loadTrips();

    final duplicate = trips.any(
      (t) =>
          t.startedAtMs == trip.startedAtMs &&
          (t.distanceM - trip.distanceM).abs() < 1,
    );

    if (!duplicate) {
      trips.insert(0, trip);
      await StorageService.saveTrips(trips);
    }
  }

  void _publishState({
    bool? isActiveOverride,
    double? speedOverride,
    double? gpsAccuracy,
    double? altitude,
    DateTime? lastUpdate,
  }) {
    LiveRideBus.instance.update(
      LiveRideState(
        isActive: isActiveOverride ?? isRideActive.value,
        isPaused: false,
        speedKmh: speedOverride ?? speedKmh.value,
        averageSpeedKmh: averageSpeedKmh.value,
        maxSpeedKmh: maxSpeedKmh.value,
        distanceKm: distanceKm.value,
        duration: rideDuration.value,
        calories: _estimateCalories(),
        gpsAccuracy:
            gpsAccuracy ?? LiveRideBus.instance.state.value.gpsAccuracy,
        altitude: altitude ?? LiveRideBus.instance.state.value.altitude,
        startedAt: _rideStart,
        lastUpdate: lastUpdate ?? DateTime.now(),
        path: List<LatLng>.from(ridePath.value),
      ),
    );
  }

  Future<void> _saveRideState() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('ride_active', isRideActive.value);
    await prefs.setDouble('ride_distance', distanceKm.value);
    await prefs.setDouble('ride_avg_speed', averageSpeedKmh.value);
    await prefs.setDouble('ride_max_speed', maxSpeedKmh.value);
    await prefs.setInt('ride_duration', rideDuration.value.inSeconds);
    await prefs.setDouble('ride_speed_total', _speedTotal);
    await prefs.setInt('ride_speed_samples', _speedSamples);

    if (_rideStart != null) {
      await prefs.setString('ride_start', _rideStart!.toIso8601String());
    }

    await prefs.setStringList(
      'ride_path',
      ridePath.value.map((p) => '${p.latitude},${p.longitude}').toList(),
    );
  }

  Future<void> _restoreRideState() async {
    final prefs = await SharedPreferences.getInstance();

    final active = prefs.getBool('ride_active') ?? false;

    distanceKm.value = prefs.getDouble('ride_distance') ?? 0;
    averageSpeedKmh.value = prefs.getDouble('ride_avg_speed') ?? 0;
    maxSpeedKmh.value = prefs.getDouble('ride_max_speed') ?? 0;

    _speedTotal = prefs.getDouble('ride_speed_total') ?? 0;
    _speedSamples = prefs.getInt('ride_speed_samples') ?? 0;

    rideDuration.value = Duration(seconds: prefs.getInt('ride_duration') ?? 0);

    final startString = prefs.getString('ride_start');
    if (startString != null) {
      _rideStart = DateTime.tryParse(startString);
    }

    final encodedPath = prefs.getStringList('ride_path') ?? [];

    ridePath.value = encodedPath
        .map((raw) {
          final parts = raw.split(',');
          if (parts.length != 2) return null;

          final lat = double.tryParse(parts[0]);
          final lng = double.tryParse(parts[1]);

          if (lat == null || lng == null) return null;

          return LatLng(lat, lng);
        })
        .whereType<LatLng>()
        .toList();

    _totalMeters = distanceKm.value * 1000;

    if (ridePath.value.isNotEmpty) {
      final last = ridePath.value.last;

      _lastPosition = Position(
        latitude: last.latitude,
        longitude: last.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        isMocked: false,
      );
    }

    isRideActive.value = active;

    _publishState();

    if (active) {
      await startRide();
    }

    debugPrint('Ride state restored');
  }

  Future<void> _saveRideHistory() async {
    final prefs = await SharedPreferences.getInstance();

    final history = prefs.getStringList('ride_history') ?? [];

    final entry = [
      DateTime.now().toIso8601String(),
      distanceKm.value.toStringAsFixed(2),
      averageSpeedKmh.value.toStringAsFixed(1),
      maxSpeedKmh.value.toStringAsFixed(1),
      rideDuration.value.inSeconds.toString(),
      ridePath.value.length.toString(),
    ].join('|');

    history.insert(0, entry);

    await prefs.setStringList('ride_history', history);
  }

  Future<void> _clearLiveRide() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('ride_active');
    await prefs.remove('ride_distance');
    await prefs.remove('ride_avg_speed');
    await prefs.remove('ride_max_speed');
    await prefs.remove('ride_duration');
    await prefs.remove('ride_start');
    await prefs.remove('ride_path');
    await prefs.remove('ride_speed_total');
    await prefs.remove('ride_speed_samples');

    speedKmh.value = 0;
    distanceKm.value = 0;
    averageSpeedKmh.value = 0;
    maxSpeedKmh.value = 0;
    rideDuration.value = Duration.zero;
    ridePath.value = [];

    _rideStart = null;
    _lastPosition = null;
    _totalMeters = 0;
    _speedTotal = 0;
    _speedSamples = 0;

    await LiveRideBus.instance.reset();
  }

  Future<bool> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) return false;

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    _durationTimer?.cancel();
  }
}
