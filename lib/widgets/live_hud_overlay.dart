import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../services/ride_session_service.dart';

class LiveHudOverlay extends StatelessWidget {
  final RideSessionData data;
  final bool bleConnected;
  final int batteryPercent;

  const LiveHudOverlay({
    super.key,
    required this.data,
    this.bleConnected = false,
    this.batteryPercent = 64,
  });

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _gpsText(double accuracy) {
    if (accuracy <= 0) return 'GPS';
    if (accuracy <= 20) return 'OK';
    return 'Weak';
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopHud(
                speedKmh: data.currentSpeedKmh,
                isRiding: data.isRiding,
                gpsText: _gpsText(data.gpsAccuracy),
                bleConnected: bleConnected,
                batteryPercent: batteryPercent,
              ),
              const SizedBox(height: 8),
              _StatsHud(
                distanceKm: data.distanceKm,
                duration: _durationText(data.rideDuration),
                avgSpeedKmh: data.averageSpeedKmh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopHud extends StatelessWidget {
  final double speedKmh;
  final bool isRiding;
  final String gpsText;
  final bool bleConnected;
  final int batteryPercent;

  const _TopHud({
    required this.speedKmh,
    required this.isRiding,
    required this.gpsText,
    required this.bleConnected,
    required this.batteryPercent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: double.infinity,
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.86),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isRiding
              ? MunjaColors.mint.withOpacity(0.34)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: isRiding
                ? MunjaColors.mint.withOpacity(0.16)
                : Colors.black.withOpacity(0.22),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          _SpeedBlock(speedKmh: speedKmh),
          const Spacer(),
          _StatusChip(
            icon: Icons.gps_fixed_rounded,
            label: gpsText,
            active: gpsText == 'OK',
          ),
          const SizedBox(width: 6),
          _StatusChip(
            icon: Icons.bluetooth_rounded,
            label: bleConnected ? 'BLE' : 'OFF',
            active: bleConnected,
          ),
          const SizedBox(width: 6),
          _BatteryChip(percent: batteryPercent),
        ],
      ),
    );
  }
}

class _SpeedBlock extends StatelessWidget {
  final double speedKmh;

  const _SpeedBlock({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text(
            speedKmh.toStringAsFixed(1),
            key: ValueKey(speedKmh.toStringAsFixed(1)),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              height: 0.9,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.8,
            ),
          ),
        ),
        const SizedBox(width: 5),
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text(
            'km/h',
            style: TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatsHud extends StatelessWidget {
  final double distanceKm;
  final String duration;
  final double avgSpeedKmh;

  const _StatsHud({
    required this.distanceKm,
    required this.duration,
    required this.avgSpeedKmh,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 70,
      child: Row(
        children: [
          Expanded(
            child: _MiniHudCard(
              icon: Icons.route_rounded,
              label: 'Distance',
              value: distanceKm.toStringAsFixed(2),
              unit: 'km',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniHudCard(
              icon: Icons.timer_rounded,
              label: 'Time',
              value: duration,
              unit: '',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MiniHudCard(
              icon: Icons.speed_rounded,
              label: 'Avg',
              value: avgSpeedKmh.toStringAsFixed(1),
              unit: 'km/h',
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniHudCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const _MiniHudCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 16),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 2),
                const Padding(
                  padding: EdgeInsets.only(bottom: 2),
                  child: Text('', style: TextStyle(fontSize: 0)),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _StatusChip({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.16)
            : Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: active ? MunjaColors.mint : Colors.white.withOpacity(0.45),
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryChip extends StatelessWidget {
  final int percent;

  const _BatteryChip({required this.percent});

  @override
  Widget build(BuildContext context) {
    final safePercent = percent.clamp(0, 100);
    final active = safePercent > 20;
    final color = active ? MunjaColors.mint : Colors.orange;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.battery_5_bar_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$safePercent%',
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
