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
}

enum CoachPriority { low, medium, high }

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

  CoachInsight analyze({
    required RideSessionData data,
    required bool bleConnected,
    int batteryPercent = 100,
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
      return _idle(now);
    }

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
        message: 'Build speed gradually and keep your breathing steady.',
        icon: Icons.local_fire_department_rounded,
        color: const Color(0xFF42F5B0),
        createdAt: now,
      );
    }

    if (speed < 4) {
      _lowSpeedTicks++;
    } else {
      _lowSpeedTicks = max(0, _lowSpeedTicks - 1);
    }

    if (avg > 0 && speed > avg * 1.35 && speed > 22) {
      _highEffortTicks++;
    } else {
      _highEffortTicks = max(0, _highEffortTicks - 1);
    }

    if (avg > 0 && (speed - avg).abs() < 2.5 && speed > 8) {
      _steadyTicks++;
    } else {
      _steadyTicks = max(0, _steadyTicks - 1);
    }

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
            'You are riding far above your average. Hold this only if intentional.',
        icon: Icons.flash_on_rounded,
        color: Colors.orangeAccent,
        createdAt: now,
      );
    }

    if (duration.inMinutes >= 12 && avg > 0 && speed < avg * 0.72) {
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
      title: 'Ride stable',
      message: 'Everything looks good. Maintain a smooth pace.',
      icon: Icons.auto_awesome_rounded,
      color: const Color(0xFF42F5B0),
      createdAt: now,
    );
  }

  CoachInsight _idle(DateTime now) {
    return CoachInsight(
      state: CoachState.idle,
      priority: CoachPriority.low,
      title: 'AI Coach ready',
      message: 'Start a ride and Munja will analyze your pace in real time.',
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
  }
}
