import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum MunjaChallengeStatus {
  pending,
  active,
  completed,
  declined,
  cancelled,
}

enum MunjaChallengeType {
  distance,
  rideCount,
  rideTime,
  streak,
}

class MunjaChallenge {
  const MunjaChallenge({
    required this.id,
    required this.type,
    required this.status,
    required this.creatorUid,
    required this.opponentUid,
    required this.targetDistanceKm,
    required this.durationDays,
    required this.creatorProgressKm,
    required this.opponentProgressKm,
    this.targetRideCount = 0,
    this.targetRideTimeMinutes = 0,
    this.targetStreakDays = 0,
    this.creatorProgressCount = 0,
    this.opponentProgressCount = 0,
    this.creatorProgressMinutes = 0,
    this.opponentProgressMinutes = 0,
    this.creatorProgressStreakDays = 0,
    this.opponentProgressStreakDays = 0,
    this.rewardCrystals = 0,
    this.rewardXp = 0,
    this.createdAt,
    this.updatedAt,
    this.startedAt,
    this.endsAt,
    this.completedAt,
    this.winnerUid,
    this.completionReason,
  });

  final String id;
  final MunjaChallengeType type;
  final MunjaChallengeStatus status;

  final String creatorUid;
  final String opponentUid;

  final double targetDistanceKm;
  final int durationDays;

  final double creatorProgressKm;
  final double opponentProgressKm;

  final int targetRideCount;
  final int targetRideTimeMinutes;
  final int targetStreakDays;

  final int creatorProgressCount;
  final int opponentProgressCount;

  final int creatorProgressMinutes;
  final int opponentProgressMinutes;

  final int creatorProgressStreakDays;
  final int opponentProgressStreakDays;

  final int rewardCrystals;
  final int rewardXp;

  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startedAt;
  final DateTime? endsAt;
  final DateTime? completedAt;

  final String? winnerUid;

  /// target_reached, expired, manual, or null for legacy rows.
  final String? completionReason;

  bool get isPending => status == MunjaChallengeStatus.pending;

  bool get isActive => status == MunjaChallengeStatus.active;

  bool get isCompleted => status == MunjaChallengeStatus.completed;

  bool involvesUser(String uid) {
    return creatorUid == uid || opponentUid == uid;
  }

  String otherUidFor(String uid) {
    if (uid == creatorUid) {
      return opponentUid;
    }

    if (uid == opponentUid) {
      return creatorUid;
    }

    return '';
  }

  double progressFor(String uid) {
    if (uid == creatorUid) {
      return creatorProgressKm;
    }

    if (uid == opponentUid) {
      return opponentProgressKm;
    }

    return 0;
  }

  num genericProgressFor(String uid) {
    switch (type) {
      case MunjaChallengeType.distance:
        return progressFor(uid);
      case MunjaChallengeType.rideCount:
        return uid == creatorUid
            ? creatorProgressCount
            : uid == opponentUid
                ? opponentProgressCount
                : 0;
      case MunjaChallengeType.rideTime:
        return uid == creatorUid
            ? creatorProgressMinutes
            : uid == opponentUid
                ? opponentProgressMinutes
                : 0;
      case MunjaChallengeType.streak:
        return uid == creatorUid
            ? creatorProgressStreakDays
            : uid == opponentUid
                ? opponentProgressStreakDays
                : 0;
    }
  }

  num get genericTarget {
    switch (type) {
      case MunjaChallengeType.distance:
        return targetDistanceKm;
      case MunjaChallengeType.rideCount:
        return targetRideCount;
      case MunjaChallengeType.rideTime:
        return targetRideTimeMinutes;
      case MunjaChallengeType.streak:
        return targetStreakDays;
    }
  }

  double progressRatioFor(String uid) {
    final target = genericTarget.toDouble();
    if (target <= 0) return 0;

    return (genericProgressFor(uid).toDouble() / target)
        .clamp(0.0, 1.0);
  }

  double get creatorProgressRatio {
    if (targetDistanceKm <= 0) {
      return 0;
    }

    return (creatorProgressKm / targetDistanceKm).clamp(0.0, 1.0);
  }

  double get opponentProgressRatio {
    if (targetDistanceKm <= 0) {
      return 0;
    }

    return (opponentProgressKm / targetDistanceKm).clamp(0.0, 1.0);
  }

  factory MunjaChallenge.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};

    return MunjaChallenge(
      id: _stringValue(
        data['id'],
        fallback: snapshot.id,
      ),
      type: _challengeTypeFromString(
        _stringValue(
          data['type'],
          fallback: 'distance',
        ),
      ),
      status: _challengeStatusFromString(
        _stringValue(
          data['status'],
          fallback: 'pending',
        ),
      ),
      creatorUid: _stringValue(
        data['creatorUid'],
      ),
      opponentUid: _stringValue(
        data['opponentUid'],
      ),
      targetDistanceKm: _doubleValue(
        data['targetDistanceKm'],
      ),
      durationDays: _intValue(
        data['durationDays'],
      ),
      creatorProgressKm: _doubleValue(
        data['creatorProgressKm'],
      ),
      opponentProgressKm: _doubleValue(
        data['opponentProgressKm'],
      ),
      targetRideCount: _intValue(
        data['targetRideCount'],
      ),
      targetRideTimeMinutes: _intValue(
        data['targetRideTimeMinutes'],
      ),
      targetStreakDays: _intValue(
        data['targetStreakDays'],
      ),
      creatorProgressCount: _intValue(
        data['creatorProgressCount'],
      ),
      opponentProgressCount: _intValue(
        data['opponentProgressCount'],
      ),
      creatorProgressMinutes: _intValue(
        data['creatorProgressMinutes'],
      ),
      opponentProgressMinutes: _intValue(
        data['opponentProgressMinutes'],
      ),
      creatorProgressStreakDays: _intValue(
        data['creatorProgressStreakDays'],
      ),
      opponentProgressStreakDays: _intValue(
        data['opponentProgressStreakDays'],
      ),
      rewardCrystals: _intValue(
        data['rewardCrystals'],
      ),
      rewardXp: _intValue(
        data['rewardXp'],
      ),
      createdAt: _dateTimeValue(
        data['createdAt'],
      ),
      updatedAt: _dateTimeValue(
        data['updatedAt'],
      ),
      startedAt: _dateTimeValue(
        data['startedAt'],
      ),
      endsAt: _dateTimeValue(
        data['endsAt'],
      ),
      completedAt: _dateTimeValue(
        data['completedAt'],
      ),
      winnerUid: _nullableStringValue(
        data['winnerUid'],
      ),
      completionReason: _nullableStringValue(
        data['completionReason'],
      ),
    );
  }

  static MunjaChallengeType _challengeTypeFromString(
    String value,
  ) {
    switch (value) {
      case 'ride_count':
        return MunjaChallengeType.rideCount;
      case 'ride_time':
        return MunjaChallengeType.rideTime;
      case 'streak':
        return MunjaChallengeType.streak;
      case 'distance':
      default:
        return MunjaChallengeType.distance;
    }
  }

  static MunjaChallengeStatus _challengeStatusFromString(
    String value,
  ) {
    switch (value) {
      case 'active':
        return MunjaChallengeStatus.active;
      case 'completed':
        return MunjaChallengeStatus.completed;
      case 'declined':
        return MunjaChallengeStatus.declined;
      case 'cancelled':
        return MunjaChallengeStatus.cancelled;
      case 'pending':
      default:
        return MunjaChallengeStatus.pending;
    }
  }

  static DateTime? _dateTimeValue(
    Object? value,
  ) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }

  static String _stringValue(
    Object? value, {
    String fallback = '',
  }) {
    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return fallback;
  }

  static String? _nullableStringValue(
    Object? value,
  ) {
    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return null;
  }

  static double _doubleValue(
    Object? value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value) ?? 0;
    }

    return 0;
  }

  static int _intValue(
    Object? value,
  ) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }
}


class ChallengeProgressResult {
  const ChallengeProgressResult({
    required this.challengeId,
    required this.progressKm,
    required this.targetDistanceKm,
    required this.completed,
    required this.winnerUid,
    required this.completionReason,
  });

  final String challengeId;
  final double progressKm;
  final double targetDistanceKm;
  final bool completed;
  final String? winnerUid;
  final String? completionReason;

  bool wonBy(String uid) =>
      completed && winnerUid != null && winnerUid == uid;

  bool get isDraw => completed && winnerUid == null;
}

class ChallengeService {
  ChallengeService._();

  static final ChallengeService instance = ChallengeService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _challenges =>
      _db.collection('challenges');

  String? get currentUid => _auth.currentUser?.uid;

  User? get currentFirebaseUser => _auth.currentUser;

  Future<String> createDistanceChallenge({
    required String opponentUid,
    required double targetDistanceKm,
    required int durationDays,
  }) {
    if (!_isAllowedDistance(targetDistanceKm)) {
      throw ArgumentError(
        'Distance must be 10, 25 or 50 km.',
      );
    }

    return _createChallenge(
      opponentUid: opponentUid,
      type: MunjaChallengeType.distance,
      durationDays: durationDays,
      targetDistanceKm: targetDistanceKm,
    );
  }

  Future<String> createRideCountChallenge({
    required String opponentUid,
    required int targetRideCount,
    required int durationDays,
  }) {
    if (!_isAllowedRideCount(targetRideCount)) {
      throw ArgumentError(
        'Ride count must be 3, 5 or 10 rides.',
      );
    }

    return _createChallenge(
      opponentUid: opponentUid,
      type: MunjaChallengeType.rideCount,
      durationDays: durationDays,
      targetRideCount: targetRideCount,
    );
  }

  Future<String> createRideTimeChallenge({
    required String opponentUid,
    required int targetRideTimeMinutes,
    required int durationDays,
  }) {
    if (!_isAllowedRideTime(targetRideTimeMinutes)) {
      throw ArgumentError(
        'Ride time must be 60, 180 or 300 minutes.',
      );
    }

    return _createChallenge(
      opponentUid: opponentUid,
      type: MunjaChallengeType.rideTime,
      durationDays: durationDays,
      targetRideTimeMinutes: targetRideTimeMinutes,
    );
  }

  Future<String> createStreakChallenge({
    required String opponentUid,
    required int targetStreakDays,
    required int durationDays,
  }) {
    if (!_isAllowedStreak(targetStreakDays)) {
      throw ArgumentError(
        'Streak must be 3, 5 or 7 days.',
      );
    }

    return _createChallenge(
      opponentUid: opponentUid,
      type: MunjaChallengeType.streak,
      durationDays: durationDays,
      targetStreakDays: targetStreakDays,
    );
  }

  Future<String> _createChallenge({
    required String opponentUid,
    required MunjaChallengeType type,
    required int durationDays,
    double targetDistanceKm = 0,
    int targetRideCount = 0,
    int targetRideTimeMinutes = 0,
    int targetStreakDays = 0,
  }) async {
    final creatorUid = _requireCurrentUid();
    final targetUid = opponentUid.trim();

    if (targetUid.isEmpty) {
      throw ArgumentError('Opponent UID cannot be empty.');
    }

    if (targetUid == creatorUid) {
      throw StateError('You cannot challenge yourself.');
    }

    if (!_isAllowedDuration(durationDays)) {
      throw ArgumentError(
        'Duration must be 3, 7 or 14 days.',
      );
    }

    final rewards = _rewardForChallenge(
      type: type,
      targetDistanceKm: targetDistanceKm,
      targetRideCount: targetRideCount,
      targetRideTimeMinutes: targetRideTimeMinutes,
      targetStreakDays: targetStreakDays,
    );

    final ref = _challenges.doc();

    await ref.set(
      <String, dynamic>{
        'id': ref.id,
        'type': _challengeTypeToString(type),
        'status': 'pending',
        'creatorUid': creatorUid,
        'opponentUid': targetUid,
        'targetDistanceKm': targetDistanceKm,
        'targetRideCount': targetRideCount,
        'targetRideTimeMinutes': targetRideTimeMinutes,
        'targetStreakDays': targetStreakDays,
        'durationDays': durationDays,
        'creatorProgressKm': 0.0,
        'opponentProgressKm': 0.0,
        'creatorProgressCount': 0,
        'opponentProgressCount': 0,
        'creatorProgressMinutes': 0,
        'opponentProgressMinutes': 0,
        'creatorProgressStreakDays': 0,
        'opponentProgressStreakDays': 0,
        'rewardCrystals': rewards.$1,
        'rewardXp': rewards.$2,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'startedAt': null,
        'endsAt': null,
        'completedAt': null,
        'winnerUid': null,
        'completionReason': null,
        'rewardGranted': false,
      },
    );

    return ref.id;
  }

  Future<List<MunjaChallenge>> getIncomingChallenges() async {
    final uid = _requireCurrentUid();

    final query = await _challenges
        .where(
          'opponentUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .get();

    return query.docs
        .map(MunjaChallenge.fromFirestore)
        .toList();
  }

  Future<List<MunjaChallenge>> getOutgoingChallenges() async {
    final uid = _requireCurrentUid();

    final query = await _challenges
        .where(
          'creatorUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .get();

    return query.docs
        .map(MunjaChallenge.fromFirestore)
        .toList();
  }

  Future<List<MunjaChallenge>> getActiveChallenges() async {
    final uid = _requireCurrentUid();

    final created = await _challenges
        .where(
          'creatorUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'active',
        )
        .get();

    final received = await _challenges
        .where(
          'opponentUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'active',
        )
        .get();

    final map = <String, MunjaChallenge>{};

    for (final doc in created.docs) {
      final challenge =
          MunjaChallenge.fromFirestore(doc);

      map[challenge.id] = challenge;
    }

    for (final doc in received.docs) {
      final challenge =
          MunjaChallenge.fromFirestore(doc);

      map[challenge.id] = challenge;
    }

    final items = map.values.toList();

    items.sort(
      (a, b) {
        final aDate =
            a.startedAt ??
            a.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final bDate =
            b.startedAt ??
            b.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bDate.compareTo(aDate);
      },
    );

    return items;
  }

  Future<List<MunjaChallenge>> getCompletedChallenges() async {
    final uid = _requireCurrentUid();

    final created = await _challenges
        .where(
          'creatorUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'completed',
        )
        .get();

    final received = await _challenges
        .where(
          'opponentUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'completed',
        )
        .get();

    final map = <String, MunjaChallenge>{};

    for (final doc in created.docs) {
      final challenge =
          MunjaChallenge.fromFirestore(doc);

      map[challenge.id] = challenge;
    }

    for (final doc in received.docs) {
      final challenge =
          MunjaChallenge.fromFirestore(doc);

      map[challenge.id] = challenge;
    }

    final items = map.values.toList();

    items.sort(
      (a, b) {
        final aDate =
            a.completedAt ??
            a.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        final bDate =
            b.completedAt ??
            b.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bDate.compareTo(aDate);
      },
    );

    return items;
  }

  Future<MunjaChallenge?> getChallengeById(
    String challengeId,
  ) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      return null;
    }

    final snapshot =
        await _challenges.doc(id).get();

    if (!snapshot.exists) {
      return null;
    }

    final challenge =
        MunjaChallenge.fromFirestore(snapshot);

    if (!challenge.involvesUser(uid)) {
      throw StateError(
        'You do not have access to this challenge.',
      );
    }

    return challenge;
  }

  Future<void> acceptChallenge({
    required String challengeId,
  }) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Challenge ID cannot be empty.',
      );
    }

    final ref = _challenges.doc(id);

    await _db.runTransaction(
      (transaction) async {
        final snapshot =
            await transaction.get(ref);

        if (!snapshot.exists) {
          throw StateError(
            'Challenge no longer exists.',
          );
        }

        final data =
            snapshot.data() ??
            <String, dynamic>{};

        final opponentUid =
            _stringValue(data['opponentUid']);

        final status =
            _stringValue(
              data['status'],
              fallback: 'pending',
            );

        final durationDays =
            _intValue(data['durationDays']);

        if (opponentUid != uid) {
          throw StateError(
            'Only the invited rider can accept this challenge.',
          );
        }

        if (status != 'pending') {
          throw StateError(
            'This challenge is no longer pending.',
          );
        }

        final now = DateTime.now();
        final endsAt =
            now.add(
              Duration(
                days: durationDays,
              ),
            );

        transaction.update(
          ref,
          <String, dynamic>{
            'status': 'active',
            'startedAt':
                Timestamp.fromDate(now),
            'endsAt':
                Timestamp.fromDate(endsAt),
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  Future<void> declineChallenge({
    required String challengeId,
  }) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Challenge ID cannot be empty.',
      );
    }

    final ref = _challenges.doc(id);
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return;
    }

    final challenge =
        MunjaChallenge.fromFirestore(snapshot);

    if (challenge.opponentUid != uid) {
      throw StateError(
        'Only the invited rider can decline this challenge.',
      );
    }

    if (!challenge.isPending) {
      throw StateError(
        'This challenge is no longer pending.',
      );
    }

    await ref.update(
      <String, dynamic>{
        'status': 'declined',
        'updatedAt':
            FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> cancelChallenge({
    required String challengeId,
  }) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Challenge ID cannot be empty.',
      );
    }

    final ref = _challenges.doc(id);
    final snapshot = await ref.get();

    if (!snapshot.exists) {
      return;
    }

    final challenge =
        MunjaChallenge.fromFirestore(snapshot);

    if (challenge.creatorUid != uid) {
      throw StateError(
        'Only the challenge creator can cancel this challenge.',
      );
    }

    if (!challenge.isPending) {
      throw StateError(
        'Only pending challenges can be cancelled.',
      );
    }

    await ref.update(
      <String, dynamic>{
        'status': 'cancelled',
        'updatedAt':
            FieldValue.serverTimestamp(),
      },
    );
  }

  Future<ChallengeProgressResult?> addDistanceProgress({
    required String challengeId,
    required double distanceKm,
  }) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      throw ArgumentError(
        'Challenge ID cannot be empty.',
      );
    }

    if (distanceKm <= 0) {
      return null;
    }

    final ref = _challenges.doc(id);

    return _db.runTransaction<ChallengeProgressResult?>(
      (transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          throw StateError(
            'Challenge no longer exists.',
          );
        }

        final challenge =
            MunjaChallenge.fromFirestore(snapshot);

        if (!challenge.involvesUser(uid)) {
          throw StateError(
            'You are not part of this challenge.',
          );
        }

        // Idempotent: a completed challenge can never receive more km.
        if (challenge.isCompleted) {
          return ChallengeProgressResult(
            challengeId: challenge.id,
            progressKm: challenge.progressFor(uid),
            targetDistanceKm: challenge.targetDistanceKm,
            completed: true,
            winnerUid: challenge.winnerUid,
            completionReason: challenge.completionReason,
          );
        }

        if (!challenge.isActive) {
          return null;
        }

        final now = DateTime.now();

        // Expired challenges are completed before any new distance is added.
        if (challenge.endsAt != null &&
            !now.isBefore(challenge.endsAt!)) {
          final completion =
              _resolveWinner(challenge: challenge);

          transaction.update(
            ref,
            <String, dynamic>{
              'status': 'completed',
              'winnerUid': completion.winnerUid,
              'completionReason': 'expired',
              'completedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );

          return ChallengeProgressResult(
            challengeId: challenge.id,
            progressKm: challenge.progressFor(uid),
            targetDistanceKm: challenge.targetDistanceKm,
            completed: true,
            winnerUid: completion.winnerUid,
            completionReason: 'expired',
          );
        }

        final target = challenge.targetDistanceKm;

        var creatorProgress =
            challenge.creatorProgressKm.clamp(0.0, target);
        var opponentProgress =
            challenge.opponentProgressKm.clamp(0.0, target);

        if (uid == challenge.creatorUid) {
          creatorProgress =
              (creatorProgress + distanceKm).clamp(0.0, target);
        } else {
          opponentProgress =
              (opponentProgress + distanceKm).clamp(0.0, target);
        }

        final creatorFinished =
            creatorProgress >= target;
        final opponentFinished =
            opponentProgress >= target;

        String? winnerUid;
        var status = 'active';
        String? completionReason;

        if (creatorFinished || opponentFinished) {
          status = 'completed';
          completionReason = 'target_reached';

          // Because the challenge is completed in the same transaction
          // that first reaches the target, normally only one rider can be
          // the finisher. The both-finished branch safely handles legacy/
          // concurrent data.
          if (creatorFinished && opponentFinished) {
            if (creatorProgress > opponentProgress) {
              winnerUid = challenge.creatorUid;
            } else if (opponentProgress > creatorProgress) {
              winnerUid = challenge.opponentUid;
            } else {
              // If both are exactly at target, prefer the rider whose
              // progress triggered this transaction: first-to-target.
              winnerUid = uid;
            }
          } else if (creatorFinished) {
            winnerUid = challenge.creatorUid;
          } else {
            winnerUid = challenge.opponentUid;
          }
        }

        final update = <String, dynamic>{
          'creatorProgressKm': creatorProgress,
          'opponentProgressKm': opponentProgress,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (status == 'completed') {
          update['winnerUid'] = winnerUid;
          update['completionReason'] = completionReason;
          update['completedAt'] =
              FieldValue.serverTimestamp();
        }

        transaction.update(ref, update);

        final myProgress = uid == challenge.creatorUid
            ? creatorProgress
            : opponentProgress;

        return ChallengeProgressResult(
          challengeId: challenge.id,
          progressKm: myProgress,
          targetDistanceKm: target,
          completed: status == 'completed',
          winnerUid: winnerUid,
          completionReason: completionReason,
        );
      },
    );
  }


  Future<ChallengeProgressResult?> addRideCountProgress({
    required String challengeId,
    int rides = 1,
  }) {
    return _addIntegerProgress(
      challengeId: challengeId,
      amount: rides,
      expectedType: MunjaChallengeType.rideCount,
      creatorField: 'creatorProgressCount',
      opponentField: 'opponentProgressCount',
      targetField: 'targetRideCount',
    );
  }

  Future<ChallengeProgressResult?> addRideTimeProgress({
    required String challengeId,
    required int minutes,
  }) {
    return _addIntegerProgress(
      challengeId: challengeId,
      amount: minutes,
      expectedType: MunjaChallengeType.rideTime,
      creatorField: 'creatorProgressMinutes',
      opponentField: 'opponentProgressMinutes',
      targetField: 'targetRideTimeMinutes',
    );
  }

  Future<ChallengeProgressResult?> setStreakProgress({
    required String challengeId,
    required int streakDays,
  }) {
    return _addIntegerProgress(
      challengeId: challengeId,
      amount: streakDays,
      expectedType: MunjaChallengeType.streak,
      creatorField: 'creatorProgressStreakDays',
      opponentField: 'opponentProgressStreakDays',
      targetField: 'targetStreakDays',
      replaceInsteadOfAdd: true,
    );
  }

  Future<ChallengeProgressResult?> _addIntegerProgress({
    required String challengeId,
    required int amount,
    required MunjaChallengeType expectedType,
    required String creatorField,
    required String opponentField,
    required String targetField,
    bool replaceInsteadOfAdd = false,
  }) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      throw ArgumentError('Challenge ID cannot be empty.');
    }

    if (amount <= 0) return null;

    final ref = _challenges.doc(id);

    return _db.runTransaction<ChallengeProgressResult?>(
      (transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          throw StateError('Challenge no longer exists.');
        }

        final challenge = MunjaChallenge.fromFirestore(snapshot);

        if (!challenge.involvesUser(uid)) {
          throw StateError('You are not part of this challenge.');
        }

        if (challenge.type != expectedType) {
          throw StateError('Wrong progress type for this challenge.');
        }

        if (challenge.isCompleted) {
          return ChallengeProgressResult(
            challengeId: challenge.id,
            progressKm: challenge.genericProgressFor(uid).toDouble(),
            targetDistanceKm: challenge.genericTarget.toDouble(),
            completed: true,
            winnerUid: challenge.winnerUid,
            completionReason: challenge.completionReason,
          );
        }

        if (!challenge.isActive) return null;

        final now = DateTime.now();

        if (challenge.endsAt != null &&
            !now.isBefore(challenge.endsAt!)) {
          final completion = _resolveWinner(challenge: challenge);

          transaction.update(
            ref,
            <String, dynamic>{
              'status': 'completed',
              'winnerUid': completion.winnerUid,
              'completionReason': 'expired',
              'completedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          );

          return ChallengeProgressResult(
            challengeId: challenge.id,
            progressKm: challenge.genericProgressFor(uid).toDouble(),
            targetDistanceKm: challenge.genericTarget.toDouble(),
            completed: true,
            winnerUid: completion.winnerUid,
            completionReason: 'expired',
          );
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final target = _intValue(data[targetField]);

        if (target <= 0) {
          throw StateError('Challenge target is invalid.');
        }

        var creatorProgress = _intValue(data[creatorField]);
        var opponentProgress = _intValue(data[opponentField]);

        if (uid == challenge.creatorUid) {
          creatorProgress = replaceInsteadOfAdd
              ? amount.clamp(0, target)
              : (creatorProgress + amount).clamp(0, target);
        } else {
          opponentProgress = replaceInsteadOfAdd
              ? amount.clamp(0, target)
              : (opponentProgress + amount).clamp(0, target);
        }

        final creatorFinished = creatorProgress >= target;
        final opponentFinished = opponentProgress >= target;

        String? winnerUid;
        var status = 'active';
        String? completionReason;

        if (creatorFinished || opponentFinished) {
          status = 'completed';
          completionReason = 'target_reached';

          if (creatorFinished && opponentFinished) {
            if (creatorProgress > opponentProgress) {
              winnerUid = challenge.creatorUid;
            } else if (opponentProgress > creatorProgress) {
              winnerUid = challenge.opponentUid;
            } else {
              winnerUid = uid;
            }
          } else if (creatorFinished) {
            winnerUid = challenge.creatorUid;
          } else {
            winnerUid = challenge.opponentUid;
          }
        }

        final update = <String, dynamic>{
          creatorField: creatorProgress,
          opponentField: opponentProgress,
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (status == 'completed') {
          update['winnerUid'] = winnerUid;
          update['completionReason'] = completionReason;
          update['completedAt'] = FieldValue.serverTimestamp();
        }

        transaction.update(ref, update);

        final myProgress = uid == challenge.creatorUid
            ? creatorProgress
            : opponentProgress;

        return ChallengeProgressResult(
          challengeId: challenge.id,
          progressKm: myProgress.toDouble(),
          targetDistanceKm: target.toDouble(),
          completed: status == 'completed',
          winnerUid: winnerUid,
          completionReason: completionReason,
        );
      },
    );
  }

  Future<void> completeExpiredChallenge({
    required String challengeId,
  }) async {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      return;
    }

    final ref = _challenges.doc(id);

    await _db.runTransaction(
      (transaction) async {
        final snapshot =
            await transaction.get(ref);

        if (!snapshot.exists) {
          return;
        }

        final challenge =
            MunjaChallenge.fromFirestore(snapshot);

        if (!challenge.involvesUser(uid)) {
          throw StateError(
            'You are not part of this challenge.',
          );
        }

        if (!challenge.isActive ||
            challenge.endsAt == null) {
          return;
        }

        if (DateTime.now().isBefore(
          challenge.endsAt!,
        )) {
          return;
        }

        final completion =
            _resolveWinner(
              challenge: challenge,
            );

        transaction.update(
          ref,
          <String, dynamic>{
            'status': 'completed',
            'winnerUid':
                completion.winnerUid,
            'completionReason': 'expired',
            'completedAt':
                FieldValue.serverTimestamp(),
            'updatedAt':
                FieldValue.serverTimestamp(),
          },
        );
      },
    );
  }

  Stream<List<MunjaChallenge>> watchCompletedChallenges() {
    final uid = _requireCurrentUid();

    final controller =
        StreamController<List<MunjaChallenge>>.broadcast();

    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? createdSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? receivedSub;

    var created = <String, MunjaChallenge>{};
    var received = <String, MunjaChallenge>{};

    void emit() {
      final merged = <String, MunjaChallenge>{
        ...created,
        ...received,
      }.values.toList();

      merged.sort((a, b) {
        final aDate = a.completedAt ??
            a.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.completedAt ??
            b.updatedAt ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!controller.isClosed) {
        controller.add(merged);
      }
    }

    controller.onListen = () {
      createdSub = _challenges
          .where('creatorUid', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .snapshots()
          .listen(
        (snapshot) {
          created = <String, MunjaChallenge>{
            for (final doc in snapshot.docs)
              doc.id: MunjaChallenge.fromFirestore(doc),
          };
          emit();
        },
        onError: controller.addError,
      );

      receivedSub = _challenges
          .where('opponentUid', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .snapshots()
          .listen(
        (snapshot) {
          received = <String, MunjaChallenge>{
            for (final doc in snapshot.docs)
              doc.id: MunjaChallenge.fromFirestore(doc),
          };
          emit();
        },
        onError: controller.addError,
      );
    };

    controller.onCancel = () async {
      await createdSub?.cancel();
      await receivedSub?.cancel();
    };

    return controller.stream;
  }

  Stream<List<MunjaChallenge>>
      watchIncomingChallenges() {
    final uid = _requireCurrentUid();

    return _challenges
        .where(
          'opponentUid',
          isEqualTo: uid,
        )
        .where(
          'status',
          isEqualTo: 'pending',
        )
        .orderBy(
          'createdAt',
          descending: true,
        )
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                MunjaChallenge.fromFirestore,
              )
              .toList(),
        );
  }

  Stream<MunjaChallenge?>
      watchChallenge(
    String challengeId,
  ) {
    final uid = _requireCurrentUid();
    final id = challengeId.trim();

    if (id.isEmpty) {
      return Stream<MunjaChallenge?>.value(
        null,
      );
    }

    return _challenges
        .doc(id)
        .snapshots()
        .map(
          (snapshot) {
            if (!snapshot.exists) {
              return null;
            }

            final challenge =
                MunjaChallenge.fromFirestore(
              snapshot,
            );

            if (!challenge.involvesUser(uid)) {
              return null;
            }

            return challenge;
          },
        );
  }

  Future<MunjaChallenge?>
      _findExistingOpenChallenge({
    required String creatorUid,
    required String opponentUid,
  }) async {
    final creatorAsCreator =
        await _challenges
            .where(
              'creatorUid',
              isEqualTo: creatorUid,
            )
            .where(
              'opponentUid',
              isEqualTo: opponentUid,
            )
            .where(
              'status',
              whereIn: const [
                'pending',
                'active',
              ],
            )
            .limit(1)
            .get();

    if (creatorAsCreator.docs.isNotEmpty) {
      return MunjaChallenge.fromFirestore(
        creatorAsCreator.docs.first,
      );
    }

    final opponentAsCreator =
        await _challenges
            .where(
              'creatorUid',
              isEqualTo: opponentUid,
            )
            .where(
              'opponentUid',
              isEqualTo: creatorUid,
            )
            .where(
              'status',
              whereIn: const [
                'pending',
                'active',
              ],
            )
            .limit(1)
            .get();

    if (opponentAsCreator.docs.isNotEmpty) {
      return MunjaChallenge.fromFirestore(
        opponentAsCreator.docs.first,
      );
    }

    return null;
  }

  static _ChallengeCompletion
      _resolveWinner({
    required MunjaChallenge challenge,
  }) {
    final creatorProgress =
        challenge.genericProgressFor(challenge.creatorUid).toDouble();
    final opponentProgress =
        challenge.genericProgressFor(challenge.opponentUid).toDouble();

    if (creatorProgress > opponentProgress) {
      return _ChallengeCompletion(
        winnerUid: challenge.creatorUid,
      );
    }

    if (opponentProgress > creatorProgress) {
      return _ChallengeCompletion(
        winnerUid: challenge.opponentUid,
      );
    }

    return const _ChallengeCompletion(
      winnerUid: null,
    );
  }

  static String _challengeTypeToString(
    MunjaChallengeType type,
  ) {
    switch (type) {
      case MunjaChallengeType.distance:
        return 'distance';
      case MunjaChallengeType.rideCount:
        return 'ride_count';
      case MunjaChallengeType.rideTime:
        return 'ride_time';
      case MunjaChallengeType.streak:
        return 'streak';
    }
  }

  static (int, int) _rewardForChallenge({
    required MunjaChallengeType type,
    double targetDistanceKm = 0,
    int targetRideCount = 0,
    int targetRideTimeMinutes = 0,
    int targetStreakDays = 0,
  }) {
    switch (type) {
      case MunjaChallengeType.distance:
        if (targetDistanceKm >= 50) return (10, 100);
        if (targetDistanceKm >= 25) return (6, 60);
        return (3, 30);
      case MunjaChallengeType.rideCount:
        if (targetRideCount >= 10) return (10, 100);
        if (targetRideCount >= 5) return (6, 60);
        return (3, 30);
      case MunjaChallengeType.rideTime:
        if (targetRideTimeMinutes >= 300) return (10, 100);
        if (targetRideTimeMinutes >= 180) return (6, 60);
        return (3, 30);
      case MunjaChallengeType.streak:
        if (targetStreakDays >= 7) return (10, 100);
        if (targetStreakDays >= 5) return (6, 60);
        return (3, 30);
    }
  }

  static bool _isAllowedRideCount(int value) =>
      value == 3 || value == 5 || value == 10;

  static bool _isAllowedRideTime(int value) =>
      value == 60 || value == 180 || value == 300;

  static bool _isAllowedStreak(int value) =>
      value == 3 || value == 5 || value == 7;

  static bool _isAllowedDistance(
    double distanceKm,
  ) {
    return distanceKm == 10 ||
        distanceKm == 25 ||
        distanceKm == 50;
  }

  static bool _isAllowedDuration(
    int durationDays,
  ) {
    return durationDays == 3 ||
        durationDays == 7 ||
        durationDays == 14;
  }

  String _requireCurrentUid() {
    final uid = currentUid;

    if (uid == null ||
        uid.trim().isEmpty) {
      throw StateError(
        'A signed-in Firebase user is required.',
      );
    }

    return uid.trim();
  }

  static String _stringValue(
    Object? value, {
    String fallback = '',
  }) {
    if (value is String) {
      final trimmed = value.trim();

      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }

    return fallback;
  }

  static int _intValue(
    Object? value,
  ) {
    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }
}

class _ChallengeCompletion {
  const _ChallengeCompletion({
    required this.winnerUid,
  });

  final String? winnerUid;
}
