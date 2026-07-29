import 'package:google_maps_flutter/google_maps_flutter.dart';

enum RideRouteType { easy, fitness, scenic, challenge, commute }

extension RideRouteTypeX on RideRouteType {
  String get title {
    switch (this) {
      case RideRouteType.easy:
        return 'Easy Ride';
      case RideRouteType.fitness:
        return 'Fitness Ride';
      case RideRouteType.scenic:
        return 'Scenic Ride';
      case RideRouteType.challenge:
        return 'Challenge Ride';
      case RideRouteType.commute:
        return 'Commute';
    }
  }

  String get subtitle {
    switch (this) {
      case RideRouteType.easy:
        return 'Short, safe and relaxed.';
      case RideRouteType.fitness:
        return 'Balanced speed and distance.';
      case RideRouteType.scenic:
        return 'Beautiful route with parks or water.';
      case RideRouteType.challenge:
        return 'Longer and more demanding.';
      case RideRouteType.commute:
        return 'Fast practical route.';
    }
  }

  String get emoji {
    switch (this) {
      case RideRouteType.easy:
        return '🌿';
      case RideRouteType.fitness:
        return '⚡';
      case RideRouteType.scenic:
        return '🌊';
      case RideRouteType.challenge:
        return '🔥';
      case RideRouteType.commute:
        return '🏙️';
    }
  }
}

class RideRoutePlan {
  final String id;
  final String title;
  final String subtitle;
  final RideRouteType type;
  final double distanceKm;
  final Duration estimatedDuration;
  final int difficulty;
  final int safetyScore;
  final int scenicScore;
  final int fitnessScore;
  final List<String> tags;
  final List<LatLng> previewPath;

  const RideRoutePlan({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.distanceKm,
    required this.estimatedDuration,
    required this.difficulty,
    required this.safetyScore,
    required this.scenicScore,
    required this.fitnessScore,
    required this.tags,
    required this.previewPath,
  });

  String get durationText {
    final h = estimatedDuration.inHours;
    final m = estimatedDuration.inMinutes.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String get difficultyText {
    if (difficulty <= 2) return 'Easy';
    if (difficulty <= 4) return 'Medium';
    return 'Hard';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'subtitle': subtitle,
      'type': type.name,
      'distanceKm': distanceKm,
      'estimatedDurationSeconds': estimatedDuration.inSeconds,
      'difficulty': difficulty,
      'safetyScore': safetyScore,
      'scenicScore': scenicScore,
      'fitnessScore': fitnessScore,
      'tags': tags,
      'previewPath': previewPath
          .map((p) => {'lat': p.latitude, 'lng': p.longitude})
          .toList(),
    };
  }

  factory RideRoutePlan.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'easy';

    return RideRoutePlan(
      id:
          json['id'] as String? ??
          'route_${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Smart Route',
      subtitle: json['subtitle'] as String? ?? 'Saved route',
      type: RideRouteType.values.firstWhere(
        (t) => t.name == typeName,
        orElse: () => RideRouteType.easy,
      ),
      distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0,
      estimatedDuration: Duration(
        seconds: (json['estimatedDurationSeconds'] as num?)?.toInt() ?? 0,
      ),
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      safetyScore: (json['safetyScore'] as num?)?.toInt() ?? 0,
      scenicScore: (json['scenicScore'] as num?)?.toInt() ?? 0,
      fitnessScore: (json['fitnessScore'] as num?)?.toInt() ?? 0,
      tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      previewPath:
          (json['previewPath'] as List?)
              ?.map(
                (p) => LatLng(
                  ((p as Map)['lat'] as num).toDouble(),
                  (p['lng'] as num).toDouble(),
                ),
              )
              .toList() ??
          [],
    );
  }

  RideRoutePlan copyWith({
    String? id,
    String? title,
    String? subtitle,
    RideRouteType? type,
    double? distanceKm,
    Duration? estimatedDuration,
    int? difficulty,
    int? safetyScore,
    int? scenicScore,
    int? fitnessScore,
    List<String>? tags,
    List<LatLng>? previewPath,
  }) {
    return RideRoutePlan(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      type: type ?? this.type,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      difficulty: difficulty ?? this.difficulty,
      safetyScore: safetyScore ?? this.safetyScore,
      scenicScore: scenicScore ?? this.scenicScore,
      fitnessScore: fitnessScore ?? this.fitnessScore,
      tags: tags ?? this.tags,
      previewPath: previewPath ?? this.previewPath,
    );
  }

  factory RideRoutePlan.mock({
    required RideRouteType type,
    required LatLng center,
  }) {
    switch (type) {
      case RideRouteType.easy:
        return RideRoutePlan(
          id: 'easy_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Easy Neighborhood Loop',
          subtitle: 'A calm beginner-friendly loop near you.',
          type: type,
          distanceKm: 3.2,
          estimatedDuration: const Duration(minutes: 14),
          difficulty: 1,
          safetyScore: 92,
          scenicScore: 68,
          fitnessScore: 35,
          tags: const ['Flat', 'Safe', 'Beginner'],
          previewPath: _loopPath(center, 0.006),
        );

      case RideRouteType.fitness:
        return RideRoutePlan(
          id: 'fitness_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Fitness Tempo Route',
          subtitle: 'A faster ride with a steady pace.',
          type: type,
          distanceKm: 8.5,
          estimatedDuration: const Duration(minutes: 28),
          difficulty: 3,
          safetyScore: 78,
          scenicScore: 60,
          fitnessScore: 86,
          tags: const ['Tempo', 'Workout', 'Medium'],
          previewPath: _loopPath(center, 0.013),
        );

      case RideRouteType.scenic:
        return RideRoutePlan(
          id: 'scenic_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Scenic Green Route',
          subtitle: 'A beautiful relaxing ride with nicer surroundings.',
          type: type,
          distanceKm: 6.7,
          estimatedDuration: const Duration(minutes: 25),
          difficulty: 2,
          safetyScore: 84,
          scenicScore: 94,
          fitnessScore: 55,
          tags: const ['Scenic', 'Relaxed', 'Parks'],
          previewPath: _wavePath(center, 0.011),
        );

      case RideRouteType.challenge:
        return RideRoutePlan(
          id: 'challenge_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Munja Challenge Ride',
          subtitle: 'A longer ride built to push your limits.',
          type: type,
          distanceKm: 15.4,
          estimatedDuration: const Duration(minutes: 52),
          difficulty: 5,
          safetyScore: 70,
          scenicScore: 72,
          fitnessScore: 96,
          tags: const ['Hard', 'Endurance', 'Challenge'],
          previewPath: _loopPath(center, 0.023),
        );

      case RideRouteType.commute:
        return RideRoutePlan(
          id: 'commute_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Fast Commute Route',
          subtitle: 'A practical route focused on time and efficiency.',
          type: type,
          distanceKm: 5.1,
          estimatedDuration: const Duration(minutes: 18),
          difficulty: 2,
          safetyScore: 80,
          scenicScore: 42,
          fitnessScore: 62,
          tags: const ['Fast', 'Direct', 'Urban'],
          previewPath: _directPath(center, 0.012),
        );
    }
  }

  static List<LatLng> _loopPath(LatLng center, double size) {
    return [
      center,
      LatLng(center.latitude + size, center.longitude + size * 0.4),
      LatLng(center.latitude + size * 0.5, center.longitude + size),
      LatLng(center.latitude - size * 0.4, center.longitude + size * 0.8),
      LatLng(center.latitude - size, center.longitude - size * 0.2),
      LatLng(center.latitude - size * 0.3, center.longitude - size),
      center,
    ];
  }

  static List<LatLng> _wavePath(LatLng center, double size) {
    return [
      center,
      LatLng(center.latitude + size * 0.4, center.longitude + size * 0.3),
      LatLng(center.latitude + size * 0.9, center.longitude - size * 0.1),
      LatLng(center.latitude + size * 1.1, center.longitude + size * 0.8),
      LatLng(center.latitude + size * 0.2, center.longitude + size * 1.1),
      LatLng(center.latitude - size * 0.5, center.longitude + size * 0.6),
    ];
  }

  static List<LatLng> _directPath(LatLng center, double size) {
    return [
      center,
      LatLng(center.latitude + size * 0.3, center.longitude + size * 0.2),
      LatLng(center.latitude + size * 0.7, center.longitude + size * 0.5),
      LatLng(center.latitude + size, center.longitude + size * 0.8),
    ];
  }
}
