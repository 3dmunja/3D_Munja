import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../services/ride_session_service.dart';

class HomeLiveRideCard extends StatelessWidget {
  final RideSessionData data;
  final bool monitoring;
  final bool bleConnected;
  final int batteryPercent;
  final VoidCallback onStartStop;
  final VoidCallback onOpenMap;

  const HomeLiveRideCard({
    super.key,
    required this.data,
    required this.monitoring,
    required this.bleConnected,
    required this.batteryPercent,
    required this.onStartStop,
    required this.onOpenMap,
  });

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) {
      return '${h}h ${m}m';
    }

    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final speed = data.currentSpeedKmh;
    final progress = (speed / 45).clamp(0.0, 1.0);
    final battery = batteryPercent.clamp(0, 100);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(42),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.050),
            Colors.white.withOpacity(0.018),
            MunjaColors.mint.withOpacity(0.020),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(monitoring ? 0.22 : 0.10),
            blurRadius: monitoring ? 46 : 28,
            spreadRadius: monitoring ? 2 : 0,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _StatusChip(
                icon: Icons.circle,
                label: monitoring ? 'LIVE' : 'READY',
                active: monitoring,
              ),
              const Spacer(),
              _StatusChip(
                icon: Icons.bluetooth_rounded,
                label: bleConnected ? 'BLE' : 'OFF',
                active: bleConnected,
              ),
              const SizedBox(width: 8),
              _StatusChip(
                icon: Icons.battery_5_bar_rounded,
                label: '$battery%',
                active: battery > 20,
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onOpenMap,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.045),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          SizedBox(
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _SpeedArcPainter(
                      progress: progress,
                      active: monitoring,
                    ),
                  ),
                ),

                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: MunjaColors.mint.withOpacity(0.95),
                      size: 34,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      speed.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 76,
                        height: 0.92,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'km/h',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),

                Positioned(
                  left: 6,
                  bottom: 20,
                  child: _HeroMetric(
                    icon: Icons.route_rounded,
                    value: data.distanceKm.toStringAsFixed(2),
                    unit: 'km',
                    label: 'Distance',
                  ),
                ),

                Positioned(
                  bottom: 18,
                  child: _HeroMetric(
                    icon: Icons.timer_rounded,
                    value: _durationText(data.rideDuration),
                    unit: '',
                    label: 'Time',
                    centered: true,
                  ),
                ),

                Positioned(
                  right: 6,
                  bottom: 20,
                  child: _HeroMetric(
                    icon: Icons.speed_rounded,
                    value: data.averageSpeedKmh.toStringAsFixed(1),
                    unit: 'km/h',
                    label: 'Avg',
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    monitoring ? 'RIDE ACTIVE' : 'START RIDE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: monitoring
                          ? MunjaColors.mint
                          : Colors.white.withOpacity(0.45),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onStartStop,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 92,
                    height: 52,
                    decoration: BoxDecoration(
                      color: monitoring
                          ? Colors.redAccent.withOpacity(0.95)
                          : MunjaColors.mint,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: monitoring
                              ? Colors.redAccent.withOpacity(0.30)
                              : MunjaColors.mint.withOpacity(0.45),
                          blurRadius: 28,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      monitoring
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: monitoring ? Colors.white : Colors.black,
                      size: 34,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    monitoring ? 'TAP TO STOP' : 'HOLD FOCUS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.42),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeedArcPainter extends CustomPainter {
  final double progress;
  final bool active;

  _SpeedArcPainter({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(10, 6, size.width - 20, size.height - 22);

    const startAngle = math.pi * 0.92;
    const sweepAngle = math.pi * 1.16;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.065)
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(active ? 0.34 : 0.16)
      ..strokeWidth = 22
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    final activePaint = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [
          MunjaColors.mint.withOpacity(0.85),
          MunjaColors.mint,
          MunjaColors.mintStrong,
        ],
      ).createShader(rect)
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    final activeSweep = sweepAngle * progress;

    if (progress > 0.01) {
      canvas.drawArc(rect, startAngle, activeSweep, false, glowPaint);
      canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);

      final endAngle = startAngle + activeSweep;
      final center = rect.center;
      final radius = rect.width / 2;

      final dot = Offset(
        center.dx + math.cos(endAngle) * radius,
        center.dy + math.sin(endAngle) * radius,
      );

      canvas.drawCircle(dot, 10, Paint()..color = MunjaColors.mint);

      canvas.drawCircle(
        dot,
        18,
        Paint()
          ..color = MunjaColors.mint.withOpacity(0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeedArcPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final bool centered;
  final bool alignRight;

  const _HeroMetric({
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    this.centered = false,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = centered
        ? CrossAxisAlignment.center
        : alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return SizedBox(
      width: 92,
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 22),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: centered
                ? MainAxisAlignment.center
                : alignRight
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
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
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.12)
            : Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(999),
        boxShadow: active
            ? [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(0.16),
                  blurRadius: 18,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: icon == Icons.circle ? 9 : 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
