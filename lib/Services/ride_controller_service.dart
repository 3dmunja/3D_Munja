import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/live_ride_state.dart';
import '../models/trip.dart';
import '../Services/live_ride_bus.dart';
import 'storage_service.dart';
import 'crystal_reward_service.dart';
import 'challenge_service.dart';

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

  Future<void>? _initializeFuture;
  bool _initialized = false;

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
      await LiveRideBus.instance.initialize();
      await _restoreRideState();
      _initialized = true;
    } finally {
      _initializeFuture = null;
    }
  }

  Future<void> startRide() async {
    final trackingAlreadyRunning =
        isRideActive.value &&
        _positionSub != null &&
        (_durationTimer?.isActive ?? false);

    if (trackingAlreadyRunning) {
      debugPrint('Ride start ignored: tracking is already running');
      return;
    }

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

    debugPrint(
      'Ride started: '
      'bus=${LiveRideBus.instance.debugInstanceId} '
      'active=${LiveRideBus.instance.state.value.isActive}',
    );
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
      final saved = await _saveCompletedTrip(completedTrip);

      if (saved) {
        await _syncActiveChallengeProgress(completedTrip);
        await _grantCompletedRideRewards(completedTrip);
      }
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

  Future<bool> _saveCompletedTrip(Trip trip) async {
    final trips = await StorageService.loadTrips();

    final duplicate = trips.any(
      (t) =>
          t.startedAtMs == trip.startedAtMs &&
          (t.distanceM - trip.distanceM).abs() < 1,
    );

    if (duplicate) {
      debugPrint(
        'RIDE CONTROLLER SAVE: duplicate skipped '
        'start=${trip.startedAtMs} distance=${trip.distanceM.toStringAsFixed(1)}m',
      );
      return false;
    }

    trips.insert(0, trip);
    await StorageService.saveTrips(trips);

    debugPrint(
      'RIDE CONTROLLER SAVE: completed trip saved '
      'start=${trip.startedAtMs} end=${trip.endedAtMs} '
      'distance=${trip.distanceM.toStringAsFixed(1)}m',
    );

    return true;
  }

  Future<void> _syncActiveChallengeProgress(Trip trip) async {
    final completedDistanceKm = trip.distanceM / 1000;

    if (completedDistanceKm <= 0) {
      debugPrint(
        'CHALLENGE PROGRESS: skipped because completed ride distance is 0 km.',
      );
      return;
    }

    try {
      final activeChallenges =
          await ChallengeService.instance.getActiveChallenges();

      if (activeChallenges.isEmpty) {
        debugPrint(
          'CHALLENGE PROGRESS: no active challenges for current user.',
        );
        return;
      }

      debugPrint(
        'CHALLENGE PROGRESS: syncing '
        '${completedDistanceKm.toStringAsFixed(3)} km '
        'to ${activeChallenges.length} active challenge(s).',
      );

      for (final challenge in activeChallenges) {
        try {
          final progressBefore = ChallengeService.instance.currentUid == null
              ? 0.0
              : challenge.progressFor(
                  ChallengeService.instance.currentUid!,
                );

          await ChallengeService.instance.addDistanceProgress(
            challengeId: challenge.id,
            distanceKm: completedDistanceKm,
          );

          debugPrint(
            'CHALLENGE PROGRESS UPDATED: '
            'challenge=${challenge.id} '
            'distanceAdded=${completedDistanceKm.toStringAsFixed(3)}km '
            'progressBefore=${progressBefore.toStringAsFixed(3)}km '
            'target=${challenge.targetDistanceKm.toStringAsFixed(1)}km',
          );
        } catch (error, stackTrace) {
          // One broken/expired challenge must not block other active
          // challenges, Crystal rewards, or the already-saved ride.
          debugPrint(
            'CHALLENGE PROGRESS UPDATE ERROR: '
            'challenge=${challenge.id} -> $error',
          );
          debugPrint('$stackTrace');
        }
      }
    } catch (error, stackTrace) {
      // The Trip has already been saved locally at this point.
      // Challenge sync is a side effect and must never make stopRide fail.
      debugPrint('CHALLENGE PROGRESS SYNC ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _grantCompletedRideRewards(Trip trip) async {
    final uid = StorageService.currentUserId?.trim();

    if (uid == null || uid.isEmpty) {
      debugPrint(
        'CRYSTAL REWARD: skipped because no Firebase user is signed in.',
      );
      return;
    }

    final rideId = _rewardRideId(trip);

    try {
      final rideReward =
          await CrystalRewardService.instance.grantRideCompletedReward(
        uid: uid,
        rideId: rideId,
        amount: 2,
        distanceKm: trip.distanceM / 1000,
      );

      debugPrint(
        'CRYSTAL REWARD RIDE: '
        'status=${rideReward.status} '
        'ride=$rideId '
        'amount=${rideReward.amount} '
        'balance=${rideReward.newBalance}',
      );

      final firstRideReward =
          await CrystalRewardService.instance.grantFirstRideReward(
        uid: uid,
        rideId: rideId,
        amount: 20,
      );

      debugPrint(
        'CRYSTAL REWARD FIRST RIDE: '
        'status=${firstRideReward.status} '
        'ride=$rideId '
        'amount=${firstRideReward.amount} '
        'balance=${firstRideReward.newBalance}',
      );
    } catch (error, stackTrace) {
      // The ride has already been saved locally at this point.
      // Reward failure must never make stopRide fail or lose the completed ride.
      debugPrint('CRYSTAL REWARD AFTER RIDE ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  String _rewardRideId(Trip trip) {
    return '${trip.startedAtMs}_${trip.endedAtMs}';
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

    final hadPersistedActiveRide =
        prefs.getBool('ride_active') ?? false;
    final persistedDistance =
        prefs.getDouble('ride_distance') ?? 0.0;
    final persistedPath =
        prefs.getStringList('ride_path') ?? const <String>[];

    if (hadPersistedActiveRide ||
        persistedDistance > 0 ||
        persistedPath.isNotEmpty) {
      debugPrint(
        'RIDE CONTROLLER STARTUP: stale persisted ride found '
        'active=$hadPersistedActiveRide '
        'distance=${persistedDistance.toStringAsFixed(3)} '
        'path=${persistedPath.length}. '
        'Discarding it instead of auto-resuming.',
      );
    }

    // IMPORTANT:
    // A new app process must not automatically resurrect a previous ride.
    //
    // Previously this service restored ride_active=true, published that state
    // back into LiveRideBus and then called startRide(). That reactivated Home
    // navigation even after LiveRideBus itself had already sanitized its own
    // persisted state.
    //
    // For now Munja uses an explicit-session rule:
    //   - app startup always begins with no active ride;
    //   - only an explicit user start may activate GPS tracking;
    //   - stale persisted ride snapshots are cleared on startup.
    //
    // Proper crash/interruption recovery can later be implemented as an
    // explicit "Resume ride?" flow instead of silently restarting a ride.
    await _clearLiveRide();

    isRideActive.value = false;

    debugPrint(
      'Ride state startup sanitized: '
      'active=${isRideActive.value} '
      'bus=${LiveRideBus.instance.debugInstanceId}',
    );
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

    isRideActive.value = false;

    await _positionSub?.cancel();
    _positionSub = null;

    _durationTimer?.cancel();
    _durationTimer = null;

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
