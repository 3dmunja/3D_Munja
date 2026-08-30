import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/social_rider_profile.dart';

class SocialRiderService {
  SocialRiderService._();

  static final SocialRiderService instance = SocialRiderService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _usersCollection =>
      _db.collection('socialRiders');

  CollectionReference<Map<String, dynamic>> get _emailLookupCollection =>
      _db.collection('emailLookup');

  User? get currentFirebaseUser => _auth.currentUser;

  String? get currentUid => _auth.currentUser?.uid;

  Future<SocialRiderProfile?> getCurrentProfile() async {
    final uid = currentUid;

    if (uid == null) {
      return null;
    }

    final snapshot = await _usersCollection.doc(uid).get();

    if (!snapshot.exists) {
      return null;
    }

    return SocialRiderProfile.fromFirestore(snapshot);
  }

  Future<SocialRiderProfile?> getProfileByUid(
    String uid,
  ) async {
    final trimmedUid = uid.trim();

    if (trimmedUid.isEmpty) {
      return null;
    }

    final snapshot = await _usersCollection.doc(trimmedUid).get();

    if (!snapshot.exists) {
      return null;
    }

    return SocialRiderProfile.fromFirestore(snapshot);
  }

  Future<bool> isUsernameAvailable(
    String username, {
    String? ignoreUid,
  }) async {
    final normalized = _normalizeUsername(username);

    if (normalized.isEmpty) {
      return false;
    }

    final query = await _usersCollection
        .where(
          'usernameLowercase',
          isEqualTo: normalized,
        )
        .limit(2)
        .get();

    if (query.docs.isEmpty) {
      return true;
    }

    if (ignoreUid == null) {
      return false;
    }

    return query.docs.every(
      (doc) => doc.id == ignoreUid,
    );
  }

  Future<SocialRiderProfile?> findByUsername(
    String username,
  ) async {
    final normalized = _normalizeUsername(username);

    if (normalized.isEmpty) {
      return null;
    }

    final query = await _usersCollection
        .where(
          'usernameLowercase',
          isEqualTo: normalized,
        )
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return SocialRiderProfile.fromFirestore(
      query.docs.first,
    );
  }

  /// User-friendly rider lookup.
  ///
  /// Supported:
  /// - @username / username
  /// - E-mail address
  /// - Full Rider ID: MUNJA-7KQ2-X9PD
  /// - Short Friend Code: 7KQ2-X9PD
  Future<SocialRiderProfile?> findRider(
    String value,
  ) async {
    final query = value.trim();

    if (query.isEmpty) {
      return null;
    }

    if (_looksLikeEmail(query)) {
      return findByEmail(query);
    }

    final normalizedCode = _normalizeFriendCode(query);

    if (_looksLikeFriendCode(query)) {
      return findByRiderId(normalizedCode);
    }

    return findByUsername(query);
  }

  /// Looks up a rider by the SHA-256 hash of the normalized e-mail address.
  ///
  /// The plain e-mail address is never stored in socialRiders or emailLookup.
  /// The lookup document only stores the owner's Firebase UID.
  Future<SocialRiderProfile?> findByEmail(
    String email,
  ) async {
    final normalizedEmail = _normalizeEmail(email);

    if (!_looksLikeEmail(normalizedEmail)) {
      return null;
    }

    final emailHash = _hashEmail(normalizedEmail);

    final snapshot =
        await _emailLookupCollection.doc(emailHash).get();

    if (!snapshot.exists) {
      return null;
    }

    final data = snapshot.data() ?? <String, dynamic>{};
    final uid = data['uid'];

    if (uid is! String || uid.trim().isEmpty) {
      return null;
    }

    return getProfileByUid(uid.trim());
  }

  String _normalizeFriendCode(String value) {
    var normalized = value.trim().toUpperCase();

    if (!normalized.startsWith('MUNJA-')) {
      normalized = 'MUNJA-$normalized';
    }

    return normalized;
  }

  bool _looksLikeFriendCode(String value) {
    final normalized = value.trim().toUpperCase();

    if (normalized.startsWith('MUNJA-')) {
      return true;
    }

    return RegExp(r'^[A-Z2-9]{4}-[A-Z2-9]{4}$')
        .hasMatch(normalized);
  }

  Future<SocialRiderProfile?> findByRiderId(
    String riderId,
  ) async {
    final normalized = riderId.trim().toUpperCase();

    if (normalized.isEmpty) {
      return null;
    }

    final query = await _usersCollection
        .where(
          'riderId',
          isEqualTo: normalized,
        )
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    return SocialRiderProfile.fromFirestore(
      query.docs.first,
    );
  }

  Future<SocialRiderProfile> ensureCurrentProfile({
    required String displayName,
    required int level,
    required int totalXp,
    String? city,
    String? photoUrl,
    String? preferredUsername,
  }) async {
    final user = currentFirebaseUser;

    if (user == null) {
      throw StateError(
        'A signed-in Firebase user is required to create a social rider profile.',
      );
    }

    final uid = user.uid;
    final existing = await getProfileByUid(uid);

    if (existing != null) {
      final updated = existing.copyWith(
        displayName: _safeDisplayName(
          displayName,
          fallback: existing.displayName,
        ),
        city: city,
        photoUrl: photoUrl,
        level: level,
        totalXp: totalXp,
      );

      await _usersCollection.doc(uid).set(
            updated.toFirestore(),
            SetOptions(merge: true),
          );

      await _ensureCurrentEmailLookup();

      return updated;
    }

    final candidate = preferredUsername == null ||
            preferredUsername.trim().isEmpty
        ? SocialRiderProfile.createUsernameCandidate(
            displayName,
          )
        : preferredUsername;

    final username = await _createAvailableUsername(
      candidate,
    );

    final riderId = await _createUniqueRiderId();

    final profile = SocialRiderProfile(
      uid: uid,
      username: username,
      riderId: riderId,
      displayName: _safeDisplayName(
        displayName,
        fallback: 'Munja Rider',
      ),
      photoUrl: _nullableTrimmed(photoUrl),
      city: _nullableTrimmed(city),
      level: level.clamp(1, 99),
      totalXp: totalXp < 0 ? 0 : totalXp,
    );

    await _usersCollection.doc(uid).set(
          profile.toFirestore(),
          SetOptions(merge: true),
        );

    await _ensureCurrentEmailLookup();

    return profile;
  }

  Future<SocialRiderProfile> updateCurrentProfile({
    String? displayName,
    String? city,
    String? photoUrl,
    int? level,
    int? totalXp,
  }) async {
    final current = await getCurrentProfile();

    if (current == null) {
      throw StateError(
        'No social rider profile exists for the current user.',
      );
    }

    final updated = current.copyWith(
      displayName: displayName == null
          ? current.displayName
          : _safeDisplayName(
              displayName,
              fallback: current.displayName,
            ),
      city: city,
      photoUrl: photoUrl,
      level: level?.clamp(1, 99),
      totalXp: totalXp == null
          ? current.totalXp
          : (totalXp < 0 ? 0 : totalXp),
    );

    await _usersCollection.doc(current.uid).set(
          updated.toFirestore(),
          SetOptions(merge: true),
        );

    return updated;
  }

  Future<SocialRiderProfile> updateUsername(
    String username,
  ) async {
    final current = await getCurrentProfile();

    if (current == null) {
      throw StateError(
        'No social rider profile exists for the current user.',
      );
    }

    final normalized = _normalizeUsername(username);

    if (normalized.length < 3) {
      throw ArgumentError(
        'Username must contain at least 3 characters.',
      );
    }

    final available = await isUsernameAvailable(
      normalized,
      ignoreUid: current.uid,
    );

    if (!available) {
      throw StateError(
        'That Munja username is already in use.',
      );
    }

    final updated = current.copyWith(
      username: normalized,
    );

    await _usersCollection.doc(current.uid).set(
          updated.toFirestore(),
          SetOptions(merge: true),
        );

    return updated;
  }

  Future<void> _ensureCurrentEmailLookup() async {
    final user = currentFirebaseUser;

    if (user == null) {
      return;
    }

    final rawEmail = user.email;
    final normalizedEmail = _normalizeEmail(rawEmail ?? '');

    if (!_looksLikeEmail(normalizedEmail)) {
      return;
    }

    final hash = _hashEmail(normalizedEmail);
    final ref = _emailLookupCollection.doc(hash);

    await ref.set(
      <String, dynamic>{
        'uid': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  String _normalizeEmail(String value) {
    return value.trim().toLowerCase();
  }

  bool _looksLikeEmail(String value) {
    final normalized = _normalizeEmail(value);

    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(normalized);
  }

  String _hashEmail(String normalizedEmail) {
    return sha256
        .convert(
          utf8.encode(
            _normalizeEmail(normalizedEmail),
          ),
        )
        .toString();
  }

  Future<String> _createAvailableUsername(
    String baseUsername,
  ) async {
    var base = _normalizeUsername(baseUsername);

    if (base.length < 3) {
      base = 'munja_rider';
    }

    if (await isUsernameAvailable(base)) {
      return base;
    }

    for (var attempt = 0; attempt < 50; attempt++) {
      final suffix = 10 + Random.secure().nextInt(989);
      final candidate = '${base}_$suffix';

      if (await isUsernameAvailable(candidate)) {
        return candidate;
      }
    }

    final timestamp = DateTime.now()
        .millisecondsSinceEpoch
        .toString()
        .substring(7);

    return '${base}_$timestamp';
  }

  Future<String> _createUniqueRiderId() async {
    for (var attempt = 0; attempt < 50; attempt++) {
      final candidate = _generateRiderId();

      final query = await _usersCollection
          .where(
            'riderId',
            isEqualTo: candidate,
          )
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return candidate;
      }
    }

    return 'MUNJA-${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generateRiderId() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    final code = List<String>.generate(
      8,
      (_) => chars[random.nextInt(chars.length)],
    ).join();

    return 'MUNJA-${code.substring(0, 4)}-${code.substring(4)}';
  }

  String _normalizeUsername(
    String username,
  ) {
    return username
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^@+'), '')
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _safeDisplayName(
    String value, {
    required String fallback,
  }) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return fallback;
    }

    return trimmed;
  }

  String? _nullableTrimmed(
    String? value,
  ) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }
}
