import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../models/bike_product.dart';
import '../../models/smart_brake_light_response.dart';
import '../../providers/digital_twin_provider.dart';

/// BLE bridge between physical Munja products and the Digital Twin.
///
/// Supported incoming payloads:
///
/// JSON:
/// {"battery":87,"firmware":"1.2.0","rssi":-53,"brake":true}
///
/// Key/value:
/// BAT=87;FW=1.2.0;RSSI=-53;BRAKE=1;PWM=80;TEMP=26.4
class DigitalTwinBleService extends ChangeNotifier {
  DigitalTwinBleService({
    required DigitalTwinProvider digitalTwinProvider,
    this.rssiInterval = const Duration(seconds: 5),
    this.connectTimeout = const Duration(seconds: 15),
  }) : _digitalTwinProvider = digitalTwinProvider;

  final DigitalTwinProvider _digitalTwinProvider;
  final Duration rssiInterval;
  final Duration connectTimeout;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _notifyCharacteristic;
  BluetoothCharacteristic? _writeCharacteristic;

  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _notificationSubscription;
  Timer? _rssiTimer;

  final StreamController<SmartBrakeLightResponse> _responseController =
      StreamController<SmartBrakeLightResponse>.broadcast(sync: true);
  final List<_PendingBleResponse> _pendingResponses = <_PendingBleResponse>[];

  String? _productId;
  String? _errorMessage;
  String? _lastRawMessage;
  DateTime? _lastMessageAt;
  SmartBrakeLightResponse? _lastResponse;

  bool _isConnecting = false;
  bool _isDisconnecting = false;
  bool _disposed = false;

  BluetoothDevice? get device => _device;
  BluetoothCharacteristic? get notifyCharacteristic => _notifyCharacteristic;
  BluetoothCharacteristic? get writeCharacteristic => _writeCharacteristic;

  String? get productId => _productId;
  String? get errorMessage => _errorMessage;
  String? get lastRawMessage => _lastRawMessage;
  DateTime? get lastMessageAt => _lastMessageAt;
  SmartBrakeLightResponse? get lastResponse => _lastResponse;
  Stream<SmartBrakeLightResponse> get responseStream =>
      _responseController.stream;

  bool get isConnecting => _isConnecting;
  bool get isDisconnecting => _isDisconnecting;
  bool get isConnected => _device?.isConnected == true;
  bool get hasError => _errorMessage?.trim().isNotEmpty ?? false;

  Future<void> connect({
    required String productId,
    required BluetoothDevice device,
    required String serviceUuid,
    required String notifyCharacteristicUuid,
    String? writeCharacteristicUuid,
    bool autoConnect = false,
  }) async {
    if (_disposed) return;

    final product = _digitalTwinProvider.productById(productId);

    if (product == null) {
      _setError('Produktet med id "$productId" blev ikke fundet.');
      return;
    }

    await disconnect(updateProductStatus: false);

    _productId = productId;
    _device = device;
    _isConnecting = true;
    _setError(null);
    _notify();

    _updateProduct(
      connectionStatus: BikeProductConnectionStatus.connecting,
      metadata: {
        'bleDeviceId': device.remoteId.str,
        'bleDeviceName': device.platformName,
        'lastConnectionAttemptAt': DateTime.now().toIso8601String(),
      },
    );

    try {
      await _connectionSubscription?.cancel();

      _connectionSubscription = device.connectionState.listen(
        _handleConnectionState,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'DigitalTwinBleService connection error: '
            '$error\n$stackTrace',
          );

          _setError('Bluetooth-forbindelsesfejl: $error');
          _updateProduct(
            connectionStatus: BikeProductConnectionStatus.error,
            metadata: {
              'bleConnectionError': error.toString(),
              'bleConnectionErrorAt': DateTime.now().toIso8601String(),
            },
          );
        },
      );

      if (!device.isConnected) {
        await device
            .connect(autoConnect: autoConnect, timeout: connectTimeout)
            .timeout(connectTimeout);
      }

      final services = await device.discoverServices();
      final normalizedServiceUuid = _normalizeUuid(serviceUuid);
      final normalizedNotifyUuid = _normalizeUuid(notifyCharacteristicUuid);
      final normalizedWriteUuid = writeCharacteristicUuid == null
          ? null
          : _normalizeUuid(writeCharacteristicUuid);

      BluetoothService? targetService;

      for (final service in services) {
        if (_normalizeUuid(service.uuid.str) == normalizedServiceUuid) {
          targetService = service;
          break;
        }
      }

      if (targetService == null) {
        throw StateError('BLE-service $serviceUuid blev ikke fundet.');
      }

      BluetoothCharacteristic? notifyCharacteristic;
      BluetoothCharacteristic? writeCharacteristic;

      for (final characteristic in targetService.characteristics) {
        final uuid = _normalizeUuid(characteristic.uuid.str);

        if (uuid == normalizedNotifyUuid) {
          notifyCharacteristic = characteristic;
        }

        if (normalizedWriteUuid != null && uuid == normalizedWriteUuid) {
          writeCharacteristic = characteristic;
        }
      }

      if (notifyCharacteristic == null) {
        throw StateError(
          'Notification-characteristic '
          '$notifyCharacteristicUuid blev ikke fundet.',
        );
      }

      if (normalizedWriteUuid != null && writeCharacteristic == null) {
        throw StateError(
          'Write-characteristic '
          '$writeCharacteristicUuid blev ikke fundet.',
        );
      }

      _notifyCharacteristic = notifyCharacteristic;
      _writeCharacteristic = writeCharacteristic;

      await _notificationSubscription?.cancel();

      _notificationSubscription = notifyCharacteristic.onValueReceived.listen(
        handleNotificationBytes,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'DigitalTwinBleService notification error: '
            '$error\n$stackTrace',
          );

          _setError('BLE-notifikationsfejl: $error');
          _updateProduct(
            connectionStatus: BikeProductConnectionStatus.error,
            metadata: {
              'bleNotificationError': error.toString(),
              'bleNotificationErrorAt': DateTime.now().toIso8601String(),
            },
          );
        },
      );

      await notifyCharacteristic.setNotifyValue(true);

      _updateProduct(
        connectionStatus: BikeProductConnectionStatus.connected,
        metadata: {
          'bleServiceUuid': normalizedServiceUuid,
          'bleNotifyCharacteristicUuid': normalizedNotifyUuid,
          if (normalizedWriteUuid != null)
            'bleWriteCharacteristicUuid': normalizedWriteUuid,
          'connectedAt': DateTime.now().toIso8601String(),
        },
      );

      _startRssiTimer();
      await refreshRssi();
    } on TimeoutException {
      _setError('Bluetooth-forbindelsen fik timeout.');
      _updateProduct(
        connectionStatus: BikeProductConnectionStatus.error,
        metadata: {
          'bleError': 'connection_timeout',
          'bleErrorAt': DateTime.now().toIso8601String(),
        },
      );
      await _safeDisconnectDevice();
    } catch (error, stackTrace) {
      debugPrint(
        'DigitalTwinBleService.connect error: '
        '$error\n$stackTrace',
      );

      _setError('Bluetooth kunne ikke forbindes: $error');
      _updateProduct(
        connectionStatus: BikeProductConnectionStatus.error,
        metadata: {
          'bleError': error.toString(),
          'bleErrorAt': DateTime.now().toIso8601String(),
        },
      );
      await _safeDisconnectDevice();
    } finally {
      _isConnecting = false;
      _notify();
    }
  }

  Future<void> disconnect({bool updateProductStatus = true}) async {
    if (_isDisconnecting) return;

    _isDisconnecting = true;
    _notify();

    try {
      _stopRssiTimer();
      _failPendingResponses(StateError('Bluetooth-forbindelsen blev afbrudt.'));

      await _notificationSubscription?.cancel();
      _notificationSubscription = null;

      final notifyCharacteristic = _notifyCharacteristic;

      if (notifyCharacteristic != null) {
        try {
          if (notifyCharacteristic.isNotifying) {
            await notifyCharacteristic.setNotifyValue(false);
          }
        } catch (error) {
          debugPrint('DigitalTwinBleService disable notify error: $error');
        }
      }

      await _connectionSubscription?.cancel();
      _connectionSubscription = null;

      await _safeDisconnectDevice();

      if (updateProductStatus && _productId != null) {
        _updateProduct(
          connectionStatus: BikeProductConnectionStatus.disconnected,
          clearRssi: true,
          metadata: {'disconnectedAt': DateTime.now().toIso8601String()},
        );
      }
    } finally {
      _device = null;
      _notifyCharacteristic = null;
      _writeCharacteristic = null;
      _productId = null;
      _isConnecting = false;
      _isDisconnecting = false;
      _notify();
    }
  }

  Future<int?> refreshRssi() async {
    final device = _device;

    if (device == null || !device.isConnected) {
      return null;
    }

    try {
      final rssi = await device.readRssi();

      _updateProduct(
        rssi: rssi,
        metadata: {'lastRssiAt': DateTime.now().toIso8601String()},
      );

      return rssi;
    } catch (error) {
      debugPrint('DigitalTwinBleService.refreshRssi error: $error');
      return null;
    }
  }

  Future<void> writeBytes(
    List<int> value, {
    bool withoutResponse = false,
  }) async {
    final characteristic = _writeCharacteristic;

    if (characteristic == null) {
      throw StateError('Ingen BLE write-characteristic er konfigureret.');
    }

    if (_device?.isConnected != true) {
      throw StateError('Bluetooth-enheden er ikke forbundet.');
    }

    const int chunkSize = 180;

    if (value.length <= chunkSize) {
      await characteristic.write(value, withoutResponse: withoutResponse);
      return;
    }

    for (int offset = 0; offset < value.length; offset += chunkSize) {
      final end = (offset + chunkSize < value.length)
          ? offset + chunkSize
          : value.length;

      await characteristic.write(
        value.sublist(offset, end),
        withoutResponse: withoutResponse,
      );

      await Future<void>.delayed(const Duration(milliseconds: 15));
    }
  }

  Future<void> writeText(
    String command, {
    bool appendNewLine = false,
    bool withoutResponse = false,
  }) {
    final value = appendNewLine ? '$command\n' : command;

    return writeBytes(utf8.encode(value), withoutResponse: withoutResponse);
  }

  Future<void> writeJson(
    Map<String, dynamic> command, {
    bool appendNewLine = false,
    bool withoutResponse = false,
  }) {
    return writeText(
      jsonEncode(command),
      appendNewLine: appendNewLine,
      withoutResponse: withoutResponse,
    );
  }

  Future<SmartBrakeLightResponse> writeJsonAndWaitForResponse(
    Map<String, dynamic> command, {
    bool appendNewLine = true,
    bool withoutResponse = false,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final requestId = _readString(command, const [
      'requestId',
      'request_id',
      'messageId',
      'message_id',
      'id',
    ]);
    final commandName = _readString(command, const [
      'cmd',
      'command',
      'action',
    ]);

    if ((requestId == null || requestId.isEmpty) &&
        (commandName == null || commandName.isEmpty)) {
      throw ArgumentError(
        'Kommandoen skal indeholde requestId eller cmd/command.',
      );
    }

    final pending = _PendingBleResponse(
      requestId: requestId,
      command: commandName,
    );
    _pendingResponses.add(pending);

    try {
      await writeJson(
        command,
        appendNewLine: appendNewLine,
        withoutResponse: withoutResponse,
      );

      return await pending.completer.future.timeout(
        timeout,
        onTimeout: () {
          _pendingResponses.remove(pending);
          throw TimeoutException(
            'Intet svar fra BLE-enheden på kommandoen '
            '"${commandName ?? requestId}" inden for '
            '${timeout.inMilliseconds} ms.',
            timeout,
          );
        },
      );
    } catch (error) {
      _pendingResponses.remove(pending);
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
      rethrow;
    }
  }

  Future<SmartBrakeLightResponse> waitForResponse({
    String? requestId,
    String? command,
    Duration timeout = const Duration(seconds: 3),
  }) {
    if ((requestId == null || requestId.trim().isEmpty) &&
        (command == null || command.trim().isEmpty)) {
      throw ArgumentError('requestId eller command skal angives.');
    }

    final pending = _PendingBleResponse(
      requestId: requestId?.trim(),
      command: command?.trim(),
    );
    _pendingResponses.add(pending);

    return pending.completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingResponses.remove(pending);
        throw TimeoutException(
          'Intet matchende BLE-svar blev modtaget inden for '
          '${timeout.inMilliseconds} ms.',
          timeout,
        );
      },
    );
  }

  void handleNotificationBytes(List<int> value) {
    if (_disposed || value.isEmpty) return;

    final raw = utf8.decode(value, allowMalformed: true);

    handleNotificationText(raw);
  }

  void handleNotificationText(String raw) {
    if (_disposed) return;

    final normalized = raw.replaceAll('\u0000', '').replaceAll('\r', '').trim();
    if (normalized.isEmpty) return;

    _lastRawMessage = normalized;
    _lastMessageAt = DateTime.now();

    try {
      final response = SmartBrakeLightResponse.parse(
        normalized,
        receivedAt: _lastMessageAt,
      );

      _lastResponse = response;
      _publishResponse(response);

      final parsedData = <String, dynamic>{
        ...response.rawData,
        ...response.toJson(),
      };

      _applyParsedData(parsedData, normalized);
      _setError(response.hasError ? response.errorMessage : null);
    } catch (error, stackTrace) {
      debugPrint(
        'DigitalTwinBleService parse error: '
        '$error\n$stackTrace',
      );

      _setError('BLE-data kunne ikke læses: $error');
      _updateProduct(
        metadata: {
          'lastBleMessage': normalized,
          'lastBleParseError': error.toString(),
          'lastBleParseErrorAt': DateTime.now().toIso8601String(),
        },
      );
    }

    _notify();
  }

  void _handleConnectionState(BluetoothConnectionState state) {
    if (_disposed || _isDisconnecting) return;

    if (state == BluetoothConnectionState.connected) {
      _updateProduct(
        connectionStatus: BikeProductConnectionStatus.connected,
        metadata: {'connectedAt': DateTime.now().toIso8601String()},
      );
      return;
    }

    if (state == BluetoothConnectionState.disconnected) {
      _stopRssiTimer();
      _failPendingResponses(StateError('Bluetooth-enheden blev afbrudt.'));
      _updateProduct(
        connectionStatus: BikeProductConnectionStatus.disconnected,
        clearRssi: true,
        metadata: {'disconnectedAt': DateTime.now().toIso8601String()},
      );
    }
  }

  void _applyParsedData(Map<String, dynamic> data, String rawMessage) {
    final product = _currentProduct;
    if (product == null) return;

    final battery = _readInt(data, const [
      'battery',
      'batteryLevel',
      'battery_level',
      'bat',
      'batt',
    ]);

    final rssi = _readInt(data, const [
      'rssi',
      'signal',
      'signalStrength',
      'signal_strength',
    ]);

    final firmware = _readString(data, const [
      'firmware',
      'firmwareVersion',
      'firmware_version',
      'fw',
      'version',
    ]);

    final latestFirmware = _readString(data, const [
      'latestFirmware',
      'latestFirmwareVersion',
      'latest_firmware',
      'latest_fw',
    ]);

    final metadata = Map<String, dynamic>.from(product.metadata)
      ..addAll(_sanitize(data))
      ..addAll({
        'lastBleMessage': rawMessage,
        'lastBleMessageAt': DateTime.now().toIso8601String(),
        'bleDeviceId': _device?.remoteId.str,
        'bleDeviceName': _device?.platformName,
      });

    final brake = _readBool(data, const [
      'brake',
      'braking',
      'brakeActive',
      'brake_active',
    ]);

    final brightness = _readInt(data, const [
      'brightness',
      'pwm',
      'led',
      'ledBrightness',
      'led_brightness',
    ]);

    final sensitivity = _readDouble(data, const [
      'sensitivity',
      'brakeSensitivity',
      'brake_sensitivity',
      'bs',
    ]);

    final temperature = _readDouble(data, const [
      'temperature',
      'temp',
      'temperatureC',
      'temperature_c',
    ]);

    final ledMode = _readString(data, const ['ledMode', 'led_mode', 'mode']);

    if (brake != null) {
      metadata['brakeActive'] = brake;
    }

    if (brightness != null) {
      metadata['brightness'] = brightness.clamp(0, 100);
    }

    if (sensitivity != null) {
      metadata['sensitivity'] = sensitivity;
    }

    if (temperature != null) {
      metadata['temperatureC'] = temperature;
    }

    if (ledMode != null && ledMode.isNotEmpty) {
      metadata['ledMode'] = ledMode;
    }

    _digitalTwinProvider.updateProduct(
      product.copyWith(
        connectionStatus: BikeProductConnectionStatus.connected,
        batteryLevel: battery?.clamp(0, 100),
        rssi: rssi,
        firmwareVersion: firmware == null || firmware.isEmpty ? null : firmware,
        latestFirmwareVersion: latestFirmware == null || latestFirmware.isEmpty
            ? null
            : latestFirmware,
        metadata: metadata,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Map<String, dynamic> _parseMessage(String raw) {
    final trimmed = raw.trim();

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      final decoded = jsonDecode(trimmed);

      if (decoded is Map) {
        return decoded.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    }

    final result = <String, dynamic>{};
    final parts = trimmed.split(RegExp(r'[;,\n|]+'));

    for (final part in parts) {
      final item = part.trim();
      if (item.isEmpty) continue;

      final equalsIndex = item.indexOf('=');
      final colonIndex = item.indexOf(':');

      int separatorIndex;

      if (equalsIndex < 0) {
        separatorIndex = colonIndex;
      } else if (colonIndex < 0) {
        separatorIndex = equalsIndex;
      } else {
        separatorIndex = equalsIndex < colonIndex ? equalsIndex : colonIndex;
      }

      if (separatorIndex <= 0) continue;

      final key = item.substring(0, separatorIndex).trim();
      final value = item.substring(separatorIndex + 1).trim();

      if (key.isNotEmpty) {
        result[key] = _parseScalar(value);
      }
    }

    return result;
  }

  dynamic _parseScalar(String value) {
    final normalized = value.trim();
    final lower = normalized.toLowerCase();

    if (lower == 'true' || lower == 'on' || lower == 'yes') {
      return true;
    }

    if (lower == 'false' || lower == 'off' || lower == 'no') {
      return false;
    }

    if (lower == 'null') return null;

    return int.tryParse(normalized) ??
        double.tryParse(normalized) ??
        normalized;
  }

  BikeProduct? get _currentProduct {
    final id = _productId;

    if (id == null || id.isEmpty) {
      return null;
    }

    return _digitalTwinProvider.productById(id);
  }

  void _updateProduct({
    BikeProductConnectionStatus? connectionStatus,
    int? batteryLevel,
    bool clearBatteryLevel = false,
    int? rssi,
    bool clearRssi = false,
    String? firmwareVersion,
    String? latestFirmwareVersion,
    Map<String, dynamic>? metadata,
  }) {
    final product = _currentProduct;
    if (product == null) return;

    final mergedMetadata = Map<String, dynamic>.from(product.metadata);

    if (metadata != null) {
      mergedMetadata.addAll(_sanitize(metadata));
    }

    _digitalTwinProvider.updateProduct(
      product.copyWith(
        connectionStatus: connectionStatus ?? product.connectionStatus,
        batteryLevel: batteryLevel,
        clearBatteryLevel: clearBatteryLevel,
        rssi: rssi,
        clearRssi: clearRssi,
        firmwareVersion: firmwareVersion,
        latestFirmwareVersion: latestFirmwareVersion,
        metadata: mergedMetadata,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _publishResponse(SmartBrakeLightResponse response) {
    if (!_responseController.isClosed) {
      _responseController.add(response);
    }
    _resolvePendingResponse(response);
  }

  void _resolvePendingResponse(SmartBrakeLightResponse response) {
    if (_pendingResponses.isEmpty) return;

    _PendingBleResponse? match;
    for (final pending in List<_PendingBleResponse>.from(_pendingResponses)) {
      if (pending.matches(response)) {
        match = pending;
        break;
      }
    }

    if (match == null) return;
    _pendingResponses.remove(match);

    if (!match.completer.isCompleted) {
      if (response.hasError) {
        match.completer.completeError(
          StateError(
            response.errorMessage ??
                response.errorCode ??
                'BLE-enheden afviste kommandoen.',
          ),
        );
      } else {
        match.completer.complete(response);
      }
    }
  }

  void _failPendingResponses(Object error) {
    if (_pendingResponses.isEmpty) return;

    final pendingResponses = List<_PendingBleResponse>.from(_pendingResponses);
    _pendingResponses.clear();

    for (final pending in pendingResponses) {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(error);
      }
    }
  }

  void _startRssiTimer() {
    _stopRssiTimer();

    _rssiTimer = Timer.periodic(rssiInterval, (_) => unawaited(refreshRssi()));
  }

  void _stopRssiTimer() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  Future<void> _safeDisconnectDevice() async {
    final device = _device;

    if (device == null || !device.isConnected) {
      return;
    }

    try {
      await device.disconnect();
    } catch (error) {
      debugPrint('DigitalTwinBleService disconnect error: $error');
    }
  }

  int? _readInt(Map<String, dynamic> data, List<String> keys) {
    final value = _readValue(data, keys);

    if (value is int) return value;
    if (value is num) return value.round();

    if (value is String) {
      return int.tryParse(value.replaceAll('%', '').trim());
    }

    return null;
  }

  double? _readDouble(Map<String, dynamic> data, List<String> keys) {
    final value = _readValue(data, keys);

    if (value is num) return value.toDouble();

    if (value is String) {
      return double.tryParse(
        value.replaceAll('°C', '').replaceAll('%', '').trim(),
      );
    }

    return null;
  }

  String? _readString(Map<String, dynamic> data, List<String> keys) {
    final value = _readValue(data, keys);
    return value?.toString().trim();
  }

  bool? _readBool(Map<String, dynamic> data, List<String> keys) {
    final value = _readValue(data, keys);

    if (value is bool) return value;
    if (value is num) return value != 0;

    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case '1':
        case 'true':
        case 'on':
        case 'yes':
        case 'active':
          return true;

        case '0':
        case 'false':
        case 'off':
        case 'no':
        case 'inactive':
          return false;
      }
    }

    return null;
  }

  dynamic _readValue(Map<String, dynamic> data, List<String> keys) {
    final normalizedKeys = keys.map(_normalizeKey).toSet();

    for (final entry in data.entries) {
      if (normalizedKeys.contains(_normalizeKey(entry.key))) {
        return entry.value;
      }
    }

    return null;
  }

  Map<String, dynamic> _sanitize(Map<String, dynamic> input) {
    final output = <String, dynamic>{};

    for (final entry in input.entries) {
      final value = entry.value;

      if (value == null || value is String || value is num || value is bool) {
        output[entry.key] = value;
      } else if (value is DateTime) {
        output[entry.key] = value.toIso8601String();
      } else if (value is List) {
        output[entry.key] = value
            .map(
              (item) =>
                  item is String || item is num || item is bool || item == null
                  ? item
                  : item.toString(),
            )
            .toList(growable: false);
      } else {
        output[entry.key] = value.toString();
      }
    }

    return output;
  }

  String _normalizeUuid(String value) {
    return value.trim().toLowerCase().replaceAll('{', '').replaceAll('}', '');
  }

  String _normalizeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _setError(String? value) {
    if (_errorMessage == value) return;

    _errorMessage = value;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;

    _disposed = true;
    _stopRssiTimer();
    _failPendingResponses(StateError('DigitalTwinBleService blev lukket.'));

    unawaited(_notificationSubscription?.cancel());
    unawaited(_connectionSubscription?.cancel());

    final notifyCharacteristic = _notifyCharacteristic;

    if (notifyCharacteristic != null && notifyCharacteristic.isNotifying) {
      unawaited(notifyCharacteristic.setNotifyValue(false));
    }

    final device = _device;

    if (device != null && device.isConnected) {
      unawaited(device.disconnect());
    }

    _notificationSubscription = null;
    _connectionSubscription = null;
    _notifyCharacteristic = null;
    _writeCharacteristic = null;
    _device = null;

    unawaited(_responseController.close());

    super.dispose();
  }
}

class _PendingBleResponse {
  _PendingBleResponse({this.requestId, this.command});

  final String? requestId;
  final String? command;
  final Completer<SmartBrakeLightResponse> completer =
      Completer<SmartBrakeLightResponse>();

  bool matches(SmartBrakeLightResponse response) {
    final expectedRequestId = requestId?.trim().toLowerCase();
    final responseRequestId = response.requestId?.trim().toLowerCase();

    if (expectedRequestId != null && expectedRequestId.isNotEmpty) {
      return responseRequestId == expectedRequestId;
    }

    final expectedCommand = command?.trim().toLowerCase();
    final responseCommand = response.command?.trim().toLowerCase();

    return expectedCommand != null &&
        expectedCommand.isNotEmpty &&
        responseCommand == expectedCommand;
  }
}
