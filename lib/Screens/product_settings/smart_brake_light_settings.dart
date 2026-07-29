import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/munja_colors.dart';
import '../../models/bike_product.dart';
import '../../providers/digital_twin_provider.dart';
import '../../services/bluetooth/digital_twin_ble_service.dart';

/// Full settings page for the Munja Smart Brake Light.
///
/// The page:
/// - Reads the latest product state from [DigitalTwinProvider]
/// - Sends commands through [DigitalTwinBleService]
/// - Keeps local settings synchronized with the Digital Twin product
/// - Disables hardware controls when BLE write access is unavailable
class SmartBrakeLightSettings extends StatefulWidget {
  const SmartBrakeLightSettings({super.key, required this.productId});

  final String productId;

  @override
  State<SmartBrakeLightSettings> createState() =>
      _SmartBrakeLightSettingsState();
}

class _SmartBrakeLightSettingsState extends State<SmartBrakeLightSettings> {
  static const List<_FlashPatternOption> _patterns = <_FlashPatternOption>[
    _FlashPatternOption(
      id: 'solid',
      label: 'Konstant',
      description: 'Et stabilt og konstant lys.',
      icon: Icons.light_mode_rounded,
    ),
    _FlashPatternOption(
      id: 'pulse',
      label: 'Pulse',
      description: 'Rolig pulsering med bløde overgange.',
      icon: Icons.blur_on_rounded,
    ),
    _FlashPatternOption(
      id: 'flash',
      label: 'Flash',
      description: 'Tydelige blink for høj synlighed.',
      icon: Icons.flash_on_rounded,
    ),
    _FlashPatternOption(
      id: 'emergency',
      label: 'Emergency',
      description: 'Hurtigt advarselsmønster.',
      icon: Icons.warning_amber_rounded,
    ),
  ];

  Timer? _brightnessDebounce;
  Timer? _sensitivityDebounce;

  bool _initialized = false;
  bool _sending = false;
  String? _activeCommand;
  String? _pageError;

  double _brightness = 80;
  double _sensitivity = 70;
  String _flashPattern = 'pulse';
  bool _autoOn = true;
  bool _autoOff = true;
  bool _brakeLightEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) {
      return;
    }

    final provider = context.read<DigitalTwinProvider>();
    final product = provider.productById(widget.productId);

    if (product != null) {
      _loadSettings(product);
    }

    _initialized = true;
  }

  @override
  void dispose() {
    _brightnessDebounce?.cancel();
    _sensitivityDebounce?.cancel();
    super.dispose();
  }

  void _loadSettings(BikeProduct product) {
    final settings = product.settings;
    final metadata = product.metadata;

    _brightness = _readNumber(settings, metadata, const <String>[
      'brightness',
      'ledBrightness',
    ], fallback: 80).clamp(0, 100);

    _sensitivity = _readNumber(settings, metadata, const <String>[
      'sensitivity',
      'brakeSensitivity',
    ], fallback: 70).clamp(0, 100);

    _flashPattern =
        _readString(settings, metadata, const <String>[
          'flashPattern',
          'pattern',
          'lightMode',
        ]) ??
        'pulse';

    if (!_patterns.any((item) => item.id == _flashPattern)) {
      _flashPattern = 'pulse';
    }

    _autoOn = _readBool(settings, metadata, const <String>[
      'autoOn',
      'automaticOn',
    ], fallback: true);

    _autoOff = _readBool(settings, metadata, const <String>[
      'autoOff',
      'automaticOff',
    ], fallback: true);

    _brakeLightEnabled = _readBool(settings, metadata, const <String>[
      'enabled',
      'brakeLightEnabled',
      'ledEnabled',
    ], fallback: product.isEnabled);
  }

  Future<void> _sendCommand({
    required String action,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? localSettings,
    bool showSuccess = false,
  }) async {
    if (_sending) {
      return;
    }

    final bleService = context.read<DigitalTwinBleService>();

    if (!bleService.isConnected || bleService.writeCharacteristic == null) {
      _showMessage(
        'Forbind Smart Brake Light, før du ændrer indstillinger.',
        error: true,
      );
      return;
    }

    setState(() {
      _sending = true;
      _activeCommand = action;
      _pageError = null;
    });

    try {
      await bleService.writeJson(<String, dynamic>{
        'product': 'smart_brake_light',
        'action': action,
        ...payload,
      });

      if (localSettings != null && mounted) {
        _updateLocalProductSettings(localSettings);
      }

      if (showSuccess && mounted) {
        _showMessage('Kommandoen blev sendt til produktet.');
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _pageError = error.toString();
      });

      _showMessage('Kommandoen kunne ikke sendes: $error', error: true);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _activeCommand = null;
        });
      }
    }
  }

  void _updateLocalProductSettings(Map<String, dynamic> values) {
    final provider = context.read<DigitalTwinProvider>();
    final product = provider.productById(widget.productId);

    if (product == null) {
      return;
    }

    final settings = Map<String, dynamic>.from(product.settings)
      ..addAll(values);

    provider.updateProduct(
      product.copyWith(
        settings: settings,
        isEnabled: values['enabled'] is bool
            ? values['enabled'] as bool
            : product.isEnabled,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _scheduleBrightness(double value) {
    setState(() {
      _brightness = value;
    });

    _brightnessDebounce?.cancel();
    _brightnessDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(
        _sendCommand(
          action: 'set_brightness',
          payload: <String, dynamic>{'brightness': value.round()},
          localSettings: <String, dynamic>{'brightness': value.round()},
        ),
      );
    });
  }

  void _scheduleSensitivity(double value) {
    setState(() {
      _sensitivity = value;
    });

    _sensitivityDebounce?.cancel();
    _sensitivityDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(
        _sendCommand(
          action: 'set_sensitivity',
          payload: <String, dynamic>{'sensitivity': value.round()},
          localSettings: <String, dynamic>{'sensitivity': value.round()},
        ),
      );
    });
  }

  Future<void> _setPattern(String pattern) async {
    final previous = _flashPattern;

    setState(() {
      _flashPattern = pattern;
    });

    try {
      await _sendCommand(
        action: 'set_flash_pattern',
        payload: <String, dynamic>{'flashPattern': pattern},
        localSettings: <String, dynamic>{'flashPattern': pattern},
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _flashPattern = previous;
        });
      }
    }
  }

  Future<void> _setAutoOn(bool value) async {
    final previous = _autoOn;

    setState(() {
      _autoOn = value;
    });

    try {
      await _sendCommand(
        action: 'set_auto_on',
        payload: <String, dynamic>{'autoOn': value},
        localSettings: <String, dynamic>{'autoOn': value},
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _autoOn = previous;
        });
      }
    }
  }

  Future<void> _setAutoOff(bool value) async {
    final previous = _autoOff;

    setState(() {
      _autoOff = value;
    });

    try {
      await _sendCommand(
        action: 'set_auto_off',
        payload: <String, dynamic>{'autoOff': value},
        localSettings: <String, dynamic>{'autoOff': value},
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _autoOff = previous;
        });
      }
    }
  }

  Future<void> _setEnabled(bool value) async {
    final previous = _brakeLightEnabled;

    setState(() {
      _brakeLightEnabled = value;
    });

    try {
      await _sendCommand(
        action: 'set_enabled',
        payload: <String, dynamic>{'enabled': value},
        localSettings: <String, dynamic>{'enabled': value},
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _brakeLightEnabled = previous;
        });
      }
    }
  }

  Future<void> _testLight() {
    return _sendCommand(
      action: 'test_light',
      payload: const <String, dynamic>{'durationMs': 3000},
      showSuccess: true,
    );
  }

  Future<void> _requestStatus() {
    return _sendCommand(
      action: 'request_status',
      payload: const <String, dynamic>{},
      showSuccess: true,
    );
  }

  Future<void> _restartDevice() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MunjaColors.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Text(
            'Genstart produktet?',
            style: TextStyle(
              color: MunjaColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Bluetooth-forbindelsen kan blive afbrudt i nogle sekunder.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.58),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ANNULLER'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('GENSTART'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    await _sendCommand(
      action: 'restart',
      payload: const <String, dynamic>{},
      showSuccess: true,
    );
  }

  Future<void> _startFirmwareUpdate(BikeProduct product) async {
    if (!product.hasFirmwareUpdate) {
      _showMessage('Produktet har allerede den nyeste firmware.');
      return;
    }

    await _sendCommand(
      action: 'start_firmware_update',
      payload: <String, dynamic>{
        'currentVersion': product.firmwareVersion,
        'targetVersion': product.latestFirmwareVersion,
      },
      showSuccess: true,
    );
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: error
              ? const Color(0xFF5B181D)
              : const Color(0xFF102E25),
          behavior: SnackBarBehavior.floating,
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<DigitalTwinProvider, DigitalTwinBleService>(
      builder: (context, digitalTwinProvider, bleService, _) {
        final product = digitalTwinProvider.productById(widget.productId);

        if (product == null) {
          return const _MissingProductPage();
        }

        final connectedToProduct =
            bleService.isConnected && bleService.productId == product.id;
        final canWrite =
            connectedToProduct && bleService.writeCharacteristic != null;
        final battery = product.safeBatteryLevel;
        final temperature = _readOptionalNumber(
          product.metadata,
          const <String>['temperatureCelsius', 'temperature', 'temp'],
        );
        final charging = _readOptionalBool(product.metadata, const <String>[
          'charging',
          'isCharging',
        ]);

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: MunjaColors.bg,
            foregroundColor: MunjaColors.text,
            titleSpacing: 4,
            title: const Text(
              'Smart Brake Light',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            actions: [
              IconButton(
                tooltip: 'Hent produktstatus',
                onPressed: canWrite && !_sending ? _requestStatus : null,
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              children: [
                _ProductHeroCard(
                  product: product,
                  connected: connectedToProduct,
                  canWrite: canWrite,
                  battery: battery,
                  temperature: temperature,
                  charging: charging,
                ),
                if (!canWrite) ...[
                  const SizedBox(height: 12),
                  const _ConnectionWarning(),
                ],
                if (_pageError != null) ...[
                  const SizedBox(height: 12),
                  _ErrorBanner(
                    message: _pageError!,
                    onClose: () {
                      setState(() {
                        _pageError = null;
                      });
                    },
                  ),
                ],
                const SizedBox(height: 20),
                _SectionHeader(
                  eyebrow: 'LYS',
                  title: 'Lys og synlighed',
                  description: 'Tilpas lysstyrke og det normale lysmønster.',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _MasterSwitch(
                      value: _brakeLightEnabled,
                      enabled: canWrite && !_sending,
                      onChanged: _setEnabled,
                    ),
                    const _SettingsDivider(),
                    _SliderSetting(
                      icon: Icons.brightness_6_rounded,
                      title: 'Lysstyrke',
                      description:
                          'Juster styrken på det normale baglygte-lys.',
                      value: _brightness,
                      valueLabel: '${_brightness.round()}%',
                      enabled: canWrite && !_sending,
                      onChanged: _scheduleBrightness,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  eyebrow: 'BREMSE',
                  title: 'Bremseregistrering',
                  description:
                      'Bestem hvor hurtigt lygten reagerer på opbremsning.',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SliderSetting(
                      icon: Icons.speed_rounded,
                      title: 'Bremsesensitivitet',
                      description: 'Højere værdi giver en hurtigere reaktion.',
                      value: _sensitivity,
                      valueLabel: '${_sensitivity.round()}%',
                      enabled: canWrite && !_sending,
                      onChanged: _scheduleSensitivity,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  eyebrow: 'MØNSTER',
                  title: 'Lysmønster',
                  description: 'Vælg hvordan lygten lyser under normal kørsel.',
                ),
                const SizedBox(height: 12),
                _PatternSelector(
                  patterns: _patterns,
                  selectedPattern: _flashPattern,
                  enabled: canWrite && !_sending,
                  onSelected: _setPattern,
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  eyebrow: 'AUTOMATIK',
                  title: 'Automatisk styring',
                  description: 'Lad produktet tænde og slukke automatisk.',
                ),
                const SizedBox(height: 12),
                _SettingsCard(
                  children: [
                    _SwitchSetting(
                      icon: Icons.wb_twilight_rounded,
                      title: 'Automatisk tænding',
                      description:
                          'Tænd lygten automatisk ved bevægelse eller mørke.',
                      value: _autoOn,
                      enabled: canWrite && !_sending,
                      onChanged: _setAutoOn,
                    ),
                    const _SettingsDivider(),
                    _SwitchSetting(
                      icon: Icons.timer_off_outlined,
                      title: 'Automatisk slukning',
                      description:
                          'Sluk lygten efter en periode uden bevægelse.',
                      value: _autoOff,
                      enabled: canWrite && !_sending,
                      onChanged: _setAutoOff,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  eyebrow: 'TEST',
                  title: 'Produktkontrol',
                  description: 'Test lyset eller genstart den fysiske enhed.',
                ),
                const SizedBox(height: 12),
                _ActionGrid(
                  busyAction: _activeCommand,
                  enabled: canWrite && !_sending,
                  onTest: _testLight,
                  onRefresh: _requestStatus,
                  onRestart: _restartDevice,
                ),
                const SizedBox(height: 18),
                _FirmwareCard(
                  product: product,
                  enabled: canWrite && !_sending,
                  updating: _activeCommand == 'start_firmware_update',
                  onUpdate: () => _startFirmwareUpdate(product),
                ),
                const SizedBox(height: 18),
                _DeviceInformationCard(
                  product: product,
                  bleService: bleService,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProductHeroCard extends StatelessWidget {
  const _ProductHeroCard({
    required this.product,
    required this.connected,
    required this.canWrite,
    required this.battery,
    required this.temperature,
    required this.charging,
  });

  final BikeProduct product;
  final bool connected;
  final bool canWrite;
  final int? battery;
  final double? temperature;
  final bool? charging;

  @override
  Widget build(BuildContext context) {
    final statusColor = connected ? MunjaColors.mint : Colors.white38;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: connected
              ? MunjaColors.mint.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.07),
        ),
        boxShadow: [
          if (connected)
            BoxShadow(
              color: MunjaColors.mint.withValues(alpha: 0.06),
              blurRadius: 30,
              offset: const Offset(0, 14),
            ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.17),
                  ),
                ),
                child: const Icon(
                  Icons.light_mode_rounded,
                  color: MunjaColors.mint,
                  size: 29,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      product.model.trim().isEmpty
                          ? 'Munja Smart Product'
                          : product.model.trim(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.43),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 31,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_disabled_rounded,
                      color: statusColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      connected ? 'FORBUNDET' : 'OFFLINE',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: charging == true
                      ? Icons.battery_charging_full_rounded
                      : Icons.battery_5_bar_rounded,
                  label: 'BATTERI',
                  value: battery == null ? '—' : '$battery%',
                  active: charging == true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.thermostat_rounded,
                  label: 'TEMPERATUR',
                  value: temperature == null
                      ? '—'
                      : '${_formatNumber(temperature!)} °C',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.edit_notifications_rounded,
                  label: 'KONTROL',
                  value: canWrite ? 'KLAR' : 'LÆS',
                  active: canWrite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final accent = active
        ? MunjaColors.mint
        : Colors.white.withValues(alpha: 0.56);

    return Container(
      height: 68,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 16),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.32),
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? MunjaColors.mint : MunjaColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionWarning extends StatelessWidget {
  const _ConnectionWarning();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Colors.amberAccent,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Indstillingerne kan ses, men produktet skal være forbundet '
              'med en write-characteristic for at kunne ændres.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.62),
                fontSize: 10,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 5, 11),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.67),
                fontSize: 10,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
            color: Colors.white38,
            iconSize: 18,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.description,
  });

  final String eyebrow;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: MunjaColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      indent: 16,
      endIndent: 16,
      color: Colors.white.withValues(alpha: 0.06),
    );
  }
}

class _MasterSwitch extends StatelessWidget {
  const _MasterSwitch({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return _SwitchSetting(
      icon: Icons.light_mode_rounded,
      title: 'Smart Brake Light',
      description: 'Slå produktets lys- og bremsefunktion til eller fra.',
      value: value,
      enabled: enabled,
      onChanged: onChanged,
      emphasize: true,
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  const _SwitchSetting({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.emphasize = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 14, 11, 14),
      child: Row(
        children: [
          Container(
            width: 39,
            height: 39,
            decoration: BoxDecoration(
              color: value
                  ? MunjaColors.mint.withValues(alpha: 0.10)
                  : Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              icon,
              color: value ? MunjaColors.mint : Colors.white38,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: emphasize && value
                        ? MunjaColors.mint
                        : MunjaColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 9,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: MunjaColors.mint,
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.valueLabel,
    required this.enabled,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final double value;
  final String valueLabel;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 15, 15, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: MunjaColors.mint, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 9,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 9),
              Container(
                constraints: const BoxConstraints(minWidth: 49),
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.16),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  valueLabel,
                  style: const TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: MunjaColors.mint,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
              thumbColor: MunjaColors.mint,
              overlayColor: MunjaColors.mint.withValues(alpha: 0.12),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(0, 100),
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PatternSelector extends StatelessWidget {
  const _PatternSelector({
    required this.patterns,
    required this.selectedPattern,
    required this.enabled,
    required this.onSelected,
  });

  final List<_FlashPatternOption> patterns;
  final String selectedPattern;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < patterns.length; index++) ...[
          _PatternTile(
            option: patterns[index],
            selected: selectedPattern == patterns[index].id,
            enabled: enabled,
            onTap: () => onSelected(patterns[index].id),
          ),
          if (index < patterns.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PatternTile extends StatelessWidget {
  const _PatternTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final _FlashPatternOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(21),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withValues(alpha: 0.08)
                : MunjaColors.panel.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: selected
                  ? MunjaColors.mint.withValues(alpha: 0.28)
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected
                      ? MunjaColors.mint.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  option.icon,
                  color: selected ? MunjaColors.mint : Colors.white38,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        color: selected ? MunjaColors.mint : MunjaColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      option.description,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.40),
                        fontSize: 9,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? MunjaColors.mint : Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? MunjaColors.mint : Colors.white24,
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF03110D),
                        size: 15,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.busyAction,
    required this.enabled,
    required this.onTest,
    required this.onRefresh,
    required this.onRestart,
  });

  final String? busyAction;
  final bool enabled;
  final VoidCallback onTest;
  final VoidCallback onRefresh;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 8) / 2;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: width,
              child: _ActionButton(
                icon: Icons.lightbulb_outline_rounded,
                label: 'TEST LYS',
                loading: busyAction == 'test_light',
                enabled: enabled,
                onPressed: onTest,
              ),
            ),
            SizedBox(
              width: width,
              child: _ActionButton(
                icon: Icons.sync_rounded,
                label: 'HENT STATUS',
                loading: busyAction == 'request_status',
                enabled: enabled,
                onPressed: onRefresh,
              ),
            ),
            SizedBox(
              width: constraints.maxWidth,
              child: _ActionButton(
                icon: Icons.restart_alt_rounded,
                label: 'GENSTART PRODUKT',
                loading: busyAction == 'restart',
                enabled: enabled,
                destructive: true,
                onPressed: onRestart,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.loading,
    required this.enabled,
    required this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool loading;
  final bool enabled;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : MunjaColors.mint;

    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: enabled && !loading ? onPressed : null,
        icon: loading
            ? SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.4,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor: color.withValues(alpha: 0.05),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.27),
          side: BorderSide(
            color: enabled
                ? color.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _FirmwareCard extends StatelessWidget {
  const _FirmwareCard({
    required this.product,
    required this.enabled,
    required this.updating,
    required this.onUpdate,
  });

  final BikeProduct product;
  final bool enabled;
  final bool updating;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final hasUpdate = product.hasFirmwareUpdate;
    final current = product.firmwareVersion.trim().isEmpty
        ? 'Ukendt'
        : product.firmwareVersion.trim();
    final latest = product.latestFirmwareVersion.trim().isEmpty
        ? current
        : product.latestFirmwareVersion.trim();
    final accent = hasUpdate ? Colors.amberAccent : MunjaColors.mint;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Firmware',
                      style: TextStyle(
                        color: MunjaColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasUpdate
                          ? 'En ny version er tilgængelig.'
                          : 'Produktet er opdateret.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.43),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  hasUpdate ? 'OPDATERING' : 'AKTUEL',
                  style: TextStyle(
                    color: accent,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: _FirmwareVersion(label: 'NUVÆRENDE', version: current),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white.withValues(alpha: 0.26),
                  size: 19,
                ),
              ),
              Expanded(
                child: _FirmwareVersion(
                  label: 'NYESTE',
                  version: latest,
                  active: hasUpdate,
                ),
              ),
            ],
          ),
          if (hasUpdate) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: enabled && !updating ? onUpdate : null,
                icon: updating
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF221A00),
                        ),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(
                  updating ? 'STARTER OPDATERING...' : 'OPDATER FIRMWARE',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  foregroundColor: const Color(0xFF221A00),
                  disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
                  disabledForegroundColor: Colors.white.withValues(alpha: 0.30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FirmwareVersion extends StatelessWidget {
  const _FirmwareVersion({
    required this.label,
    required this.version,
    this.active = false,
  });

  final String label;
  final String version;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active
              ? Colors.amberAccent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.31),
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            version,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? Colors.amberAccent : MunjaColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceInformationCard extends StatelessWidget {
  const _DeviceInformationCard({
    required this.product,
    required this.bleService,
  });

  final BikeProduct product;
  final DigitalTwinBleService bleService;

  @override
  Widget build(BuildContext context) {
    final deviceName = bleService.device?.platformName.trim().isNotEmpty == true
        ? bleService.device!.platformName.trim()
        : _metadataString(product.metadata, const <String>['bleDeviceName']) ??
              '—';
    final deviceId =
        bleService.device?.remoteId.str ??
        _metadataString(product.metadata, const <String>['bleDeviceId']) ??
        '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.67),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRODUKTINFORMATION',
            style: TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 13),
          _InformationRow(label: 'Produkt-ID', value: product.id),
          const _InformationDivider(),
          _InformationRow(label: 'Enhedsnavn', value: deviceName),
          const _InformationDivider(),
          _InformationRow(label: 'BLE-ID', value: deviceId),
          const _InformationDivider(),
          _InformationRow(
            label: 'Signal',
            value: product.rssi == null ? '—' : '${product.rssi} dBm',
          ),
          if (product.serialNumber.trim().isNotEmpty) ...[
            const _InformationDivider(),
            _InformationRow(
              label: 'Serienummer',
              value: product.serialNumber.trim(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.35),
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: MunjaColors.text,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InformationDivider extends StatelessWidget {
  const _InformationDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: Colors.white.withValues(alpha: 0.05));
  }
}

class _MissingProductPage extends StatelessWidget {
  const _MissingProductPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: MunjaColors.bg,
        foregroundColor: MunjaColors.text,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: Colors.white38,
                size: 52,
              ),
              const SizedBox(height: 16),
              const Text(
                'Produktet blev ikke fundet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MunjaColors.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Gå tilbage til Digital Twin og vælg Smart Brake Light igen.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.44),
                  fontSize: 11,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashPatternOption {
  const _FlashPatternOption({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
}

double _readNumber(
  Map<String, dynamic> settings,
  Map<String, dynamic> metadata,
  List<String> keys, {
  required double fallback,
}) {
  for (final source in <Map<String, dynamic>>[settings, metadata]) {
    for (final key in keys) {
      final value = source[key];

      if (value is num) {
        return value.toDouble();
      }

      if (value is String) {
        final parsed = double.tryParse(
          value.replaceAll('%', '').replaceAll(',', '.').trim(),
        );

        if (parsed != null) {
          return parsed;
        }
      }
    }
  }

  return fallback;
}

String? _readString(
  Map<String, dynamic> settings,
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  for (final source in <Map<String, dynamic>>[settings, metadata]) {
    for (final key in keys) {
      final value = source[key];

      if (value != null) {
        final normalized = value.toString().trim();

        if (normalized.isNotEmpty) {
          return normalized;
        }
      }
    }
  }

  return null;
}

bool _readBool(
  Map<String, dynamic> settings,
  Map<String, dynamic> metadata,
  List<String> keys, {
  required bool fallback,
}) {
  for (final source in <Map<String, dynamic>>[settings, metadata]) {
    for (final key in keys) {
      final parsed = _parseBool(source[key]);

      if (parsed != null) {
        return parsed;
      }
    }
  }

  return fallback;
}

double? _readOptionalNumber(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      final parsed = double.tryParse(
        value.replaceAll('°C', '').replaceAll(',', '.').trim(),
      );

      if (parsed != null) {
        return parsed;
      }
    }
  }

  final nested = source['lastBleData'];

  if (nested is Map) {
    for (final key in keys) {
      final value = nested[key];

      if (value is num) {
        return value.toDouble();
      }

      if (value is String) {
        final parsed = double.tryParse(
          value.replaceAll('°C', '').replaceAll(',', '.').trim(),
        );

        if (parsed != null) {
          return parsed;
        }
      }
    }
  }

  return null;
}

bool? _readOptionalBool(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final parsed = _parseBool(source[key]);

    if (parsed != null) {
      return parsed;
    }
  }

  final nested = source['lastBleData'];

  if (nested is Map) {
    for (final key in keys) {
      final parsed = _parseBool(nested[key]);

      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

bool? _parseBool(dynamic value) {
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
    'inactive',
    'disabled',
  }.contains(normalized)) {
    return false;
  }

  return null;
}

String? _metadataString(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];

    if (value != null) {
      final normalized = value.toString().trim();

      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
  }

  return null;
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }

  return value.toStringAsFixed(1);
}
