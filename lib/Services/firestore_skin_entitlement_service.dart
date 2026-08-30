import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/firestore_user.dart';

enum SkinUnlockStatus {
  success,
  alreadyOwned,
  insufficientCrystals,
  userNotFound,
  invalidRequest,
  transactionFailed,
}

class SkinUnlockResult {
  const SkinUnlockResult({
    required this.status,
    this.skinId = '',
    this.crystalPrice = 0,
    this.previousCrystalBalance,
    this.newCrystalBalance,
    this.error,
  });

  final SkinUnlockStatus status;
  final String skinId;
  final int crystalPrice;
  final int? previousCrystalBalance;
  final int? newCrystalBalance;
  final Object? error;

  bool get isSuccess => status == SkinUnlockStatus.success;

  bool get isAlreadyOwned => status == SkinUnlockStatus.alreadyOwned;

  bool get hasInsufficientCrystals =>
      status == SkinUnlockStatus.insufficientCrystals;

  @override
  String toString() {
    return 'SkinUnlockResult('
        'status: $status, '
        'skinId: $skinId, '
        'crystalPrice: $crystalPrice, '
        'previousCrystalBalance: $previousCrystalBalance, '
        'newCrystalBalance: $newCrystalBalance, '
        'error: $error'
        ')';
  }
}


enum FrameUnlockStatus {
  success,
  alreadyOwned,
  insufficientCrystals,
  userNotFound,
  invalidRequest,
  transactionFailed,
}

class FrameUnlockResult {
  const FrameUnlockResult({
    required this.status,
    this.frameId = '',
    this.crystalPrice = 0,
    this.previousCrystalBalance,
    this.newCrystalBalance,
    this.error,
  });

  final FrameUnlockStatus status;
  final String frameId;
  final int crystalPrice;
  final int? previousCrystalBalance;
  final int? newCrystalBalance;
  final Object? error;

  bool get isSuccess => status == FrameUnlockStatus.success;

  bool get isAlreadyOwned => status == FrameUnlockStatus.alreadyOwned;

  bool get hasInsufficientCrystals =>
      status == FrameUnlockStatus.insufficientCrystals;

  @override
  String toString() {
    return 'FrameUnlockResult('
        'status: $status, '
        'frameId: $frameId, '
        'crystalPrice: $crystalPrice, '
        'previousCrystalBalance: $previousCrystalBalance, '
        'newCrystalBalance: $newCrystalBalance, '
        'error: $error'
        ')';
  }
}

enum RewardSkinUnlockStatus {
  success,
  alreadyUnlocked,
  userNotFound,
  invalidRequest,
  transactionFailed,
}

class RewardSkinUnlockResult {
  const RewardSkinUnlockResult({
    required this.status,
    this.skinId = '',
    this.error,
  });

  final RewardSkinUnlockStatus status;
  final String skinId;
  final Object? error;

  bool get isSuccess => status == RewardSkinUnlockStatus.success;

  bool get isAlreadyUnlocked =>
      status == RewardSkinUnlockStatus.alreadyUnlocked;

  @override
  String toString() {
    return 'RewardSkinUnlockResult('
        'status: $status, '
        'skinId: $skinId, '
        'error: $error'
        ')';
  }
}

class FirestoreSkinEntitlementService {
  FirestoreSkinEntitlementService._({
    FirebaseFirestore? firestore,
    String userCollectionPath = 'users',
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _userCollectionPath = userCollectionPath.trim().isEmpty
            ? 'users'
            : userCollectionPath.trim();

  static final FirestoreSkinEntitlementService instance =
      FirestoreSkinEntitlementService._();

  final FirebaseFirestore _firestore;
  final String _userCollectionPath;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(_userCollectionPath);

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _users.doc(uid.trim());
  }

  Stream<FirestoreUser?> watchUser(String uid) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return Stream<FirestoreUser?>.value(null);
    }

    return _userRef(normalizedUid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return null;
      }

      return FirestoreUser.fromFirestore(snapshot);
    });
  }

  Future<FirestoreUser?> getUser(String uid) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return null;
    }

    final snapshot = await _userRef(normalizedUid).get();

    if (!snapshot.exists) {
      return null;
    }

    return FirestoreUser.fromFirestore(snapshot);
  }

  Future<int> getCrystalBalance(String uid) async {
    final user = await getUser(uid);
    return user?.crystalBalance ?? 0;
  }

  Stream<Set<String>> watchOwnedFrameIds(String uid) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return Stream<Set<String>>.value(<String>{'frame_1'});
    }

    return _userRef(normalizedUid).snapshots().map((snapshot) {
      if (!snapshot.exists) {
        return <String>{'frame_1'};
      }

      final data = snapshot.data() ?? <String, dynamic>{};
      final raw = data['ownedFrameIds'];

      final values = raw is Iterable
          ? raw
              .whereType<Object>()
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
          : <String>{};

      // Frame 1 is the base geometry for all users and remains available
      // as the compatibility/default frame. Premium frames are added here.
      values.add('frame_1');
      return values;
    });
  }

  Future<Set<String>> getOwnedFrameIds(String uid) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      return <String>{'frame_1'};
    }

    final snapshot = await _userRef(normalizedUid).get();

    if (!snapshot.exists) {
      return <String>{'frame_1'};
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final raw = data['ownedFrameIds'];

    final values = raw is Iterable
        ? raw
            .whereType<Object>()
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
        : <String>{};

    values.add('frame_1');
    return values;
  }

  Future<bool> ownsFrame({
    required String uid,
    required String frameId,
  }) async {
    final normalizedFrameId = frameId.trim();

    if (normalizedFrameId.isEmpty) {
      return false;
    }

    if (normalizedFrameId == 'frame_1') {
      return true;
    }

    final owned = await getOwnedFrameIds(uid);
    return owned.contains(normalizedFrameId);
  }

  Future<bool> ownsSkin({
    required String uid,
    required String skinId,
  }) async {
    final normalizedSkinId = skinId.trim();

    if (normalizedSkinId.isEmpty) {
      return false;
    }

    if (normalizedSkinId == 'standard') {
      return true;
    }

    final user = await getUser(uid);
    return user?.ownsSkin(normalizedSkinId) ?? false;
  }

  Future<bool> hasUnlockedRewardSkin({
    required String uid,
    required String skinId,
  }) async {
    final normalizedSkinId = skinId.trim();

    if (normalizedSkinId.isEmpty) {
      return false;
    }

    final user = await getUser(uid);
    return user?.hasUnlockedRewardSkin(normalizedSkinId) ?? false;
  }

  Future<bool> isPro({
    required String uid,
  }) async {
    final user = await getUser(uid);
    return user?.isPremiumSubscription ?? false;
  }

  Future<bool> canUseSkin({
    required String uid,
    required String skinId,
    bool requiresPro = false,
    bool requiresRewardUnlock = false,
  }) async {
    final normalizedSkinId = skinId.trim();

    if (normalizedSkinId.isEmpty) {
      return false;
    }

    final user = await getUser(uid);

    if (user == null) {
      return false;
    }

    return user.canUseSkin(
      skinId: normalizedSkinId,
      requiresPro: requiresPro,
      requiresRewardUnlock: requiresRewardUnlock,
    );
  }

  Future<SkinUnlockResult> unlockSkinWithCrystals({
    required String uid,
    required String skinId,
    required int crystalPrice,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedSkinId = skinId.trim();

    if (normalizedUid.isEmpty ||
        normalizedSkinId.isEmpty ||
        crystalPrice < 0) {
      return SkinUnlockResult(
        status: SkinUnlockStatus.invalidRequest,
        skinId: normalizedSkinId,
        crystalPrice: crystalPrice,
      );
    }

    if (normalizedSkinId == 'standard') {
      return SkinUnlockResult(
        status: SkinUnlockStatus.alreadyOwned,
        skinId: normalizedSkinId,
        crystalPrice: crystalPrice,
      );
    }

    final userReference = _userRef(normalizedUid);

    try {
      return await _firestore.runTransaction<SkinUnlockResult>(
        (transaction) async {
          final snapshot = await transaction.get(userReference);

          if (!snapshot.exists) {
            return SkinUnlockResult(
              status: SkinUnlockStatus.userNotFound,
              skinId: normalizedSkinId,
              crystalPrice: crystalPrice,
            );
          }

          final data = snapshot.data() ?? <String, dynamic>{};

          final user = FirestoreUser.fromMap(
            uid: snapshot.id,
            data: data,
          );

          if (user.ownsSkin(normalizedSkinId)) {
            return SkinUnlockResult(
              status: SkinUnlockStatus.alreadyOwned,
              skinId: normalizedSkinId,
              crystalPrice: crystalPrice,
              previousCrystalBalance: user.crystalBalance,
              newCrystalBalance: user.crystalBalance,
            );
          }

          final currentBalance = user.crystalBalance;

          if (!user.canAffordCrystals(crystalPrice)) {
            return SkinUnlockResult(
              status: SkinUnlockStatus.insufficientCrystals,
              skinId: normalizedSkinId,
              crystalPrice: crystalPrice,
              previousCrystalBalance: currentBalance,
              newCrystalBalance: currentBalance,
            );
          }

          final newBalance = currentBalance - crystalPrice;

          final updatedOwnedSkinIds = <String>[
            ...user.ownedSkinIds,
            normalizedSkinId,
          ];

          transaction.update(
            userReference,
            <String, dynamic>{
              'crystals': newBalance,
              'ownedSkinIds': updatedOwnedSkinIds,
            },
          );

          return SkinUnlockResult(
            status: SkinUnlockStatus.success,
            skinId: normalizedSkinId,
            crystalPrice: crystalPrice,
            previousCrystalBalance: currentBalance,
            newCrystalBalance: newBalance,
          );
        },
      );
    } catch (error, stackTrace) {
      // Keep errors visible in debug logs without leaking implementation
      // details into the UI layer.
      // ignore: avoid_print
      print(
        'FIRESTORE SKIN ENTITLEMENT CRYSTAL UNLOCK ERROR: '
        '$normalizedSkinId -> $error',
      );
      // ignore: avoid_print
      print(stackTrace);

      return SkinUnlockResult(
        status: SkinUnlockStatus.transactionFailed,
        skinId: normalizedSkinId,
        crystalPrice: crystalPrice,
        error: error,
      );
    }
  }

  Future<FrameUnlockResult> unlockFrameWithCrystals({
    required String uid,
    required String frameId,
    required int crystalPrice,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedFrameId = frameId.trim();

    if (normalizedUid.isEmpty ||
        normalizedFrameId.isEmpty ||
        crystalPrice < 0) {
      return FrameUnlockResult(
        status: FrameUnlockStatus.invalidRequest,
        frameId: normalizedFrameId,
        crystalPrice: crystalPrice,
      );
    }

    // Frame 1 is the compatibility/default frame. It is always available.
    if (normalizedFrameId == 'frame_1') {
      return FrameUnlockResult(
        status: FrameUnlockStatus.alreadyOwned,
        frameId: normalizedFrameId,
        crystalPrice: crystalPrice,
      );
    }

    final userReference = _userRef(normalizedUid);

    try {
      return await _firestore.runTransaction<FrameUnlockResult>(
        (transaction) async {
          final snapshot = await transaction.get(userReference);

          if (!snapshot.exists) {
            return FrameUnlockResult(
              status: FrameUnlockStatus.userNotFound,
              frameId: normalizedFrameId,
              crystalPrice: crystalPrice,
            );
          }

          final data = snapshot.data() ?? <String, dynamic>{};
          final user = FirestoreUser.fromMap(
            uid: snapshot.id,
            data: data,
          );

          final rawOwnedFrames = data['ownedFrameIds'];
          final ownedFrameIds = rawOwnedFrames is Iterable
              ? rawOwnedFrames
                  .whereType<Object>()
                  .map((value) => value.toString().trim())
                  .where((value) => value.isNotEmpty)
                  .toSet()
              : <String>{};

          ownedFrameIds.add('frame_1');

          if (ownedFrameIds.contains(normalizedFrameId)) {
            return FrameUnlockResult(
              status: FrameUnlockStatus.alreadyOwned,
              frameId: normalizedFrameId,
              crystalPrice: crystalPrice,
              previousCrystalBalance: user.crystalBalance,
              newCrystalBalance: user.crystalBalance,
            );
          }

          final currentBalance = user.crystalBalance;

          if (!user.canAffordCrystals(crystalPrice)) {
            return FrameUnlockResult(
              status: FrameUnlockStatus.insufficientCrystals,
              frameId: normalizedFrameId,
              crystalPrice: crystalPrice,
              previousCrystalBalance: currentBalance,
              newCrystalBalance: currentBalance,
            );
          }

          final newBalance = currentBalance - crystalPrice;
          ownedFrameIds.add(normalizedFrameId);

          transaction.update(
            userReference,
            <String, dynamic>{
              'crystals': newBalance,
              'ownedFrameIds': ownedFrameIds.toList()..sort(),
            },
          );

          return FrameUnlockResult(
            status: FrameUnlockStatus.success,
            frameId: normalizedFrameId,
            crystalPrice: crystalPrice,
            previousCrystalBalance: currentBalance,
            newCrystalBalance: newBalance,
          );
        },
      );
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print(
        'FIRESTORE FRAME ENTITLEMENT CRYSTAL UNLOCK ERROR: '
        '$normalizedFrameId -> $error',
      );
      // ignore: avoid_print
      print(stackTrace);

      return FrameUnlockResult(
        status: FrameUnlockStatus.transactionFailed,
        frameId: normalizedFrameId,
        crystalPrice: crystalPrice,
        error: error,
      );
    }
  }

  Future<RewardSkinUnlockResult> unlockRewardSkin({
    required String uid,
    required String skinId,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedSkinId = skinId.trim();

    if (normalizedUid.isEmpty || normalizedSkinId.isEmpty) {
      return RewardSkinUnlockResult(
        status: RewardSkinUnlockStatus.invalidRequest,
        skinId: normalizedSkinId,
      );
    }

    final userReference = _userRef(normalizedUid);

    try {
      return await _firestore.runTransaction<RewardSkinUnlockResult>(
        (transaction) async {
          final snapshot = await transaction.get(userReference);

          if (!snapshot.exists) {
            return RewardSkinUnlockResult(
              status: RewardSkinUnlockStatus.userNotFound,
              skinId: normalizedSkinId,
            );
          }

          final user = FirestoreUser.fromMap(
            uid: snapshot.id,
            data: snapshot.data() ?? <String, dynamic>{},
          );

          if (user.hasUnlockedRewardSkin(normalizedSkinId)) {
            return RewardSkinUnlockResult(
              status: RewardSkinUnlockStatus.alreadyUnlocked,
              skinId: normalizedSkinId,
            );
          }

          final updatedRewardSkinIds = <String>[
            ...user.unlockedRewardSkinIds,
            normalizedSkinId,
          ];

          transaction.update(
            userReference,
            <String, dynamic>{
              'unlockedRewardSkinIds': updatedRewardSkinIds,
            },
          );

          return RewardSkinUnlockResult(
            status: RewardSkinUnlockStatus.success,
            skinId: normalizedSkinId,
          );
        },
      );
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print(
        'FIRESTORE SKIN ENTITLEMENT REWARD UNLOCK ERROR: '
        '$normalizedSkinId -> $error',
      );
      // ignore: avoid_print
      print(stackTrace);

      return RewardSkinUnlockResult(
        status: RewardSkinUnlockStatus.transactionFailed,
        skinId: normalizedSkinId,
        error: error,
      );
    }
  }

  Future<void> grantCrystals({
    required String uid,
    required int amount,
  }) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty || amount <= 0) {
      throw ArgumentError(
        'uid must not be empty and amount must be greater than zero.',
      );
    }

    final userReference = _userRef(normalizedUid);

    await _firestore.runTransaction<void>(
      (transaction) async {
        final snapshot = await transaction.get(userReference);

        if (!snapshot.exists) {
          throw StateError('Firestore user does not exist.');
        }

        final user = FirestoreUser.fromMap(
          uid: snapshot.id,
          data: snapshot.data() ?? <String, dynamic>{},
        );

        transaction.update(
          userReference,
          <String, dynamic>{
            'crystals': user.crystalBalance + amount,
          },
        );
      },
    );
  }

  Future<bool> spendCrystals({
    required String uid,
    required int amount,
  }) async {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty || amount <= 0) {
      return false;
    }

    final userReference = _userRef(normalizedUid);

    return _firestore.runTransaction<bool>(
      (transaction) async {
        final snapshot = await transaction.get(userReference);

        if (!snapshot.exists) {
          return false;
        }

        final user = FirestoreUser.fromMap(
          uid: snapshot.id,
          data: snapshot.data() ?? <String, dynamic>{},
        );

        if (!user.canAffordCrystals(amount)) {
          return false;
        }

        transaction.update(
          userReference,
          <String, dynamic>{
            'crystals': user.crystalBalance - amount,
          },
        );

        return true;
      },
    );
  }

  Future<void> grantOwnedFrame({
    required String uid,
    required String frameId,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedFrameId = frameId.trim();

    if (normalizedUid.isEmpty || normalizedFrameId.isEmpty) {
      throw ArgumentError('uid and frameId must not be empty.');
    }

    final userReference = _userRef(normalizedUid);

    await _firestore.runTransaction<void>(
      (transaction) async {
        final snapshot = await transaction.get(userReference);

        if (!snapshot.exists) {
          throw StateError('Firestore user does not exist.');
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final rawOwnedFrames = data['ownedFrameIds'];

        final ownedFrameIds = rawOwnedFrames is Iterable
            ? rawOwnedFrames
                .whereType<Object>()
                .map((value) => value.toString().trim())
                .where((value) => value.isNotEmpty)
                .toSet()
            : <String>{};

        ownedFrameIds.add('frame_1');

        if (ownedFrameIds.contains(normalizedFrameId)) {
          return;
        }

        ownedFrameIds.add(normalizedFrameId);

        transaction.update(
          userReference,
          <String, dynamic>{
            'ownedFrameIds': ownedFrameIds.toList()..sort(),
          },
        );
      },
    );
  }

  Future<void> grantOwnedSkin({
    required String uid,
    required String skinId,
  }) async {
    final normalizedUid = uid.trim();
    final normalizedSkinId = skinId.trim();

    if (normalizedUid.isEmpty || normalizedSkinId.isEmpty) {
      throw ArgumentError('uid and skinId must not be empty.');
    }

    final userReference = _userRef(normalizedUid);

    await _firestore.runTransaction<void>(
      (transaction) async {
        final snapshot = await transaction.get(userReference);

        if (!snapshot.exists) {
          throw StateError('Firestore user does not exist.');
        }

        final user = FirestoreUser.fromMap(
          uid: snapshot.id,
          data: snapshot.data() ?? <String, dynamic>{},
        );

        if (user.ownsSkin(normalizedSkinId)) {
          return;
        }

        transaction.update(
          userReference,
          <String, dynamic>{
            'ownedSkinIds': <String>[
              ...user.ownedSkinIds,
              normalizedSkinId,
            ],
          },
        );
      },
    );
  }
}
