import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants/app_constants.dart';
import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../widgets/munja_card.dart';
import '../widgets/section_title.dart';
import '../widgets/stat_pill.dart';
import '../main.dart';

class BrakeLightDashboard extends StatefulWidget {
  final String? deviceId;

  const BrakeLightDashboard({super.key, this.deviceId});

  @override
  State<BrakeLightDashboard> createState() => _BrakeLightDashboardState();
}

class _BrakeLightDashboardState extends State<BrakeLightDashboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  BluetoothDevice? device;
  BluetoothCharacteristic? statusChar;
  BluetoothCharacteristic? configChar;

  StreamSubscription<BluetoothConnectionState>? connSub;
  StreamSubscription<List<int>>? statusSub;

  bool connecting = false;
  bool connected = false;
  bool brakeActive = false;

  int battery = 86;
  int brightness = 70;
  int sensitivity = 55;
  int rssi = -62;

  String firmware = '1.0.0';
  String mode = 'AUTO';

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    if (widget.deviceId != null) {
      _connect(widget.deviceId!);
    }
  }

  @override
  void dispose() {
    connSub?.cancel();
    statusSub?.cancel();
    _pulseCtrl.dispose();
    device?.disconnect();
    super.dispose();
  }

  Future<void> _connect(String id) async {
    if (connecting) return;

    setState(() => connecting = true);

    try {
      device = BluetoothDevice.fromId(id);

      connSub = device!.connectionState.listen((state) {
        if (!mounted) return;
        setState(() {
          connected = state == BluetoothConnectionState.connected;
        });
      });

      await device!.connect(timeout: const Duration(seconds: 8));

      final services = await device!.discoverServices();

      for (final service in services) {
        for (final c in service.characteristics) {
          final uuid = c.uuid.str.toLowerCase();

          if (uuid == statusCharUuid.toLowerCase()) {
            statusChar = c;
          }

          if (uuid == configCharUuid.toLowerCase()) {
            configChar = c;
          }
        }
      }

      if (statusChar != null) {
        await statusChar!.setNotifyValue(true);

        statusSub = statusChar!.lastValueStream.listen((value) {
          final raw = String.fromCharCodes(value);
          _parseStatus(raw);
        });
      }

      await _readRssi();
    } catch (_) {
      if (!mounted) return;
      setState(() => connected = false);
    }

    if (mounted) {
      setState(() => connecting = false);
    }
  }

  Future<void> _readRssi() async {
    try {
      final value = await device?.readRssi();
      if (value != null && mounted) {
        setState(() => rssi = value);
      }
    } catch (_) {}
  }

  void _parseStatus(String raw) {
    final parts = raw.split(';');
    final map = <String, String>{};

    for (final p in parts) {
      if (!p.contains('=')) continue;
      final split = p.split('=');
      if (split.length == 2) {
        map[split[0].trim().toUpperCase()] = split[1].trim();
      }
    }

    if (!mounted) return;

    setState(() {
      brakeActive = map['BRAKE'] == '1';

      battery = int.tryParse(map['BAT'] ?? '') ?? battery;
      brightness = int.tryParse(map['BRI'] ?? '') ?? brightness;
      sensitivity = int.tryParse(map['SENS'] ?? '') ?? sensitivity;
      firmware = map['FW'] ?? firmware;
      mode = map['MODE'] ?? mode;
    });
  }

  Future<void> _sendConfig() async {
    if (configChar == null) return;

    final command = 'BRI=$brightness;SENS=$sensitivity;MODE=$mode;';

    try {
      await configChar!.write(command.codeUnits, withoutResponse: false);
    } catch (_) {}
  }

  Color get _connectionColor {
    if (connected) return MunjaColors.success;
    if (connecting) return MunjaColors.warning;
    return MunjaColors.danger;
  }

  String get _connectionText {
    if (connected) return AppText.t('connected');
    if (connecting) return AppText.t('connecting');
    return AppText.t('disconnected');
  }

  String get _signalText {
    if (rssi >= -55) return AppText.t('veryClose');
    if (rssi >= -70) return AppText.t('nearby');
    return AppText.t('farAway');
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: AppText.t('smartBrakeLight'),
      actions: [
        IconButton(
          onPressed: _readRssi,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title: AppText.t('brakeLightDashboard'),
                  subtitle: AppText.t('brakeLightDashboardSubtitle'),
                ),
                const SizedBox(height: 20),

                Center(
                  child: AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) {
                      final scale = brakeActive
                          ? 1.0 + (_pulseCtrl.value * 0.03)
                          : 1.0;

                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: MunjaColors.panelSoft,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: brakeActive
                                    ? Colors.redAccent.withOpacity(0.35)
                                    : MunjaColors.mint.withOpacity(0.12),
                                blurRadius: brakeActive ? 40 : 18,
                                spreadRadius: brakeActive ? 6 : 1,
                              ),
                            ],
                            border: Border.all(
                              color: brakeActive
                                  ? Colors.redAccent
                                  : MunjaColors.mintStrong.withOpacity(0.25),
                            ),
                          ),
                          child: Image.asset(
                            'assets/brake_light.jpeg',
                            height: 220,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 18),

                Center(
                  child: Text(
                    brakeActive
                        ? AppText.t('brakingNow')
                        : AppText.t('brakeReady'),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: brakeActive ? Colors.redAccent : MunjaColors.mint,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MunjaColors.panelSoft,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _connectionColor.withOpacity(0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        connected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        color: _connectionColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _connectionText,
                          style: TextStyle(
                            color: _connectionColor,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Text(
                        '$rssi dBm',
                        style: const TextStyle(color: MunjaColors.textSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              StatPill(
                icon: Icons.battery_full_rounded,
                iconColor: battery > 25
                    ? MunjaColors.success
                    : MunjaColors.danger,
                label: AppText.t('battery'),
                value: '$battery%',
              ),
              const SizedBox(width: 10),
              StatPill(
                icon: Icons.wifi_tethering_rounded,
                label: AppText.t('signal'),
                value: _signalText,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              StatPill(
                icon: Icons.memory_rounded,
                label: AppText.t('firmware'),
                value: firmware,
              ),
              const SizedBox(width: 10),
              StatPill(
                icon: Icons.auto_mode_rounded,
                label: AppText.t('mode'),
                value: mode,
              ),
            ],
          ),

          const SizedBox(height: 16),

          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title: AppText.t('lightSettings'),
                  subtitle: AppText.t('lightSettingsSubtitle'),
                ),
                const SizedBox(height: 18),

                Text(
                  '${AppText.t('brightness')}: $brightness%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Slider(
                  min: 10,
                  max: 100,
                  divisions: 18,
                  value: brightness.toDouble(),
                  label: '$brightness%',
                  onChanged: (v) {
                    setState(() => brightness = v.round());
                  },
                  onChangeEnd: (_) => _sendConfig(),
                ),

                const SizedBox(height: 10),

                Text(
                  '${AppText.t('sensitivity')}: $sensitivity%',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Slider(
                  min: 10,
                  max: 100,
                  divisions: 18,
                  value: sensitivity.toDouble(),
                  label: '$sensitivity%',
                  onChanged: (v) {
                    setState(() => sensitivity = v.round());
                  },
                  onChangeEnd: (_) => _sendConfig(),
                ),

                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: mode,
                  decoration: InputDecoration(labelText: AppText.t('mode')),
                  items: const [
                    DropdownMenuItem(value: 'AUTO', child: Text('AUTO')),
                    DropdownMenuItem(value: 'CITY', child: Text('CITY')),
                    DropdownMenuItem(value: 'NIGHT', child: Text('NIGHT')),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setState(() => mode = value);
                    await _sendConfig();
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title: AppText.t('hardwareInfo'),
                  subtitle: AppText.t('hardwareInfoSubtitle'),
                ),
                const SizedBox(height: 14),

                _InfoRow(
                  icon: Icons.light_mode_rounded,
                  label: AppText.t('product'),
                  value: AppText.t('smartBrakeLight'),
                ),
                _InfoRow(
                  icon: Icons.bluetooth_rounded,
                  label: AppText.t('connection'),
                  value: _connectionText,
                ),
                _InfoRow(
                  icon: Icons.signal_cellular_alt_rounded,
                  label: AppText.t('rssi'),
                  value: '$rssi dBm',
                ),
                _InfoRow(
                  icon: Icons.memory_rounded,
                  label: AppText.t('firmware'),
                  value: firmware,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panelSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: MunjaColors.textSoft),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
