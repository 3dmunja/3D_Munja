import 'package:cloud_firestore/cloud_firestore.dart';

enum BikeProductType {
  smartLight,
  gps,
  battery,
  sensor,
  display,
  lock,
  camera,
  skin,
  accessory,
  other,
}

enum BikeProductConnectionStatus { disconnected, connecting, connected, error }

enum BikeProductInstallStatus {
  available,
  installed,
  updateAvailable,
  unavailable,
}

class BikeProduct {
  const BikeProduct({
    required this.id,
    required this.ownerId,
    required this.bikeId,
    required this.name,
    required this.type,
    required this.connectionStatus,
    required this.installStatus,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.manufacturer = '',
    this.model = '',
    this.serialNumber = '',
    this.imageUrl = '',
    this.glbModelUrl = '',
    this.firmwareVersion = '',
    this.latestFirmwareVersion = '',
    this.batteryLevel,
    this.rssi,
    this.isEnabled = true,
    this.isVisibleOnDigitalTwin = true,
    this.hotspotId = '',
    this.settings = const <String, dynamic>{},
    this.metadata = const <String, dynamic>{},
  });

  final String id;
  final String ownerId;
  final String bikeId;

  final String name;
  final String description;
  final BikeProductType type;

  final String manufacturer;
  final String model;
  final String serialNumber;

  final String imageUrl;
  final String glbModelUrl;

  final BikeProductConnectionStatus connectionStatus;
  final BikeProductInstallStatus installStatus;

  final String firmwareVersion;
  final String latestFirmwareVersion;

  final int? batteryLevel;
  final int? rssi;

  final bool isEnabled;
  final bool isVisibleOnDigitalTwin;

  /// The hotspot that this product is attached to.
  ///
  /// Examples:
  /// `smartLight`, `battery`, `gps`, `handlebar`, `rearWheel`.
  final String hotspotId;

  /// Product-specific user settings.
  ///
  /// Example:
  /// {
  ///   'brightness': 80,
  ///   'sensitivity': 3,
  ///   'autoBrakeLight': true,
  /// }
  final Map<String, dynamic> settings;

  /// Extra technical data that does not belong in the main model.
  final Map<String, dynamic> metadata;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isConnected =>
      connectionStatus == BikeProductConnectionStatus.connected;

  bool get isConnecting =>
      connectionStatus == BikeProductConnectionStatus.connecting;

  bool get hasConnectionError =>
      connectionStatus == BikeProductConnectionStatus.error;

  bool get isInstalled =>
      installStatus == BikeProductInstallStatus.installed ||
      installStatus == BikeProductInstallStatus.updateAvailable;

  bool get hasFirmwareUpdate {
    if (latestFirmwareVersion.trim().isEmpty) {
      return false;
    }

    return latestFirmwareVersion.trim() != firmwareVersion.trim();
  }

  bool get hasBatteryLevel => batteryLevel != null;

  bool get hasImage => imageUrl.trim().isNotEmpty;

  bool get has3DModel => glbModelUrl.trim().isNotEmpty;

  int? get safeBatteryLevel {
    final value = batteryLevel;

    if (value == null) {
      return null;
    }

    return value.clamp(0, 100);
  }

  String get displayName {
    final value = name.trim();

    if (value.isNotEmpty) {
      return value;
    }

    if (model.trim().isNotEmpty) {
      return model.trim();
    }

    return bikeProductTypeLabel(type);
  }

  String get connectionStatusLabel {
    switch (connectionStatus) {
      case BikeProductConnectionStatus.disconnected:
        return 'Disconnected';
      case BikeProductConnectionStatus.connecting:
        return 'Connecting';
      case BikeProductConnectionStatus.connected:
        return 'Connected';
      case BikeProductConnectionStatus.error:
        return 'Connection error';
    }
  }

  String get installStatusLabel {
    switch (installStatus) {
      case BikeProductInstallStatus.available:
        return 'Available';
      case BikeProductInstallStatus.installed:
        return 'Installed';
      case BikeProductInstallStatus.updateAvailable:
        return 'Update available';
      case BikeProductInstallStatus.unavailable:
        return 'Unavailable';
    }
  }

  factory BikeProduct.empty({
    required String ownerId,
    required String bikeId,
    String id = '',
  }) {
    final now = DateTime.now();

    return BikeProduct(
      id: id,
      ownerId: ownerId,
      bikeId: bikeId,
      name: '',
      type: BikeProductType.other,
      connectionStatus: BikeProductConnectionStatus.disconnected,
      installStatus: BikeProductInstallStatus.available,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BikeProduct.smartBrakeLight({
    required String id,
    required String ownerId,
    required String bikeId,
    String name = 'Munja Smart Brake Light',
    String firmwareVersion = '',
  }) {
    final now = DateTime.now();

    return BikeProduct(
      id: id,
      ownerId: ownerId,
      bikeId: bikeId,
      name: name,
      description: 'Smart connected rear brake light for your Munja bike.',
      type: BikeProductType.smartLight,
      manufacturer: 'Munja',
      model: 'Smart Brake Light',
      connectionStatus: BikeProductConnectionStatus.disconnected,
      installStatus: BikeProductInstallStatus.installed,
      firmwareVersion: firmwareVersion,
      hotspotId: 'smartLight',
      settings: const <String, dynamic>{
        'brightness': 80,
        'sensitivity': 3,
        'autoBrakeLight': true,
        'daylightMode': false,
      },
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BikeProduct.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    return BikeProduct.fromMap(
      document.data() ?? const <String, dynamic>{},
      id: document.id,
    );
  }

  factory BikeProduct.fromMap(Map<String, dynamic> map, {String? id}) {
    return BikeProduct(
      id: id ?? _readString(map['id']),
      ownerId: _readString(map['ownerId']),
      bikeId: _readString(map['bikeId']),
      name: _readString(map['name']),
      description: _readString(map['description']),
      type: bikeProductTypeFromValue(map['type']),
      manufacturer: _readString(map['manufacturer']),
      model: _readString(map['model']),
      serialNumber: _readString(map['serialNumber']),
      imageUrl: _readString(map['imageUrl']),
      glbModelUrl: _readString(map['glbModelUrl']),
      connectionStatus: bikeProductConnectionStatusFromValue(
        map['connectionStatus'],
      ),
      installStatus: bikeProductInstallStatusFromValue(map['installStatus']),
      firmwareVersion: _readString(map['firmwareVersion']),
      latestFirmwareVersion: _readString(map['latestFirmwareVersion']),
      batteryLevel: _readNullableInt(map['batteryLevel']),
      rssi: _readNullableInt(map['rssi']),
      isEnabled: _readBool(map['isEnabled'], fallback: true),
      isVisibleOnDigitalTwin: _readBool(
        map['isVisibleOnDigitalTwin'],
        fallback: true,
      ),
      hotspotId: _readString(map['hotspotId']),
      settings: _readMap(map['settings']),
      metadata: _readMap(map['metadata']),
      createdAt: _readDateTime(map['createdAt']),
      updatedAt: _readDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'ownerId': ownerId.trim(),
      'bikeId': bikeId.trim(),
      'name': name.trim(),
      'description': description.trim(),
      'type': type.name,
      'manufacturer': manufacturer.trim(),
      'model': model.trim(),
      'serialNumber': serialNumber.trim(),
      'imageUrl': imageUrl.trim(),
      'glbModelUrl': glbModelUrl.trim(),
      'connectionStatus': connectionStatus.name,
      'installStatus': installStatus.name,
      'firmwareVersion': firmwareVersion.trim(),
      'latestFirmwareVersion': latestFirmwareVersion.trim(),
      'batteryLevel': safeBatteryLevel,
      'rssi': rssi,
      'isEnabled': isEnabled,
      'isVisibleOnDigitalTwin': isVisibleOnDigitalTwin,
      'hotspotId': hotspotId.trim(),
      'settings': Map<String, dynamic>.from(settings),
      'metadata': Map<String, dynamic>.from(metadata),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'ownerId': ownerId,
      'bikeId': bikeId,
      'name': name,
      'description': description,
      'type': type.name,
      'manufacturer': manufacturer,
      'model': model,
      'serialNumber': serialNumber,
      'imageUrl': imageUrl,
      'glbModelUrl': glbModelUrl,
      'connectionStatus': connectionStatus.name,
      'installStatus': installStatus.name,
      'firmwareVersion': firmwareVersion,
      'latestFirmwareVersion': latestFirmwareVersion,
      'batteryLevel': safeBatteryLevel,
      'rssi': rssi,
      'isEnabled': isEnabled,
      'isVisibleOnDigitalTwin': isVisibleOnDigitalTwin,
      'hotspotId': hotspotId,
      'settings': Map<String, dynamic>.from(settings),
      'metadata': Map<String, dynamic>.from(metadata),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  BikeProduct copyWith({
    String? id,
    String? ownerId,
    String? bikeId,
    String? name,
    String? description,
    BikeProductType? type,
    String? manufacturer,
    String? model,
    String? serialNumber,
    String? imageUrl,
    String? glbModelUrl,
    BikeProductConnectionStatus? connectionStatus,
    BikeProductInstallStatus? installStatus,
    String? firmwareVersion,
    String? latestFirmwareVersion,
    int? batteryLevel,
    bool clearBatteryLevel = false,
    int? rssi,
    bool clearRssi = false,
    bool? isEnabled,
    bool? isVisibleOnDigitalTwin,
    String? hotspotId,
    Map<String, dynamic>? settings,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BikeProduct(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      bikeId: bikeId ?? this.bikeId,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      manufacturer: manufacturer ?? this.manufacturer,
      model: model ?? this.model,
      serialNumber: serialNumber ?? this.serialNumber,
      imageUrl: imageUrl ?? this.imageUrl,
      glbModelUrl: glbModelUrl ?? this.glbModelUrl,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      installStatus: installStatus ?? this.installStatus,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      latestFirmwareVersion:
          latestFirmwareVersion ?? this.latestFirmwareVersion,
      batteryLevel: clearBatteryLevel
          ? null
          : batteryLevel ?? this.batteryLevel,
      rssi: clearRssi ? null : rssi ?? this.rssi,
      isEnabled: isEnabled ?? this.isEnabled,
      isVisibleOnDigitalTwin:
          isVisibleOnDigitalTwin ?? this.isVisibleOnDigitalTwin,
      hotspotId: hotspotId ?? this.hotspotId,
      settings: settings == null
          ? Map<String, dynamic>.from(this.settings)
          : Map<String, dynamic>.from(settings),
      metadata: metadata == null
          ? Map<String, dynamic>.from(this.metadata)
          : Map<String, dynamic>.from(metadata),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  BikeProduct withUpdatedSetting(String key, dynamic value) {
    final updatedSettings = Map<String, dynamic>.from(settings);
    updatedSettings[key] = value;

    return copyWith(settings: updatedSettings, updatedAt: DateTime.now());
  }

  BikeProduct withoutSetting(String key) {
    final updatedSettings = Map<String, dynamic>.from(settings);
    updatedSettings.remove(key);

    return copyWith(settings: updatedSettings, updatedAt: DateTime.now());
  }

  dynamic setting(String key, {dynamic fallback}) {
    return settings.containsKey(key) ? settings[key] : fallback;
  }

  T settingAs<T>(String key, {required T fallback}) {
    final value = settings[key];

    if (value is T) {
      return value;
    }

    return fallback;
  }

  @override
  String toString() {
    return 'BikeProduct('
        'id: $id, '
        'bikeId: $bikeId, '
        'name: $name, '
        'type: ${type.name}, '
        'connectionStatus: ${connectionStatus.name}, '
        'installStatus: ${installStatus.name}'
        ')';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is BikeProduct &&
        other.id == id &&
        other.ownerId == ownerId &&
        other.bikeId == bikeId &&
        other.name == name &&
        other.description == description &&
        other.type == type &&
        other.manufacturer == manufacturer &&
        other.model == model &&
        other.serialNumber == serialNumber &&
        other.imageUrl == imageUrl &&
        other.glbModelUrl == glbModelUrl &&
        other.connectionStatus == connectionStatus &&
        other.installStatus == installStatus &&
        other.firmwareVersion == firmwareVersion &&
        other.latestFirmwareVersion == latestFirmwareVersion &&
        other.batteryLevel == batteryLevel &&
        other.rssi == rssi &&
        other.isEnabled == isEnabled &&
        other.isVisibleOnDigitalTwin == isVisibleOnDigitalTwin &&
        other.hotspotId == hotspotId &&
        _mapEquals(other.settings, settings) &&
        _mapEquals(other.metadata, metadata) &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hashAll(<Object?>[
      id,
      ownerId,
      bikeId,
      name,
      description,
      type,
      manufacturer,
      model,
      serialNumber,
      imageUrl,
      glbModelUrl,
      connectionStatus,
      installStatus,
      firmwareVersion,
      latestFirmwareVersion,
      batteryLevel,
      rssi,
      isEnabled,
      isVisibleOnDigitalTwin,
      hotspotId,
      Object.hashAll(settings.entries),
      Object.hashAll(metadata.entries),
      createdAt,
      updatedAt,
    ]);
  }
}

BikeProductType bikeProductTypeFromValue(dynamic value) {
  final normalized = _normalizeEnumValue(value);

  for (final type in BikeProductType.values) {
    if (type.name.toLowerCase() == normalized) {
      return type;
    }
  }

  switch (normalized) {
    case 'smart-light':
    case 'smart_light':
    case 'light':
    case 'brake-light':
    case 'brake_light':
      return BikeProductType.smartLight;
    case 'e-bike-battery':
    case 'ebike-battery':
      return BikeProductType.battery;
    case 'bike-lock':
    case 'smart-lock':
      return BikeProductType.lock;
    default:
      return BikeProductType.other;
  }
}

BikeProductConnectionStatus bikeProductConnectionStatusFromValue(
  dynamic value,
) {
  final normalized = _normalizeEnumValue(value);

  for (final status in BikeProductConnectionStatus.values) {
    if (status.name.toLowerCase() == normalized) {
      return status;
    }
  }

  return BikeProductConnectionStatus.disconnected;
}

BikeProductInstallStatus bikeProductInstallStatusFromValue(dynamic value) {
  final normalized = _normalizeEnumValue(value);

  for (final status in BikeProductInstallStatus.values) {
    if (status.name.toLowerCase() == normalized) {
      return status;
    }
  }

  switch (normalized) {
    case 'update':
    case 'update-available':
    case 'update_available':
      return BikeProductInstallStatus.updateAvailable;
    default:
      return BikeProductInstallStatus.available;
  }
}

String bikeProductTypeLabel(BikeProductType type) {
  switch (type) {
    case BikeProductType.smartLight:
      return 'Smart light';
    case BikeProductType.gps:
      return 'GPS';
    case BikeProductType.battery:
      return 'Battery';
    case BikeProductType.sensor:
      return 'Sensor';
    case BikeProductType.display:
      return 'Display';
    case BikeProductType.lock:
      return 'Lock';
    case BikeProductType.camera:
      return 'Camera';
    case BikeProductType.skin:
      return 'Skin';
    case BikeProductType.accessory:
      return 'Accessory';
    case BikeProductType.other:
      return 'Other';
  }
}

String _normalizeEnumValue(dynamic value) {
  return value
      .toString()
      .trim()
      .split('.')
      .last
      .replaceAll(' ', '')
      .toLowerCase();
}

String _readString(dynamic value) {
  return value?.toString().trim() ?? '';
}

int? _readNullableInt(dynamic value) {
  if (value == null) {
    return null;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value.toString().trim());
}

bool _readBool(dynamic value, {required bool fallback}) {
  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = value?.toString().trim().toLowerCase();

  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }

  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }

  return fallback;
}

Map<String, dynamic> _readMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return Map<String, dynamic>.from(value);
  }

  if (value is Map) {
    return value.map(
      (key, dynamic item) => MapEntry<String, dynamic>(key.toString(), item),
    );
  }

  return <String, dynamic>{};
}

DateTime _readDateTime(dynamic value) {
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
    return DateTime.tryParse(value) ?? DateTime.now();
  }

  return DateTime.now();
}

bool _mapEquals(Map<String, dynamic> first, Map<String, dynamic> second) {
  if (identical(first, second)) {
    return true;
  }

  if (first.length != second.length) {
    return false;
  }

  for (final entry in first.entries) {
    if (!second.containsKey(entry.key) || second[entry.key] != entry.value) {
      return false;
    }
  }

  return true;
}
