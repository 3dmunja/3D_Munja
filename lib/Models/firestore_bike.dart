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
    return FirestoreBike(
      id: _readString(id ?? map['id']),
      ownerId: _readString(map['ownerId']),
      name: _readString(map['name'] ?? map['bikeName']),
      brand: _readString(map['brand']),
      model: _readString(map['model']),
      type: _parseBikeType(map['type'] ?? map['bikeType']),
      color: _readString(map['color'] ?? map['frameColor']),
      frameSize: _readString(map['frameSize']),
      wheelSize: _readString(map['wheelSize']),
      serialNumber: _readString(map['serialNumber']),
      imageUrl: _readString(map['imageUrl']),
      glbModelUrl: _readString(map['glbModelUrl'] ?? map['glbModel']),
      firmwareVersion: _readString(map['firmwareVersion']),
      active: _readBool(map['active']),
      digitalTwinEnabled: _readBool(map['digitalTwinEnabled']),
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
    return glbModelUrl.trim().isNotEmpty;
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
        'active: $active'
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
