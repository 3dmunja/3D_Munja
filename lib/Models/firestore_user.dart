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

    return FirestoreUser(
      uid: uid,
      displayName: _readString(data, const ['displayName', 'name']),
      email: _readString(data, const ['email']),
      photoUrl: _readString(data, const ['photoUrl', 'photoURL']),
      language: _readString(data, const ['language', 'locale'], fallback: 'da'),
      createdAt: _readDateTime(data, const ['createdAt'], fallback: now),
      lastLoginAt: _readDateTime(data, const [
        'lastLoginAt',
        'lastLogin',
      ], fallback: now),
      activeBikeId: _readNullableString(data, const [
        'activeBikeId',
        'activeBike',
      ]),
      subscription: _readString(data, const [
        'subscription',
        'subscriptionPlan',
      ], fallback: 'free'),
      role: _readString(data, const ['role'], fallback: 'user'),
      platform: _readString(data, const ['platform'], fallback: 'unknown'),
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
  }) {
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
    );
  }

  bool get hasDisplayName => displayName.trim().isNotEmpty;

  bool get hasEmail => email.trim().isNotEmpty;

  bool get hasPhoto => photoUrl.trim().isNotEmpty;

  bool get hasActiveBike =>
      activeBikeId != null && activeBikeId!.trim().isNotEmpty;

  bool get isFreeSubscription => subscription.trim().toLowerCase() == 'free';

  bool get isPremiumSubscription {
    final value = subscription.trim().toLowerCase();

    return value == 'premium' || value == 'pro' || value == 'plus';
  }

  bool get isAdmin => role.trim().toLowerCase() == 'admin';

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
        other.platform == platform;
  }

  @override
  int get hashCode => Object.hash(
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
  );

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
        'platform: $platform'
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
}
