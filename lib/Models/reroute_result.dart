enum RerouteStatus {
  idle,
  waitingForConfirmation,
  rerouting,
  success,
  failed,
  cooldown,
}

class RerouteResult {
  const RerouteResult({
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.originLatitude,
    required this.originLongitude,
    required this.destinationLatitude,
    required this.destinationLongitude,
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.encodedPolyline,
    this.message,
    this.error,
  });

  final RerouteStatus status;

  final DateTime startedAt;
  final DateTime finishedAt;

  final double originLatitude;
  final double originLongitude;

  final double destinationLatitude;
  final double destinationLongitude;

  final double? routeDistanceMeters;
  final int? routeDurationSeconds;
  final String? encodedPolyline;

  final String? message;
  final String? error;

  bool get isSuccess => status == RerouteStatus.success;

  bool get isFailure => status == RerouteStatus.failed;

  bool get hasRoute {
    return encodedPolyline != null &&
        encodedPolyline!.trim().isNotEmpty &&
        routeDistanceMeters != null &&
        routeDurationSeconds != null;
  }

  Duration get elapsed {
    return finishedAt.difference(startedAt);
  }

  String get distanceLabel {
    final meters = routeDistanceMeters;

    if (meters == null) {
      return '—';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String get durationLabel {
    final seconds = routeDurationSeconds;

    if (seconds == null) {
      return '—';
    }

    final minutes = (seconds / 60).ceil();

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes.remainder(60);

    if (remainingMinutes == 0) {
      return '$hours t';
    }

    return '$hours t $remainingMinutes min';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'status': status.name,
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'originLatitude': originLatitude,
      'originLongitude': originLongitude,
      'destinationLatitude': destinationLatitude,
      'destinationLongitude': destinationLongitude,
      'routeDistanceMeters': routeDistanceMeters,
      'routeDurationSeconds': routeDurationSeconds,
      'encodedPolyline': encodedPolyline,
      'message': message,
      'error': error,
    };
  }

  factory RerouteResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return RerouteResult(
      status: RerouteStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => RerouteStatus.failed,
      ),
      startedAt: DateTime.tryParse(
            json['startedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      finishedAt: DateTime.tryParse(
            json['finishedAt'] as String? ?? '',
          ) ??
          DateTime.now(),
      originLatitude:
          (json['originLatitude'] as num?)?.toDouble() ?? 0,
      originLongitude:
          (json['originLongitude'] as num?)?.toDouble() ?? 0,
      destinationLatitude:
          (json['destinationLatitude'] as num?)?.toDouble() ?? 0,
      destinationLongitude:
          (json['destinationLongitude'] as num?)?.toDouble() ?? 0,
      routeDistanceMeters:
          (json['routeDistanceMeters'] as num?)?.toDouble(),
      routeDurationSeconds:
          (json['routeDurationSeconds'] as num?)?.toInt(),
      encodedPolyline:
          json['encodedPolyline'] as String?,
      message: json['message'] as String?,
      error: json['error'] as String?,
    );
  }

  @override
  String toString() {
    return 'RerouteResult('
        'status: ${status.name}, '
        'distance: $routeDistanceMeters, '
        'duration: $routeDurationSeconds, '
        'elapsed: ${elapsed.inMilliseconds}ms, '
        'message: $message, '
        'error: $error'
        ')';
  }
}
