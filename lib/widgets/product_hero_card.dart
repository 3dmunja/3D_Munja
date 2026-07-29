import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../core/localization/app_text.dart';

class ProductHeroCard extends StatelessWidget {
  final bool connected;
  final bool scanning;
  final double batteryPercent;
  final VoidCallback onRideTap;
  final VoidCallback onProductsTap;

  const ProductHeroCard({
    super.key,
    required this.connected,
    required this.scanning,
    required this.batteryPercent,
    required this.onRideTap,
    required this.onProductsTap,
  });

  @override
  Widget build(BuildContext context) {
    final battery = batteryPercent.clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(36),
        border: Border.all(
          color: connected
              ? MunjaColors.mint.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: connected
                ? MunjaColors.mint.withOpacity(0.22)
                : Colors.black.withOpacity(0.35),
            blurRadius: 42,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatusChip(
                icon: connected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_disabled_rounded,
                text: connected
                    ? AppText.t('hardwareFound')
                    : AppText.t('softwareOnly'),
                active: connected,
              ),
              const Spacer(),
              if (scanning)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _BatteryRing(value: battery),
            ],
          ),

          const SizedBox(height: 24),

          Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: connected ? 250 : 220,
                height: connected ? 250 : 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: connected
                      ? MunjaColors.mint.withOpacity(0.08)
                      : Colors.white.withOpacity(0.035),
                  boxShadow: [
                    BoxShadow(
                      color: connected
                          ? MunjaColors.mint.withOpacity(0.26)
                          : Colors.black.withOpacity(0.2),
                      blurRadius: connected ? 55 : 32,
                      spreadRadius: connected ? 8 : 2,
                    ),
                  ],
                ),
              ),

              Image.asset(
                'assets/brake_light.png',
                height: 250,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return const Icon(
                    Icons.light_mode_rounded,
                    size: 120,
                    color: MunjaColors.mint,
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          Text(
            AppText.t('smartBrakeLight'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            connected
                ? AppText.t('hardwareNearby')
                : AppText.t('noHardwareFound'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 15,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onRideTap,
                  icon: const Icon(Icons.directions_bike_rounded),
                  label: Text(AppText.t('openAutoRide')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onProductsTap,
                  icon: const Icon(Icons.memory_rounded),
                  label: Text(AppText.t('myProducts')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool active;

  const _StatusChip({
    required this.icon,
    required this.text,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.13)
            : Colors.orangeAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.32)
              : Colors.orangeAccent.withOpacity(0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: active ? MunjaColors.mint : Colors.orangeAccent,
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: active ? MunjaColors.mint : Colors.orangeAccent,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryRing extends StatelessWidget {
  final double value;

  const _BatteryRing({required this.value});

  @override
  Widget build(BuildContext context) {
    final percent = (value * 100).round();

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value,
            strokeWidth: 5,
            backgroundColor: Colors.white12,
          ),
          Text(
            '$percent%',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
