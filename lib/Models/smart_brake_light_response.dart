import 'dart:convert';

/// Parsed response received from the Munja Smart Brake Light.
///
/// The model supports:
/// - Command acknowledgements
/// - Error responses
/// - Live product status
/// - Flexible key aliases from different firmware versions
/// - JSON and key/value payloads
class SmartBrakeLightResponse {
  const SmartBrakeLightResponse({
    this.acknowledged,
    this.command,
    this.requestId,
    this.success,
    this.errorCode,
    this.errorMessage,
    this.batteryLevel,
    this.temperatureCelsius,
    this.firmwareVersion,
    this.latestFirmwareVersion,
    this.brightness,
    this.sensitivity,
    this.flashPattern,
    this.enabled,
    this.autoOn,
    this.autoOff,
    this.brakeActive,
    this.charging,
    this.rssi,
    this.deviceId,
    this.deviceName,
    this.receivedAt,
    this.rawData = const <String, dynamic>{},
  });

  /// Whether the physical device acknowledged the command.
  final bool? acknowledged;

  /// Command name related to the response.
  ///
  /// Examples:
  /// - set_brightness
  /// - set_sensitivity
  /// - request_status
  /// - restart
  final String? command;

  /// Optional identifier used to match a response with a sent command.
  final String? requestId;

  /// General success state returned by the firmware.
  final bool? success;

  /// Optional machine-readable firmware error code.
  final String? errorCode;

  /// Optional human-readable firmware error message.
  final String? errorMessage;

  /// Battery level from 0 to 100.
  final int? batteryLevel;

  /// Product temperature in degrees Celsius.
  final double? temperatureCelsius;

  /// Firmware version currently installed on the product.
  final String? firmwareVersion;

  /// Latest available firmware version, when provided.
  final String? latestFirmwareVersion;

  /// LED brightness from 0 to 100.
  final int? brightness;

  /// Brake sensitivity from 0 to 100.
  final int? sensitivity;

  /// Current normal light pattern.
  ///
  /// Examples:
  /// - solid
  /// - pulse
  /// - flash
  /// - emergency
  final String? flashPattern;

  /// Whether the Smart Brake Light is enabled.
  final bool? enabled;

  /// Whether automatic activation is enabled.
  final bool? autoOn;

  /// Whether automatic shutdown is enabled.
  final bool? autoOff;

  /// Whether braking is currently detected.
  final bool? brakeActive;

  /// Whether the battery is currently charging.
  final bool? charging;

  /// Bluetooth signal strength in dBm.
  final int? rssi;

  /// Optional hardware or BLE device identifier.
  final String? deviceId;

  /// Optional product or BLE device name.
  final String? deviceName;

  /// Time at which the response was parsed by the app.
  final DateTime? receivedAt;

  /// Original normalized payload.
  final Map<String, dynamic> rawData;

  /// Returns true when the response explicitly indicates success.
  bool get isSuccessful =>
      success == true ||
      acknowledged == true ||
      (errorCode == null && errorMessage == null);

  /// Returns true when the firmware explicitly rejected the command.
  bool get hasError =>
      success == false ||
      acknowledged == false ||
      _hasText(errorCode) ||
      _hasText(errorMessage);

  /// Returns true when the response contains command acknowledgement data.
  bool get isAcknowledgement =>
      acknowledged != null || success != null || _hasText(command);

  /// Returns true when the response contains live device status.
  bool get containsStatus =>
      batteryLevel != null ||
      temperatureCelsius != null ||
      firmwareVersion != null ||
      brightness != null ||
      sensitivity != null ||
      flashPattern != null ||
      enabled != null ||
      autoOn != null ||
      autoOff != null ||
      brakeActive != null ||
      charging != null ||
      rssi != null;

  /// Creates a response from a JSON-compatible map.
  factory SmartBrakeLightResponse.fromJson(
    Map<String, dynamic> json, {
    DateTime? receivedAt,
  }) {
    final normalized = _normalizeMap(json);

    return SmartBrakeLightResponse(
      acknowledged: _readBool(normalized, const <String>[
        'ack',
        'acknowledged',
        'acknowledgement',
        'accepted',
      ]),
      command: _readString(normalized, const <String>[
        'cmd',
        'command',
        'action',
      ]),
      requestId: _readString(normalized, const <String>[
        'requestid',
        'request_id',
        'messageid',
        'message_id',
        'id',
      ]),
      success: _readBool(normalized, const <String>['success', 'ok', 'result']),
      errorCode: _readString(normalized, const <String>[
        'errorcode',
        'error_code',
        'code',
      ]),
      errorMessage: _readString(normalized, const <String>[
        'errormessage',
        'error_message',
        'error',
        'message',
      ]),
      batteryLevel: _readInt(normalized, const <String>[
        'battery',
        'batterylevel',
        'battery_level',
        'bat',
        'batt',
      ])?.clamp(0, 100),
      temperatureCelsius: _readDouble(normalized, const <String>[
        'temperature',
        'temperaturecelsius',
        'temperature_celsius',
        'temperaturec',
        'temperature_c',
        'temp',
      ]),
      firmwareVersion: _readString(normalized, const <String>[
        'firmware',
        'firmwareversion',
        'firmware_version',
        'fw',
        'version',
      ]),
      latestFirmwareVersion: _readString(normalized, const <String>[
        'latestfirmware',
        'latest_firmware',
        'latestfirmwareversion',
        'latest_firmware_version',
        'latestfw',
        'latest_fw',
      ]),
      brightness: _readInt(normalized, const <String>[
        'brightness',
        'ledbrightness',
        'led_brightness',
        'pwm',
        'led',
      ])?.clamp(0, 100),
      sensitivity: _readInt(normalized, const <String>[
        'sensitivity',
        'brakesensitivity',
        'brake_sensitivity',
        'bs',
      ])?.clamp(0, 100),
      flashPattern: _readString(normalized, const <String>[
        'flashpattern',
        'flash_pattern',
        'pattern',
        'lightmode',
        'light_mode',
        'ledmode',
        'led_mode',
        'mode',
      ]),
      enabled: _readBool(normalized, const <String>[
        'enabled',
        'isenabled',
        'is_enabled',
        'ledenabled',
        'led_enabled',
        'brakelightenabled',
        'brake_light_enabled',
      ]),
      autoOn: _readBool(normalized, const <String>[
        'autoon',
        'auto_on',
        'automaticon',
        'automatic_on',
      ]),
      autoOff: _readBool(normalized, const <String>[
        'autooff',
        'auto_off',
        'automaticoff',
        'automatic_off',
      ]),
      brakeActive: _readBool(normalized, const <String>[
        'brake',
        'braking',
        'brakeactive',
        'brake_active',
      ]),
      charging: _readBool(normalized, const <String>[
        'charging',
        'ischarging',
        'is_charging',
      ]),
      rssi: _readInt(normalized, const <String>[
        'rssi',
        'signal',
        'signalstrength',
        'signal_strength',
      ]),
      deviceId: _readString(normalized, const <String>[
        'deviceid',
        'device_id',
        'bledeviceid',
        'ble_device_id',
      ]),
      deviceName: _readString(normalized, const <String>[
        'devicename',
        'device_name',
        'bledevicename',
        'ble_device_name',
        'name',
      ]),
      receivedAt: receivedAt ?? DateTime.now(),
      rawData: Map<String, dynamic>.unmodifiable(normalized),
    );
  }

  /// Parses either:
  ///
  /// JSON:
  /// {"ack":true,"cmd":"set_brightness","brightness":80}
  ///
  /// Key/value:
  /// ACK=1;CMD=set_brightness;BRIGHTNESS=80
  factory SmartBrakeLightResponse.parse(String raw, {DateTime? receivedAt}) {
    final cleaned = raw.replaceAll('\u0000', '').replaceAll('\r', '').trim();

    if (cleaned.isEmpty) {
      throw const FormatException(
        'Smart Brake Light response payload is empty.',
      );
    }

    final jsonMap = _tryDecodeJson(cleaned);

    if (jsonMap != null) {
      return SmartBrakeLightResponse.fromJson(jsonMap, receivedAt: receivedAt);
    }

    final keyValueMap = _parseKeyValuePayload(cleaned);

    if (keyValueMap.isEmpty) {
      throw FormatException(
        'Smart Brake Light response could not be parsed: $cleaned',
      );
    }

    return SmartBrakeLightResponse.fromJson(
      keyValueMap,
      receivedAt: receivedAt,
    );
  }

  /// Converts the parsed response to a serializable map.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      if (acknowledged != null) 'ack': acknowledged,
      if (_hasText(command)) 'cmd': command,
      if (_hasText(requestId)) 'requestId': requestId,
      if (success != null) 'success': success,
      if (_hasText(errorCode)) 'errorCode': errorCode,
      if (_hasText(errorMessage)) 'errorMessage': errorMessage,
      if (batteryLevel != null) 'battery': batteryLevel,
      if (temperatureCelsius != null) 'temperatureCelsius': temperatureCelsius,
      if (_hasText(firmwareVersion)) 'firmware': firmwareVersion,
      if (_hasText(latestFirmwareVersion))
        'latestFirmware': latestFirmwareVersion,
      if (brightness != null) 'brightness': brightness,
      if (sensitivity != null) 'sensitivity': sensitivity,
      if (_hasText(flashPattern)) 'flashPattern': flashPattern,
      if (enabled != null) 'enabled': enabled,
      if (autoOn != null) 'autoOn': autoOn,
      if (autoOff != null) 'autoOff': autoOff,
      if (brakeActive != null) 'brakeActive': brakeActive,
      if (charging != null) 'charging': charging,
      if (rssi != null) 'rssi': rssi,
      if (_hasText(deviceId)) 'deviceId': deviceId,
      if (_hasText(deviceName)) 'deviceName': deviceName,
      if (receivedAt != null) 'receivedAt': receivedAt!.toIso8601String(),
    };
  }

  /// Creates a copy with selected values replaced.
  SmartBrakeLightResponse copyWith({
    bool? acknowledged,
    bool clearAcknowledged = false,
    String? command,
    bool clearCommand = false,
    String? requestId,
    bool clearRequestId = false,
    bool? success,
    bool clearSuccess = false,
    String? errorCode,
    bool clearErrorCode = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    int? batteryLevel,
    bool clearBatteryLevel = false,
    double? temperatureCelsius,
    bool clearTemperatureCelsius = false,
    String? firmwareVersion,
    bool clearFirmwareVersion = false,
    String? latestFirmwareVersion,
    bool clearLatestFirmwareVersion = false,
    int? brightness,
    bool clearBrightness = false,
    int? sensitivity,
    bool clearSensitivity = false,
    String? flashPattern,
    bool clearFlashPattern = false,
    bool? enabled,
    bool clearEnabled = false,
    bool? autoOn,
    bool clearAutoOn = false,
    bool? autoOff,
    bool clearAutoOff = false,
    bool? brakeActive,
    bool clearBrakeActive = false,
    bool? charging,
    bool clearCharging = false,
    int? rssi,
    bool clearRssi = false,
    String? deviceId,
    bool clearDeviceId = false,
    String? deviceName,
    bool clearDeviceName = false,
    DateTime? receivedAt,
    bool clearReceivedAt = false,
    Map<String, dynamic>? rawData,
  }) {
    return SmartBrakeLightResponse(
      acknowledged: clearAcknowledged
          ? null
          : acknowledged ?? this.acknowledged,
      command: clearCommand ? null : command ?? this.command,
      requestId: clearRequestId ? null : requestId ?? this.requestId,
      success: clearSuccess ? null : success ?? this.success,
      errorCode: clearErrorCode ? null : errorCode ?? this.errorCode,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      batteryLevel: clearBatteryLevel
          ? null
          : batteryLevel ?? this.batteryLevel,
      temperatureCelsius: clearTemperatureCelsius
          ? null
          : temperatureCelsius ?? this.temperatureCelsius,
      firmwareVersion: clearFirmwareVersion
          ? null
          : firmwareVersion ?? this.firmwareVersion,
      latestFirmwareVersion: clearLatestFirmwareVersion
          ? null
          : latestFirmwareVersion ?? this.latestFirmwareVersion,
      brightness: clearBrightness ? null : brightness ?? this.brightness,
      sensitivity: clearSensitivity ? null : sensitivity ?? this.sensitivity,
      flashPattern: clearFlashPattern
          ? null
          : flashPattern ?? this.flashPattern,
      enabled: clearEnabled ? null : enabled ?? this.enabled,
      autoOn: clearAutoOn ? null : autoOn ?? this.autoOn,
      autoOff: clearAutoOff ? null : autoOff ?? this.autoOff,
      brakeActive: clearBrakeActive ? null : brakeActive ?? this.brakeActive,
      charging: clearCharging ? null : charging ?? this.charging,
      rssi: clearRssi ? null : rssi ?? this.rssi,
      deviceId: clearDeviceId ? null : deviceId ?? this.deviceId,
      deviceName: clearDeviceName ? null : deviceName ?? this.deviceName,
      receivedAt: clearReceivedAt ? null : receivedAt ?? this.receivedAt,
      rawData: Map<String, dynamic>.unmodifiable(rawData ?? this.rawData),
    );
  }

  @override
  String toString() {
    return 'SmartBrakeLightResponse('
        'acknowledged: $acknowledged, '
        'command: $command, '
        'requestId: $requestId, '
        'success: $success, '
        'errorCode: $errorCode, '
        'errorMessage: $errorMessage, '
        'batteryLevel: $batteryLevel, '
        'temperatureCelsius: $temperatureCelsius, '
        'firmwareVersion: $firmwareVersion, '
        'latestFirmwareVersion: $latestFirmwareVersion, '
        'brightness: $brightness, '
        'sensitivity: $sensitivity, '
        'flashPattern: $flashPattern, '
        'enabled: $enabled, '
        'autoOn: $autoOn, '
        'autoOff: $autoOff, '
        'brakeActive: $brakeActive, '
        'charging: $charging, '
        'rssi: $rssi, '
        'deviceId: $deviceId, '
        'deviceName: $deviceName, '
        'receivedAt: $receivedAt'
        ')';
  }

  static Map<String, dynamic>? _tryDecodeJson(String raw) {
    try {
      final decoded = jsonDecode(raw);

      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } on FormatException {
      return null;
    }

    return null;
  }

  static Map<String, dynamic> _parseKeyValuePayload(String raw) {
    final result = <String, dynamic>{};
    final parts = raw.split(RegExp(r'[;,\n|]+'));

    for (final part in parts) {
      final item = part.trim();

      if (item.isEmpty) {
        continue;
      }

      final equalsIndex = item.indexOf('=');
      final colonIndex = item.indexOf(':');

      final separatorIndex = switch ((equalsIndex, colonIndex)) {
        (< 0, < 0) => -1,
        (< 0, _) => colonIndex,
        (_, < 0) => equalsIndex,
        _ => equalsIndex < colonIndex ? equalsIndex : colonIndex,
      };

      if (separatorIndex <= 0) {
        continue;
      }

      final key = item.substring(0, separatorIndex).trim();
      final value = item.substring(separatorIndex + 1).trim();

      if (key.isNotEmpty) {
        result[key] = _parseScalar(value);
      }
    }

    return result;
  }

  static dynamic _parseScalar(String value) {
    final normalized = value.trim();
    final lower = normalized.toLowerCase();

    if (lower == 'true' ||
        lower == 'on' ||
        lower == 'yes' ||
        lower == 'enabled' ||
        lower == 'active') {
      return true;
    }

    if (lower == 'false' ||
        lower == 'off' ||
        lower == 'no' ||
        lower == 'disabled' ||
        lower == 'inactive') {
      return false;
    }

    if (lower == 'null') {
      return null;
    }

    final integer = int.tryParse(normalized);

    if (integer != null) {
      return integer;
    }

    final decimal = double.tryParse(normalized.replaceAll(',', '.'));

    if (decimal != null) {
      return decimal;
    }

    return normalized;
  }

  static Map<String, dynamic> _normalizeMap(Map<String, dynamic> input) {
    final result = <String, dynamic>{};

    void addEntries(Map<dynamic, dynamic> source) {
      for (final entry in source.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value;

        if (value is Map) {
          addEntries(value);
        }

        result[key] = value;
        result[_normalizeKey(key)] = value;
      }
    }

    addEntries(input);

    return result;
  }

  static String? _readString(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);

    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    return text.isEmpty ? null : text;
  }

  static int? _readInt(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(
        value.replaceAll('%', '').replaceAll('dBm', '').trim(),
      );
    }

    return null;
  }

  static double? _readDouble(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(
        value
            .replaceAll('°C', '')
            .replaceAll('%', '')
            .replaceAll(',', '.')
            .trim(),
      );
    }

    return null;
  }

  static bool? _readBool(Map<String, dynamic> source, List<String> keys) {
    final value = _readValue(source, keys);

    if (value is bool) {
      return value;
    }

    if (value is num) {
      return value != 0;
    }

    final normalized = value?.toString().trim().toLowerCase();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    if (<String>{
      '1',
      'true',
      'on',
      'yes',
      'ok',
      'success',
      'accepted',
      'active',
      'enabled',
    }.contains(normalized)) {
      return true;
    }

    if (<String>{
      '0',
      'false',
      'off',
      'no',
      'error',
      'failed',
      'rejected',
      'inactive',
      'disabled',
    }.contains(normalized)) {
      return false;
    }

    return null;
  }

  static dynamic _readValue(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      if (source.containsKey(key)) {
        return source[key];
      }

      final normalizedKey = _normalizeKey(key);

      if (source.containsKey(normalizedKey)) {
        return source[normalizedKey];
      }
    }

    return null;
  }

  static String _normalizeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static bool _hasText(String? value) {
    return value?.trim().isNotEmpty ?? false;
  }
}
