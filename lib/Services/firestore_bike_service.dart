import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/firestore_bike.dart';
import 'firestore_user_service.dart';

class FirestoreBikeService {
  FirestoreBikeService._();

  static final FirestoreBikeService instance = FirestoreBikeService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  static const String usersCollectionName = 'users';
  static const String bikesCollectionName = 'bikes';

  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  CollectionReference<Map<String, dynamic>> bikesCollection() {
    return _firestore.collection(bikesCollectionName);
  }

  Query<Map<String, dynamic>> userBikesQuery(String uid) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-uid',
        message: 'Brugerens ID mangler.',
      );
    }

    return bikesCollection().where('ownerId', isEqualTo: normalizedUid);
  }

  Query<Map<String, dynamic>> currentUserBikesQuery() {
    final user = _requireFirebaseUser();
    return userBikesQuery(user.uid);
  }

  DocumentReference<Map<String, dynamic>> bikeDocument({
    required String uid,
    required String bikeId,
  }) {
    final normalizedUid = uid.trim();
    final normalizedBikeId = bikeId.trim();

    if (normalizedUid.isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-uid',
        message: 'Brugerens ID mangler.',
      );
    }

    if (normalizedBikeId.isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-bike-id',
        message: 'Cyklens ID mangler.',
      );
    }

    return bikesCollection().doc(normalizedBikeId);
  }

  DocumentReference<Map<String, dynamic>> currentUserBikeDocument(
    String bikeId,
  ) {
    final user = _requireFirebaseUser();

    return bikeDocument(uid: user.uid, bikeId: bikeId);
  }

  Stream<List<FirestoreBike>> watchCurrentUserBikes() {
    final user = currentFirebaseUser;

    if (user == null) {
      return Stream<List<FirestoreBike>>.value(const <FirestoreBike>[]);
    }

    return watchUserBikes(user.uid);
  }

  Stream<List<FirestoreBike>> watchUserBikes(String uid) {
    return userBikesQuery(uid)
        .snapshots()
        .map((snapshot) {
          final bikes = snapshot.docs
              .map(FirestoreBike.fromFirestore)
              .toList(growable: false);

          return _sortBikes(bikes);
        })
        .handleError((Object error, StackTrace stackTrace) {
          debugPrint('WATCH FIRESTORE BIKES ERROR: $error');
          debugPrintStack(stackTrace: stackTrace);

          throw _mapException(
            error,
            fallbackCode: 'watch-bikes-failed',
            fallbackMessage: 'Cyklerne kunne ikke overvåges.',
          );
        });
  }

  Stream<FirestoreBike?> watchCurrentUserBike(String bikeId) {
    final user = currentFirebaseUser;

    if (user == null) {
      return Stream<FirestoreBike?>.value(null);
    }

    return watchBike(uid: user.uid, bikeId: bikeId);
  }

  Stream<FirestoreBike?> watchBike({
    required String uid,
    required String bikeId,
  }) {
    return bikeDocument(uid: uid, bikeId: bikeId)
        .snapshots()
        .map((document) {
          if (!document.exists) {
            return null;
          }

          return FirestoreBike.fromFirestore(document);
        })
        .handleError((Object error, StackTrace stackTrace) {
          debugPrint('WATCH FIRESTORE BIKE ERROR: $error');
          debugPrintStack(stackTrace: stackTrace);

          throw _mapException(
            error,
            fallbackCode: 'watch-bike-failed',
            fallbackMessage: 'Cyklen kunne ikke overvåges.',
          );
        });
  }

  Future<List<FirestoreBike>> getCurrentUserBikes() async {
    final user = currentFirebaseUser;

    if (user == null) {
      return const <FirestoreBike>[];
    }

    return getUserBikes(user.uid);
  }

  Future<List<FirestoreBike>> getUserBikes(String uid) async {
    try {
      final snapshot = await userBikesQuery(uid).get();

      final bikes = snapshot.docs
          .map(FirestoreBike.fromFirestore)
          .toList(growable: false);

      return _sortBikes(bikes);
    } catch (error, stackTrace) {
      debugPrint('GET FIRESTORE BIKES ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'get-bikes-failed',
        fallbackMessage: 'Cyklerne kunne ikke hentes.',
      );
    }
  }

  Future<FirestoreBike?> getCurrentUserBike(String bikeId) async {
    final user = currentFirebaseUser;

    if (user == null) {
      return null;
    }

    return getBike(uid: user.uid, bikeId: bikeId);
  }

  Future<FirestoreBike?> getBike({
    required String uid,
    required String bikeId,
  }) async {
    try {
      final document = await bikeDocument(uid: uid, bikeId: bikeId).get();

      if (!document.exists) {
        return null;
      }

      return FirestoreBike.fromFirestore(document);
    } catch (error, stackTrace) {
      debugPrint('GET FIRESTORE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'get-bike-failed',
        fallbackMessage: 'Cyklen kunne ikke hentes.',
      );
    }
  }

  Future<FirestoreBike?> getActiveBike() async {
    final user = currentFirebaseUser;

    if (user == null) {
      return null;
    }

    try {
      final snapshot = await userBikesQuery(
        user.uid,
      ).where('active', isEqualTo: true).limit(1).get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return FirestoreBike.fromFirestore(snapshot.docs.first);
    } catch (error, stackTrace) {
      debugPrint('GET ACTIVE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'get-active-bike-failed',
        fallbackMessage: 'Den aktive cykel kunne ikke hentes.',
      );
    }
  }

  Stream<FirestoreBike?> watchActiveBike() {
    final user = currentFirebaseUser;

    if (user == null) {
      return Stream<FirestoreBike?>.value(null);
    }

    return userBikesQuery(user.uid)
        .where('active', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
          if (snapshot.docs.isEmpty) {
            return null;
          }

          return FirestoreBike.fromFirestore(snapshot.docs.first);
        })
        .handleError((Object error, StackTrace stackTrace) {
          debugPrint('WATCH ACTIVE BIKE ERROR: $error');
          debugPrintStack(stackTrace: stackTrace);

          throw _mapException(
            error,
            fallbackCode: 'watch-active-bike-failed',
            fallbackMessage: 'Den aktive cykel kunne ikke overvåges.',
          );
        });
  }

  Future<FirestoreBike> createBike(
    FirestoreBike bike, {
    bool makeActive = false,
  }) async {
    final user = _requireFirebaseUser();
    final normalizedBike = bike.normalized();

    _validateBikeForCreate(normalizedBike, currentUserId: user.uid);

    final reference = normalizedBike.id.isEmpty
        ? bikesCollection().doc()
        : bikeDocument(uid: user.uid, bikeId: normalizedBike.id);

    final bikeToCreate = normalizedBike.copyWith(
      id: reference.id,
      ownerId: user.uid,
      active: makeActive || normalizedBike.active,
    );

    try {
      if (bikeToCreate.active) {
        await _createAndActivateBike(
          uid: user.uid,
          reference: reference,
          bike: bikeToCreate,
        );
      } else {
        await reference.set(bikeToCreate.toCreateMap());
      }

      final createdBike = await getBike(uid: user.uid, bikeId: reference.id);

      if (createdBike == null) {
        throw const FirestoreBikeServiceException(
          code: 'created-bike-missing',
          message: 'Cyklen blev ikke fundet efter oprettelsen.',
        );
      }

      return createdBike;
    } catch (error, stackTrace) {
      debugPrint('CREATE FIRESTORE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'create-bike-failed',
        fallbackMessage: 'Cyklen kunne ikke oprettes.',
      );
    }
  }

  Future<void> updateBike(FirestoreBike bike) async {
    final user = _requireFirebaseUser();
    final normalizedBike = bike.normalized();

    _validateBikeForUpdate(normalizedBike, currentUserId: user.uid);

    try {
      if (normalizedBike.active) {
        await _updateAndActivateBike(uid: user.uid, bike: normalizedBike);
        return;
      }

      await bikeDocument(
        uid: user.uid,
        bikeId: normalizedBike.id,
      ).set(normalizedBike.toUpdateMap(), SetOptions(merge: true));
    } catch (error, stackTrace) {
      debugPrint('UPDATE FIRESTORE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'update-bike-failed',
        fallbackMessage: 'Cyklen kunne ikke opdateres.',
      );
    }
  }

  Future<void> updateBikeFields({
    required String bikeId,
    String? name,
    String? brand,
    String? model,
    FirestoreBikeType? type,
    String? color,
    String? frameSize,
    String? wheelSize,
    String? serialNumber,
    String? imageUrl,
    String? glbModelUrl,
    String? firmwareVersion,
    bool? digitalTwinEnabled,
    String? notes,
  }) async {
    final user = _requireFirebaseUser();

    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (name != null) {
      final normalizedName = name.trim();

      if (normalizedName.isEmpty) {
        throw const FirestoreBikeServiceException(
          code: 'missing-bike-name',
          message: 'Indtast et navn til cyklen.',
        );
      }

      updates['name'] = normalizedName;
    }

    if (brand != null) {
      updates['brand'] = brand.trim();
    }

    if (model != null) {
      updates['model'] = model.trim();
    }

    if (type != null) {
      updates['type'] = type.value;
    }

    if (color != null) {
      updates['color'] = color.trim();
    }

    if (frameSize != null) {
      updates['frameSize'] = frameSize.trim();
    }

    if (wheelSize != null) {
      updates['wheelSize'] = wheelSize.trim();
    }

    if (serialNumber != null) {
      updates['serialNumber'] = serialNumber.trim();
    }

    if (imageUrl != null) {
      updates['imageUrl'] = imageUrl.trim();
    }

    if (glbModelUrl != null) {
      updates['glbModelUrl'] = glbModelUrl.trim();
    }

    if (firmwareVersion != null) {
      updates['firmwareVersion'] = firmwareVersion.trim();
    }

    if (digitalTwinEnabled != null) {
      updates['digitalTwinEnabled'] = digitalTwinEnabled;
    }

    if (notes != null) {
      updates['notes'] = notes.trim();
    }

    await _updateBikeDocument(
      uid: user.uid,
      bikeId: bikeId,
      updates: updates,
      fallbackCode: 'update-bike-fields-failed',
      fallbackMessage: 'Cykeloplysningerne kunne ikke opdateres.',
    );
  }

  Future<void> setActiveBike(String bikeId) async {
    final user = _requireFirebaseUser();
    final normalizedBikeId = bikeId.trim();

    if (normalizedBikeId.isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-bike-id',
        message: 'Cyklens ID mangler.',
      );
    }

    try {
      final targetReference = bikeDocument(
        uid: user.uid,
        bikeId: normalizedBikeId,
      );

      await _firestore.runTransaction((transaction) async {
        final targetSnapshot = await transaction.get(targetReference);

        if (!targetSnapshot.exists) {
          throw const FirestoreBikeServiceException(
            code: 'bike-not-found',
            message: 'Cyklen blev ikke fundet.',
          );
        }

        final activeSnapshot = await userBikesQuery(
          user.uid,
        ).where('active', isEqualTo: true).get();

        for (final document in activeSnapshot.docs) {
          if (document.id == normalizedBikeId) {
            continue;
          }

          transaction.set(document.reference, <String, dynamic>{
            'active': false,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        transaction.set(targetReference, <String, dynamic>{
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(
          _firestore.collection(usersCollectionName).doc(user.uid),
          <String, dynamic>{
            'activeBikeId': normalizedBikeId,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (error, stackTrace) {
      debugPrint('SET ACTIVE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'set-active-bike-failed',
        fallbackMessage: 'Den aktive cykel kunne ikke vælges.',
      );
    }
  }

  Future<void> clearActiveBike() async {
    final user = _requireFirebaseUser();

    try {
      final activeSnapshot = await userBikesQuery(
        user.uid,
      ).where('active', isEqualTo: true).get();

      final batch = _firestore.batch();

      for (final document in activeSnapshot.docs) {
        batch.set(document.reference, <String, dynamic>{
          'active': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      batch.set(
        _firestore.collection(usersCollectionName).doc(user.uid),
        <String, dynamic>{
          'activeBikeId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint('CLEAR ACTIVE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'clear-active-bike-failed',
        fallbackMessage: 'Den aktive cykel kunne ikke fjernes.',
      );
    }
  }

  Future<void> deleteBike(String bikeId) async {
    final user = _requireFirebaseUser();
    final reference = bikeDocument(uid: user.uid, bikeId: bikeId);

    try {
      final snapshot = await reference.get();

      if (!snapshot.exists) {
        return;
      }

      final bike = FirestoreBike.fromFirestore(snapshot);
      final batch = _firestore.batch();

      batch.delete(reference);

      if (bike.active) {
        batch.set(
          _firestore.collection(usersCollectionName).doc(user.uid),
          <String, dynamic>{
            'activeBikeId': null,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      await batch.commit();
    } catch (error, stackTrace) {
      debugPrint('DELETE FIRESTORE BIKE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'delete-bike-failed',
        fallbackMessage: 'Cyklen kunne ikke slettes.',
      );
    }
  }

  Future<void> updateImageUrl({
    required String bikeId,
    required String imageUrl,
  }) async {
    final user = _requireFirebaseUser();

    await _updateBikeDocument(
      uid: user.uid,
      bikeId: bikeId,
      updates: <String, dynamic>{
        'imageUrl': imageUrl.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-bike-image-failed',
      fallbackMessage: 'Cykelbilledet kunne ikke opdateres.',
    );
  }

  Future<void> updateGlbModelUrl({
    required String bikeId,
    required String glbModelUrl,
    bool enableDigitalTwin = true,
  }) async {
    final user = _requireFirebaseUser();

    await _updateBikeDocument(
      uid: user.uid,
      bikeId: bikeId,
      updates: <String, dynamic>{
        'glbModelUrl': glbModelUrl.trim(),
        'digitalTwinEnabled': enableDigitalTwin,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-glb-model-failed',
      fallbackMessage: '3D-modellen kunne ikke opdateres.',
    );
  }

  Future<void> updateFirmwareVersion({
    required String bikeId,
    required String firmwareVersion,
  }) async {
    final user = _requireFirebaseUser();

    await _updateBikeDocument(
      uid: user.uid,
      bikeId: bikeId,
      updates: <String, dynamic>{
        'firmwareVersion': firmwareVersion.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-firmware-failed',
      fallbackMessage: 'Firmwareversionen kunne ikke opdateres.',
    );
  }

  Future<void> addInstalledProduct({
    required String bikeId,
    required String productId,
  }) async {
    final user = _requireFirebaseUser();
    final normalizedProductId = productId.trim();

    if (normalizedProductId.isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-product-id',
        message: 'Produktets ID mangler.',
      );
    }

    await _updateBikeDocument(
      uid: user.uid,
      bikeId: bikeId,
      updates: <String, dynamic>{
        'installedProductIds': FieldValue.arrayUnion(<String>[
          normalizedProductId,
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'add-product-failed',
      fallbackMessage: 'Produktet kunne ikke tilføjes til cyklen.',
    );
  }

  Future<void> removeInstalledProduct({
    required String bikeId,
    required String productId,
  }) async {
    final user = _requireFirebaseUser();
    final normalizedProductId = productId.trim();

    if (normalizedProductId.isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-product-id',
        message: 'Produktets ID mangler.',
      );
    }

    await _updateBikeDocument(
      uid: user.uid,
      bikeId: bikeId,
      updates: <String, dynamic>{
        'installedProductIds': FieldValue.arrayRemove(<String>[
          normalizedProductId,
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'remove-product-failed',
      fallbackMessage: 'Produktet kunne ikke fjernes fra cyklen.',
    );
  }

  Future<bool> bikeExists(String bikeId) async {
    final user = currentFirebaseUser;

    if (user == null) {
      return false;
    }

    try {
      final document = await bikeDocument(uid: user.uid, bikeId: bikeId).get();

      return document.exists;
    } catch (error, stackTrace) {
      debugPrint('CHECK BIKE EXISTS ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'check-bike-failed',
        fallbackMessage: 'Cyklen kunne ikke kontrolleres.',
      );
    }
  }

  Future<void> _createAndActivateBike({
    required String uid,
    required DocumentReference<Map<String, dynamic>> reference,
    required FirestoreBike bike,
  }) async {
    final existingBikes = await userBikesQuery(uid).get();
    final batch = _firestore.batch();

    for (final document in existingBikes.docs) {
      batch.set(document.reference, <String, dynamic>{
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    batch.set(reference, bike.copyWith(active: true).toCreateMap());

    batch.set(
      _firestore.collection(usersCollectionName).doc(uid),
      <String, dynamic>{
        'activeBikeId': reference.id,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> _updateAndActivateBike({
    required String uid,
    required FirestoreBike bike,
  }) async {
    final existingBikes = await userBikesQuery(uid).get();
    final batch = _firestore.batch();

    for (final document in existingBikes.docs) {
      if (document.id == bike.id) {
        continue;
      }

      batch.set(document.reference, <String, dynamic>{
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    batch.set(
      bikeDocument(uid: uid, bikeId: bike.id),
      bike.copyWith(active: true).toUpdateMap(),
      SetOptions(merge: true),
    );

    batch.set(
      _firestore.collection(usersCollectionName).doc(uid),
      <String, dynamic>{
        'activeBikeId': bike.id,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> _updateBikeDocument({
    required String uid,
    required String bikeId,
    required Map<String, dynamic> updates,
    required String fallbackCode,
    required String fallbackMessage,
  }) async {
    try {
      await bikeDocument(
        uid: uid,
        bikeId: bikeId,
      ).set(updates, SetOptions(merge: true));
    } catch (error, stackTrace) {
      debugPrint('UPDATE BIKE DOCUMENT ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: fallbackCode,
        fallbackMessage: fallbackMessage,
      );
    }
  }

  void _validateBikeForCreate(
    FirestoreBike bike, {
    required String currentUserId,
  }) {
    if (bike.ownerId.isNotEmpty && bike.ownerId != currentUserId) {
      throw const FirestoreBikeServiceException(
        code: 'invalid-owner',
        message: 'Cyklen tilhører en anden bruger.',
      );
    }

    if (bike.name.trim().isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-bike-name',
        message: 'Indtast et navn til cyklen.',
      );
    }
  }

  void _validateBikeForUpdate(
    FirestoreBike bike, {
    required String currentUserId,
  }) {
    if (bike.id.trim().isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-bike-id',
        message: 'Cyklens ID mangler.',
      );
    }

    if (bike.ownerId != currentUserId) {
      throw const FirestoreBikeServiceException(
        code: 'invalid-owner',
        message: 'Cyklen tilhører en anden bruger.',
      );
    }

    if (bike.name.trim().isEmpty) {
      throw const FirestoreBikeServiceException(
        code: 'missing-bike-name',
        message: 'Indtast et navn til cyklen.',
      );
    }
  }

  List<FirestoreBike> _sortBikes(List<FirestoreBike> bikes) {
    final sorted = List<FirestoreBike>.from(bikes);

    sorted.sort((first, second) {
      if (first.active != second.active) {
        return first.active ? -1 : 1;
      }

      final firstCreatedAt = first.createdAt;
      final secondCreatedAt = second.createdAt;

      if (firstCreatedAt != null && secondCreatedAt != null) {
        final dateComparison = firstCreatedAt.compareTo(secondCreatedAt);

        if (dateComparison != 0) {
          return dateComparison;
        }
      }

      return first.displayName.toLowerCase().compareTo(
        second.displayName.toLowerCase(),
      );
    });

    return List<FirestoreBike>.unmodifiable(sorted);
  }

  User _requireFirebaseUser() {
    final user = currentFirebaseUser;

    if (user == null) {
      throw const FirestoreBikeServiceException(
        code: 'not-signed-in',
        message: 'Du skal være logget ind først.',
      );
    }

    return user;
  }

  FirestoreBikeServiceException _mapException(
    Object error, {
    required String fallbackCode,
    required String fallbackMessage,
  }) {
    if (error is FirestoreBikeServiceException) {
      return error;
    }

    if (error is FirestoreUserServiceException) {
      return FirestoreBikeServiceException(
        code: error.code,
        message: error.message,
        originalError: error,
      );
    }

    if (error is FirebaseException) {
      return FirestoreBikeServiceException.fromFirebase(
        error,
        fallbackCode: fallbackCode,
        fallbackMessage: fallbackMessage,
      );
    }

    return FirestoreBikeServiceException(
      code: fallbackCode,
      message: fallbackMessage,
      originalError: error,
    );
  }
}

class FirestoreBikeServiceException implements Exception {
  final String code;
  final String message;
  final Object? originalError;

  const FirestoreBikeServiceException({
    required this.code,
    required this.message,
    this.originalError,
  });

  factory FirestoreBikeServiceException.fromFirebase(
    FirebaseException error, {
    required String fallbackCode,
    required String fallbackMessage,
  }) {
    return FirestoreBikeServiceException(
      code: error.code.isEmpty ? fallbackCode : error.code,
      message: _messageForFirebaseCode(
        error.code,
        fallbackMessage: fallbackMessage,
      ),
      originalError: error,
    );
  }

  static String _messageForFirebaseCode(
    String code, {
    required String fallbackMessage,
  }) {
    switch (code) {
      case 'permission-denied':
        return 'Du har ikke adgang til disse cykeldata.';
      case 'unauthenticated':
        return 'Du skal være logget ind først.';
      case 'not-found':
        return 'Cyklen blev ikke fundet.';
      case 'already-exists':
        return 'Cyklen findes allerede.';
      case 'unavailable':
        return 'Firestore er midlertidigt utilgængelig. Prøv igen.';
      case 'deadline-exceeded':
        return 'Forbindelsen tog for lang tid. Prøv igen.';
      case 'cancelled':
        return 'Handlingen blev annulleret.';
      case 'resource-exhausted':
        return 'Tjenesten er midlertidigt overbelastet.';
      case 'failed-precondition':
        return 'Firestore er ikke korrekt konfigureret.';
      case 'aborted':
        return 'Handlingen blev afbrudt. Prøv igen.';
      case 'data-loss':
        return 'Der opstod en fejl under behandling af cykeldata.';
      default:
        return fallbackMessage;
    }
  }

  @override
  String toString() {
    return 'FirestoreBikeServiceException('
        'code: $code, '
        'message: $message'
        ')';
  }
}
