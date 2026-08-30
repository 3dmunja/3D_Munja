import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreUser {
  final String uid;
  final String displayName;
  final String email;
  final String photoUrl;
  final String language;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final String? activeBikeId;
  final String subscription;
  final String role;
  final String platform;

  // Munja ownership / monetization.
  // Ownership belongs to the user, while the active customization belongs
  // to the individual bike / Digital Twin.
  final int crystals;

  // Persistent rider progression. XP belongs to the account, not the device.
  final int totalXp;

  final List<String> ownedSkinIds;
  final List<String> unlockedRewardSkinIds;

  const FirestoreUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    required this.language,
    required this.createdAt,
    required this.lastLoginAt,
    required this.activeBikeId,
    required this.subscription,
    required this.role,
    required this.platform,
    this.crystals = 0,
    this.totalXp = 0,
    this.ownedSkinIds = const <String>['standard'],
    this.unlockedRewardSkinIds = const <String>[],
  });

  factory FirestoreUser.empty({required String uid}) {
    final now = DateTime.now();

    return FirestoreUser(
      uid: uid,
      displayName: '',
      email: '',
      photoUrl: '',
      language: 'da',
      createdAt: now,
      lastLoginAt: now,
      activeBikeId: null,
      subscription: 'free',
      role: 'user',
      platform: 'unknown',
      crystals: 0,
      totalXp: 0,
      ownedSkinIds: const <String>['standard'],
      unlockedRewardSkinIds: const <String>[],
    );
  }

  factory FirestoreUser.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return FirestoreUser.fromMap(
      uid: document.id,
      data: document.data() ?? <String, dynamic>{},
    );
  }

  factory FirestoreUser.fromMap({
    required String uid,
    required Map<String, dynamic> data,
  }) {
    final now = DateTime.now();

    final ownedSkinIds = _normalizeSkinIds(
      _readStringList(
        data,
        const <String>['ownedSkinIds', 'ownedSkins'],
        fallback: const <String>['standard'],
      ),
      alwaysIncludeStandard: true,
    );

    final unlockedRewardSkinIds = _normalizeSkinIds(
      _readStringList(
        data,
        const <String>[
          'unlockedRewardSkinIds',
          'rewardSkinIds',
          'unlockedSkins',
        ],
      ),
    );

    return FirestoreUser(
      uid: uid,
      displayName: _readString(data, const ['displayName', 'name']),
      email: _readString(data, const ['email']),
      photoUrl: _readString(data, const ['photoUrl', 'photoURL']),
      language: _readString(
        data,
        const ['language', 'locale'],
        fallback: 'da',
      ),
      createdAt: _readDateTime(
        data,
        const ['createdAt'],
        fallback: now,
      ),
      lastLoginAt: _readDateTime(
        data,
        const ['lastLoginAt', 'lastLogin'],
        fallback: now,
      ),
      activeBikeId: _readNullableString(
        data,
        const ['activeBikeId', 'activeBike'],
      ),
      subscription: _readString(
        data,
        const ['subscription', 'subscriptionPlan'],
        fallback: 'free',
      ),
      role: _readString(data, const ['role'], fallback: 'user'),
      platform: _readString(
        data,
        const ['platform'],
        fallback: 'unknown',
      ),
      crystals: _readInt(
        data,
        const ['crystals', 'crystalBalance', 'munjaCrystals'],
        fallback: 0,
        minimum: 0,
      ),
      totalXp: _readInt(
        data,
        const ['totalXp', 'xp', 'riderXp'],
        fallback: 0,
        minimum: 0,
      ),
      ownedSkinIds: ownedSkinIds,
      unlockedRewardSkinIds: unlockedRewardSkinIds,
    );
  }

  Map<String, dynamic> toFirestore({bool includeUid = false}) {
    return <String, dynamic>{
      if (includeUid) 'uid': uid,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'language': language,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'activeBikeId': activeBikeId,
      'subscription': subscription,
      'role': role,
      'platform': platform,
      'crystals': crystalBalance,
      'totalXp': safeTotalXp,
      'ownedSkinIds': _normalizeSkinIds(
        ownedSkinIds,
        alwaysIncludeStandard: true,
      ),
      'unlockedRewardSkinIds': _normalizeSkinIds(
        unlockedRewardSkinIds,
      ),
    };
  }

  Map<String, dynamic> toCreateFirestore() {
    return <String, dynamic>{
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'language': language,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
      'activeBikeId': activeBikeId,
      'subscription': subscription,
      'role': role,
      'platform': platform,
      'crystals': crystalBalance,
      'totalXp': safeTotalXp,
      'ownedSkinIds': _normalizeSkinIds(
        ownedSkinIds,
        alwaysIncludeStandard: true,
      ),
      'unlockedRewardSkinIds': _normalizeSkinIds(
        unlockedRewardSkinIds,
      ),
    };
  }

  Map<String, dynamic> toUpdateFirestore() {
    return <String, dynamic>{
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'language': language,
      'lastLoginAt': FieldValue.serverTimestamp(),
      'activeBikeId': activeBikeId,
      'subscription': subscription,
      'role': role,
      'platform': platform,
      'crystals': crystalBalance,
      'totalXp': safeTotalXp,
      'ownedSkinIds': _normalizeSkinIds(
        ownedSkinIds,
        alwaysIncludeStandard: true,
      ),
      'unlockedRewardSkinIds': _normalizeSkinIds(
        unlockedRewardSkinIds,
      ),
    };
  }

  FirestoreUser copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? photoUrl,
    String? language,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    String? activeBikeId,
    bool clearActiveBikeId = false,
    String? subscription,
    String? role,
    String? platform,
    int? crystals,
    int? totalXp,
    List<String>? ownedSkinIds,
    List<String>? unlockedRewardSkinIds,
  }) {
    final resolvedCrystals = crystals ?? this.crystals;
    final resolvedTotalXp = totalXp ?? this.totalXp;

    return FirestoreUser(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      language: language ?? this.language,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      activeBikeId: clearActiveBikeId
          ? null
          : activeBikeId ?? this.activeBikeId,
      subscription: subscription ?? this.subscription,
      role: role ?? this.role,
      platform: platform ?? this.platform,
      crystals: resolvedCrystals < 0 ? 0 : resolvedCrystals,
      totalXp: resolvedTotalXp < 0 ? 0 : resolvedTotalXp,
      ownedSkinIds: _normalizeSkinIds(
        ownedSkinIds ?? this.ownedSkinIds,
        alwaysIncludeStandard: true,
      ),
      unlockedRewardSkinIds: _normalizeSkinIds(
        unlockedRewardSkinIds ?? this.unlockedRewardSkinIds,
      ),
    );
  }

  FirestoreUser normalized() {
    final normalizedActiveBikeId = activeBikeId?.trim();

    return copyWith(
      uid: uid.trim(),
      displayName: displayName.trim(),
      email: email.trim(),
      photoUrl: photoUrl.trim(),
      language: language.trim().isEmpty ? 'da' : language.trim(),
      activeBikeId: normalizedActiveBikeId,
      clearActiveBikeId:
          normalizedActiveBikeId == null || normalizedActiveBikeId.isEmpty,
      subscription:
          subscription.trim().isEmpty ? 'free' : subscription.trim(),
      role: role.trim().isEmpty ? 'user' : role.trim(),
      platform: platform.trim().isEmpty ? 'unknown' : platform.trim(),
      crystals: crystalBalance,
      totalXp: safeTotalXp,
      ownedSkinIds: ownedSkinIds,
      unlockedRewardSkinIds: unlockedRewardSkinIds,
    );
  }

  bool get hasDisplayName => displayName.trim().isNotEmpty;

  bool get hasEmail => email.trim().isNotEmpty;

  bool get hasPhoto => photoUrl.trim().isNotEmpty;

  bool get hasActiveBike =>
      activeBikeId != null && activeBikeId!.trim().isNotEmpty;

  bool get isFreeSubscription =>
      subscription.trim().toLowerCase() == 'free';

  bool get isPremiumSubscription {
    final value = subscription.trim().toLowerCase();

    return value == 'premium' || value == 'pro' || value == 'plus';
  }

  bool get isProSubscription => isPremiumSubscription;

  bool get isAdmin => role.trim().toLowerCase() == 'admin';

  bool get hasCrystals => crystalBalance > 0;

  int get crystalBalance => crystals < 0 ? 0 : crystals;

  int get safeTotalXp => totalXp < 0 ? 0 : totalXp;

  bool canAffordCrystals(int amount) {
    if (amount <= 0) return true;
    return crystalBalance >= amount;
  }

  bool ownsSkin(String skinId) {
    final normalizedId = skinId.trim();

    if (normalizedId.isEmpty) return false;
    if (normalizedId == 'standard') return true;

    return ownedSkinIds.contains(normalizedId);
  }

  bool hasUnlockedRewardSkin(String skinId) {
    final normalizedId = skinId.trim();

    if (normalizedId.isEmpty) return false;

    return unlockedRewardSkinIds.contains(normalizedId);
  }

  bool canUseSkin({
    required String skinId,
    bool requiresPro = false,
    bool requiresRewardUnlock = false,
  }) {
    final normalizedId = skinId.trim();

    if (normalizedId.isEmpty) return false;
    if (ownsSkin(normalizedId)) return true;

    if (requiresPro && isPremiumSubscription) {
      return true;
    }

    if (requiresRewardUnlock && hasUnlockedRewardSkin(normalizedId)) {
      return true;
    }

    return false;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is FirestoreUser &&
        other.uid == uid &&
        other.displayName == displayName &&
        other.email == email &&
        other.photoUrl == photoUrl &&
        other.language == language &&
        other.createdAt == createdAt &&
        other.lastLoginAt == lastLoginAt &&
        other.activeBikeId == activeBikeId &&
        other.subscription == subscription &&
        other.role == role &&
        other.platform == platform &&
        other.crystals == crystals &&
        other.totalXp == totalXp &&
        _listEquals(other.ownedSkinIds, ownedSkinIds) &&
        _listEquals(
          other.unlockedRewardSkinIds,
          unlockedRewardSkinIds,
        );
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        uid,
        displayName,
        email,
        photoUrl,
        language,
        createdAt,
        lastLoginAt,
        activeBikeId,
        subscription,
        role,
        platform,
        crystals,
        totalXp,
        Object.hashAll(ownedSkinIds),
        Object.hashAll(unlockedRewardSkinIds),
      ]);

  @override
  String toString() {
    return 'FirestoreUser('
        'uid: $uid, '
        'displayName: $displayName, '
        'email: $email, '
        'language: $language, '
        'activeBikeId: $activeBikeId, '
        'subscription: $subscription, '
        'role: $role, '
        'platform: $platform, '
        'crystals: $crystals, '
        'totalXp: $totalXp, '
        'ownedSkinIds: ${ownedSkinIds.length}, '
        'unlockedRewardSkinIds: ${unlockedRewardSkinIds.length}'
        ')';
  }

  static String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return fallback;
  }

  static String? _readNullableString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = data[key];

      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return null;
  }

  static int _readInt(
    Map<String, dynamic> data,
    List<String> keys, {
    int fallback = 0,
    int? minimum,
    int? maximum,
  }) {
    int? parsed;

    for (final key in keys) {
      final value = data[key];

      if (value is int) {
        parsed = value;
      } else if (value is num) {
        parsed = value.toInt();
      } else if (value is String && value.trim().isNotEmpty) {
        parsed = int.tryParse(value.trim());
      }

      if (parsed != null) break;
    }

    var resolved = parsed ?? fallback;

    if (minimum != null && resolved < minimum) {
      resolved = minimum;
    }

    if (maximum != null && resolved > maximum) {
      resolved = maximum;
    }

    return resolved;
  }

  static List<String> _readStringList(
    Map<String, dynamic> data,
    List<String> keys, {
    List<String> fallback = const <String>[],
  }) {
    for (final key in keys) {
      final value = data[key];

      if (value is Iterable) {
        return value
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
      }
    }

    return List<String>.from(fallback, growable: false);
  }

  static List<String> _normalizeSkinIds(
    Iterable<String> skinIds, {
    bool alwaysIncludeStandard = false,
  }) {
    final seen = <String>{};
    final result = <String>[];

    if (alwaysIncludeStandard) {
      seen.add('standard');
      result.add('standard');
    }

    for (final skinId in skinIds) {
      final normalizedId = skinId.trim();

      if (normalizedId.isEmpty || seen.contains(normalizedId)) {
        continue;
      }

      seen.add(normalizedId);
      result.add(normalizedId);
    }

    return List<String>.unmodifiable(result);
  }

  static DateTime _readDateTime(
    Map<String, dynamic> data,
    List<String> keys, {
    required DateTime fallback,
  }) {
    for (final key in keys) {
      final value = _parseDateTime(data[key]);

      if (value != null) {
        return value;
      }
    }

    return fallback;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

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

    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value.trim());
    }

    return null;
  }

  static bool _listEquals(
    List<String> first,
    List<String> second,
  ) {
    if (identical(first, second)) return true;
    if (first.length != second.length) return false;

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }
}
