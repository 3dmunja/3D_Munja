import 'package:cloud_firestore/cloud_firestore.dart';

class SocialRiderProfile {
  const SocialRiderProfile({
    required this.uid,
    required this.username,
    required this.riderId,
    required this.displayName,
    required this.level,
    required this.totalXp,
    this.photoUrl,
    this.city,
    this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String username;
  final String riderId;
  final String displayName;
  final String? photoUrl;
  final String? city;
  final int level;
  final int totalXp;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get normalizedUsername {
    return username.trim().toLowerCase();
  }

  String get usernameWithAt {
    final value = username.trim();

    if (value.isEmpty) {
      return '@rider';
    }

    return value.startsWith('@') ? value : '@$value';
  }

  SocialRiderProfile copyWith({
    String? uid,
    String? username,
    String? riderId,
    String? displayName,
    String? photoUrl,
    bool clearPhotoUrl = false,
    String? city,
    bool clearCity = false,
    int? level,
    int? totalXp,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return SocialRiderProfile(
      uid: uid ?? this.uid,
      username: username ?? this.username,
      riderId: riderId ?? this.riderId,
      displayName: displayName ?? this.displayName,
      photoUrl: clearPhotoUrl ? null : photoUrl ?? this.photoUrl,
      city: clearCity ? null : city ?? this.city,
      level: level ?? this.level,
      totalXp: totalXp ?? this.totalXp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'uid': uid,
      'username': normalizedUsername,
      'usernameLowercase': normalizedUsername,
      'riderId': riderId.trim().toUpperCase(),
      'displayName': displayName.trim(),
      'photoUrl': _nullableTrimmed(photoUrl),
      'city': _nullableTrimmed(city),
      'level': level,
      'totalXp': totalXp,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory SocialRiderProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? <String, dynamic>{};

    return SocialRiderProfile(
      uid: _stringValue(
        data['uid'],
        fallback: snapshot.id,
      ),
      username: _stringValue(data['username']),
      riderId: _stringValue(data['riderId']),
      displayName: _stringValue(
        data['displayName'],
        fallback: 'Munja Rider',
      ),
      photoUrl: _nullableStringValue(data['photoUrl']),
      city: _nullableStringValue(data['city']),
      level: _intValue(
        data['level'],
        fallback: 1,
      ).clamp(1, 99),
      totalXp: _intValue(data['totalXp']),
      createdAt: _dateTimeValue(data['createdAt']),
      updatedAt: _dateTimeValue(data['updatedAt']),
    );
  }

  static String createUsernameCandidate(String displayName) {
    final normalized = displayName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return normalized.isEmpty ? 'munja_rider' : normalized;
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

  static String? _nullableStringValue(Object? value) {
    if (value is! String) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _nullableTrimmed(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int _intValue(
    Object? value, {
    int fallback = 0,
  }) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return fallback;
  }

  static DateTime? _dateTimeValue(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    return null;
  }
}
