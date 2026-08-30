import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/trip.dart';
import 'challenge_service.dart';
import 'crystal_reward_service.dart';
import 'monthly_special_service.dart';

/// Bridges completed, persisted rides into Munja Challenge V2.
///
/// Important rules:
/// - Called only after a ride is safely persisted.
/// - One completed ride can advance every active challenge involving the rider.
/// - Distance, ride-count, ride-time and streak challenges are supported.
/// - Challenge Crystal rewards are idempotent through CrystalRewardService.
/// - Challenge XP is idempotent through a dedicated Firestore claim document.
/// - Active Munja Pro Monthly Specials are progressed from the same ride.
/// - Monthly Special totals are recalculated from persisted rides to avoid duplicates.
class ChallengeRideProgressService {
  ChallengeRideProgressService._();

  static final ChallengeRideProgressService instance =
      ChallengeRideProgressService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> processCompletedRide({
    required Trip trip,
    required List<Trip> allTrips,
  }) async {
    final uid = _auth.currentUser?.uid.trim();

    if (uid == null || uid.isEmpty) {
      debugPrint(
        'CHALLENGE RIDE PROGRESS: skipped - no signed-in user.',
      );
      return;
    }

    final rideDistanceKm =
        (trip.distanceM / 1000).clamp(0.0, double.infinity);

    final rideMinutes =
        trip.duration.inMinutes <= 0 ? 1 : trip.duration.inMinutes;

    final streakDays = _currentRideStreakDays(allTrips);

    debugPrint(
      'RIDE PROGRESS START: '
      'ride=${_rideId(trip)} '
      'distance=${rideDistanceKm.toStringAsFixed(2)}km '
      'minutes=$rideMinutes '
      'streak=$streakDays',
    );

    await _processStandardChallenges(
      uid: uid,
      distanceKm: rideDistanceKm,
      rideMinutes: rideMinutes,
      streakDays: streakDays,
    );

    await _processMonthlySpecial(
      trip: trip,
      allTrips: allTrips,
    );
  }

  Future<void> _processStandardChallenges({
    required String uid,
    required double distanceKm,
    required int rideMinutes,
    required int streakDays,
  }) async {
    try {
      final active =
          await ChallengeService.instance.getActiveChallenges();

      if (active.isEmpty) {
        debugPrint(
          'CHALLENGE RIDE PROGRESS: no active standard challenges.',
        );
        return;
      }

      debugPrint(
        'CHALLENGE RIDE PROGRESS: active=${active.length}',
      );

      for (final challenge in active) {
        try {
          final result = await _applyRideToChallenge(
            challenge: challenge,
            distanceKm: distanceKm,
            rideMinutes: rideMinutes,
            streakDays: streakDays,
          );

          if (result == null) {
            continue;
          }

          debugPrint(
            'CHALLENGE RIDE PROGRESS RESULT: '
            'challenge=${challenge.id} '
            'type=${challenge.type.name} '
            'progress=${result.progressKm}/'
            '${result.targetDistanceKm} '
            'completed=${result.completed} '
            'winner=${result.winnerUid}',
          );

          if (result.completed && result.wonBy(uid)) {
            await _grantWinnerRewards(
              uid: uid,
              challenge: challenge,
            );
          }
        } catch (error, stackTrace) {
          debugPrint(
            'CHALLENGE RIDE PROGRESS ITEM ERROR: '
            'challenge=${challenge.id} '
            'error=$error',
          );
          debugPrint('$stackTrace');
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'CHALLENGE RIDE PROGRESS LOAD ERROR: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<void> _processMonthlySpecial({
    required Trip trip,
    required List<Trip> allTrips,
  }) async {
    try {
      final service = MonthlySpecialService.instance;
      final activation = await service.getActiveActivation();

      if (activation == null ||
          activation.status !=
              MonthlySpecialActivationStatus.active) {
        debugPrint(
          'MONTHLY SPECIAL PROGRESS: no active Special.',
        );
        return;
      }

      final special =
          service.specialForActivation(activation);

      final eligibleTrips = allTrips.where(
        (savedTrip) {
          final startedAt =
              DateTime.fromMillisecondsSinceEpoch(
            savedTrip.startedAtMs,
          );

          final endedAt =
              DateTime.fromMillisecondsSinceEpoch(
            savedTrip.endedAtMs,
          );

          return !startedAt.isBefore(activation.startedAt) &&
              !endedAt.isAfter(activation.endsAt);
        },
      ).toList(growable: false);

      double progressValue;

      switch (special.goalType) {
        case MonthlySpecialGoalType.distanceKm:
          progressValue = eligibleTrips.fold<double>(
            0.0,
            (sum, savedTrip) =>
                sum + (savedTrip.distanceM / 1000.0),
          );
          break;

        case MonthlySpecialGoalType.rideCount:
          progressValue = eligibleTrips.length.toDouble();
          break;

        case MonthlySpecialGoalType.rideMinutes:
          progressValue = eligibleTrips.fold<double>(
            0.0,
            (sum, savedTrip) {
              final minutes =
                  savedTrip.duration.inMinutes <= 0
                      ? 1
                      : savedTrip.duration.inMinutes;

              return sum + minutes;
            },
          );
          break;

        case MonthlySpecialGoalType.streakDays:
          progressValue =
              _currentRideStreakDays(eligibleTrips).toDouble();
          break;
      }

      final updated = await service.setProgressValue(
        activationId: activation.id,
        value: progressValue,
      );

      if (updated == null) {
        debugPrint(
          'MONTHLY SPECIAL PROGRESS: activation missing during update.',
        );
        return;
      }

      final ratio = service.progress(
        special: special,
        currentValue: updated.progressValue,
      );

      debugPrint(
        'MONTHLY SPECIAL PROGRESS RESULT: '
        'special=${special.title} '
        'type=${special.goalType.name} '
        'progress=${updated.progressValue.toStringAsFixed(2)}/'
        '${special.goalValue.toStringAsFixed(2)} '
        'percent=${(ratio * 100).round()} '
        'status=${updated.status.name}',
      );

      if (updated.status ==
          MonthlySpecialActivationStatus.completed) {
        debugPrint(
          'MONTHLY SPECIAL COMPLETED: '
          '${special.title}. Reward claim is handled separately.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'MONTHLY SPECIAL PROGRESS ERROR: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<ChallengeProgressResult?> _applyRideToChallenge({
    required MunjaChallenge challenge,
    required double distanceKm,
    required int rideMinutes,
    required int streakDays,
  }) {
    switch (challenge.type) {
      case MunjaChallengeType.distance:
        if (distanceKm <= 0) {
          return Future<ChallengeProgressResult?>.value(null);
        }

        return ChallengeService.instance.addDistanceProgress(
          challengeId: challenge.id,
          distanceKm: distanceKm,
        );

      case MunjaChallengeType.rideCount:
        return ChallengeService.instance.addRideCountProgress(
          challengeId: challenge.id,
          rides: 1,
        );

      case MunjaChallengeType.rideTime:
        return ChallengeService.instance.addRideTimeProgress(
          challengeId: challenge.id,
          minutes: rideMinutes,
        );

      case MunjaChallengeType.streak:
        if (streakDays <= 0) {
          return Future<ChallengeProgressResult?>.value(null);
        }

        return ChallengeService.instance.setStreakProgress(
          challengeId: challenge.id,
          streakDays: streakDays,
        );
    }
  }

  Future<void> _grantWinnerRewards({
    required String uid,
    required MunjaChallenge challenge,
  }) async {
    final crystalAmount =
        challenge.rewardCrystals < 0 ? 0 : challenge.rewardCrystals;
    final xpAmount =
        challenge.rewardXp < 0 ? 0 : challenge.rewardXp;

    if (crystalAmount > 0) {
      final crystalResult =
          await CrystalRewardService.instance.grantReward(
        uid: uid,
        rewardId: 'challenge_${challenge.id}',
        rewardType: CrystalRewardType.weeklyChallenge,
        amount: crystalAmount,
        sourceId: challenge.id,
        metadata: <String, dynamic>{
          'challengeId': challenge.id,
          'challengeType': challenge.type.name,
          'rewardXp': xpAmount,
        },
      );

      debugPrint(
        'CHALLENGE CRYSTAL REWARD: '
        'challenge=${challenge.id} '
        'status=${crystalResult.status} '
        'amount=${crystalResult.amount} '
        'balance=${crystalResult.newBalance}',
      );
    }

    if (xpAmount > 0) {
      final xpGranted = await _grantChallengeXpOnce(
        uid: uid,
        challengeId: challenge.id,
        amount: xpAmount,
      );

      debugPrint(
        'CHALLENGE XP REWARD: '
        'challenge=${challenge.id} '
        'amount=$xpAmount '
        'granted=$xpGranted',
      );
    }
  }

  Future<bool> _grantChallengeXpOnce({
    required String uid,
    required String challengeId,
    required int amount,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedChallengeId = challengeId.trim();

    if (normalizedUid.isEmpty ||
        normalizedChallengeId.isEmpty ||
        amount <= 0) {
      return false;
    }

    final userRef =
        _db.collection('users').doc(normalizedUid);

    final claimRef = userRef
        .collection('challengeXpClaims')
        .doc(normalizedChallengeId);

    return _db.runTransaction<bool>(
      (transaction) async {
        final claimSnapshot =
            await transaction.get(claimRef);

        if (claimSnapshot.exists) {
          return false;
        }

        final userSnapshot =
            await transaction.get(userRef);

        if (!userSnapshot.exists) {
          debugPrint(
            'CHALLENGE XP REWARD: user document missing '
            'uid=$normalizedUid',
          );
          return false;
        }

        final data =
            userSnapshot.data() ?? const <String, dynamic>{};

        final currentXp = _readInt(data['totalXp']);
        final nextXp = currentXp + amount;

        transaction.set(
          userRef,
          <String, dynamic>{
            'totalXp': nextXp,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          claimRef,
          <String, dynamic>{
            'challengeId': normalizedChallengeId,
            'amount': amount,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );

        return true;
      },
    );
  }

  int _currentRideStreakDays(List<Trip> trips) {
    if (trips.isEmpty) {
      return 0;
    }

    final uniqueDays = trips
        .map(
          (trip) {
            final date = DateTime.fromMillisecondsSinceEpoch(
              trip.startedAtMs,
            );

            return DateTime(
              date.year,
              date.month,
              date.day,
            );
          },
        )
        .toSet()
        .toList()
      ..sort();

    if (uniqueDays.isEmpty) {
      return 0;
    }

    var streak = 1;

    for (var i = uniqueDays.length - 1; i > 0; i--) {
      final current = uniqueDays[i];
      final previous = uniqueDays[i - 1];

      final difference =
          current.difference(previous).inDays;

      if (difference == 1) {
        streak++;
        continue;
      }

      if (difference > 1) {
        break;
      }
    }

    return streak;
  }

  String _rideId(Trip trip) {
    return '${trip.startedAtMs}_${trip.endedAtMs}';
  }

  static int _readInt(Object? value) {
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
}
