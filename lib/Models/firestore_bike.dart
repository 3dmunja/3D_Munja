import 'package:cloud_firestore/cloud_firestore.dart';

enum FirestoreBikeType { road, gravel, mtb, city, ebike, kids, other }

extension FirestoreBikeTypeValue on FirestoreBikeType {
  String get value {
    switch (this) {
      case FirestoreBikeType.road:
        return 'road';
      case FirestoreBikeType.gravel:
        return 'gravel';
      case FirestoreBikeType.mtb:
        return 'mtb';
      case FirestoreBikeType.city:
        return 'city';
      case FirestoreBikeType.ebike:
        return 'ebike';
      case FirestoreBikeType.kids:
        return 'kids';
      case FirestoreBikeType.other:
        return 'other';
    }
  }
}

class FirestoreBikeDigitalTwin {
  final String glbModelUrl;
  final String imageUrl;
  final String thumbnailUrl;
  final String activeSkinId;
  final String activeFrameId;
  final String frameColor;

  const FirestoreBikeDigitalTwin({
    this.glbModelUrl = '',
    this.imageUrl = '',
    this.thumbnailUrl = '',
    this.activeSkinId = '',
    this.activeFrameId = '',
    this.frameColor = '',
  });

  factory FirestoreBikeDigitalTwin.fromMap(dynamic value) {
    if (value is! Map) {
      return const FirestoreBikeDigitalTwin();
    }

    final map = Map<String, dynamic>.from(value);

    return FirestoreBikeDigitalTwin(
      glbModelUrl: _readDigitalTwinString(map['glbModelUrl']),
      imageUrl: _readDigitalTwinString(map['imageUrl']),
      thumbnailUrl: _readDigitalTwinString(map['thumbnailUrl']),
      activeSkinId: _readDigitalTwinString(
        map['activeSkinId'] ?? map['activeSkin'],
      ),
      activeFrameId: _readDigitalTwinString(
        map['activeFrameId'] ?? map['activeFrame'],
      ),
      frameColor: _readDigitalTwinString(map['frameColor']),
    );
  }

  FirestoreBikeDigitalTwin copyWith({
    String? glbModelUrl,
    String? imageUrl,
    String? thumbnailUrl,
    String? activeSkinId,
    String? activeFrameId,
    String? frameColor,
  }) {
    return FirestoreBikeDigitalTwin(
      glbModelUrl: glbModelUrl ?? this.glbModelUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      activeSkinId: activeSkinId ?? this.activeSkinId,
      activeFrameId: activeFrameId ?? this.activeFrameId,
      frameColor: frameColor ?? this.frameColor,
    );
  }

  FirestoreBikeDigitalTwin normalized() {
    return FirestoreBikeDigitalTwin(
      glbModelUrl: glbModelUrl.trim(),
      imageUrl: imageUrl.trim(),
      thumbnailUrl: thumbnailUrl.trim(),
      activeSkinId: activeSkinId.trim(),
      activeFrameId: activeFrameId.trim(),
      frameColor: frameColor.trim(),
    );
  }

  bool get hasData =>
      glbModelUrl.trim().isNotEmpty ||
      imageUrl.trim().isNotEmpty ||
      thumbnailUrl.trim().isNotEmpty ||
      activeSkinId.trim().isNotEmpty ||
      activeFrameId.trim().isNotEmpty ||
      frameColor.trim().isNotEmpty;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      if (glbModelUrl.trim().isNotEmpty)
        'glbModelUrl': glbModelUrl.trim(),
      if (imageUrl.trim().isNotEmpty)
        'imageUrl': imageUrl.trim(),
      if (thumbnailUrl.trim().isNotEmpty)
        'thumbnailUrl': thumbnailUrl.trim(),
      if (activeSkinId.trim().isNotEmpty)
        'activeSkinId': activeSkinId.trim(),
      if (activeFrameId.trim().isNotEmpty)
        'activeFrameId': activeFrameId.trim(),
      if (frameColor.trim().isNotEmpty)
        'frameColor': frameColor.trim(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is FirestoreBikeDigitalTwin &&
        other.glbModelUrl == glbModelUrl &&
        other.imageUrl == imageUrl &&
        other.thumbnailUrl == thumbnailUrl &&
        other.activeSkinId == activeSkinId &&
        other.activeFrameId == activeFrameId &&
        other.frameColor == frameColor;
  }

  @override
  int get hashCode => Object.hash(
        glbModelUrl,
        imageUrl,
        thumbnailUrl,
        activeSkinId,
        activeFrameId,
        frameColor,
      );

  static String _readDigitalTwinString(dynamic value) {
    if (value is String) {
      return value.trim();
    }

    return '';
  }
}

class FirestoreBike {
  final String id;
  final String ownerId;
  final String name;
  final String brand;
  final String model;
  final FirestoreBikeType type;
  final String color;
  final String frameSize;
  final String wheelSize;
  final String serialNumber;
  final String imageUrl;
  final String glbModelUrl;
  final String thumbnailUrl;
  final String activeSkin;
  final String activeFrameId;
  final String frameColor;
  final FirestoreBikeDigitalTwin digitalTwin;
  final String firmwareVersion;
  final bool active;
  final bool digitalTwinEnabled;
  final List<String> installedProductIds;
  final String notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const FirestoreBike({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.brand,
    required this.model,
    required this.type,
    required this.color,
    required this.frameSize,
    required this.wheelSize,
    required this.serialNumber,
    required this.imageUrl,
    required this.glbModelUrl,
    this.thumbnailUrl = '',
    this.activeSkin = '',
    this.activeFrameId = '',
    this.frameColor = '',
    this.digitalTwin = const FirestoreBikeDigitalTwin(),
    required this.firmwareVersion,
    required this.active,
    required this.digitalTwinEnabled,
    required this.installedProductIds,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FirestoreBike.empty({required String ownerId, String id = ''}) {
    return FirestoreBike(
      id: id,
      ownerId: ownerId.trim(),
      name: '',
      brand: '',
      model: '',
      type: FirestoreBikeType.other,
      color: '',
      frameSize: '',
      wheelSize: '',
      serialNumber: '',
      imageUrl: '',
      glbModelUrl: '',
      thumbnailUrl: '',
      activeSkin: '',
      activeFrameId: '',
      frameColor: '',
      digitalTwin: const FirestoreBikeDigitalTwin(),
      firmwareVersion: '',
      active: false,
      digitalTwinEnabled: false,
      installedProductIds: const <String>[],
      notes: '',
      createdAt: null,
      updatedAt: null,
    );
  }

  factory FirestoreBike.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data() ?? const <String, dynamic>{};

    return FirestoreBike.fromMap(data, id: document.id);
  }

  factory FirestoreBike.fromMap(Map<String, dynamic> map, {String? id}) {
    final digitalTwin = FirestoreBikeDigitalTwin.fromMap(
      map['digitalTwin'],
    );

    final topLevelGlbModelUrl =
        _readString(map['glbModelUrl'] ?? map['glbModel']);
    final topLevelImageUrl = _readString(map['imageUrl']);
    final topLevelThumbnailUrl = _readString(map['thumbnailUrl']);
    final topLevelActiveSkin = _readString(map['activeSkin']);
    final topLevelActiveFrameId = _readString(
      map['activeFrameId'] ?? map['activeFrame'],
    );
    final topLevelFrameColor = _readString(map['frameColor']);

    final resolvedGlbModelUrl = topLevelGlbModelUrl.isNotEmpty
        ? topLevelGlbModelUrl
        : digitalTwin.glbModelUrl;

    final resolvedImageUrl = topLevelImageUrl.isNotEmpty
        ? topLevelImageUrl
        : digitalTwin.imageUrl;

    final resolvedThumbnailUrl = topLevelThumbnailUrl.isNotEmpty
        ? topLevelThumbnailUrl
        : digitalTwin.thumbnailUrl;

    final resolvedActiveSkin = topLevelActiveSkin.isNotEmpty
        ? topLevelActiveSkin
        : digitalTwin.activeSkinId;

    final resolvedActiveFrameId = topLevelActiveFrameId.isNotEmpty
        ? topLevelActiveFrameId
        : digitalTwin.activeFrameId;

    final resolvedFrameColor = topLevelFrameColor.isNotEmpty
        ? topLevelFrameColor
        : digitalTwin.frameColor;

    final topLevelColor = _readString(map['color']);
    final resolvedColor = topLevelColor.isNotEmpty
        ? topLevelColor
        : resolvedFrameColor;

    final synchronizedDigitalTwin = digitalTwin.copyWith(
      glbModelUrl: digitalTwin.glbModelUrl.isNotEmpty
          ? digitalTwin.glbModelUrl
          : resolvedGlbModelUrl,
      imageUrl: digitalTwin.imageUrl.isNotEmpty
          ? digitalTwin.imageUrl
          : resolvedImageUrl,
      thumbnailUrl: digitalTwin.thumbnailUrl.isNotEmpty
          ? digitalTwin.thumbnailUrl
          : resolvedThumbnailUrl,
      activeSkinId: digitalTwin.activeSkinId.isNotEmpty
          ? digitalTwin.activeSkinId
          : resolvedActiveSkin,
      activeFrameId: digitalTwin.activeFrameId.isNotEmpty
          ? digitalTwin.activeFrameId
          : resolvedActiveFrameId,
      frameColor: digitalTwin.frameColor.isNotEmpty
          ? digitalTwin.frameColor
          : resolvedFrameColor,
    );

    return FirestoreBike(
      id: _readString(id ?? map['id']),
      ownerId: _readString(map['ownerId'] ?? map['userId']),
      name: _readString(map['name'] ?? map['bikeName']),
      brand: _readString(map['brand']),
      model: _readString(map['model']),
      type: _parseBikeType(map['type'] ?? map['bikeType']),
      color: resolvedColor,
      frameSize: _readString(map['frameSize']),
      wheelSize: _readString(map['wheelSize']),
      serialNumber: _readString(map['serialNumber']),
      imageUrl: resolvedImageUrl,
      glbModelUrl: resolvedGlbModelUrl,
      thumbnailUrl: resolvedThumbnailUrl,
      activeSkin: resolvedActiveSkin,
      activeFrameId: resolvedActiveFrameId,
      frameColor: resolvedFrameColor,
      digitalTwin: synchronizedDigitalTwin,
      firmwareVersion: _readString(map['firmwareVersion']),
      active: _readBool(map['active'] ?? map['isActive']),
      digitalTwinEnabled:
          _readBool(map['digitalTwinEnabled']) ||
          synchronizedDigitalTwin.hasData,
      installedProductIds: _readStringList(map['installedProductIds']),
      notes: _readString(map['notes']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'ownerId': ownerId,
      'name': name,
      'brand': brand,
      'model': model,
      'type': type.value,
      'color': color,
      'frameSize': frameSize,
      'wheelSize': wheelSize,
      'serialNumber': serialNumber,
      'imageUrl': imageUrl,
      'glbModelUrl': glbModelUrl,
      'thumbnailUrl': thumbnailUrl,
      'activeSkin': activeSkin,
      'activeFrameId': activeFrameId,
      'frameColor': frameColor,
      'digitalTwin': digitalTwin.toMap(),
      'firmwareVersion': firmwareVersion,
      'active': active,
      'digitalTwinEnabled': digitalTwinEnabled,
      'installedProductIds': installedProductIds,
      'notes': notes,
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
    };
  }

  Map<String, dynamic> toCreateMap() {
    return <String, dynamic>{
      'ownerId': ownerId,
      'name': name,
      'brand': brand,
      'model': model,
      'type': type.value,
      'color': color,
      'frameSize': frameSize,
      'wheelSize': wheelSize,
      'serialNumber': serialNumber,
      'imageUrl': imageUrl,
      'glbModelUrl': glbModelUrl,
      'thumbnailUrl': thumbnailUrl,
      'activeSkin': activeSkin,
      'activeFrameId': activeFrameId,
      'frameColor': frameColor,
      if (digitalTwin.hasData) 'digitalTwin': digitalTwin.toMap(),
      'firmwareVersion': firmwareVersion,
      'active': active,
      'digitalTwinEnabled': digitalTwinEnabled,
      'installedProductIds': installedProductIds,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return <String, dynamic>{
      'ownerId': ownerId,
      'name': name,
      'brand': brand,
      'model': model,
      'type': type.value,
      'color': color,
      'frameSize': frameSize,
      'wheelSize': wheelSize,
      'serialNumber': serialNumber,
      'imageUrl': imageUrl,
      'glbModelUrl': glbModelUrl,
      'thumbnailUrl': thumbnailUrl,
      'activeSkin': activeSkin,
      'activeFrameId': activeFrameId,
      'frameColor': frameColor,
      'digitalTwin': digitalTwin.toMap(),
      'firmwareVersion': firmwareVersion,
      'active': active,
      'digitalTwinEnabled': digitalTwinEnabled,
      'installedProductIds': installedProductIds,
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  FirestoreBike copyWith({
    String? id,
    String? ownerId,
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
    String? thumbnailUrl,
    String? activeSkin,
    String? activeFrameId,
    String? frameColor,
    FirestoreBikeDigitalTwin? digitalTwin,
    String? firmwareVersion,
    bool? active,
    bool? digitalTwinEnabled,
    List<String>? installedProductIds,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearCreatedAt = false,
    bool clearUpdatedAt = false,
  }) {
    return FirestoreBike(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      type: type ?? this.type,
      color: color ?? this.color,
      frameSize: frameSize ?? this.frameSize,
      wheelSize: wheelSize ?? this.wheelSize,
      serialNumber: serialNumber ?? this.serialNumber,
      imageUrl: imageUrl ?? this.imageUrl,
      glbModelUrl: glbModelUrl ?? this.glbModelUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      activeSkin: activeSkin ?? this.activeSkin,
      activeFrameId: activeFrameId ?? this.activeFrameId,
      frameColor: frameColor ?? this.frameColor,
      digitalTwin: digitalTwin ?? this.digitalTwin,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      active: active ?? this.active,
      digitalTwinEnabled: digitalTwinEnabled ?? this.digitalTwinEnabled,
      installedProductIds: installedProductIds == null
          ? this.installedProductIds
          : List<String>.unmodifiable(installedProductIds),
      notes: notes ?? this.notes,
      createdAt: clearCreatedAt ? null : createdAt ?? this.createdAt,
      updatedAt: clearUpdatedAt ? null : updatedAt ?? this.updatedAt,
    );
  }

  FirestoreBike normalized() {
    return copyWith(
      id: id.trim(),
      ownerId: ownerId.trim(),
      name: name.trim(),
      brand: brand.trim(),
      model: model.trim(),
      color: color.trim(),
      frameSize: frameSize.trim(),
      wheelSize: wheelSize.trim(),
      serialNumber: serialNumber.trim(),
      imageUrl: imageUrl.trim(),
      glbModelUrl: glbModelUrl.trim(),
      thumbnailUrl: thumbnailUrl.trim(),
      activeSkin: activeSkin.trim(),
      activeFrameId: activeFrameId.trim(),
      frameColor: frameColor.trim(),
      digitalTwin: digitalTwin.normalized(),
      firmwareVersion: firmwareVersion.trim(),
      installedProductIds: installedProductIds
          .map((productId) => productId.trim())
          .where((productId) => productId.isNotEmpty)
          .toSet()
          .toList(growable: false),
      notes: notes.trim(),
    );
  }

  bool get isValid {
    return ownerId.trim().isNotEmpty && name.trim().isNotEmpty;
  }

  bool get hasDigitalTwinModel {
    return glbModelUrl.trim().isNotEmpty ||
        digitalTwin.glbModelUrl.trim().isNotEmpty;
  }

  bool get hasDigitalTwinCustomization {
    return activeSkin.trim().isNotEmpty ||
        activeFrameId.trim().isNotEmpty ||
        frameColor.trim().isNotEmpty ||
        digitalTwin.activeSkinId.trim().isNotEmpty ||
        digitalTwin.activeFrameId.trim().isNotEmpty ||
        digitalTwin.frameColor.trim().isNotEmpty;
  }

  String get effectiveActiveSkin {
    if (activeSkin.trim().isNotEmpty) {
      return activeSkin.trim();
    }

    return digitalTwin.activeSkinId.trim();
  }

  String get effectiveActiveFrameId {
    if (activeFrameId.trim().isNotEmpty) {
      return activeFrameId.trim();
    }

    return digitalTwin.activeFrameId.trim();
  }

  String get effectiveFrameColor {
    if (frameColor.trim().isNotEmpty) {
      return frameColor.trim();
    }

    if (digitalTwin.frameColor.trim().isNotEmpty) {
      return digitalTwin.frameColor.trim();
    }

    return color.trim();
  }

  bool get hasImage {
    return imageUrl.trim().isNotEmpty;
  }

  bool get hasInstalledProducts {
    return installedProductIds.isNotEmpty;
  }

  String get displayName {
    if (name.trim().isNotEmpty) {
      return name.trim();
    }

    final brandAndModel = <String>[
      brand.trim(),
      model.trim(),
    ].where((value) => value.isNotEmpty).join(' ');

    if (brandAndModel.isNotEmpty) {
      return brandAndModel;
    }

    return 'Min cykel';
  }

  @override
  String toString() {
    return 'FirestoreBike('
        'id: $id, '
        'ownerId: $ownerId, '
        'name: $name, '
        'brand: $brand, '
        'model: $model, '
        'type: ${type.value}, '
        'active: $active, '
        'activeSkin: $activeSkin, '
        'activeFrameId: $activeFrameId, '
        'frameColor: $frameColor'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is FirestoreBike &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.name == name &&
        other.brand == brand &&
        other.model == model &&
        other.type == type &&
        other.color == color &&
        other.frameSize == frameSize &&
        other.wheelSize == wheelSize &&
        other.serialNumber == serialNumber &&
        other.imageUrl == imageUrl &&
        other.glbModelUrl == glbModelUrl &&
        other.thumbnailUrl == thumbnailUrl &&
        other.activeSkin == activeSkin &&
        other.activeFrameId == activeFrameId &&
        other.frameColor == frameColor &&
        other.digitalTwin == digitalTwin &&
        other.firmwareVersion == firmwareVersion &&
        other.active == active &&
        other.digitalTwinEnabled == digitalTwinEnabled &&
        _listEquals(other.installedProductIds, installedProductIds) &&
        other.notes == notes &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hashAll(<Object?>[
      id,
      ownerId,
      name,
      brand,
      model,
      type,
      color,
      frameSize,
      wheelSize,
      serialNumber,
      imageUrl,
      glbModelUrl,
      thumbnailUrl,
      activeSkin,
      activeFrameId,
      frameColor,
      digitalTwin,
      firmwareVersion,
      active,
      digitalTwinEnabled,
      Object.hashAll(installedProductIds),
      notes,
      createdAt,
      updatedAt,
    ]);
  }

  static FirestoreBikeType _parseBikeType(dynamic value) {
    final normalized = _readString(value).toLowerCase();

    switch (normalized) {
      case 'road':
        return FirestoreBikeType.road;
      case 'gravel':
        return FirestoreBikeType.gravel;
      case 'mtb':
      case 'mountainbike':
      case 'mountain_bike':
        return FirestoreBikeType.mtb;
      case 'city':
        return FirestoreBikeType.city;
      case 'ebike':
      case 'e-bike':
      case 'electric':
        return FirestoreBikeType.ebike;
      case 'kids':
      case 'kid':
      case 'children':
        return FirestoreBikeType.kids;
      default:
        return FirestoreBikeType.other;
    }
  }

  static String _readString(dynamic value) {
    if (value is String) {
      return value.trim();
    }

    return '';
  }

  static bool _readBool(dynamic value) {
    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }

    return false;
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! Iterable) {
      return const <String>[];
    }

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
  }

  static bool _listEquals(List<String> first, List<String> second) {
    if (identical(first, second)) {
      return true;
    }

    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) {
        return false;
      }
    }

    return true;
  }
}
