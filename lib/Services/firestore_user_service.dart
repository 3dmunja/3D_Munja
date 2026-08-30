import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/localization/app_text.dart';
import '../models/firestore_user.dart';
import 'auth_service.dart';

class FirestoreUserService {
  FirestoreUserService._();

  static final FirestoreUserService instance = FirestoreUserService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  static const String usersCollectionName = 'users';

  CollectionReference<Map<String, dynamic>> get _usersCollection {
    return _firestore.collection(usersCollectionName);
  }

  User? get currentFirebaseUser {
    return _firebaseAuth.currentUser;
  }

  DocumentReference<Map<String, dynamic>> userDocument(String uid) {
    final normalizedUid = uid.trim();

    if (normalizedUid.isEmpty) {
      throw const FirestoreUserServiceException(
        code: 'missing-uid',
        message: 'Brugerens ID mangler.',
      );
    }

    return _usersCollection.doc(normalizedUid);
  }

  DocumentReference<Map<String, dynamic>> currentUserDocument() {
    final user = _requireFirebaseUser();
    return userDocument(user.uid);
  }

  Stream<FirestoreUser?> watchCurrentUser() {
    final user = currentFirebaseUser;

    if (user == null) {
      return Stream<FirestoreUser?>.value(null);
    }

    return watchUser(user.uid);
  }

  Stream<FirestoreUser?> watchUser(String uid) {
    return userDocument(uid)
        .snapshots()
        .map((document) {
          if (!document.exists) {
            return null;
          }

          return FirestoreUser.fromFirestore(document);
        })
        .handleError((Object error, StackTrace stackTrace) {
          debugPrint('WATCH FIRESTORE USER ERROR: $error');
          debugPrintStack(stackTrace: stackTrace);

          throw _mapException(
            error,
            fallbackCode: 'watch-user-failed',
            fallbackMessage: 'Brugerprofilen kunne ikke overvåges.',
          );
        });
  }

  Future<FirestoreUser?> getCurrentUser() async {
    final user = currentFirebaseUser;

    if (user == null) {
      return null;
    }

    return getUser(user.uid);
  }

  Future<FirestoreUser?> getUser(String uid) async {
    try {
      final document = await userDocument(uid).get();

      if (!document.exists) {
        return null;
      }

      return FirestoreUser.fromFirestore(document);
    } catch (error, stackTrace) {
      debugPrint('GET FIRESTORE USER ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'get-user-failed',
        fallbackMessage: 'Brugerprofilen kunne ikke hentes.',
      );
    }
  }

  Future<FirestoreUser> ensureCurrentUserExists({
    bool updateLastLogin = true,
  }) async {
    final firebaseUser = _requireFirebaseUser();

    return ensureUserExists(
      firebaseUser: firebaseUser,
      updateLastLogin: updateLastLogin,
    );
  }

  Future<FirestoreUser> ensureUserExists({
    required User firebaseUser,
    bool updateLastLogin = true,
  }) async {
    final reference = userDocument(firebaseUser.uid);
    final platform = _platformName();
    final language = _normalizedLanguage(AppText.currentLocale.languageCode);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(reference);

        if (!snapshot.exists) {
          transaction.set(reference, <String, dynamic>{
            'uid': firebaseUser.uid,
            'displayName': _safeString(firebaseUser.displayName),
            'email': _safeString(firebaseUser.email),
            'photoUrl': _safeString(firebaseUser.photoURL),
            'language': language,
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
            'activeBikeId': null,
            'subscription': 'free',
            'totalXp': 0,
            'role': 'user',
            'platform': platform,
            'emailVerified': firebaseUser.emailVerified,
            'authProvider': _primaryProvider(firebaseUser),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          return;
        }

        final currentData = snapshot.data() ?? const <String, dynamic>{};

        final updates = <String, dynamic>{
          'uid': firebaseUser.uid,
          'email': _safeString(firebaseUser.email),
          'emailVerified': firebaseUser.emailVerified,
          'platform': platform,
          'authProvider': _primaryProvider(firebaseUser),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        final firebaseDisplayName = _safeString(firebaseUser.displayName);
        final firestoreDisplayName = _safeString(currentData['displayName']);

        if (firebaseDisplayName.isNotEmpty && firestoreDisplayName.isEmpty) {
          updates['displayName'] = firebaseDisplayName;
        }

        final firebasePhotoUrl = _safeString(firebaseUser.photoURL);
        final firestorePhotoUrl = _safeString(
          currentData['photoUrl'] ?? currentData['photoURL'],
        );

        if (firebasePhotoUrl.isNotEmpty && firestorePhotoUrl.isEmpty) {
          updates['photoUrl'] = firebasePhotoUrl;
        }

        if (!currentData.containsKey('language')) {
          updates['language'] = language;
        }

        if (!currentData.containsKey('subscription')) {
          updates['subscription'] = 'free';
        }

        if (!currentData.containsKey('totalXp')) {
          updates['totalXp'] = 0;
        }

        if (!currentData.containsKey('role')) {
          updates['role'] = 'user';
        }

        if (!currentData.containsKey('activeBikeId')) {
          updates['activeBikeId'] = null;
        }

        if (!currentData.containsKey('createdAt')) {
          updates['createdAt'] = FieldValue.serverTimestamp();
        }

        if (updateLastLogin) {
          updates['lastLoginAt'] = FieldValue.serverTimestamp();
        }

        transaction.set(reference, updates, SetOptions(merge: true));
      });

      final createdUser = await getUser(firebaseUser.uid);

      if (createdUser == null) {
        throw const FirestoreUserServiceException(
          code: 'user-document-missing',
          message: 'Brugerprofilen blev ikke fundet efter synkronisering.',
        );
      }

      return createdUser;
    } catch (error, stackTrace) {
      debugPrint('ENSURE FIRESTORE USER ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'ensure-user-failed',
        fallbackMessage:
            'Brugerprofilen kunne ikke oprettes eller synkroniseres.',
      );
    }
  }

  Future<void> updateCurrentUserProfile({
    String? displayName,
    String? email,
    String? photoUrl,
    String? language,
  }) async {
    final user = _requireFirebaseUser();

    await updateUserProfile(
      uid: user.uid,
      displayName: displayName,
      email: email,
      photoUrl: photoUrl,
      language: language,
    );
  }

  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? email,
    String? photoUrl,
    String? language,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (displayName != null) {
      final normalizedDisplayName = displayName.trim();

      if (normalizedDisplayName.isEmpty) {
        throw const FirestoreUserServiceException(
          code: 'missing-display-name',
          message: 'Indtast et navn.',
        );
      }

      updates['displayName'] = normalizedDisplayName;
    }

    if (email != null) {
      updates['email'] = email.trim().toLowerCase();
    }

    if (photoUrl != null) {
      updates['photoUrl'] = photoUrl.trim();
    }

    if (language != null) {
      updates['language'] = _normalizedLanguage(language);
    }

    await _updateDocument(
      uid: uid,
      updates: updates,
      fallbackCode: 'update-profile-failed',
      fallbackMessage: 'Brugerprofilen kunne ikke opdateres.',
    );
  }

  Future<void> updateDisplayName(String displayName) async {
    final user = _requireFirebaseUser();
    final normalizedName = displayName.trim();

    if (normalizedName.isEmpty) {
      throw const FirestoreUserServiceException(
        code: 'missing-display-name',
        message: 'Indtast et navn.',
      );
    }

    try {
      await AuthService.instance.updateDisplayName(normalizedName);

      await _updateDocument(
        uid: user.uid,
        updates: <String, dynamic>{
          'displayName': normalizedName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        fallbackCode: 'update-display-name-failed',
        fallbackMessage: 'Navnet kunne ikke opdateres.',
      );
    } catch (error, stackTrace) {
      debugPrint('UPDATE DISPLAY NAME SYNC ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'update-display-name-failed',
        fallbackMessage: 'Navnet kunne ikke opdateres.',
      );
    }
  }

  Future<void> updateLanguage(String languageCode) async {
    final user = _requireFirebaseUser();

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'language': _normalizedLanguage(languageCode),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-language-failed',
      fallbackMessage: 'Sproget kunne ikke opdateres.',
    );
  }

  /// Sets account XP to an exact non-negative value.
  ///
  /// Prefer [syncTotalXpAtLeast] for migration/reconciliation and [addXp]
  /// for future XP rewards.
  Future<void> setTotalXp(int totalXp) async {
    final user = _requireFirebaseUser();
    final safeXp = totalXp < 0 ? 0 : totalXp;

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'totalXp': safeXp,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-xp-failed',
      fallbackMessage: 'XP kunne ikke opdateres.',
    );
  }

  /// Non-destructive migration/reconciliation.
  ///
  /// Firestore is only increased when [candidateTotalXp] is greater than the
  /// value already stored. A device with missing/old local rides can therefore
  /// never reduce account XP.
  Future<int> syncTotalXpAtLeast(int candidateTotalXp) async {
    final user = _requireFirebaseUser();
    final reference = userDocument(user.uid);
    final safeCandidate =
        candidateTotalXp < 0 ? 0 : candidateTotalXp;

    try {
      return await _firestore.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(reference);

        if (!snapshot.exists) {
          throw const FirestoreUserServiceException(
            code: 'user-document-missing',
            message: 'Brugerprofilen blev ikke fundet.',
          );
        }

        final data = snapshot.data() ?? const <String, dynamic>{};
        final currentXp = _safeInt(data['totalXp']);

        final resolvedXp =
            safeCandidate > currentXp ? safeCandidate : currentXp;

        if (!data.containsKey('totalXp') || resolvedXp != currentXp) {
          transaction.set(
            reference,
            <String, dynamic>{
              'totalXp': resolvedXp,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        return resolvedXp;
      });
    } catch (error, stackTrace) {
      debugPrint('SYNC FIRESTORE XP ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'sync-xp-failed',
        fallbackMessage: 'XP kunne ikke synkroniseres.',
      );
    }
  }

  /// Atomically adds XP for a completed reward/event.
  Future<int> addXp(int amount) async {
    if (amount <= 0) {
      final current = await getCurrentUser();
      return current?.safeTotalXp ?? 0;
    }

    final user = _requireFirebaseUser();
    final reference = userDocument(user.uid);

    try {
      return await _firestore.runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(reference);

        if (!snapshot.exists) {
          throw const FirestoreUserServiceException(
            code: 'user-document-missing',
            message: 'Brugerprofilen blev ikke fundet.',
          );
        }

        final data = snapshot.data() ?? const <String, dynamic>{};
        final currentXp = _safeInt(data['totalXp']);
        final nextXp = currentXp + amount;

        transaction.set(
          reference,
          <String, dynamic>{
            'totalXp': nextXp,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        return nextXp;
      });
    } catch (error, stackTrace) {
      debugPrint('ADD FIRESTORE XP ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'add-xp-failed',
        fallbackMessage: 'XP-belønningen kunne ikke gemmes.',
      );
    }
  }

  Future<void> updatePhotoUrl(String? photoUrl) async {
    final user = _requireFirebaseUser();

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'photoUrl': photoUrl?.trim() ?? '',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-photo-failed',
      fallbackMessage: 'Profilbilledet kunne ikke opdateres.',
    );
  }

  Future<void> updateActiveBike(String? bikeId) async {
    final user = _requireFirebaseUser();
    final normalizedBikeId = bikeId?.trim();

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'activeBikeId': normalizedBikeId == null || normalizedBikeId.isEmpty
            ? null
            : normalizedBikeId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-active-bike-failed',
      fallbackMessage: 'Den aktive cykel kunne ikke opdateres.',
    );
  }

  Future<void> clearActiveBike() async {
    await updateActiveBike(null);
  }

  Future<void> updateSubscription(String subscription) async {
    final user = _requireFirebaseUser();
    final normalizedSubscription = subscription.trim().toLowerCase();

    if (normalizedSubscription.isEmpty) {
      throw const FirestoreUserServiceException(
        code: 'missing-subscription',
        message: 'Abonnementet mangler.',
      );
    }

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'subscription': normalizedSubscription,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-subscription-failed',
      fallbackMessage: 'Abonnementet kunne ikke opdateres.',
    );
  }

  Future<void> updateRole(String role) async {
    final user = _requireFirebaseUser();
    final normalizedRole = role.trim().toLowerCase();

    if (normalizedRole.isEmpty) {
      throw const FirestoreUserServiceException(
        code: 'missing-role',
        message: 'Brugerrollen mangler.',
      );
    }

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'role': normalizedRole,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-role-failed',
      fallbackMessage: 'Brugerrollen kunne ikke opdateres.',
    );
  }

  Future<void> updateLastLogin() async {
    final user = _requireFirebaseUser();

    await _updateDocument(
      uid: user.uid,
      updates: <String, dynamic>{
        'lastLoginAt': FieldValue.serverTimestamp(),
        'platform': _platformName(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      fallbackCode: 'update-last-login-failed',
      fallbackMessage: 'Seneste login kunne ikke opdateres.',
    );
  }

  Future<bool> currentUserDocumentExists() async {
    final user = currentFirebaseUser;

    if (user == null) return false;

    try {
      final document = await userDocument(user.uid).get();
      return document.exists;
    } catch (error, stackTrace) {
      debugPrint('CHECK USER DOCUMENT ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'check-user-failed',
        fallbackMessage: 'Brugerprofilen kunne ikke kontrolleres.',
      );
    }
  }

  Future<void> deleteCurrentUserDocument() async {
    final user = _requireFirebaseUser();

    try {
      await userDocument(user.uid).delete();
    } catch (error, stackTrace) {
      debugPrint('DELETE USER DOCUMENT ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: 'delete-user-document-failed',
        fallbackMessage: 'Brugerdata kunne ikke slettes.',
      );
    }
  }

  Future<void> _updateDocument({
    required String uid,
    required Map<String, dynamic> updates,
    required String fallbackCode,
    required String fallbackMessage,
  }) async {
    try {
      await userDocument(uid).set(updates, SetOptions(merge: true));
    } catch (error, stackTrace) {
      debugPrint('UPDATE FIRESTORE USER DOCUMENT ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      throw _mapException(
        error,
        fallbackCode: fallbackCode,
        fallbackMessage: fallbackMessage,
      );
    }
  }

  User _requireFirebaseUser() {
    final user = currentFirebaseUser;

    if (user == null) {
      throw const FirestoreUserServiceException(
        code: 'not-signed-in',
        message: 'Du skal være logget ind først.',
      );
    }

    return user;
  }

  String _primaryProvider(User user) {
    if (user.providerData.isEmpty) {
      return 'unknown';
    }

    final providers = user.providerData
        .map((provider) => provider.providerId.trim())
        .where((providerId) => providerId.isNotEmpty)
        .toList();

    if (providers.contains(GoogleAuthProvider.PROVIDER_ID)) {
      return 'google';
    }

    if (providers.contains(EmailAuthProvider.PROVIDER_ID)) {
      return 'password';
    }

    return providers.firstOrNull ?? 'unknown';
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _normalizedLanguage(String languageCode) {
    final normalized = languageCode.trim().toLowerCase();

    switch (normalized) {
      case 'da':
      case 'en':
      case 'bs':
        return normalized;
      default:
        return 'da';
    }
  }

  int _safeInt(dynamic value) {
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

  String _safeString(dynamic value) {
    if (value is String) {
      return value.trim();
    }

    return '';
  }

  FirestoreUserServiceException _mapException(
    Object error, {
    required String fallbackCode,
    required String fallbackMessage,
  }) {
    if (error is FirestoreUserServiceException) {
      return error;
    }

    if (error is FirebaseException) {
      return FirestoreUserServiceException.fromFirebase(
        error,
        fallbackCode: fallbackCode,
        fallbackMessage: fallbackMessage,
      );
    }

    if (error is AuthServiceException) {
      return FirestoreUserServiceException(
        code: error.code,
        message: error.message,
        originalError: error,
      );
    }

    return FirestoreUserServiceException(
      code: fallbackCode,
      message: fallbackMessage,
      originalError: error,
    );
  }
}

class FirestoreUserServiceException implements Exception {
  final String code;
  final String message;
  final Object? originalError;

  const FirestoreUserServiceException({
    required this.code,
    required this.message,
    this.originalError,
  });

  factory FirestoreUserServiceException.fromFirebase(
    FirebaseException error, {
    required String fallbackCode,
    required String fallbackMessage,
  }) {
    return FirestoreUserServiceException(
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
        return 'Du har ikke adgang til disse brugerdata.';
      case 'unauthenticated':
        return 'Du skal være logget ind først.';
      case 'not-found':
        return 'Brugerprofilen blev ikke fundet.';
      case 'already-exists':
        return 'Brugerprofilen findes allerede.';
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
        return 'Der opstod en fejl under behandling af brugerdata.';
      default:
        return fallbackMessage;
    }
  }

  @override
  String toString() {
    return 'FirestoreUserServiceException('
        'code: $code, '
        'message: $message'
        ')';
  }
}

extension _FirstOrNullExtension<T> on List<T> {
  T? get firstOrNull {
    if (isEmpty) return null;
    return first;
  }
}
