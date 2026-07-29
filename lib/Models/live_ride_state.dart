import 'package:google_maps_flutter/google_maps_flutter.dart';

class LiveRideState {
  final bool isActive;
  final bool isPaused;
  final double speedKmh;
  final double averageSpeedKmh;
  final double maxSpeedKmh;
  final double distanceKm;
  final Duration duration;
  final int calories;
  final double gpsAccuracy;
  final double? altitude;
  final DateTime? startedAt;
  final DateTime? lastUpdate;
  final List<LatLng> path;

  const LiveRideState({
    required this.isActive,
    required this.isPaused,
    required this.speedKmh,
    required this.averageSpeedKmh,
    required this.maxSpeedKmh,
    required this.distanceKm,
    required this.duration,
    required this.calories,
    required this.gpsAccuracy,
    required this.altitude,
    required this.startedAt,
    required this.lastUpdate,
    required this.path,
  });

  factory LiveRideState.initial() {
    return const LiveRideState(
      isActive: false,
      isPaused: false,
      speedKmh: 0,
      averageSpeedKmh: 0,
      maxSpeedKmh: 0,
      distanceKm: 0,
      duration: Duration.zero,
      calories: 0,
      gpsAccuracy: 0,
      altitude: null,
      startedAt: null,
      lastUpdate: null,
      path: [],
    );
  }

  LiveRideState copyWith({
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
    return LiveRideState(
      isActive: isActive ?? this.isActive,
      isPaused: isPaused ?? this.isPaused,
      speedKmh: speedKmh ?? this.speedKmh,
      averageSpeedKmh: averageSpeedKmh ?? this.averageSpeedKmh,
      maxSpeedKmh: maxSpeedKmh ?? this.maxSpeedKmh,
      distanceKm: distanceKm ?? this.distanceKm,
      duration: duration ?? this.duration,
      calories: calories ?? this.calories,
      gpsAccuracy: gpsAccuracy ?? this.gpsAccuracy,
      altitude: altitude ?? this.altitude,
      startedAt: startedAt ?? this.startedAt,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      path: path ?? this.path,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isActive': isActive,
      'isPaused': isPaused,
      'speedKmh': speedKmh,
      'averageSpeedKmh': averageSpeedKmh,
      'maxSpeedKmh': maxSpeedKmh,
      'distanceKm': distanceKm,
      'durationSeconds': duration.inSeconds,
      'calories': calories,
      'gpsAccuracy': gpsAccuracy,
      'altitude': altitude,
      'startedAt': startedAt?.millisecondsSinceEpoch,
      'lastUpdate': lastUpdate?.millisecondsSinceEpoch,
      'path': path.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    };
  }

  factory LiveRideState.fromJson(Map<String, dynamic> json) {
    return LiveRideState(
      isActive: json['isActive'] == true,
      isPaused: json['isPaused'] == true,
      speedKmh: ((json['speedKmh'] as num?) ?? 0).toDouble(),
      averageSpeedKmh: ((json['averageSpeedKmh'] as num?) ?? 0).toDouble(),
      maxSpeedKmh: ((json['maxSpeedKmh'] as num?) ?? 0).toDouble(),
      distanceKm: ((json['distanceKm'] as num?) ?? 0).toDouble(),
      duration: Duration(
        seconds: ((json['durationSeconds'] as num?) ?? 0).toInt(),
      ),
      calories: ((json['calories'] as num?) ?? 0).toInt(),
      gpsAccuracy: ((json['gpsAccuracy'] as num?) ?? 0).toDouble(),
      altitude: json['altitude'] == null
          ? null
          : (json['altitude'] as num).toDouble(),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['startedAt']),
      lastUpdate: json['lastUpdate'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(json['lastUpdate']),
      path: ((json['path'] as List?) ?? const []).map((p) {
        final map = p as Map;
        return LatLng(
          ((map['lat'] as num?) ?? 0).toDouble(),
          ((map['lng'] as num?) ?? 0).toDouble(),
        );
      }).toList(),
    );
  }
}
