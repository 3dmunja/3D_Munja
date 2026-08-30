import 'dart:math';

import 'package:flutter/material.dart';

import 'ride_session_service.dart';

enum CoachState {
  idle,
  warmingUp,
  optimalPace,
  pushingTooHard,
  fatigueDetected,
  recovering,
  sprintReady,
  urbanCaution,
  gpsWeak,
  milestone,
  personalBest,
}

enum CoachPriority { low, medium, high }

enum AiCoachTier {
  free,
  pro,
}

class CoachInsight {
  final CoachState state;
  final CoachPriority priority;
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final DateTime createdAt;

  const CoachInsight({
    required this.state,
    required this.priority,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.createdAt,
  });
}

class AiRideCoachService {
  RideSessionData? _previousData;
  DateTime? _lastInsightAt;

  double _lastSpeedKmh = 0;
  int _lowSpeedTicks = 0;
  int _highEffortTicks = 0;
  int _steadyTicks = 0;

  int _lastDistanceMilestoneKm = 0;
  int _lastDurationMilestoneMin = 0;

  /// Clears temporary ride-adaptation state.
  ///
  /// Call this when a ride ends, a new rider session starts, or when switching
  /// accounts. It does not persist or delete any ride history.
  void reset() {
    _resetSoft();
  }

  /// True when the caller is allowed to use the adaptive Pro layer.
  static bool isAdaptiveTier(AiCoachTier tier) {
    return tier == AiCoachTier.pro;
  }

  /// FREE:
  /// - safety
  /// - warm-up
  /// - basic pace feedback
  /// - simple ride milestones
  ///
  /// PRO:
  /// - all FREE feedback
  /// - fatigue detection
  /// - recovery detection
  /// - stronger acceleration / effort coaching
  /// - personalized comparison against historic averages
  CoachInsight analyze({
    required RideSessionData data,
    required bool bleConnected,
    int batteryPercent = 100,
    AiCoachTier tier = AiCoachTier.free,
    double? historicAverageSpeedKmh,
    double? historicAverageDistanceKm,
  }) {
    final now = DateTime.now();

    final speed = data.currentSpeedKmh;
    final avg = data.averageSpeedKmh;
    final duration = data.rideDuration;
    final accuracy = data.gpsAccuracy;

    final acceleration = speed - _lastSpeedKmh;
    _lastSpeedKmh = speed;

    if (!data.isRiding) {
      _resetSoft();
      return _idle(now, tier);
    }

    // Safety feedback is always available.
    if (accuracy > 35) {
      return _gpsWeak(now);
    }

    if (!bleConnected && duration.inSeconds > 20) {
      return _urbanCaution(now);
    }

    if (batteryPercent <= 15) {
      return CoachInsight(
        state: CoachState.urbanCaution,
        priority: CoachPriority.high,
        title: 'Low device battery',
        message:
            'Brake light battery is low. Consider ending or reducing night ride.',
        icon: Icons.battery_alert_rounded,
        color: Colors.orangeAccent,
        createdAt: now,
      );
    }

    if (duration.inSeconds < 45) {
      return CoachInsight(
        state: CoachState.warmingUp,
        priority: CoachPriority.low,
        title: 'Warming up',
        message: tier == AiCoachTier.pro
            ? 'Build speed gradually. Munja Pro is learning your pace for this ride.'
            : 'Build speed gradually and keep your breathing steady.',
        icon: Icons.local_fire_department_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    _updateCounters(
      speed: speed,
      averageSpeed: avg,
    );

    final milestone = _distanceOrTimeMilestone(
      now: now,
      data: data,
      tier: tier,
    );

    if (milestone != null) {
      return milestone;
    }

    // FREE gets useful live pacing without the deeper adaptation.
    if (tier == AiCoachTier.free) {
      if (_highEffortTicks >= 8) {
        return CoachInsight(
          state: CoachState.pushingTooHard,
          priority: CoachPriority.medium,
          title: 'High pace',
          message:
              'You are riding well above your current average. Keep it controlled.',
          icon: Icons.flash_on_rounded,
          color: Colors.orangeAccent,
          createdAt: now,
        );
      }

      if (_steadyTicks >= 15) {
        return CoachInsight(
          state: CoachState.optimalPace,
          priority: CoachPriority.low,
          title: 'Steady pace',
          message: 'Nice rhythm. Keep your pace smooth and consistent.',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF42F5B0),
          createdAt: now,
        );
      }

      _previousData = data;
      _lastInsightAt = now;

      return CoachInsight(
        state: CoachState.optimalPace,
        priority: CoachPriority.low,
        title: 'Ride stable',
        message: 'Everything looks good. Maintain a smooth pace.',
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    // PRO: deeper adaptive coaching.
    if (_lowSpeedTicks >= 12 && duration.inMinutes >= 3) {
      return CoachInsight(
        state: CoachState.recovering,
        priority: CoachPriority.medium,
        title: 'Recovery phase',
        message:
            'You have slowed down. Use this moment to recover and reset cadence.',
        icon: Icons.self_improvement_rounded,
        color: Colors.lightBlueAccent,
        createdAt: now,
      );
    }

    if (_highEffortTicks >= 8) {
      return CoachInsight(
        state: CoachState.pushingTooHard,
        priority: CoachPriority.high,
        title: 'High effort detected',
        message:
            'You are riding far above your ride average. Hold this only if intentional.',
        icon: Icons.flash_on_rounded,
        color: Colors.orangeAccent,
        createdAt: now,
      );
    }

    if (duration.inMinutes >= 12 &&
        avg > 0 &&
        speed < avg * 0.72) {
      return CoachInsight(
        state: CoachState.fatigueDetected,
        priority: CoachPriority.high,
        title: 'Fatigue detected',
        message:
            'Your speed is dropping below your ride average. Ease pace for 2 minutes.',
        icon: Icons.monitor_heart_rounded,
        color: Colors.redAccent,
        createdAt: now,
      );
    }

    final historyComparison = _historicComparison(
      now: now,
      data: data,
      historicAverageSpeedKmh: historicAverageSpeedKmh,
      historicAverageDistanceKm: historicAverageDistanceKm,
    );

    if (historyComparison != null) {
      return historyComparison;
    }

    if (_steadyTicks >= 15) {
      return CoachInsight(
        state: CoachState.optimalPace,
        priority: CoachPriority.low,
        title: 'Optimal pacing',
        message:
            'Great consistency. Keep this rhythm and avoid unnecessary braking.',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    if (acceleration > 4 && speed > 18) {
      return CoachInsight(
        state: CoachState.sprintReady,
        priority: CoachPriority.medium,
        title: 'Strong acceleration',
        message: 'Nice power increase. Stay smooth and keep your line stable.',
        icon: Icons.rocket_launch_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    _previousData = data;
    _lastInsightAt = now;

    return CoachInsight(
      state: CoachState.optimalPace,
      priority: CoachPriority.low,
      title: 'Pro ride stable',
      message:
          'Your current pace is stable. Munja Pro will adapt as the ride develops.',
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFF42F5B0),
      createdAt: now,
    );
  }

  void _updateCounters({
    required double speed,
    required double averageSpeed,
  }) {
    if (speed < 4) {
      _lowSpeedTicks++;
    } else {
      _lowSpeedTicks = max(0, _lowSpeedTicks - 1);
    }

    if (averageSpeed > 0 &&
        speed > averageSpeed * 1.35 &&
        speed > 22) {
      _highEffortTicks++;
    } else {
      _highEffortTicks = max(0, _highEffortTicks - 1);
    }

    if (averageSpeed > 0 &&
        (speed - averageSpeed).abs() < 2.5 &&
        speed > 8) {
      _steadyTicks++;
    } else {
      _steadyTicks = max(0, _steadyTicks - 1);
    }
  }

  CoachInsight? _distanceOrTimeMilestone({
    required DateTime now,
    required RideSessionData data,
    required AiCoachTier tier,
  }) {
    final distanceKm = data.distanceKm.floor();

    if (distanceKm > 0 &&
        distanceKm > _lastDistanceMilestoneKm &&
        distanceKm % 5 == 0) {
      _lastDistanceMilestoneKm = distanceKm;

      return CoachInsight(
        state: CoachState.milestone,
        priority: CoachPriority.low,
        title: '$distanceKm km reached',
        message: tier == AiCoachTier.pro
            ? 'Strong progress. Keep the effort sustainable for the next segment.'
            : 'Nice work. Keep your rhythm smooth.',
        icon: Icons.flag_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    final durationMin = data.rideDuration.inMinutes;

    if (durationMin >= 30 &&
        durationMin > _lastDurationMilestoneMin &&
        durationMin % 30 == 0) {
      _lastDurationMilestoneMin = durationMin;

      return CoachInsight(
        state: CoachState.milestone,
        priority: CoachPriority.low,
        title: '$durationMin min ride',
        message: tier == AiCoachTier.pro
            ? 'Good endurance block. Check your effort and hydration.'
            : 'Great consistency. Keep riding comfortably.',
        icon: Icons.timer_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    return null;
  }

  CoachInsight? _historicComparison({
    required DateTime now,
    required RideSessionData data,
    required double? historicAverageSpeedKmh,
    required double? historicAverageDistanceKm,
  }) {
    final historicSpeed = historicAverageSpeedKmh ?? 0;

    if (data.rideDuration.inMinutes >= 8 &&
        historicSpeed > 0 &&
        data.averageSpeedKmh >= historicSpeed * 1.10) {
      return CoachInsight(
        state: CoachState.personalBest,
        priority: CoachPriority.medium,
        title: 'Above your usual pace',
        message:
            'Your average speed is more than 10% above your historical average.',
        icon: Icons.trending_up_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    final historicDistance = historicAverageDistanceKm ?? 0;

    if (historicDistance > 0 &&
        data.distanceKm >= historicDistance &&
        data.distanceKm < historicDistance + 0.5) {
      return CoachInsight(
        state: CoachState.personalBest,
        priority: CoachPriority.low,
        title: 'Typical ride distance reached',
        message:
            'You have reached your usual ride distance. Continue if today is a longer session.',
        icon: Icons.route_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    return null;
  }

  CoachInsight _idle(
    DateTime now,
    AiCoachTier tier,
  ) {
    return CoachInsight(
      state: CoachState.idle,
      priority: CoachPriority.low,
      title: tier == AiCoachTier.pro
          ? 'AI Coach Pro ready'
          : 'AI Coach ready',
      message: tier == AiCoachTier.pro
          ? 'Start a ride and Munja Pro will adapt coaching to your ride and history.'
          : 'Start a ride and Munja will analyze your pace in real time.',
      icon: Icons.psychology_rounded,
      color: const Color(0xFF42F5B0),
      createdAt: now,
    );
  }

  CoachInsight _gpsWeak(DateTime now) {
    return CoachInsight(
      state: CoachState.gpsWeak,
      priority: CoachPriority.medium,
      title: 'Weak GPS signal',
      message:
          'Move to an open area for more accurate speed and distance tracking.',
      icon: Icons.gps_off_rounded,
      color: Colors.orangeAccent,
      createdAt: now,
    );
  }

  CoachInsight _urbanCaution(DateTime now) {
    return CoachInsight(
      state: CoachState.urbanCaution,
      priority: CoachPriority.medium,
      title: 'Safety check',
      message: 'Brake light not connected. Ride cautiously in traffic.',
      icon: Icons.warning_amber_rounded,
      color: Colors.orangeAccent,
      createdAt: now,
    );
  }

  void _resetSoft() {
    _lowSpeedTicks = 0;
    _highEffortTicks = 0;
    _steadyTicks = 0;
    _lastSpeedKmh = 0;
    _previousData = null;
    _lastInsightAt = null;
    _lastDistanceMilestoneKm = 0;
    _lastDurationMilestoneMin = 0;
  }
}
