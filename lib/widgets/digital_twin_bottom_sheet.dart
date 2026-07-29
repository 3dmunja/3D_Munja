import 'package:flutter/material.dart';

import '../../core/theme/munja_colors.dart';

class DigitalTwinBottomSheet extends StatelessWidget {
  final String title;
  final int batteryPercent;
  final bool connected;
  final bool nightModeActive;
  final bool autoBrakeActive;
  final int visibilityBoostPercent;
  final String firmwareVersion;
  final VoidCallback? onOpenGear;
  final VoidCallback? onClose;

  const DigitalTwinBottomSheet({
    super.key,
    this.title = 'Smart Lighting Brake',
    required this.batteryPercent,
    required this.connected,
    this.nightModeActive = true,
    this.autoBrakeActive = true,
    this.visibilityBoostPercent = 40,
    this.firmwareVersion = '1.0.0',
    this.onOpenGear,
    this.onClose,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Smart Lighting Brake',
    required int batteryPercent,
    required bool connected,
    bool nightModeActive = true,
    bool autoBrakeActive = true,
    int visibilityBoostPercent = 40,
    String firmwareVersion = '1.0.0',
    VoidCallback? onOpenGear,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: MunjaColors.panel,
      barrierColor: Colors.black.withOpacity(0.72),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
      ),
      builder: (_) {
        return DigitalTwinBottomSheet(
          title: title,
          batteryPercent: batteryPercent,
          connected: connected,
          nightModeActive: nightModeActive,
          autoBrakeActive: autoBrakeActive,
          visibilityBoostPercent: visibilityBoostPercent,
          firmwareVersion: firmwareVersion,
          onOpenGear: onOpenGear,
          onClose: () => Navigator.pop(context),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionText = connected ? 'Aktiv' : 'Søger';
    final connectionColor = connected ? MunjaColors.mint : Colors.white38;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                _BrakeLightPreview(
                  connected: connected,
                  batteryPercent: batteryPercent,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: MunjaColors.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: connectionColor,
                              boxShadow: connected
                                  ? [
                                      BoxShadow(
                                        color: MunjaColors.mint.withOpacity(
                                          0.55,
                                        ),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                    ]
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            connectionText,
                            style: TextStyle(
                              color: connectionColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _BatteryBar(batteryPercent: batteryPercent),
            const SizedBox(height: 20),
            _InfoCard(
              children: [
                _ProductLine(
                  icon: Icons.battery_5_bar_rounded,
                  label: 'Batteri',
                  value: '$batteryPercent%',
                  active: batteryPercent > 20,
                ),
                _ProductLine(
                  icon: Icons.bluetooth_rounded,
                  label: 'Forbindelse',
                  value: connectionText,
                  active: connected,
                ),
                _ProductLine(
                  icon: Icons.nightlight_round,
                  label: 'Night Mode',
                  value: nightModeActive ? 'Aktiv' : 'Fra',
                  active: nightModeActive,
                ),
                _ProductLine(
                  icon: Icons.emergency_share_rounded,
                  label: 'Auto Brake',
                  value: autoBrakeActive ? 'Aktiv' : 'Fra',
                  active: autoBrakeActive,
                ),
                _ProductLine(
                  icon: Icons.visibility_rounded,
                  label: 'Visibility Boost',
                  value: '+$visibilityBoostPercent%',
                  active: visibilityBoostPercent > 0,
                ),
                _ProductLine(
                  icon: Icons.system_update_alt_rounded,
                  label: 'Firmware',
                  value: firmwareVersion,
                  active: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'Luk',
                    icon: Icons.close_rounded,
                    filled: false,
                    onTap: onClose ?? () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    label: 'Åbn udstyr',
                    icon: Icons.inventory_2_rounded,
                    filled: true,
                    onTap: onOpenGear,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BrakeLightPreview extends StatelessWidget {
  final bool connected;
  final int batteryPercent;

  const _BrakeLightPreview({
    required this.connected,
    required this.batteryPercent,
  });

  @override
  Widget build(BuildContext context) {
    final color = connected ? MunjaColors.danger : Colors.white30;

    return Container(
      width: 72,
      height: 112,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: RadialGradient(
          colors: [
            color.withOpacity(connected ? 0.32 : 0.14),
            Colors.white.withOpacity(0.04),
            Colors.transparent,
          ],
        ),
        boxShadow: connected
            ? [
                BoxShadow(
                  color: color.withOpacity(0.40),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ]
            : null,
      ),
      child: Container(
        width: 34,
        height: 78,
        decoration: BoxDecoration(
          color: const Color(0xFF101917),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: color.withOpacity(connected ? 0.95 : 0.42),
            width: 2,
          ),
          boxShadow: connected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.48),
                    blurRadius: 18,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LedDot(active: connected),
            const SizedBox(height: 7),
            _LedDot(active: connected),
            const SizedBox(height: 7),
            _LedDot(active: connected),
            const SizedBox(height: 9),
            Text(
              '$batteryPercent%',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LedDot extends StatelessWidget {
  final bool active;

  const _LedDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 11,
      height: 5,
      decoration: BoxDecoration(
        color: active ? MunjaColors.danger : Colors.white24,
        borderRadius: BorderRadius.circular(99),
        boxShadow: active
            ? [
                BoxShadow(
                  color: MunjaColors.danger.withOpacity(0.8),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

class _BatteryBar extends StatelessWidget {
  final int batteryPercent;

  const _BatteryBar({required this.batteryPercent});

  @override
  Widget build(BuildContext context) {
    final clamped = batteryPercent.clamp(0, 100);
    final active = clamped > 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Batteri',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              '$clamped%',
              style: TextStyle(
                color: active ? MunjaColors.mint : MunjaColors.danger,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Stack(
            children: [
              Container(height: 8, color: Colors.white.withOpacity(0.08)),
              FractionallySizedBox(
                widthFactor: clamped / 100,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? MunjaColors.mint : MunjaColors.danger,
                    boxShadow: [
                      BoxShadow(
                        color: (active ? MunjaColors.mint : MunjaColors.danger)
                            .withOpacity(0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1)
              Divider(height: 1, color: Colors.white.withOpacity(0.06)),
          ],
        ],
      ),
    );
  }
}

class _ProductLine extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool active;

  const _ProductLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.54),
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: enabled ? 1 : 0.46,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: filled
                ? MunjaColors.mint.withOpacity(0.92)
                : Colors.white.withOpacity(0.045),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: filled
                  ? MunjaColors.mint.withOpacity(0.65)
                  : Colors.white.withOpacity(0.08),
            ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: MunjaColors.mint.withOpacity(0.28),
                      blurRadius: 22,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: filled ? const Color(0xFF02100B) : Colors.white70,
                size: 19,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? const Color(0xFF02100B) : Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
