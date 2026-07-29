import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/munja_device.dart';
import '../services/ble_service.dart';
import '../services/storage_service.dart';
import '../widgets/digital_twin/digital_twin.dart';
import '../widgets/digital_twin_bottom_sheet.dart';

class GearScreen extends StatefulWidget {
  const GearScreen({super.key});

  @override
  State<GearScreen> createState() => _GearScreenState();
}

class _GearScreenState extends State<GearScreen> {
  bool loading = true;
  bool scanning = false;

  List<MunjaDevice> savedDevices = [];
  List<MunjaDevice> nearbyDevices = [];

  static const double bottomWheelSafePadding = 360;

  bool get hasBrakeLight {
    return savedDevices.any(
          (device) => device.type == MunjaProductType.brakeLight,
        ) ||
        nearbyDevices.any(
          (device) => device.type == MunjaProductType.brakeLight,
        );
  }

  int get brakeBatteryPercent => hasBrakeLight ? 82 : 64;

  int get mountedProducts {
    var count = 0;
    if (hasBrakeLight) count++;
    return count;
  }

  String t(String key) => AppText.t(key);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await StorageService.loadSavedDevices();

      if (!mounted) return;

      setState(() {
        savedDevices = saved;
        loading = false;
      });

      await _scan();
    } catch (e) {
      debugPrint('GEAR LOAD ERROR: $e');

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    }
  }

  Future<void> _scan() async {
    if (scanning) return;

    setState(() {
      scanning = true;
    });

    try {
      final saved = await StorageService.loadSavedDevices();
      final nearby = await BleService.scanNearbyMunjaDevices(saved: saved);

      if (!mounted) return;

      setState(() {
        savedDevices = saved;
        nearbyDevices = nearby;
        scanning = false;
      });
    } catch (e) {
      debugPrint('GEAR SCAN ERROR: $e');

      if (!mounted) return;

      setState(() {
        scanning = false;
      });
    }
  }

  Future<void> _saveDevice(MunjaDevice device) async {
    await StorageService.saveDevice(device);

    HapticFeedback.selectionClick();

    await _load();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${device.name} ${t('savedToMyProducts')}'),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  void _openProductSheet({
    required String title,
    required bool installed,
    int batteryPercent = 0,
    String firmwareVersion = '1.0.0',
  }) {
    HapticFeedback.selectionClick();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DigitalTwinBottomSheet(
          title: title,
          batteryPercent: installed ? batteryPercent : 0,
          connected: installed,
          nightModeActive: installed,
          autoBrakeActive: installed,
          visibilityBoostPercent: installed ? 40 : 0,
          firmwareVersion: installed ? firmwareVersion : t('notInstalled'),
          onClose: () => Navigator.pop(context),
        );
      },
    );
  }

  void _showAddProductHint() {
    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('qrActivationComingSoon')),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(child: CircularProgressIndicator(color: MunjaColors.mint)),
      );
    }

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: MunjaColors.mint,
          backgroundColor: MunjaColors.panel,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              bottomWheelSafePadding,
            ),
            children: [
              _GarageHeader(
                title: t('garage'),
                subtitle: t('garageSubtitle'),
                scanning: scanning,
                onScan: _scan,
              ),

              const SizedBox(height: 18),

              _GarageHero(
                hasBrakeLight: hasBrakeLight,
                batteryPercent: brakeBatteryPercent,
                mountedProducts: mountedProducts,
                mountedLabel: t('mounted'),
                batteryLabel: t('battery'),
                readyLabel: t('ready'),
                activeLabel: t('active'),
                offLabel: t('off'),
                scanMountText: t('scanAndMountProducts'),
                brakeMountedText: t('brakeMountedOnBike'),
                onBikeTap: () {
                  _openProductSheet(
                    title: t('digitalTwin'),
                    installed: true,
                    batteryPercent: brakeBatteryPercent,
                    firmwareVersion: 'Munja Twin 1.0',
                  );
                },
                onBrakeLightTap: () {
                  _openProductSheet(
                    title: 'Smart Lighting Brake',
                    installed: hasBrakeLight,
                    batteryPercent: brakeBatteryPercent,
                  );
                },
              ),

              const SizedBox(height: 16),

              _AddProductCard(
                title: t('addProduct'),
                subtitle: t('scanBleQrLater'),
                scanLabel: t('scan'),
                scanningLabel: t('searching'),
                scanning: scanning,
                onScan: _scan,
                onAdd: _showAddProductHint,
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('mountedOnBike'),
                subtitle: t('mountedOnBikeSubtitle'),
                child: Column(
                  children: [
                    _GarageProductCard(
                      title: 'Smart Lighting Brake',
                      subtitle: hasBrakeLight
                          ? t('brakeMountedReady')
                          : t('brakeProductSubtitle'),
                      icon: Icons.light_mode_rounded,
                      mounted: hasBrakeLight,
                      batteryPercent: hasBrakeLight
                          ? brakeBatteryPercent
                          : null,
                      position: t('rear'),
                      activeLabel: t('active'),
                      offLabel: t('off'),
                      onTap: () {
                        _openProductSheet(
                          title: 'Smart Lighting Brake',
                          installed: hasBrakeLight,
                          batteryPercent: brakeBatteryPercent,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _GarageProductCard(
                      title: 'Smart Helmet',
                      subtitle: t('helmetProductSubtitle'),
                      icon: Icons.health_and_safety_rounded,
                      mounted: false,
                      batteryPercent: null,
                      position: t('helmet'),
                      activeLabel: t('active'),
                      offLabel: t('off'),
                      onTap: () {
                        _openProductSheet(
                          title: 'Smart Helmet',
                          installed: false,
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _GarageProductCard(
                      title: 'Munja Band',
                      subtitle: t('bandProductSubtitle'),
                      icon: Icons.watch_rounded,
                      mounted: false,
                      batteryPercent: null,
                      position: t('wrist'),
                      activeLabel: t('active'),
                      offLabel: t('off'),
                      onTap: () {
                        _openProductSheet(
                          title: 'Munja Band',
                          installed: false,
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('nearby'),
                subtitle: scanning
                    ? t('scanningMunjaProducts')
                    : t('foundNearbyProducts'),
                child: nearbyDevices.isEmpty
                    ? _EmptyScanState(scanning: scanning, onScan: _scan)
                    : Column(
                        children: nearbyDevices.map((device) {
                          final alreadySaved = savedDevices.any(
                            (saved) => saved.id == device.id,
                          );

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DeviceTile(
                              device: device,
                              saved: alreadySaved,
                              savedText: t('saved'),
                              readyText: t('readyToMount'),
                              saveText: t('save'),
                              onSave: alreadySaved
                                  ? null
                                  : () => _saveDevice(device),
                            ),
                          );
                        }).toList(),
                      ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('savedProducts'),
                subtitle: t('savedProductsSubtitle'),
                child: savedDevices.isEmpty
                    ? const _EmptySavedState()
                    : Column(
                        children: savedDevices.map((device) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DeviceTile(
                              device: device,
                              saved: true,
                              savedText: t('saved'),
                              readyText: t('readyToMount'),
                              saveText: t('save'),
                              onSave: null,
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GarageHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool scanning;
  final VoidCallback onScan;

  const _GarageHeader({
    required this.title,
    required this.subtitle,
    required this.scanning,
    required this.onScan,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'MUNJA GARAGE',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 9),
              Text(
                subtitle,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        GestureDetector(
          onTap: scanning ? null : onScan,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: scanning
                  ? MunjaColors.mint.withOpacity(0.08)
                  : MunjaColors.mint.withOpacity(0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: MunjaColors.mint.withOpacity(0.24)),
            ),
            child: scanning
                ? const Padding(
                    padding: EdgeInsets.all(15),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MunjaColors.mint,
                    ),
                  )
                : const Icon(Icons.radar_rounded, color: MunjaColors.mint),
          ),
        ),
      ],
    );
  }
}

class _GarageHero extends StatelessWidget {
  final bool hasBrakeLight;
  final int batteryPercent;
  final int mountedProducts;
  final String mountedLabel;
  final String batteryLabel;
  final String readyLabel;
  final String activeLabel;
  final String offLabel;
  final String scanMountText;
  final String brakeMountedText;
  final VoidCallback onBikeTap;
  final VoidCallback onBrakeLightTap;

  const _GarageHero({
    required this.hasBrakeLight,
    required this.batteryPercent,
    required this.mountedProducts,
    required this.mountedLabel,
    required this.batteryLabel,
    required this.readyLabel,
    required this.activeLabel,
    required this.offLabel,
    required this.scanMountText,
    required this.brakeMountedText,
    required this.onBikeTap,
    required this.onBrakeLightTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _premiumDecoration(glow: true),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      child: Column(
        children: [
          Row(
            children: [
              _GarageStatusPill(
                label: 'Twin',
                value: readyLabel.toUpperCase(),
                active: true,
              ),
              const SizedBox(width: 8),
              _GarageStatusPill(
                label: mountedLabel,
                value: '$mountedProducts',
                active: mountedProducts > 0,
              ),
              const SizedBox(width: 8),
              _GarageStatusPill(
                label: batteryLabel,
                value: '$batteryPercent%',
                active: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 350,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: onBikeTap,
                    child: DigitalTwin(
                      isLive: false,
                      brakeLightConnected: hasBrakeLight,
                      brakeLightBattery: batteryPercent.toDouble(),
                      onBikeTap: onBikeTap,
                      onBrakeLightTap: onBrakeLightTap,
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 74,
                  child: _MountedBadge(
                    label: 'HELMET',
                    active: false,
                    icon: Icons.health_and_safety_rounded,
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 102,
                  child: GestureDetector(
                    onTap: onBrakeLightTap,
                    child: _MountedBadge(
                      label: 'BRAKE',
                      active: hasBrakeLight,
                      icon: Icons.light_mode_rounded,
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 80,
                  child: _MountedBadge(
                    label: 'BAND',
                    active: false,
                    icon: Icons.watch_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            hasBrakeLight ? brakeMountedText : scanMountText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MountedBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;

  const _MountedBadge({
    required this.label,
    required this.icon,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.16)
            : Colors.black.withOpacity(0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.42)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(0.16),
                  blurRadius: 22,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: active ? MunjaColors.mint : Colors.white38,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: active ? MunjaColors.mint : Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _GarageStatusPill extends StatelessWidget {
  final String label;
  final String value;
  final bool active;

  const _GarageStatusPill({
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: active
              ? MunjaColors.mint.withOpacity(0.12)
              : Colors.black.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? MunjaColors.mint.withOpacity(0.34)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? MunjaColors.mint : Colors.white38,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddProductCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String scanLabel;
  final String scanningLabel;
  final bool scanning;
  final VoidCallback onScan;
  final VoidCallback onAdd;

  const _AddProductCard({
    required this.title,
    required this.subtitle,
    required this.scanLabel,
    required this.scanningLabel,
    required this.scanning,
    required this.onScan,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _premiumDecoration(),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.13),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: MunjaColors.mint.withOpacity(0.22)),
            ),
            child: Icon(
              scanning ? Icons.radar_rounded : Icons.qr_code_scanner_rounded,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: scanning ? null : onScan,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: MunjaColors.mint,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                scanning ? scanningLabel : scanLabel,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _premiumDecoration(),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _GarageProductCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool mounted;
  final int? batteryPercent;
  final String position;
  final String activeLabel;
  final String offLabel;
  final VoidCallback onTap;

  const _GarageProductCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.mounted,
    required this.batteryPercent,
    required this.position,
    required this.activeLabel,
    required this.offLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = mounted ? MunjaColors.mint : Colors.white38;

    return Material(
      color: mounted
          ? MunjaColors.mint.withOpacity(0.12)
          : Colors.black.withOpacity(0.15),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: mounted
                  ? MunjaColors.mint.withOpacity(0.42)
                  : Colors.white.withOpacity(0.07),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: mounted
                      ? MunjaColors.mint.withOpacity(0.18)
                      : Colors.white.withOpacity(0.045),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: mounted ? Colors.white : Colors.white70,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: mounted
                                ? MunjaColors.mint.withOpacity(0.16)
                                : Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            position.toUpperCase(),
                            style: TextStyle(
                              color: mounted
                                  ? MunjaColors.mint
                                  : Colors.white38,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (batteryPercent != null) ...[
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (batteryPercent! / 100).clamp(0.0, 1.0),
                          minHeight: 7,
                          backgroundColor: Colors.white.withOpacity(0.08),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            MunjaColors.mint,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                mounted
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: mounted ? MunjaColors.mint : Colors.white30,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final MunjaDevice device;
  final bool saved;
  final String savedText;
  final String readyText;
  final String saveText;
  final VoidCallback? onSave;

  const _DeviceTile({
    required this.device,
    required this.saved,
    required this.savedText,
    required this.readyText,
    required this.saveText,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final isBrakeLight = device.type == MunjaProductType.brakeLight;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: saved
            ? MunjaColors.mint.withOpacity(0.10)
            : Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: saved
              ? MunjaColors.mint.withOpacity(0.35)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              isBrakeLight
                  ? Icons.light_mode_rounded
                  : Icons.devices_other_rounded,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  saved ? savedText : readyText,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (onSave == null)
            const Icon(Icons.check_circle_rounded, color: MunjaColors.mint)
          else
            GestureDetector(
              onTap: onSave,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: MunjaColors.mint,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  saveText,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyScanState extends StatelessWidget {
  final bool scanning;
  final VoidCallback onScan;

  const _EmptyScanState({required this.scanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    final title = scanning
        ? AppText.t('searching')
        : AppText.t('noProductsNearby');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          Icon(
            scanning ? Icons.radar_rounded : Icons.bluetooth_searching_rounded,
            color: MunjaColors.mint,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            AppText.t('appWorksWithoutHardware'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: scanning ? null : onScan,
              icon: const Icon(Icons.radar_rounded),
              label: Text(
                scanning ? AppText.t('searching') : AppText.t('scanAgain'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySavedState extends StatelessWidget {
  const _EmptySavedState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.inventory_2_rounded,
            color: MunjaColors.mint,
            size: 34,
          ),
          const SizedBox(height: 12),
          Text(
            AppText.t('noSavedProducts'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            AppText.t('savedProductsAppearHere'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _premiumDecoration({bool glow = false}) {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.86),
    borderRadius: BorderRadius.circular(32),
    border: Border.all(color: Colors.white.withOpacity(0.075)),
    boxShadow: glow
        ? [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(0.16),
              blurRadius: 44,
              spreadRadius: 2,
              offset: const Offset(0, 18),
            ),
          ]
        : null,
  );
}
