import 'package:flutter/foundation.dart';

import 'digital_twin_ble_service.dart';

/// Centralized BLE command layer for the Munja Smart Brake Light.
///
/// All commands used by the settings UI should go through this service.
/// This keeps the BLE protocol in one place, so future firmware changes
/// do not require changes across multiple UI files.
class SmartBrakeLightCommandService {
  const SmartBrakeLightCommandService(this._bleService);

  final DigitalTwinBleService _bleService;

  /// Returns true when a device is connected and a writable BLE
  /// characteristic is available.
  bool get canSendCommands =>
      _bleService.isConnected && _bleService.writeCharacteristic != null;

  /// Enables or disables the Smart Brake Light.
  Future<void> setEnabled(bool enabled) {
    return _sendCommand(<String, dynamic>{
      'cmd': 'set_enabled',
      'enabled': enabled,
    });
  }

  /// Changes LED brightness from 0 to 100 percent.
  Future<void> setBrightness(int value) {
    final normalizedValue = value.clamp(0, 100);

    return _sendCommand(<String, dynamic>{
      'cmd': 'set_brightness',
      'value': normalizedValue,
    });
  }

  /// Changes brake sensitivity from 0 to 100 percent.
  Future<void> setSensitivity(int value) {
    final normalizedValue = value.clamp(0, 100);

    return _sendCommand(<String, dynamic>{
      'cmd': 'set_sensitivity',
      'value': normalizedValue,
    });
  }

  /// Changes the active flash pattern.
  Future<void> setFlashPattern(String pattern) {
    final normalizedPattern = pattern.trim();

    if (normalizedPattern.isEmpty) {
      throw ArgumentError.value(
        pattern,
        'pattern',
        'Flashmønsteret må ikke være tomt.',
      );
    }

    return _sendCommand(<String, dynamic>{
      'cmd': 'set_flash_pattern',
      'pattern': normalizedPattern,
    });
  }

  /// Enables or disables automatic light activation.
  Future<void> setAutoOn(bool enabled) {
    return _sendCommand(<String, dynamic>{
      'cmd': 'set_auto_on',
      'enabled': enabled,
    });
  }

  /// Enables or disables automatic light deactivation.
  Future<void> setAutoOff(bool enabled) {
    return _sendCommand(<String, dynamic>{
      'cmd': 'set_auto_off',
      'enabled': enabled,
    });
  }

  /// Runs a temporary light test.
  Future<void> testLight() {
    return _sendCommand(<String, dynamic>{'cmd': 'test_light'});
  }

  /// Requests the latest product status from the device.
  Future<void> requestStatus() {
    return _sendCommand(<String, dynamic>{'cmd': 'get_status'});
  }

  /// Restarts the connected Smart Brake Light.
  Future<void> restart() {
    return _sendCommand(<String, dynamic>{'cmd': 'restart'});
  }

  /// Requests the device to enter firmware-update mode.
  Future<void> startFirmwareUpdate() {
    return _sendCommand(<String, dynamic>{'cmd': 'firmware_update'});
  }

  /// Sends a custom command.
  ///
  /// This should mainly be used while developing or testing new firmware
  /// commands that do not yet have a dedicated method.
  Future<void> sendRawCommand(Map<String, dynamic> payload) {
    if (payload.isEmpty) {
      throw ArgumentError.value(
        payload,
        'payload',
        'BLE-kommandoen må ikke være tom.',
      );
    }

    return _sendCommand(Map<String, dynamic>.from(payload));
  }

  Future<void> _sendCommand(Map<String, dynamic> payload) async {
    if (!canSendCommands) {
      throw StateError(
        'Smart Brake Light er ikke forbundet, eller enheden understøtter '
        'ikke BLE-skrivning.',
      );
    }

    debugPrint('SmartBrakeLightCommandService sending: $payload');

    await _bleService.writeJson(payload, appendNewLine: true);
  }
}
