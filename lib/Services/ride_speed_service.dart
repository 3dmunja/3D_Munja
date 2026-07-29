import 'dart:async';
import 'package:geolocator/geolocator.dart';

class RideSpeedData {
  final double speedKmh;
  final double rawSpeedMs;
  final double accuracy;
  final DateTime timestamp;

  const RideSpeedData({
    required this.speedKmh,
    required this.rawSpeedMs,
    required this.accuracy,
    required this.timestamp,
  });
}

class RideSpeedService {
  StreamSubscription<Position>? _sub;

  final _controller = StreamController<RideSpeedData>.broadcast();

  Stream<RideSpeedData> get stream => _controller.stream;

  Future<void> start() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );

    _sub = Geolocator.getPositionStream(locationSettings: settings).listen((
      position,
    ) {
      final rawMs = position.speed < 0 ? 0.0 : position.speed;
      final kmh = rawMs * 3.6;

      _controller.add(
        RideSpeedData(
          speedKmh: kmh,
          rawSpeedMs: rawMs,
          accuracy: position.accuracy,
          timestamp: position.timestamp,
        ),
      );
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }
}
