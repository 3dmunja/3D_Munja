import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';

class RideSessionData {
  final bool isRiding;
  final double currentSpeedKmh;
  final double averageSpeedKmh;
  final double maxSpeedKmh;
  final double distanceKm;
  final Duration rideDuration;
  final double calories;
  final double? altitude;
  final double gpsAccuracy;
  final DateTime? lastUpdate;

  /// Path format:
  /// [
  ///   [latitude, longitude],
  ///   [latitude, longitude],
  /// ]
  ///
  /// Denne path bliver gemt i Trip.path, så ruten kan vises efter turen.
  final List<List<double>> path;

  const RideSessionData({
    required this.isRiding,
    required this.currentSpeedKmh,
    required this.averageSpeedKmh,
    required this.maxSpeedKmh,
    required this.distanceKm,
    required this.rideDuration,
    required this.calories,
    required this.altitude,
    required this.gpsAccuracy,
    required this.lastUpdate,
    required this.path,
  });

  factory RideSessionData.initial() {
    return const RideSessionData(
      isRiding: false,
      currentSpeedKmh: 0,
      averageSpeedKmh: 0,
      maxSpeedKmh: 0,
      distanceKm: 0,
      rideDuration: Duration.zero,
      calories: 0,
      altitude: null,
      gpsAccuracy: 0,
      lastUpdate: null,
      path: [],
    );
  }

  RideSessionData copyWith({
    bool? isRiding,
    double? currentSpeedKmh,
    double? averageSpeedKmh,
    double? maxSpeedKmh,
    double? distanceKm,
    Duration? rideDuration,
    double? calories,
    double? altitude,
    double? gpsAccuracy,
    DateTime? lastUpdate,
    List<List<double>>? path,
  }) {
    return RideSessionData(
      isRiding: isRiding ?? this.isRiding,
      currentSpeedKmh: currentSpeedKmh ?? this.currentSpeedKmh,
      averageSpeedKmh: averageSpeedKmh ?? this.averageSpeedKmh,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      distanceKm: distanceKm ?? this.distanceKm,
      rideDuration: rideDuration ?? this.rideDuration,
      calories: calories ?? this.calories,
      altitude: altitude ?? this.altitude,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      path: path ?? this.path,
    );
  }
}

class RideSessionService {
  static final RideSessionService instance = RideSessionService._internal();

  factory RideSessionService() => instance;

  RideSessionService._internal();

  final StreamController<RideSessionData> _controller =
      StreamController<RideSessionData>.broadcast();

  Stream<RideSessionData> get stream => _controller.stream;

  RideSessionData _data = RideSessionData.initial();

  StreamSubscription<Position>? _positionSub;
  Timer? _timer;

  Position? _lastAcceptedPosition;
  DateTime? _startedAt;

  double _distanceMeters = 0;
  double _speedTotal = 0;
  int _speedSamples = 0;

  final List<List<double>> _path = [];

  RideSessionData get current => _data;

  Future<void> start() async {
    if (_data.isRiding) return;

    final ready = await _ensureLocationReady();

    if (!ready) {
      _data = RideSessionData.initial();
      _emit();
      return;
    }

    _startedAt = DateTime.now();
    _lastAcceptedPosition = null;
    _distanceMeters = 0;
    _speedTotal = 0;
    _speedSamples = 0;
    _path.clear();

    _data = RideSessionData.initial().copyWith(
      isRiding: true,
      lastUpdate: DateTime.now(),
      path: const [],
    );

    _emit();

    try {
      final firstPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      _acceptFirstPosition(firstPosition);
    } catch (_) {
      // Appen skal ikke crashe hvis første GPS punkt fejler.
      // Streamen nedenfor prøver videre.
    }

    _timer?.cancel();

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_startedAt == null) return;

      _data = _data.copyWith(
        rideDuration: DateTime.now().difference(_startedAt!),
        distanceKm: _distanceMeters / 1000,
        calories: _estimateCalories(
          distanceKm: _distanceMeters / 1000,
          averageSpeedKmh: _data.averageSpeedKmh,
        ),
        path: List<List<double>>.from(_path),
      );

      _emit();
    });

    await _positionSub?.cancel();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen(_onPosition, onError: (_) {}, cancelOnError: false);
  }

  Future<RideSessionData?> stop() async {
    if (!_data.isRiding) return null;

    final finishedRide = _data.copyWith(
      isRiding: false,
      currentSpeedKmh: 0,
      distanceKm: _distanceMeters / 1000,
      rideDuration: _startedAt == null
          ? _data.rideDuration
          : DateTime.now().difference(_startedAt!),
      calories: _estimateCalories(
        distanceKm: _distanceMeters / 1000,
        averageSpeedKmh: _data.averageSpeedKmh,
      ),
      lastUpdate: DateTime.now(),
      path: List<List<double>>.from(_path),
    );

    await _positionSub?.cancel();
    _positionSub = null;

    _timer?.cancel();
    _timer = null;

    _lastAcceptedPosition = null;
    _startedAt = null;

    _data = finishedRide;

    _emit();

    return finishedRide;
  }

  Future<void> reset() async {
    await stop();

    _distanceMeters = 0;
    _speedTotal = 0;
    _speedSamples = 0;
    _path.clear();

    _data = RideSessionData.initial();

    _emit();
  }

  void _acceptFirstPosition(Position position) {
    if (!_isUsablePosition(position)) return;

    _lastAcceptedPosition = position;

    _addPathPoint(position);

    _data = _data.copyWith(
      altitude: position.altitude,
      gpsAccuracy: position.accuracy,
      lastUpdate: DateTime.now(),
      path: List<List<double>>.from(_path),
    );

    _emit();
  }

  void _onPosition(Position position) {
    if (!_data.isRiding) return;
    if (!_isUsablePosition(position)) return;

    final rawSpeedMs = position.speed < 0 ? 0.0 : position.speed;
    final speedKmh = rawSpeedMs * 3.6;

    if (_lastAcceptedPosition != null) {
      final meters = Geolocator.distanceBetween(
        _lastAcceptedPosition!.latitude,
        _lastAcceptedPosition!.longitude,
        position.latitude,
        position.longitude,
      );

      final seconds = _secondsBetween(
        _lastAcceptedPosition!.timestamp,
        position.timestamp,
      );

      final maxPossibleMeters = max(35.0, seconds * 22.5);

      if (meters >= 0.8 && meters <= maxPossibleMeters) {
        _distanceMeters += meters;
        _addPathPoint(position);
      }
    } else {
      _addPathPoint(position);
    }

    _lastAcceptedPosition = position;

    if (speedKmh >= 0 && speedKmh <= 80) {
      _speedTotal += speedKmh;
      _speedSamples++;

      final averageSpeed = _speedSamples == 0
          ? 0.0
          : _speedTotal / _speedSamples;

      _data = _data.copyWith(
        currentSpeedKmh: speedKmh,
        averageSpeedKmh: averageSpeed,
        maxSpeedKmh: max(_data.maxSpeedKmh, speedKmh),
        distanceKm: _distanceMeters / 1000,
        rideDuration: _startedAt == null
            ? _data.rideDuration
            : DateTime.now().difference(_startedAt!),
        calories: _estimateCalories(
          distanceKm: _distanceMeters / 1000,
          averageSpeedKmh: averageSpeed,
        ),
        altitude: position.altitude,
        gpsAccuracy: position.accuracy,
        lastUpdate: DateTime.now(),
        path: List<List<double>>.from(_path),
      );

      _emit();
    }
  }

  void _addPathPoint(Position position) {
    final point = <double>[position.latitude, position.longitude];

    if (_path.isEmpty) {
      _path.add(point);
      return;
    }

    final last = _path.last;

    final lastLat = last[0];
    final lastLng = last[1];

    final meters = Geolocator.distanceBetween(
      lastLat,
      lastLng,
      position.latitude,
      position.longitude,
    );

    if (meters >= 0.8) {
      _path.add(point);
    }
  }

  bool _isUsablePosition(Position position) {
    if (position.latitude == 0 && position.longitude == 0) return false;

    if (position.accuracy.isNaN || position.accuracy.isInfinite) return false;

    if (position.accuracy > 50) return false;

    return true;
  }

  double _secondsBetween(DateTime? previous, DateTime? current) {
    if (previous == null || current == null) return 1;

    final seconds = current.difference(previous).inMilliseconds / 1000.0;

    if (seconds <= 0) return 1;

    return seconds;
  }

  double _estimateCalories({
    required double distanceKm,
    required double averageSpeedKmh,
  }) {
    if (distanceKm <= 0) return 0;

    final intensity = averageSpeedKmh < 12
        ? 22
        : averageSpeedKmh < 18
        ? 30
        : averageSpeedKmh < 25
        ? 38
        : 46;

    return distanceKm * intensity;
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  void _emit() {
    if (_controller.isClosed) return;
    _controller.add(_data);
  }

  Future<void> dispose() async {
    await _positionSub?.cancel();
    _positionSub = null;

    _timer?.cancel();
    _timer = null;

    await _controller.close();
  }
}
