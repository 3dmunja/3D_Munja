import 'package:cloud_firestore/cloud_firestore.dart';

enum CrystalRewardType {
  firstRide,
  rideCompleted,
  distanceMilestone,
  weeklyChallenge,
  monthlySpecial,
  streak,
  achievement,
  manual,
}

extension CrystalRewardTypeValue on CrystalRewardType {
  String get value {
    switch (this) {
      case CrystalRewardType.firstRide:
        return 'first_ride';
      case CrystalRewardType.rideCompleted:
        return 'ride_completed';
      case CrystalRewardType.distanceMilestone:
        return 'distance_milestone';
      case CrystalRewardType.weeklyChallenge:
        return 'weekly_challenge';
      case CrystalRewardType.monthlySpecial:
        return 'monthly_special';
      case CrystalRewardType.streak:
        return 'streak';
      case CrystalRewardType.achievement:
        return 'achievement';
      case CrystalRewardType.manual:
        return 'manual';
    }
  }
}

enum CrystalRewardStatus {
  success,
  alreadyClaimed,
  userNotFound,
  invalidRequest,
  transactionFailed,
}

class CrystalRewardResult {
  const CrystalRewardResult({
    required this.status,
    required this.rewardId,
    required this.rewardType,
    this.amount = 0,
    this.previousBalance,
    this.newBalance,
    this.error,
  });

  final CrystalRewardStatus status;
  final String rewardId;
  final CrystalRewardType rewardType;
  final int amount;
  final int? previousBalance;
  final int? newBalance;
  final Object? error;

  bool get isSuccess => status == CrystalRewardStatus.success;

  bool get isAlreadyClaimed =>
      status == CrystalRewardStatus.alreadyClaimed;

  @override
  String toString() {
    return 'CrystalRewardResult('
        'status: $status, '
        'rewardId: $rewardId, '
        'rewardType: ${rewardType.value}, '
        'amount: $amount, '
        'previousBalance: $previousBalance, '
        'newBalance: $newBalance, '
        'error: $error'
        ')';
  }
}

class CrystalRewardClaim {
  const CrystalRewardClaim({
    required this.id,
    required this.type,
    required this.amount,
    required this.sourceId,
    required this.createdAt,
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final CrystalRewardType type;
  final int amount;
  final String sourceId;
  final DateTime? createdAt;
  final Map<String, dynamic> metadata;

  factory CrystalRewardClaim.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    return CrystalRewardClaim(
      id: document.id,
      type: _parseType(data['type']),
      amount: _readInt(data['amount']),
      sourceId: _readString(data['sourceId']),
      createdAt: _readDateTime(data['createdAt']),
      metadata: _readMap(data['metadata']),
    );
  }

  static CrystalRewardType _parseType(dynamic value) {
    final normalized = _readString(value).toLowerCase();

    for (final type in CrystalRewardType.values) {
      if (type.value == normalized) {
        return type;
      }
    }

    return CrystalRewardType.manual;
  }

  static String _readString(dynamic value) {
    if (value is String) {
      return value.trim();
    }

    return '';
  }

  static int _readInt(dynamic value) {
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

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }

    if (value is String) {
      return DateTime.tryParse(value.trim());
    }

    return null;
  }

  static Map<String, dynamic> _readMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.unmodifiable(value);
    }

    if (value is Map) {
      return Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(value),
      );
    }

    return const <String, dynamic>{};
  }
}

class CrystalRewardService {
  CrystalRewardService._({
    FirebaseFirestore? firestore,
    String userCollectionPath = 'users',
    String rewardClaimsCollectionName = 'crystalRewardClaims',
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _userCollectionPath = userCollectionPath.trim().isEmpty
            ? 'users'
            : userCollectionPath.trim(),
        _rewardClaimsCollectionName =
            rewardClaimsCollectionName.trim().isEmpty
                ? 'crystalRewardClaims'
                : rewardClaimsCollectionName.trim();

  static final CrystalRewardService instance =
      CrystalRewardService._();

  final FirebaseFirestore _firestore;
  final String _userCollectionPath;
  final String _rewardClaimsCollectionName;

  // ---------------------------------------------------------------------------
  // MUNJA RIDE CRYSTAL ECONOMY
  // ---------------------------------------------------------------------------
  //
  // Normal rides should be the slowest Crystal source in Munja.
  // Challenges, Monthly Specials and achievements remain separate reward paths.
  //
  // Ride reward matrix:
  //   < 5 km       -> 0 Crystals
  //   5 - 9.99 km -> 1 Crystal
  //   10 - 19.99  -> 2 Crystals
  //   20 - 39.99  -> 3 Crystals
  //   40 - 59.99  -> 5 Crystals
  //   60 - 99.99  -> 7 Crystals
  //   100+ km      -> 10 Crystals
  //
  // A rider can earn at most 10 normal ride Crystals per UTC day.
  // Special/challenge rewards are NOT included in this cap.
  static const double minimumRewardRideKm = 5.0;
  static const int dailyRideCrystalCap = 10;

  /// Returns the base Crystal reward for one completed ride.
  ///
  /// This is intentionally conservative so normal riding cannot flood the
  /// Crystal economy. Other reward systems can still grant larger amounts.
  static int rideCrystalAmountForDistance(double distanceKm) {
    if (!distanceKm.isFinite || distanceKm < minimumRewardRideKm) {
      return 0;
    }

    if (distanceKm < 10) {
      return 1;
    }

    if (distanceKm < 20) {
      return 2;
    }

    if (distanceKm < 40) {
      return 3;
    }

    if (distanceKm < 60) {
      return 5;
    }

    if (distanceKm < 100) {
      return 7;
    }

    return 10;
  }

  static String _utcDayKey(DateTime dateTime) {
    final utc = dateTime.toUtc();

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    return '${utc.year}-'
        '${twoDigits(utc.month)}-'
        '${twoDigits(utc.day)}';
  }

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(_userCollectionPath);

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _users.doc(uid.trim());
  }

  CollectionReference<Map<String, dynamic>> _claimsRef(String uid) {
    return _userRef(uid).collection(_rewardClaimsCollectionName);
  }

  DocumentReference<Map<String, dynamic>> _claimRef({
    required String uid,
    required String rewardId,
  }) {
    return _claimsRef(uid).doc(rewardId.trim());
  }

  /// Atomically grants a Crystal reward.
  ///
  /// The reward claim document is the idempotency key. The same rewardId can
  /// therefore never increase the balance twice, even after retry/app restart.
  ///
  /// The user document is written with SetOptions(merge: true), so Crystal
  /// rewards also work safely when `crystals` does not exist yet.
  Future<CrystalRewardResult> grantReward({
    required String uid,
    required String rewardId,
    required CrystalRewardType rewardType,
    required int amount,
    String sourceId = '',
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final normalizedUid = uid.trim();
    final normalizedRewardId = rewardId.trim();
    final normalizedSourceId = sourceId.trim();

    if (normalizedUid.isEmpty ||
        normalizedRewardId.isEmpty ||
        amount <= 0) {
      return CrystalRewardResult(
        status: CrystalRewardStatus.invalidRequest,
        rewardId: normalizedRewardId,
        rewardType: rewardType,
        amount: amount,
      );
    }

    final userReference = _userRef(normalizedUid);
    final claimReference = _claimRef(
      uid: normalizedUid,
      rewardId: normalizedRewardId,
    );

    try {
      return await _firestore.runTransaction<CrystalRewardResult>(
        (transaction) async {
          final userSnapshot = await transaction.get(userReference);

          final claimSnapshot = await transaction.get(claimReference);

          final userData =
              userSnapshot.data() ?? const <String, dynamic>{};

          if (claimSnapshot.exists) {
            final currentBalance =
                _readCrystalBalance(userData);

            return CrystalRewardResult(
              status: CrystalRewardStatus.alreadyClaimed,
              rewardId: normalizedRewardId,
              rewardType: rewardType,
              amount: amount,
              previousBalance: currentBalance,
              newBalance: currentBalance,
            );
          }

          final previousBalance =
              _readCrystalBalance(userData);

          final newBalance =
              previousBalance + amount;

          transaction.set(
            userReference,
            <String, dynamic>{
              'crystals': newBalance,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          transaction.set(
            claimReference,
            <String, dynamic>{
              'rewardId': normalizedRewardId,
              'type': rewardType.value,
              'amount': amount,
              'sourceId': normalizedSourceId,
              'metadata': _sanitizeMetadata(metadata),
              'createdAt': FieldValue.serverTimestamp(),
            },
          );

          return CrystalRewardResult(
            status: CrystalRewardStatus.success,
            rewardId: normalizedRewardId,
            rewardType: rewardType,
            amount: amount,
            previousBalance: previousBalance,
            newBalance: newBalance,
          );
        },
      );
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print(
        'CRYSTAL REWARD TRANSACTION ERROR: '
        '$normalizedRewardId -> $error',
      );
      // ignore: avoid_print
      print(stackTrace);

      return CrystalRewardResult(
        status: CrystalRewardStatus.transactionFailed,
        rewardId: normalizedRewardId,
        rewardType: rewardType,
        amount: amount,
        error: error,
      );
    }
  }

  Future<CrystalRewardResult> grantFirstRideReward({
    required String uid,
    required String rideId,
    int amount = 20,
  }) {
    final normalizedRideId = rideId.trim();

    return grantReward(
      uid: uid,
      rewardId: 'first_ride',
      rewardType: CrystalRewardType.firstRide,
      amount: amount,
      sourceId: normalizedRideId,
      metadata: <String, dynamic>{
        'rideId': normalizedRideId,
      },
    );
  }

  /// Grants the normal Crystal reward for a completed ride.
  ///
  /// IMPORTANT:
  /// The old API accepted a fixed `amount` (normally 2), which meant even a
  /// 10-metre start/stop test ride could earn Crystals. The amount is now
  /// calculated centrally from distance and cannot be overridden by callers.
  ///
  /// `amount` is intentionally kept in the signature for backwards
  /// compatibility with existing callers. It is recorded as metadata only and
  /// does NOT decide the actual reward.
  ///
  /// This method also:
  /// - creates a claim for zero-reward rides, preventing later farming/retry;
  /// - enforces a 10-Crystal daily cap for normal ride rewards;
  /// - remains idempotent by using `ride_completed_<rideId>` as the claim ID.
  Future<CrystalRewardResult> grantRideCompletedReward({
    required String uid,
    required String rideId,
    int amount = 2,
    double distanceKm = 0,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedRideId = rideId.trim();
    final normalizedDistanceKm =
        distanceKm.isFinite && distanceKm > 0 ? distanceKm : 0.0;

    final rewardId = 'ride_completed_$normalizedRideId';
    const rewardType = CrystalRewardType.rideCompleted;

    if (normalizedUid.isEmpty || normalizedRideId.isEmpty) {
      return CrystalRewardResult(
        status: CrystalRewardStatus.invalidRequest,
        rewardId: rewardId,
        rewardType: rewardType,
        amount: 0,
      );
    }

    final baseAmount =
        rideCrystalAmountForDistance(normalizedDistanceKm);

    final userReference = _userRef(normalizedUid);
    final claimReference = _claimRef(
      uid: normalizedUid,
      rewardId: rewardId,
    );

    final dayKey = _utcDayKey(DateTime.now());

    try {
      return await _firestore.runTransaction<CrystalRewardResult>(
        (transaction) async {
          final userSnapshot =
              await transaction.get(userReference);

          final claimSnapshot =
              await transaction.get(claimReference);

          final userData =
              userSnapshot.data() ?? const <String, dynamic>{};

          final currentBalance =
              _readCrystalBalance(userData);

          // The same ride can never pay twice.
          if (claimSnapshot.exists) {
            final claimData =
                claimSnapshot.data() ?? const <String, dynamic>{};

            final storedAmount =
                _readNonNegativeInt(claimData['amount']);

            return CrystalRewardResult(
              status: CrystalRewardStatus.alreadyClaimed,
              rewardId: rewardId,
              rewardType: rewardType,
              amount: storedAmount,
              previousBalance: currentBalance,
              newBalance: currentBalance,
            );
          }

          final storedDayKey =
              _readStringValue(userData['rideCrystalDayKey']);

          final storedDayEarned =
              _readNonNegativeInt(
            userData['rideCrystalDayEarned'],
          );

          final alreadyEarnedToday =
              storedDayKey == dayKey
                  ? storedDayEarned
                  : 0;

          final remainingToday =
              (dailyRideCrystalCap - alreadyEarnedToday)
                  .clamp(0, dailyRideCrystalCap);

          final awardedAmount =
              baseAmount.clamp(0, remainingToday);

          final newBalance =
              currentBalance + awardedAmount;

          final newDailyRideTotal =
              alreadyEarnedToday + awardedAmount;

          String qualificationReason;

          if (baseAmount <= 0) {
            qualificationReason = 'distance_below_minimum';
          } else if (remainingToday <= 0) {
            qualificationReason = 'daily_cap_reached';
          } else if (awardedAmount < baseAmount) {
            qualificationReason = 'daily_cap_partial';
          } else {
            qualificationReason = 'qualified';
          }

          // Only mutate the Crystal balance if this ride actually earned
          // something. We still update the ride-day ledger for qualified
          // rewards so the daily cap is transactional.
          if (awardedAmount > 0) {
            transaction.set(
              userReference,
              <String, dynamic>{
                'crystals': newBalance,
                'rideCrystalDayKey': dayKey,
                'rideCrystalDayEarned': newDailyRideTotal,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }

          // Zero-reward rides ALSO receive a claim.
          // That matters: a 0.01 km ride must stay permanently worth 0 rather
          // than becoming claimable later after a retry or app restart.
          transaction.set(
            claimReference,
            <String, dynamic>{
              'rewardId': rewardId,
              'type': rewardType.value,
              'amount': awardedAmount,
              'sourceId': normalizedRideId,
              'metadata': _sanitizeMetadata(
                <String, dynamic>{
                  'rideId': normalizedRideId,
                  'distanceKm': normalizedDistanceKm,
                  'minimumRewardRideKm': minimumRewardRideKm,
                  'baseAmount': baseAmount,
                  'awardedAmount': awardedAmount,
                  'dailyRideCrystalCap': dailyRideCrystalCap,
                  'dailyEarnedBefore': alreadyEarnedToday,
                  'dailyEarnedAfter': newDailyRideTotal,
                  'qualificationReason': qualificationReason,
                  // Kept only so older callers passing `amount: 2` can be
                  // diagnosed during migration. It never controls payout.
                  'legacyRequestedAmount': amount,
                  'economyVersion': 2,
                },
              ),
              'createdAt': FieldValue.serverTimestamp(),
            },
          );

          return CrystalRewardResult(
            status: CrystalRewardStatus.success,
            rewardId: rewardId,
            rewardType: rewardType,
            amount: awardedAmount,
            previousBalance: currentBalance,
            newBalance: newBalance,
          );
        },
      );
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print(
        'RIDE CRYSTAL REWARD TRANSACTION ERROR: '
        '$rewardId -> $error',
      );

      // ignore: avoid_print
      print(stackTrace);

      return CrystalRewardResult(
        status: CrystalRewardStatus.transactionFailed,
        rewardId: rewardId,
        rewardType: rewardType,
        amount: 0,
        error: error,
      );
    }
  }

  /// Convenience helper for Ride Saved UI.
  ///
  /// Returns the exact completed-ride claim if it already exists. This lets the
  /// summary screen show the awarded amount after navigation/restart without
  /// granting the reward again.
  Future<CrystalRewardClaim?> getRideCompletedClaim({
    required String uid,
    required String rideId,
  }) {
    final normalizedRideId = rideId.trim();

    if (uid.trim().isEmpty ||
        normalizedRideId.isEmpty) {
      return Future<CrystalRewardClaim?>.value(null);
    }

    return getClaim(
      uid: uid,
      rewardId: 'ride_completed_$normalizedRideId',
    );
  }

  Future<CrystalRewardResult> grantDistanceMilestoneReward({
    required String uid,
    required String milestoneId,
    required double distanceKm,
    required int amount,
  }) {
    final normalizedMilestoneId = milestoneId.trim();

    return grantReward(
      uid: uid,
      rewardId: 'distance_$normalizedMilestoneId',
      rewardType: CrystalRewardType.distanceMilestone,
      amount: amount,
      sourceId: normalizedMilestoneId,
      metadata: <String, dynamic>{
        'distanceKm': distanceKm,
      },
    );
  }

  Future<CrystalRewardResult> grantWeeklyChallengeReward({
    required String uid,
    required String challengeId,
    required int amount,
  }) {
    final normalizedChallengeId = challengeId.trim();

    return grantReward(
      uid: uid,
      rewardId: 'weekly_challenge_$normalizedChallengeId',
      rewardType: CrystalRewardType.weeklyChallenge,
      amount: amount,
      sourceId: normalizedChallengeId,
      metadata: <String, dynamic>{
        'challengeId': normalizedChallengeId,
      },
    );
  }

  /// Idempotent Crystal reward for a completed Munja Pro Monthly Special.
  ///
  /// Use the activation ID as the stable source. Repeated calls with the same
  /// activation ID cannot grant Crystals twice because grantReward() stores a
  /// dedicated claim document.
  Future<CrystalRewardResult> grantMonthlySpecialReward({
    required String uid,
    required String activationId,
    required int amount,
    String specialTitle = '',
    String cosmeticRewardId = '',
  }) {
    final normalizedActivationId = activationId.trim();

    return grantReward(
      uid: uid,
      rewardId: 'monthly_special_$normalizedActivationId',
      rewardType: CrystalRewardType.monthlySpecial,
      amount: amount,
      sourceId: normalizedActivationId,
      metadata: <String, dynamic>{
        'activationId': normalizedActivationId,
        if (specialTitle.trim().isNotEmpty)
          'specialTitle': specialTitle.trim(),
        if (cosmeticRewardId.trim().isNotEmpty)
          'cosmeticRewardId': cosmeticRewardId.trim(),
      },
    );
  }

  Future<CrystalRewardResult> grantStreakReward({
    required String uid,
    required String streakId,
    required int streakDays,
    required int amount,
  }) {
    final normalizedStreakId = streakId.trim();

    return grantReward(
      uid: uid,
      rewardId: 'streak_$normalizedStreakId',
      rewardType: CrystalRewardType.streak,
      amount: amount,
      sourceId: normalizedStreakId,
      metadata: <String, dynamic>{
        'streakDays': streakDays,
      },
    );
  }

  Future<CrystalRewardResult> grantAchievementReward({
    required String uid,
    required String achievementId,
    required int amount,
  }) {
    final normalizedAchievementId = achievementId.trim();

    return grantReward(
      uid: uid,
      rewardId: 'achievement_$normalizedAchievementId',
      rewardType: CrystalRewardType.achievement,
      amount: amount,
      sourceId: normalizedAchievementId,
      metadata: <String, dynamic>{
        'achievementId': normalizedAchievementId,
      },
    );
  }

  /// Live Crystal balance for Home/Profile/Shop.
  ///
  /// Every successful reward transaction updates users/{uid}.crystals, so all
  /// listeners rebuild immediately without requiring navigation or a manual
  /// refresh.
  Stream<int> watchBalance({
    required String uid,
  }) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return Stream<int>.value(0);
    }

    return _userRef(normalizedUid)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? _readCrystalBalance(
                  snapshot.data() ??
                      const <String, dynamic>{},
                )
              : 0,
        )
        .distinct();
  }

  /// One-time Crystal balance read.
  Future<int> getBalance({
    required String uid,
  }) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return 0;
    }

    final snapshot =
        await _userRef(normalizedUid).get();

    if (!snapshot.exists) {
      return 0;
    }

    return _readCrystalBalance(
      snapshot.data() ??
          const <String, dynamic>{},
    );
  }

  Future<bool> hasClaimed({
    required String uid,
    required String rewardId,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedRewardId = rewardId.trim();

    if (normalizedUid.isEmpty || normalizedRewardId.isEmpty) {
      return false;
    }

    final snapshot = await _claimRef(
      uid: normalizedUid,
      rewardId: normalizedRewardId,
    ).get();

    return snapshot.exists;
  }

  Future<CrystalRewardClaim?> getClaim({
    required String uid,
    required String rewardId,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedRewardId = rewardId.trim();

    if (normalizedUid.isEmpty || normalizedRewardId.isEmpty) {
      return null;
    }

    final snapshot = await _claimRef(
      uid: normalizedUid,
      rewardId: normalizedRewardId,
    ).get();

    if (!snapshot.exists) {
      return null;
    }

    return CrystalRewardClaim.fromFirestore(snapshot);
  }

  Stream<List<CrystalRewardClaim>> watchRewardHistory({
    required String uid,
    int limit = 50,
  }) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return Stream<List<CrystalRewardClaim>>.value(
        const <CrystalRewardClaim>[],
      );
    }

    final safeLimit = limit <= 0 ? 50 : limit;

    return _claimsRef(normalizedUid)
        .orderBy('createdAt', descending: true)
        .limit(safeLimit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(CrystalRewardClaim.fromFirestore)
              .toList(growable: false),
        );
  }

  Future<List<CrystalRewardClaim>> getRewardHistory({
    required String uid,
    int limit = 50,
  }) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return const <CrystalRewardClaim>[];
    }

    final safeLimit = limit <= 0 ? 50 : limit;

    final snapshot = await _claimsRef(normalizedUid)
        .orderBy('createdAt', descending: true)
        .limit(safeLimit)
        .get();

    return snapshot.docs
        .map(CrystalRewardClaim.fromFirestore)
        .toList(growable: false);
  }

  static int _readNonNegativeInt(dynamic value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }

    if (value is num) {
      final parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }

    if (value is String) {
      final parsed = int.tryParse(value.trim()) ?? 0;
      return parsed < 0 ? 0 : parsed;
    }

    return 0;
  }

  static String _readStringValue(dynamic value) {
    if (value is String) {
      return value.trim();
    }

    return '';
  }

  static int _readCrystalBalance(
    Map<String, dynamic> data,
  ) {
    final value = data['crystals'];

    if (value is int) {
      return value < 0 ? 0 : value;
    }

    if (value is num) {
      final parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }

    if (value is String) {
      final parsed = int.tryParse(value.trim()) ?? 0;
      return parsed < 0 ? 0 : parsed;
    }

    return 0;
  }

  static Map<String, dynamic> _sanitizeMetadata(
    Map<String, dynamic> metadata,
  ) {
    if (metadata.isEmpty) {
      return const <String, dynamic>{};
    }

    final sanitized = <String, dynamic>{};

    metadata.forEach((key, value) {
      final normalizedKey = key.trim();

      if (normalizedKey.isEmpty) {
        return;
      }

      if (_isFirestoreSafeValue(value)) {
        sanitized[normalizedKey] = value;
      }
    });

    return sanitized;
  }

  static bool _isFirestoreSafeValue(dynamic value) {
    if (value == null ||
        value is String ||
        value is bool ||
        value is num ||
        value is DateTime ||
        value is Timestamp ||
        value is GeoPoint ||
        value is DocumentReference) {
      return true;
    }

    if (value is Iterable) {
      return value.every(_isFirestoreSafeValue);
    }

    if (value is Map) {
      return value.entries.every(
        (entry) =>
            entry.key is String &&
            _isFirestoreSafeValue(entry.value),
      );
    }

    return false;
  }
}
