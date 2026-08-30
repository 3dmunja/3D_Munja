import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// The supported goal types for Munja Monthly Special.
///
/// These intentionally mirror the normal Munja challenge concepts so the same
/// ride-progress engine can later feed both standard challenges and Monthly
/// Specials.
enum MonthlySpecialGoalType {
  distanceKm,
  rideCount,
  rideMinutes,
  streakDays,
}

/// Optional special reward unlocked when a Monthly Special is completed.
///
/// `rewardId` is a stable key that the Shop/Garage can later use to unlock the
/// actual skin, frame or badge without changing the challenge definition.
enum MonthlySpecialRewardType {
  badge,
  skin,
  frame,
}

@immutable
class MonthlySpecialReward {
  const MonthlySpecialReward({
    required this.type,
    required this.rewardId,
    required this.name,
  });

  final MonthlySpecialRewardType type;
  final String rewardId;
  final String name;

  String get typeLabel {
    switch (type) {
      case MonthlySpecialRewardType.badge:
        return 'Badge';
      case MonthlySpecialRewardType.skin:
        return 'Skin';
      case MonthlySpecialRewardType.frame:
        return 'Frame';
    }
  }
}

/// Definition of one recurring themed Monthly Special.
///
/// The theme is chosen from the month in which the rider ACTIVATES the event.
/// Once activated, the rider always receives a full 30-day window, even if the
/// calendar month changes in the meantime.
@immutable
class MonthlySpecial {
  const MonthlySpecial({
    required this.month,
    required this.title,
    required this.subtitle,
    required this.goalType,
    required this.goalValue,
    required this.xpReward,
    required this.crystalReward,
    required this.specialReward,
  }) : assert(month >= 1 && month <= 12);

  final int month;
  final String title;
  final String subtitle;
  final MonthlySpecialGoalType goalType;
  final double goalValue;
  final int xpReward;
  final int crystalReward;
  final MonthlySpecialReward specialReward;

  String get monthName {
    switch (month) {
      case 1:
        return 'January';
      case 2:
        return 'February';
      case 3:
        return 'March';
      case 4:
        return 'April';
      case 5:
        return 'May';
      case 6:
        return 'June';
      case 7:
        return 'July';
      case 8:
        return 'August';
      case 9:
        return 'September';
      case 10:
        return 'October';
      case 11:
        return 'November';
      case 12:
        return 'December';
      default:
        return '';
    }
  }

  String get goalLabel {
    switch (goalType) {
      case MonthlySpecialGoalType.distanceKm:
        return '${_formatGoal(goalValue)} km';
      case MonthlySpecialGoalType.rideCount:
        return '${_formatGoal(goalValue)} rides';
      case MonthlySpecialGoalType.rideMinutes:
        final minutes = goalValue.round();

        if (minutes % 60 == 0) {
          return '${minutes ~/ 60} hours';
        }

        return '$minutes min';
      case MonthlySpecialGoalType.streakDays:
        return '${_formatGoal(goalValue)} day streak';
    }
  }

  String get eventKey =>
      'monthly_special_${month.toString().padLeft(2, '0')}';

  String eventKeyForYear(int year) => '${eventKey}_$year';

  static String _formatGoal(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }
}

enum MonthlySpecialActivationStatus {
  active,
  completed,
  expired,
}

@immutable
class MonthlySpecialActivation {
  const MonthlySpecialActivation({
    required this.id,
    required this.uid,
    required this.specialMonth,
    required this.specialYear,
    required this.startedAt,
    required this.endsAt,
    required this.progressValue,
    required this.status,
    this.completedAt,
    this.rewardClaimed = false,
  });

  final String id;
  final String uid;

  /// The month whose themed Special was activated.
  ///
  /// Example: activation on 31 August keeps the August theme/reward for the
  /// entire 30-day run.
  final int specialMonth;

  /// Used together with [specialMonth] to prevent claiming/starting the same
  /// themed period more than once.
  final int specialYear;

  final DateTime startedAt;
  final DateTime endsAt;
  final double progressValue;
  final MonthlySpecialActivationStatus status;
  final DateTime? completedAt;
  final bool rewardClaimed;

  bool get isActive =>
      status == MonthlySpecialActivationStatus.active &&
      DateTime.now().isBefore(endsAt);

  bool get isCompleted =>
      status == MonthlySpecialActivationStatus.completed;

  bool get isExpired =>
      status == MonthlySpecialActivationStatus.expired ||
      DateTime.now().isAfter(endsAt);

  Duration timeRemaining({
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();

    if (!endsAt.isAfter(current)) {
      return Duration.zero;
    }

    return endsAt.difference(current);
  }

  double progressRatio(MonthlySpecial special) {
    if (special.goalValue <= 0) {
      return 0;
    }

    return (progressValue / special.goalValue)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  factory MonthlySpecialActivation.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};

    return MonthlySpecialActivation(
      id: snapshot.id,
      uid: _readString(data['uid']),
      specialMonth: _readInt(data['specialMonth']),
      specialYear: _readInt(data['specialYear']),
      startedAt: _readDate(data['startedAt']) ?? DateTime.now(),
      endsAt: _readDate(data['endsAt']) ?? DateTime.now(),
      progressValue: _readDouble(data['progressValue']),
      status: _readActivationStatus(data['status']),
      completedAt: _readDate(data['completedAt']),
      rewardClaimed: _readBool(data['rewardClaimed']),
    );
  }

  static MonthlySpecialActivationStatus _readActivationStatus(
    Object? value,
  ) {
    switch (_readString(value)) {
      case 'completed':
        return MonthlySpecialActivationStatus.completed;
      case 'expired':
        return MonthlySpecialActivationStatus.expired;
      case 'active':
      default:
        return MonthlySpecialActivationStatus.active;
    }
  }
}

/// Result returned when the rider attempts to start the current Special.
@immutable
class MonthlySpecialActivationResult {
  const MonthlySpecialActivationResult({
    required this.activation,
    required this.created,
  });

  final MonthlySpecialActivation activation;

  /// `true` only when a brand-new 30-day activation was created.
  ///
  /// `false` means an existing active activation was returned.
  final bool created;
}

enum MonthlySpecialClaimStatus {
  success,
  alreadyClaimed,
  notCompleted,
  activationNotFound,
  userNotFound,
}

@immutable
class MonthlySpecialClaimResult {
  const MonthlySpecialClaimResult({
    required this.status,
    required this.activationId,
    this.xpGranted = 0,
    this.crystalsGranted = 0,
    this.rewardId = '',
    this.rewardName = '',
    this.rewardType = '',
    this.newTotalXp,
    this.newCrystalBalance,
  });

  final MonthlySpecialClaimStatus status;
  final String activationId;
  final int xpGranted;
  final int crystalsGranted;
  final String rewardId;
  final String rewardName;
  final String rewardType;
  final int? newTotalXp;
  final int? newCrystalBalance;

  bool get success =>
      status == MonthlySpecialClaimStatus.success;

  bool get alreadyClaimed =>
      status == MonthlySpecialClaimStatus.alreadyClaimed;
}

/// Central source of truth for Munja Monthly Special V2.
///
/// V2 fairness rule:
///
/// - The current calendar month only decides WHICH themed Special is offered.
/// - The rider receives a FULL 30 DAYS from the moment they activate it.
/// - An activation keeps its original theme even after the month changes.
/// - Only ONE active Monthly Special is allowed at a time.
/// - The same month/year Special cannot be started repeatedly.
///
/// Firestore structure:
///
/// users/{uid}/monthlySpecials/{activationId}
///
/// This service persists activation/status/progress and provides an atomic,
/// idempotent reward-claim transaction for completed Specials.
class MonthlySpecialService {
  MonthlySpecialService._();

  static final MonthlySpecialService instance =
      MonthlySpecialService._();

  static const Duration activationDuration =
      Duration(days: 30);

  final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  final FirebaseAuth _auth =
      FirebaseAuth.instance;

  static const List<MonthlySpecial> yearlyRotation =
      <MonthlySpecial>[
    MonthlySpecial(
      month: 1,
      title: 'New Year Momentum',
      subtitle: 'Start the year by building a strong riding rhythm.',
      goalType: MonthlySpecialGoalType.rideCount,
      goalValue: 12,
      xpReward: 180,
      crystalReward: 110,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.badge,
        rewardId: 'monthly_january_momentum_badge',
        name: 'Momentum 01',
      ),
    ),
    MonthlySpecial(
      month: 2,
      title: 'Winter Streak',
      subtitle: 'Keep showing up when the easy choice is staying home.',
      goalType: MonthlySpecialGoalType.streakDays,
      goalValue: 7,
      xpReward: 190,
      crystalReward: 115,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.frame,
        rewardId: 'monthly_february_frost_frame',
        name: 'Frost Frame',
      ),
    ),
    MonthlySpecial(
      month: 3,
      title: 'Spring Distance',
      subtitle: 'Welcome longer days with a serious distance target.',
      goalType: MonthlySpecialGoalType.distanceKm,
      goalValue: 150,
      xpReward: 210,
      crystalReward: 125,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.skin,
        rewardId: 'monthly_march_spring_skin',
        name: 'Spring Pulse',
      ),
    ),
    MonthlySpecial(
      month: 4,
      title: 'Ride More',
      subtitle: 'Consistency beats one huge ride. Stack your sessions.',
      goalType: MonthlySpecialGoalType.rideCount,
      goalValue: 15,
      xpReward: 220,
      crystalReward: 130,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.badge,
        rewardId: 'monthly_april_ride_more_badge',
        name: 'Ride More 04',
      ),
    ),
    MonthlySpecial(
      month: 5,
      title: 'May Endurance',
      subtitle: 'Build endurance with time in the saddle.',
      goalType: MonthlySpecialGoalType.rideMinutes,
      goalValue: 600,
      xpReward: 230,
      crystalReward: 135,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.frame,
        rewardId: 'monthly_may_endurance_frame',
        name: 'Endurance Frame',
      ),
    ),
    MonthlySpecial(
      month: 6,
      title: 'Summer 200',
      subtitle: 'Kick off summer with a 200 km monthly mission.',
      goalType: MonthlySpecialGoalType.distanceKm,
      goalValue: 200,
      xpReward: 250,
      crystalReward: 145,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.skin,
        rewardId: 'monthly_june_summer_skin',
        name: 'Summer Volt',
      ),
    ),
    MonthlySpecial(
      month: 7,
      title: 'July Consistency',
      subtitle: 'Ride regularly through the heart of summer.',
      goalType: MonthlySpecialGoalType.rideCount,
      goalValue: 18,
      xpReward: 250,
      crystalReward: 145,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.badge,
        rewardId: 'monthly_july_consistency_badge',
        name: 'Consistency 07',
      ),
    ),
    MonthlySpecial(
      month: 8,
      title: 'August 250',
      subtitle: 'Push your summer total with a premium distance mission.',
      goalType: MonthlySpecialGoalType.distanceKm,
      goalValue: 250,
      xpReward: 280,
      crystalReward: 160,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.frame,
        rewardId: 'monthly_august_neon_frame',
        name: 'Neon Storm Frame',
      ),
    ),
    MonthlySpecial(
      month: 9,
      title: 'September Streak',
      subtitle: 'Build a routine as the season begins to change.',
      goalType: MonthlySpecialGoalType.streakDays,
      goalValue: 10,
      xpReward: 270,
      crystalReward: 155,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.skin,
        rewardId: 'monthly_september_streak_skin',
        name: 'Afterglow',
      ),
    ),
    MonthlySpecial(
      month: 10,
      title: 'October Hours',
      subtitle: 'Own the autumn with focused time on the bike.',
      goalType: MonthlySpecialGoalType.rideMinutes,
      goalValue: 720,
      xpReward: 280,
      crystalReward: 160,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.frame,
        rewardId: 'monthly_october_night_frame',
        name: 'Night Ride Frame',
      ),
    ),
    MonthlySpecial(
      month: 11,
      title: 'November Grind',
      subtitle: 'Keep the wheels moving when the season gets harder.',
      goalType: MonthlySpecialGoalType.rideCount,
      goalValue: 14,
      xpReward: 290,
      crystalReward: 165,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.badge,
        rewardId: 'monthly_november_grind_badge',
        name: 'The Grind 11',
      ),
    ),
    MonthlySpecial(
      month: 12,
      title: 'Year End 300',
      subtitle: 'Finish the Munja year with its biggest distance mission.',
      goalType: MonthlySpecialGoalType.distanceKm,
      goalValue: 300,
      xpReward: 350,
      crystalReward: 190,
      specialReward: MonthlySpecialReward(
        type: MonthlySpecialRewardType.skin,
        rewardId: 'monthly_december_finale_skin',
        name: 'Year End Lightning',
      ),
    ),
  ];

  String get _currentUid {
    final uid = _auth.currentUser?.uid.trim();

    if (uid == null || uid.isEmpty) {
      throw StateError(
        'You must be signed in to use Monthly Special.',
      );
    }

    return uid;
  }

  CollectionReference<Map<String, dynamic>>
      _activationCollection(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('monthlySpecials');
  }

  /// The theme currently available to START.
  ///
  /// This does not imply that an already-active rider should switch theme.
  MonthlySpecial current({
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    return forMonth(date.month);
  }

  MonthlySpecial forMonth(int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError.value(
        month,
        'month',
        'Month must be between 1 and 12.',
      );
    }

    return yearlyRotation[month - 1];
  }

  MonthlySpecial next({
    DateTime? now,
  }) {
    final date = now ?? DateTime.now();
    final nextMonth =
        date.month == 12 ? 1 : date.month + 1;

    return forMonth(nextMonth);
  }

  MonthlySpecial specialForActivation(
    MonthlySpecialActivation activation,
  ) {
    return forMonth(activation.specialMonth);
  }

  /// Start the current month's Special with a fresh 30-day timer.
  ///
  /// Fairness / abuse protection:
  /// - Existing active Special is returned instead of creating another.
  /// - Same month/year themed Special cannot be started again.
  Future<MonthlySpecialActivationResult>
      activateCurrentSpecial({
    DateTime? now,
  }) async {
    final uid = _currentUid;
    final currentDate = now ?? DateTime.now();
    final special = current(now: currentDate);
    final collection = _activationCollection(uid);

    final activationId = claimId(
      special: special,
      year: currentDate.year,
    );

    final newRef = collection.doc(activationId);

    return _db.runTransaction<
        MonthlySpecialActivationResult>(
      (transaction) async {
        // First check whether this exact themed period already exists.
        final exactSnapshot =
            await transaction.get(newRef);

        if (exactSnapshot.exists) {
          final existing =
              MonthlySpecialActivation.fromFirestore(
            exactSnapshot,
          );

          return MonthlySpecialActivationResult(
            activation: existing,
            created: false,
          );
        }

        // A user may only have one active Monthly Special.
        //
        // Firestore transactions cannot safely query arbitrary collections and
        // then lock the result in every environment, so the authoritative
        // active pointer lives on users/{uid}.
        final userRef =
            _db.collection('users').doc(uid);

        final userSnapshot =
            await transaction.get(userRef);

        final userData =
            userSnapshot.data() ??
                const <String, dynamic>{};

        final activeId =
            _readString(
          userData['activeMonthlySpecialId'],
        );

        if (activeId.isNotEmpty) {
          final activeRef =
              collection.doc(activeId);

          final activeSnapshot =
              await transaction.get(activeRef);

          if (activeSnapshot.exists) {
            final active =
                MonthlySpecialActivation.fromFirestore(
              activeSnapshot,
            );

            if (active.status ==
                    MonthlySpecialActivationStatus.active &&
                active.endsAt.isAfter(currentDate)) {
              return MonthlySpecialActivationResult(
                activation: active,
                created: false,
              );
            }

            // Clean stale pointer. The old record remains as history.
            if (active.status ==
                    MonthlySpecialActivationStatus.active &&
                !active.endsAt.isAfter(currentDate)) {
              transaction.set(
                activeRef,
                <String, dynamic>{
                  'status': 'expired',
                  'updatedAt':
                      FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true),
              );
            }
          }
        }

        final startedAt = currentDate;
        final endsAt =
            startedAt.add(activationDuration);

        transaction.set(
          newRef,
          <String, dynamic>{
            'id': activationId,
            'uid': uid,
            'specialMonth': special.month,
            'specialYear': currentDate.year,
            'status': 'active',
            'startedAt': Timestamp.fromDate(startedAt),
            'endsAt': Timestamp.fromDate(endsAt),
            'progressValue': 0.0,
            'rewardClaimed': false,
            'completedAt': null,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),

            // Snapshot reward/goal data for audit/history.
            'title': special.title,
            'goalType':
                _goalTypeToString(special.goalType),
            'goalValue': special.goalValue,
            'xpReward': special.xpReward,
            'crystalReward':
                special.crystalReward,
            'specialRewardType':
                _rewardTypeToString(
              special.specialReward.type,
            ),
            'specialRewardId':
                special.specialReward.rewardId,
            'specialRewardName':
                special.specialReward.name,
          },
        );

        transaction.set(
          userRef,
          <String, dynamic>{
            'activeMonthlySpecialId':
                activationId,
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return MonthlySpecialActivationResult(
          activation: MonthlySpecialActivation(
            id: activationId,
            uid: uid,
            specialMonth: special.month,
            specialYear: currentDate.year,
            startedAt: startedAt,
            endsAt: endsAt,
            progressValue: 0,
            status:
                MonthlySpecialActivationStatus.active,
          ),
          created: true,
        );
      },
    );
  }

  /// Returns the current active activation, if one exists.
  ///
  /// Expired records are automatically marked expired and the account pointer
  /// is cleared.
  Future<MonthlySpecialActivation?>
      getActiveActivation({
    DateTime? now,
  }) async {
    final uid = _currentUid;
    final date = now ?? DateTime.now();

    final userRef =
        _db.collection('users').doc(uid);

    final userSnapshot = await userRef.get();

    if (!userSnapshot.exists) {
      return null;
    }

    final activeId =
        _readString(
      userSnapshot.data()?['activeMonthlySpecialId'],
    );

    if (activeId.isEmpty) {
      return null;
    }

    final ref =
        _activationCollection(uid).doc(activeId);

    final snapshot = await ref.get();

    if (!snapshot.exists) {
      await userRef.set(
        <String, dynamic>{
          'activeMonthlySpecialId':
              FieldValue.delete(),
          'updatedAt':
              FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return null;
    }

    final activation =
        MonthlySpecialActivation.fromFirestore(
      snapshot,
    );

    if (activation.status ==
            MonthlySpecialActivationStatus.active &&
        !activation.endsAt.isAfter(date)) {
      await _expireActivation(
        uid: uid,
        activationId: activation.id,
      );

      return MonthlySpecialActivation(
        id: activation.id,
        uid: activation.uid,
        specialMonth: activation.specialMonth,
        specialYear: activation.specialYear,
        startedAt: activation.startedAt,
        endsAt: activation.endsAt,
        progressValue: activation.progressValue,
        status:
            MonthlySpecialActivationStatus.expired,
        completedAt: activation.completedAt,
        rewardClaimed: activation.rewardClaimed,
      );
    }

    return activation;
  }

  /// Live account stream for UI.
  ///
  /// It follows the account's `activeMonthlySpecialId`. For simple screens the
  /// Future getter above is sufficient; this stream is useful once live ride
  /// progress is connected.
  Stream<MonthlySpecialActivation?>
      watchActiveActivation() async* {
    final uid = _currentUid;

    await for (final userSnapshot in _db
        .collection('users')
        .doc(uid)
        .snapshots()) {
      final activeId =
          _readString(
        userSnapshot.data()?['activeMonthlySpecialId'],
      );

      if (activeId.isEmpty) {
        yield null;
        continue;
      }

      yield* _activationCollection(uid)
          .doc(activeId)
          .snapshots()
          .map(
        (snapshot) {
          if (!snapshot.exists) {
            return null;
          }

          return MonthlySpecialActivation
              .fromFirestore(snapshot);
        },
      );

      // The nested activation stream only ends if its document stream ends.
      // In normal Firestore use it stays alive; a new page instance will pick
      // up a changed pointer. The screen integration can also resubscribe after
      // completion/activation.
      break;
    }
  }

  /// Generic V2 progress setter used by the next ride-progress integration.
  ///
  /// This is intentionally a SET operation rather than blindly incrementing:
  /// the caller can calculate the authoritative total since [startedAt] and
  /// write it, which is safer against duplicate ride processing.
  Future<MonthlySpecialActivation?>
      setProgressValue({
    required String activationId,
    required double value,
    DateTime? now,
  }) async {
    final uid = _currentUid;
    final date = now ?? DateTime.now();
    final id = activationId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Monthly Special activation ID cannot be empty.',
      );
    }

    final ref =
        _activationCollection(uid).doc(id);

    return _db.runTransaction<
        MonthlySpecialActivation?>(
      (transaction) async {
        final snapshot =
            await transaction.get(ref);

        if (!snapshot.exists) {
          return null;
        }

        final activation =
            MonthlySpecialActivation.fromFirestore(
          snapshot,
        );

        if (activation.status !=
            MonthlySpecialActivationStatus.active) {
          return activation;
        }

        if (!activation.endsAt.isAfter(date)) {
          transaction.set(
            ref,
            <String, dynamic>{
              'status': 'expired',
              'updatedAt':
                  FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          transaction.set(
            _db.collection('users').doc(uid),
            <String, dynamic>{
              'activeMonthlySpecialId':
                  FieldValue.delete(),
              'updatedAt':
                  FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          return MonthlySpecialActivation(
            id: activation.id,
            uid: activation.uid,
            specialMonth: activation.specialMonth,
            specialYear: activation.specialYear,
            startedAt: activation.startedAt,
            endsAt: activation.endsAt,
            progressValue: activation.progressValue,
            status:
                MonthlySpecialActivationStatus.expired,
            completedAt: activation.completedAt,
            rewardClaimed: activation.rewardClaimed,
          );
        }

        final special =
            specialForActivation(activation);

        final safeValue =
            value < 0 ? 0.0 : value;

        final completed =
            safeValue >= special.goalValue;

        final nextValue = completed
            ? special.goalValue
            : safeValue;

        transaction.set(
          ref,
          <String, dynamic>{
            'progressValue': nextValue,
            'status':
                completed ? 'completed' : 'active',
            if (completed)
              'completedAt':
                  FieldValue.serverTimestamp(),
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // IMPORTANT:
        // Keep activeMonthlySpecialId pointing at a completed Special until
        // the reward has been claimed or a later Special is activated.
        // This lets the UI reopen after a ride/app restart and still show
        // CLAIM REWARD safely. activateCurrentSpecial() already replaces a
        // stale/completed pointer when a new eligible Special is started.

        return MonthlySpecialActivation(
          id: activation.id,
          uid: activation.uid,
          specialMonth: activation.specialMonth,
          specialYear: activation.specialYear,
          startedAt: activation.startedAt,
          endsAt: activation.endsAt,
          progressValue: nextValue,
          status: completed
              ? MonthlySpecialActivationStatus.completed
              : MonthlySpecialActivationStatus.active,
          completedAt:
              completed ? date : activation.completedAt,
          rewardClaimed: activation.rewardClaimed,
        );
      },
    );
  }

  /// Atomically claims the rewards for one completed Monthly Special.
  ///
  /// This transaction grants all three reward layers together:
  /// - XP
  /// - Crystals
  /// - the limited cosmetic/badge unlock
  ///
  /// The activation's `rewardClaimed` flag and a dedicated claim document make
  /// this idempotent. Repeated taps, app restarts or retries cannot grant the
  /// same reward twice.
  Future<MonthlySpecialClaimResult> claimCompletedReward({
    required String activationId,
  }) async {
    final uid = _currentUid;
    final id = activationId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Monthly Special activation ID cannot be empty.',
      );
    }

    final activationRef =
        _activationCollection(uid).doc(id);

    final userRef =
        _db.collection('users').doc(uid);

    final claimRef = userRef
        .collection('monthlySpecialRewardClaims')
        .doc(id);

    return _db.runTransaction<MonthlySpecialClaimResult>(
      (transaction) async {
        final activationSnapshot =
            await transaction.get(activationRef);

        if (!activationSnapshot.exists) {
          return MonthlySpecialClaimResult(
            status:
                MonthlySpecialClaimStatus.activationNotFound,
            activationId: id,
          );
        }

        final activation =
            MonthlySpecialActivation.fromFirestore(
          activationSnapshot,
        );

        final special =
            specialForActivation(activation);

        if (activation.status !=
            MonthlySpecialActivationStatus.completed) {
          return MonthlySpecialClaimResult(
            status:
                MonthlySpecialClaimStatus.notCompleted,
            activationId: id,
            rewardId: special.specialReward.rewardId,
            rewardName: special.specialReward.name,
            rewardType:
                _rewardTypeToString(
              special.specialReward.type,
            ),
          );
        }

        // Check both protection mechanisms. Either one being present means the
        // reward has already been consumed.
        final existingClaim =
            await transaction.get(claimRef);

        if (activation.rewardClaimed ||
            existingClaim.exists) {
          return MonthlySpecialClaimResult(
            status:
                MonthlySpecialClaimStatus.alreadyClaimed,
            activationId: id,
            rewardId: special.specialReward.rewardId,
            rewardName: special.specialReward.name,
            rewardType:
                _rewardTypeToString(
              special.specialReward.type,
            ),
          );
        }

        final userSnapshot =
            await transaction.get(userRef);

        if (!userSnapshot.exists) {
          return MonthlySpecialClaimResult(
            status:
                MonthlySpecialClaimStatus.userNotFound,
            activationId: id,
          );
        }

        final userData =
            userSnapshot.data() ??
                const <String, dynamic>{};

        final currentXp =
            _readInt(userData['totalXp']);

        // Support the current Munja field and a possible legacy alias without
        // ever adding both.
        final currentCrystals =
            userData.containsKey('crystals')
                ? _readInt(userData['crystals'])
                : _readInt(
                    userData['crystalBalance'],
                  );

        final xpReward =
            special.xpReward < 0
                ? 0
                : special.xpReward;

        final crystalReward =
            special.crystalReward < 0
                ? 0
                : special.crystalReward;

        final nextXp =
            currentXp + xpReward;

        final nextCrystals =
            currentCrystals + crystalReward;

        final reward = special.specialReward;

        final cosmeticUnlockRef = userRef
            .collection('cosmeticUnlocks')
            .doc(reward.rewardId);

        // A cosmetic can already be owned from an earlier/manual migration,
        // promotion, shop grant, or restored account. Read it before any writes
        // in this transaction and NEVER overwrite its original ownership data.
        final existingCosmeticUnlock =
            await transaction.get(cosmeticUnlockRef);

        transaction.set(
          userRef,
          <String, dynamic>{
            'totalXp': nextXp,
            'crystals': nextCrystals,
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (!existingCosmeticUnlock.exists) {
          transaction.set(
            cosmeticUnlockRef,
            <String, dynamic>{
              'rewardId': reward.rewardId,
              'name': reward.name,
              'type':
                  _rewardTypeToString(reward.type),
              'source':
                  'monthly_special',
              'sourceId': id,
              'specialMonth':
                  activation.specialMonth,
              'specialYear':
                  activation.specialYear,
              'unlockedAt':
                  FieldValue.serverTimestamp(),
            },
          );
        } else {
          debugPrint(
            'MUNJA MONTHLY SPECIAL CLAIM: '
            '${reward.rewardId} already owned -> cosmetic preserved',
          );
        }

        transaction.set(
          claimRef,
          <String, dynamic>{
            'activationId': id,
            'specialMonth':
                activation.specialMonth,
            'specialYear':
                activation.specialYear,
            'xpGranted': xpReward,
            'crystalsGranted':
                crystalReward,
            'rewardId': reward.rewardId,
            'rewardName': reward.name,
            'rewardType':
                _rewardTypeToString(reward.type),
            'claimedAt':
                FieldValue.serverTimestamp(),
          },
        );

        transaction.set(
          activationRef,
          <String, dynamic>{
            'rewardClaimed': true,
            'rewardClaimedAt':
                FieldValue.serverTimestamp(),
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return MonthlySpecialClaimResult(
          status:
              MonthlySpecialClaimStatus.success,
          activationId: id,
          xpGranted: xpReward,
          crystalsGranted: crystalReward,
          rewardId: reward.rewardId,
          rewardName: reward.name,
          rewardType:
              _rewardTypeToString(reward.type),
          newTotalXp: nextXp,
          newCrystalBalance:
              nextCrystals,
        );
      },
    );
  }


  /// Claims the currently active/completed Monthly Special, if one is
  /// available. This is a UI-friendly wrapper around [claimCompletedReward].
  ///
  /// The actual claim remains atomic and idempotent:
  /// XP + Crystals + cosmeticUnlock + claim document + rewardClaimed flag
  /// are still written inside the same Firestore transaction.
  Future<MonthlySpecialClaimResult> claimCurrentCompletedReward() async {
    final activation = await getActiveActivation();

    if (activation == null) {
      return const MonthlySpecialClaimResult(
        status: MonthlySpecialClaimStatus.activationNotFound,
        activationId: '',
      );
    }

    return claimCompletedReward(
      activationId: activation.id,
    );
  }

  Future<void> _expireActivation({
    required String uid,
    required String activationId,
  }) async {
    final activationRef =
        _activationCollection(uid).doc(activationId);

    final userRef =
        _db.collection('users').doc(uid);

    final batch = _db.batch();

    batch.set(
      activationRef,
      <String, dynamic>{
        'status': 'expired',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    batch.set(
      userRef,
      <String, dynamic>{
        'activeMonthlySpecialId':
            FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// Full 30-day period from the actual activation time.
  DateTime endsAtForActivation(
    DateTime startedAt,
  ) {
    return startedAt.add(activationDuration);
  }

  Duration timeRemainingForActivation({
    required MonthlySpecialActivation activation,
    DateTime? now,
  }) {
    return activation.timeRemaining(
      now: now,
    );
  }

  double progress({
    required MonthlySpecial special,
    required double currentValue,
  }) {
    if (special.goalValue <= 0) {
      return 0;
    }

    return (currentValue / special.goalValue)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  bool isCompleted({
    required MonthlySpecial special,
    required double currentValue,
  }) {
    return currentValue >= special.goalValue;
  }

  /// Stable activation / reward-claim ID.
  ///
  /// Example:
  /// `monthly_special_08_2026`
  ///
  /// This prevents the same themed period from being activated or rewarded
  /// multiple times for the same account.
  String claimId({
    required MonthlySpecial special,
    required int year,
  }) {
    return special.eventKeyForYear(year);
  }

  static String _goalTypeToString(
    MonthlySpecialGoalType type,
  ) {
    switch (type) {
      case MonthlySpecialGoalType.distanceKm:
        return 'distance_km';
      case MonthlySpecialGoalType.rideCount:
        return 'ride_count';
      case MonthlySpecialGoalType.rideMinutes:
        return 'ride_minutes';
      case MonthlySpecialGoalType.streakDays:
        return 'streak_days';
    }
  }

  static String _rewardTypeToString(
    MonthlySpecialRewardType type,
  ) {
    switch (type) {
      case MonthlySpecialRewardType.badge:
        return 'badge';
      case MonthlySpecialRewardType.skin:
        return 'skin';
      case MonthlySpecialRewardType.frame:
        return 'frame';
    }
  }
}

String _readString(Object? value) {
  if (value == null) {
    return '';
  }

  return value.toString().trim();
}

int _readInt(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value is String) {
    return int.tryParse(value.trim()) ?? 0;
  }

  return 0;
}

double _readDouble(Object? value) {
  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  if (value is String) {
    return double.tryParse(value.trim()) ?? 0;
  }

  return 0;
}

bool _readBool(Object? value) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  if (value is String) {
    final normalized =
        value.trim().toLowerCase();

    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes';
  }

  return false;
}

DateTime? _readDate(Object? value) {
  if (value is Timestamp) {
    return value.toDate();
  }

  if (value is DateTime) {
    return value;
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      value,
    );
  }

  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(
      value.toInt(),
    );
  }

  if (value is String) {
    return DateTime.tryParse(
      value.trim(),
    );
  }

  return null;
}
