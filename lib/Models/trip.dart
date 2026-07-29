import 'package:google_maps_flutter/google_maps_flutter.dart';

enum TripSource { software, hardware }

class Trip {
  final int startedAtMs;
  final int endedAtMs;
  final double distanceM;
  final int brakes;
  final int hardBrakes;
  final List<List<double>> path;
  final String source;

  const Trip({
    required this.startedAtMs,
    required this.endedAtMs,
    required this.distanceM,
    required this.brakes,
    required this.hardBrakes,
    required this.path,
    required this.source,
  });

  TripSource get tripSource =>
      source == 'hardware' ? TripSource.hardware : TripSource.software;

  Duration get duration => Duration(
    milliseconds: endedAtMs - startedAtMs < 0 ? 0 : endedAtMs - startedAtMs,
  );

  List<LatLng> get latLngPath =>
      path.where((e) => e.length >= 2).map((e) => LatLng(e[0], e[1])).toList();

  Map<String, dynamic> toJson() => {
    'startedAtMs': startedAtMs,
    'endedAtMs': endedAtMs,
    'distanceM': distanceM,
    'brakes': brakes,
    'hardBrakes': hardBrakes,
    'path': path,
    'source': source,
  };

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      startedAtMs: json['startedAtMs'] as int,
      endedAtMs: json['endedAtMs'] as int,
      distanceM: (json['distanceM'] as num).toDouble(),
      brakes: (json['brakes'] as int?) ?? 0,
      hardBrakes: (json['hardBrakes'] as int?) ?? 0,
      path: (json['path'] as List? ?? const [])
          .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
          .where((e) => e.length >= 2)
          .map((e) => <double>[e[0], e[1]])
          .toList(),
      source: (json['source'] as String?) ?? 'software',
    );
  }
}
