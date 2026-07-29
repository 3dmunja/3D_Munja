import 'dart:convert';
import 'dart:typed_data';

/// Supported notification payload formats.
enum BleNotificationFormat { empty, json, keyValue, plainText, binary }

/// Normalized BLE notification data used by Munja smart products.
///
/// The parser keeps all recognized values in strongly typed fields while also
/// preserving unknown values inside [extra].
class BleNotificationData {
  const BleNotificationData({
    required this.format,
    required this.rawText,
    required this.rawBytes,
    required this.receivedAt,
    this.batteryLevel,
    this.rssi,
    this.firmwareVersion,
    this.latestFirmwareVersion,
    this.temperatureCelsius,
    this.brakePressed,
    this.ledEnabled,
    this.charging,
    this.brightness,
    this.sensitivity,
    this.flashPattern,
    this.deviceName,
    this.deviceId,
    this.errorCode,
    this.status,
    this.extra = const <String, dynamic>{},
  });

  final BleNotificationFormat format;
  final String rawText;
  final List<int> rawBytes;
  final DateTime receivedAt;

  final int? batteryLevel;
  final int? rssi;
  final String? firmwareVersion;
  final String? latestFirmwareVersion;
  final double? temperatureCelsius;
  final bool? brakePressed;
  final bool? ledEnabled;
  final bool? charging;
  final int? brightness;
  final int? sensitivity;
  final String? flashPattern;
  final String? deviceName;
  final String? deviceId;
  final String? errorCode;
  final String? status;

  /// Unknown or product-specific values that were not mapped to a typed field.
  final Map<String, dynamic> extra;

  bool get isEmpty {
    return batteryLevel == null &&
        rssi == null &&
        firmwareVersion == null &&
        latestFirmwareVersion == null &&
        temperatureCelsius == null &&
        brakePressed == null &&
        ledEnabled == null &&
        charging == null &&
        brightness == null &&
        sensitivity == null &&
        flashPattern == null &&
        deviceName == null &&
        deviceId == null &&
        errorCode == null &&
        status == null &&
        extra.isEmpty;
  }

  bool get hasError {
    final normalizedError = errorCode?.trim();
    if (normalizedError != null && normalizedError.isNotEmpty) {
      return true;
    }

    final normalizedStatus = status?.trim().toLowerCase();

    return normalizedStatus == 'error' ||
        normalizedStatus == 'fault' ||
        normalizedStatus == 'failed';
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'format': format.name,
      'receivedAt': receivedAt.toIso8601String(),
      'rawText': rawText,
      'rawBytes': List<int>.unmodifiable(rawBytes),
      if (batteryLevel != null) 'battery': batteryLevel,
      if (rssi != null) 'rssi': rssi,
      if (firmwareVersion != null) 'firmware': firmwareVersion,
      if (latestFirmwareVersion != null)
        'latestFirmware': latestFirmwareVersion,
      if (temperatureCelsius != null) 'temperature': temperatureCelsius,
      if (brakePressed != null) 'brake': brakePressed,
      if (ledEnabled != null) 'led': ledEnabled,
      if (charging != null) 'charging': charging,
      if (brightness != null) 'brightness': brightness,
      if (sensitivity != null) 'sensitivity': sensitivity,
      if (flashPattern != null) 'flashPattern': flashPattern,
      if (deviceName != null) 'deviceName': deviceName,
      if (deviceId != null) 'deviceId': deviceId,
      if (errorCode != null) 'errorCode': errorCode,
      if (status != null) 'status': status,
      ...extra,
    };
  }

  Map<String, dynamic> toProductMetadata() {
    return <String, dynamic>{
      'lastBleMessage': rawText,
      'lastBleMessageAt': receivedAt.toIso8601String(),
      'lastBlePayloadFormat': format.name,
      if (temperatureCelsius != null) 'temperatureCelsius': temperatureCelsius,
      if (brakePressed != null) 'brakePressed': brakePressed,
      if (ledEnabled != null) 'ledEnabled': ledEnabled,
      if (charging != null) 'charging': charging,
      if (brightness != null) 'brightness': brightness,
      if (sensitivity != null) 'sensitivity': sensitivity,
      if (flashPattern != null) 'flashPattern': flashPattern,
      if (deviceName != null) 'bleReportedDeviceName': deviceName,
      if (deviceId != null) 'bleReportedDeviceId': deviceId,
      if (errorCode != null) 'bleErrorCode': errorCode,
      if (status != null) 'bleReportedStatus': status,
      if (extra.isNotEmpty) 'bleExtra': extra,
    };
  }

  @override
  String toString() {
    return 'BleNotificationData(${toMap()})';
  }
}

/// Exception thrown when a BLE notification cannot be parsed.
class BleNotificationParseException implements FormatException {
  const BleNotificationParseException(this.message, {this.source, this.offset});

  @override
  final String message;

  @override
  final Object? source;

  @override
  final int? offset;

  @override
  String toString() {
    return 'BleNotificationParseException: $message';
  }
}

/// Parses Munja BLE notifications into [BleNotificationData].
///
/// Supported text payloads:
///
/// JSON:
/// ```json
/// {"battery":87,"firmware":"1.2.0","rssi":-53,"brake":true}
/// ```
///
/// Key/value:
/// ```text
/// BAT=87;FW=1.2.0;RSSI=-53;BRAKE=1;PWM=80;TEMP=26.4
/// ```
///
/// Alternative separators are accepted:
/// ```text
/// battery:87, firmware:1.2.0, led:on
/// ```
///
/// A compact binary Munja packet is also supported:
///
/// ```text
/// Byte 0  : 0x4D ('M')
/// Byte 1  : 0x4A ('J')
/// Byte 2  : protocol version
/// Byte 3  : flags
/// Byte 4  : battery 0-100, 0xFF = unavailable
/// Byte 5  : signed RSSI
/// Byte 6  : brightness 0-100, 0xFF = unavailable
/// Byte 7  : sensitivity 0-100, 0xFF = unavailable
/// Byte 8-9: temperature in tenths °C, signed little-endian
/// Remaining bytes: optional UTF-8 firmware version
/// ```
///
/// Flag bits:
/// - bit 0: brake pressed
/// - bit 1: LED enabled
/// - bit 2: charging
/// - bit 3: device error
class BleNotificationParser {
  const BleNotificationParser._();

  static const int _binaryHeaderM = 0x4D;
  static const int _binaryHeaderJ = 0x4A;

  static BleNotificationData parseBytes(
    List<int> bytes, {
    DateTime? receivedAt,
  }) {
    final safeBytes = List<int>.unmodifiable(
      bytes.map((value) => value.clamp(0, 255)),
    );

    if (safeBytes.isEmpty) {
      return BleNotificationData(
        format: BleNotificationFormat.empty,
        rawText: '',
        rawBytes: safeBytes,
        receivedAt: receivedAt ?? DateTime.now(),
      );
    }

    if (_looksLikeMunjaBinaryPacket(safeBytes)) {
      return _parseBinaryPacket(safeBytes, receivedAt: receivedAt);
    }

    final text = utf8.decode(safeBytes, allowMalformed: true);

    return parseText(text, rawBytes: safeBytes, receivedAt: receivedAt);
  }

  static BleNotificationData parseText(
    String value, {
    List<int>? rawBytes,
    DateTime? receivedAt,
  }) {
    final normalized = _normalizeText(value);
    final bytes = List<int>.unmodifiable(rawBytes ?? utf8.encode(normalized));
    final timestamp = receivedAt ?? DateTime.now();

    if (normalized.isEmpty) {
      return BleNotificationData(
        format: BleNotificationFormat.empty,
        rawText: '',
        rawBytes: bytes,
        receivedAt: timestamp,
      );
    }

    final jsonResult = _tryParseJson(normalized);

    if (jsonResult != null) {
      return _fromMap(
        jsonResult,
        format: BleNotificationFormat.json,
        rawText: normalized,
        rawBytes: bytes,
        receivedAt: timestamp,
      );
    }

    final keyValueResult = _tryParseKeyValue(normalized);

    if (keyValueResult != null && keyValueResult.isNotEmpty) {
      return _fromMap(
        keyValueResult,
        format: BleNotificationFormat.keyValue,
        rawText: normalized,
        rawBytes: bytes,
        receivedAt: timestamp,
      );
    }

    return BleNotificationData(
      format: BleNotificationFormat.plainText,
      rawText: normalized,
      rawBytes: bytes,
      receivedAt: timestamp,
      status: normalized,
    );
  }

  static Map<String, dynamic> parseToMap(String value) {
    return parseText(value).toMap();
  }

  static bool canParseText(String value) {
    final normalized = _normalizeText(value);

    if (normalized.isEmpty) {
      return false;
    }

    if (_tryParseJson(normalized) != null) {
      return true;
    }

    final keyValue = _tryParseKeyValue(normalized);
    return keyValue != null && keyValue.isNotEmpty;
  }

  static BleNotificationData _fromMap(
    Map<String, dynamic> source, {
    required BleNotificationFormat format,
    required String rawText,
    required List<int> rawBytes,
    required DateTime receivedAt,
  }) {
    final normalized = _normalizeMap(source);
    final consumedKeys = <String>{};

    T? readValue<T>(
      List<String> aliases,
      T? Function(dynamic value) converter,
    ) {
      for (final alias in aliases) {
        final normalizedAlias = _normalizeKey(alias);

        if (!normalized.containsKey(normalizedAlias)) {
          continue;
        }

        consumedKeys.add(normalizedAlias);
        final converted = converter(normalized[normalizedAlias]);

        if (converted != null) {
          return converted;
        }
      }

      return null;
    }

    final battery = readValue<int>(const <String>[
      'battery',
      'batteryLevel',
      'battery_level',
      'batteryPercent',
      'battery_percent',
      'bat',
      'batt',
      'soc',
    ], _toInt);

    final rssi = readValue<int>(const <String>[
      'rssi',
      'signal',
      'signalStrength',
      'signal_strength',
      'dbm',
    ], _toInt);

    final firmware = readValue<String>(const <String>[
      'firmware',
      'firmwareVersion',
      'firmware_version',
      'fw',
      'version',
    ], _toStringValue);

    final latestFirmware = readValue<String>(const <String>[
      'latestFirmware',
      'latestFirmwareVersion',
      'latest_firmware',
      'latest_fw',
      'availableFirmware',
    ], _toStringValue);

    final temperature = readValue<double>(const <String>[
      'temperature',
      'temperatureCelsius',
      'temperature_celsius',
      'temp',
      'tempC',
      'temp_c',
    ], _toDouble);

    final brake = readValue<bool>(const <String>[
      'brake',
      'brakePressed',
      'brake_pressed',
      'braking',
      'stop',
    ], _toBool);

    final led = readValue<bool>(const <String>[
      'led',
      'ledEnabled',
      'led_enabled',
      'light',
      'lightOn',
      'light_on',
      'lamp',
    ], _toBool);

    final charging = readValue<bool>(const <String>[
      'charging',
      'isCharging',
      'is_charging',
      'charge',
    ], _toBool);

    final brightness = readValue<int>(const <String>[
      'brightness',
      'ledBrightness',
      'led_brightness',
      'pwm',
      'intensity',
    ], _toInt);

    final sensitivity = readValue<int>(const <String>[
      'sensitivity',
      'brakeSensitivity',
      'brake_sensitivity',
      'sens',
    ], _toInt);

    final flashPattern = readValue<String>(const <String>[
      'flashPattern',
      'flash_pattern',
      'pattern',
      'mode',
      'lightMode',
      'light_mode',
    ], _toStringValue);

    final deviceName = readValue<String>(const <String>[
      'deviceName',
      'device_name',
      'name',
      'productName',
      'product_name',
    ], _toStringValue);

    final deviceId = readValue<String>(const <String>[
      'deviceId',
      'device_id',
      'id',
      'serial',
      'serialNumber',
      'serial_number',
    ], _toStringValue);

    final errorCode = readValue<String>(const <String>[
      'error',
      'errorCode',
      'error_code',
      'fault',
      'faultCode',
      'fault_code',
    ], _toStringValue);

    final status = readValue<String>(const <String>[
      'status',
      'state',
      'deviceStatus',
      'device_status',
    ], _toStringValue);

    final extra = <String, dynamic>{};

    for (final entry in normalized.entries) {
      if (!consumedKeys.contains(entry.key)) {
        extra[entry.key] = entry.value;
      }
    }

    return BleNotificationData(
      format: format,
      rawText: rawText,
      rawBytes: rawBytes,
      receivedAt: receivedAt,
      batteryLevel: battery?.clamp(0, 100),
      rssi: rssi,
      firmwareVersion: firmware,
      latestFirmwareVersion: latestFirmware,
      temperatureCelsius: temperature,
      brakePressed: brake,
      ledEnabled: led,
      charging: charging,
      brightness: brightness?.clamp(0, 100),
      sensitivity: sensitivity?.clamp(0, 100),
      flashPattern: flashPattern,
      deviceName: deviceName,
      deviceId: deviceId,
      errorCode: errorCode,
      status: status,
      extra: Map<String, dynamic>.unmodifiable(extra),
    );
  }

  static BleNotificationData _parseBinaryPacket(
    List<int> bytes, {
    DateTime? receivedAt,
  }) {
    if (bytes.length < 10) {
      throw BleNotificationParseException(
        'Munja binary packet is too short. Expected at least 10 bytes.',
        source: bytes,
      );
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));

    final protocolVersion = bytes[2];
    final flags = bytes[3];

    final batteryByte = bytes[4];
    final rssi = byteData.getInt8(5);
    final brightnessByte = bytes[6];
    final sensitivityByte = bytes[7];
    final temperatureTenths = byteData.getInt16(8, Endian.little);

    final firmware = bytes.length > 10
        ? _normalizeText(utf8.decode(bytes.sublist(10), allowMalformed: true))
        : '';

    final hasDeviceError = flags & 0x08 != 0;

    return BleNotificationData(
      format: BleNotificationFormat.binary,
      rawText: firmware.isEmpty ? 'MUNJA_BINARY_V$protocolVersion' : firmware,
      rawBytes: List<int>.unmodifiable(bytes),
      receivedAt: receivedAt ?? DateTime.now(),
      batteryLevel: batteryByte == 0xFF ? null : batteryByte.clamp(0, 100),
      rssi: rssi,
      firmwareVersion: firmware.isEmpty ? null : firmware,
      temperatureCelsius: temperatureTenths / 10,
      brakePressed: flags & 0x01 != 0,
      ledEnabled: flags & 0x02 != 0,
      charging: flags & 0x04 != 0,
      brightness: brightnessByte == 0xFF ? null : brightnessByte.clamp(0, 100),
      sensitivity: sensitivityByte == 0xFF
          ? null
          : sensitivityByte.clamp(0, 100),
      errorCode: hasDeviceError ? 'device_error' : null,
      status: hasDeviceError ? 'error' : 'ok',
      extra: <String, dynamic>{
        'protocolVersion': protocolVersion,
        'flags': flags,
      },
    );
  }

  static bool _looksLikeMunjaBinaryPacket(List<int> bytes) {
    return bytes.length >= 2 &&
        bytes[0] == _binaryHeaderM &&
        bytes[1] == _binaryHeaderJ;
  }

  static Map<String, dynamic>? _tryParseJson(String value) {
    final first = value.codeUnitAt(0);

    if (first != 0x7B && first != 0x5B) {
      return null;
    }

    try {
      final decoded = jsonDecode(value);

      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (dynamic key, dynamic item) =>
              MapEntry<String, dynamic>(key.toString(), item),
        );
      }

      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        final firstItem = decoded.first as Map;

        return firstItem.map<String, dynamic>(
          (dynamic key, dynamic item) =>
              MapEntry<String, dynamic>(key.toString(), item),
        );
      }

      return <String, dynamic>{'value': decoded};
    } on FormatException {
      return null;
    }
  }

  static Map<String, dynamic>? _tryParseKeyValue(String value) {
    final result = <String, dynamic>{};

    final normalizedSeparators = value
        .replaceAll('\n', ';')
        .replaceAll('|', ';');

    final segments = normalizedSeparators.split(
      RegExp(r'[;,](?=\s*[A-Za-z_][A-Za-z0-9_\- ]*\s*[:=])'),
    );

    for (final segment in segments) {
      final trimmed = segment.trim();

      if (trimmed.isEmpty) {
        continue;
      }

      final match = RegExp(
        r'^([A-Za-z_][A-Za-z0-9_\- ]*)\s*[:=]\s*(.*)$',
      ).firstMatch(trimmed);

      if (match == null) {
        continue;
      }

      final key = match.group(1)?.trim();
      final rawValue = match.group(2)?.trim();

      if (key == null || key.isEmpty || rawValue == null) {
        continue;
      }

      result[key] = _parseScalar(rawValue);
    }

    if (result.isNotEmpty) {
      return result;
    }

    final whitespaceMatches = RegExp(
      r'''([A-Za-z_][A-Za-z0-9_\-]*)\s*[:=]\s*("[^"]*"|'[^']*'|[^\s]+)''',
    ).allMatches(value);

    for (final match in whitespaceMatches) {
      final key = match.group(1)?.trim();
      final rawValue = match.group(2)?.trim();

      if (key == null || key.isEmpty || rawValue == null) {
        continue;
      }

      result[key] = _parseScalar(rawValue);
    }

    return result.isEmpty ? null : result;
  }

  static dynamic _parseScalar(String value) {
    final trimmed = _removeMatchingQuotes(value.trim());

    if (trimmed.isEmpty) {
      return '';
    }

    final normalized = trimmed.toLowerCase();

    if (const <String>{
      'true',
      'on',
      'yes',
      'enabled',
      'active',
      'high',
    }.contains(normalized)) {
      return true;
    }

    if (const <String>{
      'false',
      'off',
      'no',
      'disabled',
      'inactive',
      'low',
    }.contains(normalized)) {
      return false;
    }

    if (normalized == 'null' || normalized == 'none' || normalized == 'n/a') {
      return null;
    }

    final intValue = int.tryParse(trimmed);

    if (intValue != null) {
      return intValue;
    }

    final doubleValue = double.tryParse(trimmed.replaceAll(',', '.'));

    if (doubleValue != null) {
      return doubleValue;
    }

    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        return jsonDecode(trimmed);
      } on FormatException {
        // Keep the original text when nested JSON is malformed.
      }
    }

    return trimmed;
  }

  static Map<String, dynamic> _normalizeMap(Map<String, dynamic> source) {
    final result = <String, dynamic>{};

    void flatten(Map<dynamic, dynamic> map, {String? prefix}) {
      for (final entry in map.entries) {
        final rawKey = entry.key.toString();
        final key = _normalizeKey(
          prefix == null ? rawKey : '${prefix}_$rawKey',
        );
        final value = entry.value;

        if (value is Map) {
          flatten(value, prefix: key);
        } else {
          result[key] = value;
        }
      }
    }

    flatten(source);

    for (final entry in source.entries) {
      result[_normalizeKey(entry.key)] = entry.value;
    }

    return result;
  }

  static String _normalizeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static String _normalizeText(String value) {
    return value.replaceAll('\u0000', '').replaceAll('\r', '').trim();
  }

  static String _removeMatchingQuotes(String value) {
    if (value.length < 2) {
      return value;
    }

    final first = value[0];
    final last = value[value.length - 1];

    if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
      return value.substring(1, value.length - 1);
    }

    return value;
  }

  static int? _toInt(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is double) {
      return value.round();
    }

    if (value is bool) {
      return value ? 1 : 0;
    }

    final text = value
        .toString()
        .trim()
        .replaceAll('%', '')
        .replaceAll('dBm', '')
        .replaceAll('dbm', '');

    return int.tryParse(text) ?? double.tryParse(text)?.round();
  }

  static double? _toDouble(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    final text = value
        .toString()
        .trim()
        .replaceAll('°C', '')
        .replaceAll('C', '')
        .replaceAll(',', '.');

    return double.tryParse(text);
  }

  static bool? _toBool(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value.toString().trim().toLowerCase();

    if (const <String>{
      '1',
      'true',
      'yes',
      'on',
      'enabled',
      'active',
      'pressed',
      'braking',
      'high',
    }.contains(normalized)) {
      return true;
    }

    if (const <String>{
      '0',
      'false',
      'no',
      'off',
      'disabled',
      'inactive',
      'released',
      'idle',
      'low',
    }.contains(normalized)) {
      return false;
    }

    return null;
  }

  static String? _toStringValue(dynamic value) {
    if (value == null) {
      return null;
    }

    final normalized = value.toString().trim();

    return normalized.isEmpty ? null : normalized;
  }
}
