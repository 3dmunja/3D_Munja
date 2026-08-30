import 'dart:async';

import 'package:flutter/foundation.dart';

import '../Models/navigation_instruction.dart';

enum ArrivalStatus {
  idle,
  waitingForConfirmation,
  confirmed,
}

class ArrivalState {
  const ArrivalState({
    required this.status,
    required this.distanceToDestinationMeters,
    required this.confirmationProgress,
    required this.updatedAt,
  });

  final ArrivalStatus status;

  /// Current direct distance to the destination.
  final double distanceToDestinationMeters;

  /// Value from 0.0 to 1.0 while arrival is being confirmed.
  final double confirmationProgress;

  final DateTime updatedAt;

  bool get isWaiting {
    return status == ArrivalStatus.waitingForConfirmation;
  }

  bool get isConfirmed {
    return status == ArrivalStatus.confirmed;
  }

  ArrivalState copyWith({
    ArrivalStatus? status,
    double? distanceToDestinationMeters,
    double? confirmationProgress,
    DateTime? updatedAt,
  }) {
    return ArrivalState(
      status: status ?? this.status,
      distanceToDestinationMeters:
          distanceToDestinationMeters ??
              this.distanceToDestinationMeters,
      confirmationProgress:
          confirmationProgress ??
              this.confirmationProgress,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static ArrivalState initial() {
    return ArrivalState(
      status: ArrivalStatus.idle,
      distanceToDestinationMeters:
          double.infinity,
      confirmationProgress: 0,
      updatedAt: DateTime.now(),
    );
  }
}

class ArrivalService {
  ArrivalService._();

  static final ArrivalService instance =
      ArrivalService._();

  /// The rider must be inside this radius before confirmation starts.
  static const double defaultArrivalRadiusMeters = 25;

  /// Confirmation is cancelled when GPS moves outside this larger radius.
  ///
  /// The extra margin prevents small GPS jumps from constantly resetting
  /// the confirmation timer.
  static const double defaultExitRadiusMeters = 42;

  /// The rider must remain close to the destination for this duration.
  static const Duration defaultConfirmationDuration =
      Duration(seconds: 4);

  final ValueNotifier<ArrivalState> state =
      ValueNotifier<ArrivalState>(
    ArrivalState.initial(),
  );

  Timer? _confirmationTimer;
  Timer? _progressTimer;

  DateTime? _confirmationStartedAt;

  bool _arrivalHandled = false;
  bool _confirmationRunning = false;

  FutureOr<void> Function()? _onArrivalConfirmed;

  bool get hasConfirmedArrival => _arrivalHandled;

  bool get isConfirming => _confirmationRunning;

  /// Registers the action that should run after arrival is confirmed.
  ///
  /// In AutoRideScreen this callback can:
  /// - stop rerouting
  /// - stop the active ride
  /// - save the trip
  /// - open Ride Summary
  void configure({
    FutureOr<void> Function()? onArrivalConfirmed,
  }) {
    _onArrivalConfirmed = onArrivalConfirmed;
  }

  /// Evaluates the current navigation instruction.
  ///
  /// Call this whenever NavigationService publishes a new state.
  void handleNavigationInstruction({
    required NavigationInstruction? instruction,
    required bool rideIsActive,
    double arrivalRadiusMeters =
        defaultArrivalRadiusMeters,
    double exitRadiusMeters =
        defaultExitRadiusMeters,
    Duration confirmationDuration =
        defaultConfirmationDuration,
  }) {
    if (_arrivalHandled) {
      return;
    }

    if (!rideIsActive || instruction == null) {
      cancelPendingConfirmation();
      return;
    }

    final distance =
        instruction.distanceToInstructionMeters;

    final indicatesArrival =
        instruction.maneuver ==
                NavigationManeuver.arrive ||
            instruction.isArrival;

    final insideArrivalRadius =
        indicatesArrival &&
        distance <= arrivalRadiusMeters;

    if (insideArrivalRadius) {
      _startConfirmation(
        distanceToDestinationMeters: distance,
        confirmationDuration:
            confirmationDuration,
      );
      return;
    }

    if (_confirmationRunning &&
        distance <= exitRadiusMeters) {
      _publishProgress(
        distanceToDestinationMeters: distance,
        confirmationDuration:
            confirmationDuration,
      );
      return;
    }

    cancelPendingConfirmation(
      distanceToDestinationMeters: distance,
    );
  }

  void _startConfirmation({
    required double distanceToDestinationMeters,
    required Duration confirmationDuration,
  }) {
    if (_confirmationRunning) {
      _publishProgress(
        distanceToDestinationMeters:
            distanceToDestinationMeters,
        confirmationDuration:
            confirmationDuration,
      );
      return;
    }

    _confirmationRunning = true;
    _confirmationStartedAt = DateTime.now();

    state.value = ArrivalState(
      status:
          ArrivalStatus.waitingForConfirmation,
      distanceToDestinationMeters:
          distanceToDestinationMeters,
      confirmationProgress: 0,
      updatedAt: DateTime.now(),
    );

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        _publishProgress(
          distanceToDestinationMeters:
              state.value
                  .distanceToDestinationMeters,
          confirmationDuration:
              confirmationDuration,
        );
      },
    );

    _confirmationTimer?.cancel();
    _confirmationTimer = Timer(
      confirmationDuration,
      _confirmArrival,
    );

    debugPrint(
      'ARRIVAL CONFIRMATION STARTED: '
      '${distanceToDestinationMeters.toStringAsFixed(1)} m',
    );
  }

  void _publishProgress({
    required double distanceToDestinationMeters,
    required Duration confirmationDuration,
  }) {
    final startedAt = _confirmationStartedAt;

    if (!_confirmationRunning ||
        startedAt == null) {
      return;
    }

    final elapsed =
        DateTime.now().difference(startedAt);

    final totalMilliseconds =
        confirmationDuration.inMilliseconds;

    final progress = totalMilliseconds <= 0
        ? 1.0
        : (elapsed.inMilliseconds /
                totalMilliseconds)
            .clamp(0.0, 1.0);

    state.value = ArrivalState(
      status:
          ArrivalStatus.waitingForConfirmation,
      distanceToDestinationMeters:
          distanceToDestinationMeters,
      confirmationProgress: progress,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _confirmArrival() async {
    if (_arrivalHandled ||
        !_confirmationRunning) {
      return;
    }

    _confirmationTimer?.cancel();
    _confirmationTimer = null;

    _progressTimer?.cancel();
    _progressTimer = null;

    _confirmationRunning = false;
    _confirmationStartedAt = null;
    _arrivalHandled = true;

    state.value = ArrivalState(
      status: ArrivalStatus.confirmed,
      distanceToDestinationMeters:
          state.value
              .distanceToDestinationMeters,
      confirmationProgress: 1,
      updatedAt: DateTime.now(),
    );

    debugPrint('ARRIVAL CONFIRMED');

    final callback = _onArrivalConfirmed;

    if (callback == null) {
      return;
    }

    try {
      await callback();
    } catch (error, stackTrace) {
      debugPrint(
        'ARRIVAL CONFIRMED CALLBACK ERROR: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  void cancelPendingConfirmation({
    double? distanceToDestinationMeters,
  }) {
    final current = state.value;
    final nextDistance =
        distanceToDestinationMeters ??
            current.distanceToDestinationMeters;

    final alreadyIdle =
        !_confirmationRunning &&
        current.status == ArrivalStatus.idle &&
        current.confirmationProgress == 0 &&
        current.distanceToDestinationMeters ==
            nextDistance;

    if (alreadyIdle || _arrivalHandled) {
      return;
    }

    _confirmationTimer?.cancel();
    _confirmationTimer = null;

    _progressTimer?.cancel();
    _progressTimer = null;

    _confirmationRunning = false;
    _confirmationStartedAt = null;

    state.value = ArrivalState(
      status: ArrivalStatus.idle,
      distanceToDestinationMeters: nextDistance,
      confirmationProgress: 0,
      updatedAt: DateTime.now(),
    );
  }

  /// Resets arrival detection for a new route or a new ride.
  void reset() {
    final current = state.value;

    final alreadyReset =
        !_confirmationRunning &&
        !_arrivalHandled &&
        current.status == ArrivalStatus.idle &&
        current.confirmationProgress == 0 &&
        current.distanceToDestinationMeters ==
            double.infinity;

    if (alreadyReset) {
      return;
    }

    _confirmationTimer?.cancel();
    _confirmationTimer = null;

    _progressTimer?.cancel();
    _progressTimer = null;

    _confirmationStartedAt = null;
    _confirmationRunning = false;
    _arrivalHandled = false;

    state.value = ArrivalState.initial();

    debugPrint('ARRIVAL SERVICE RESET');
  }

  void dispose() {
    _confirmationTimer?.cancel();
    _progressTimer?.cancel();
    state.dispose();
  }
}
