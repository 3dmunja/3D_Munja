import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../models/live_ride_state.dart';

class RideRecoverySheet extends StatelessWidget {
  final LiveRideState state;
  final VoidCallback onContinueRide;
  final VoidCallback onOpenMap;
  final VoidCallback onStopRide;

  const RideRecoverySheet({
    super.key,
    required this.state,
    required this.onContinueRide,
    required this.onOpenMap,
    required this.onStopRide,
  });

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: const BoxDecoration(
          color: MunjaColors.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),

            const SizedBox(height: 18),

            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.14),
                shape: BoxShape.circle,
                border: Border.all(color: MunjaColors.mint.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: MunjaColors.mint.withOpacity(0.22),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                Icons.directions_bike_rounded,
                color: MunjaColors.mint,
                size: 34,
              ),
            ),

            const SizedBox(height: 16),

            const Text(
              'Active ride found',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Munja restored your ride session.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: _RecoveryMetric(
                    icon: Icons.route_rounded,
                    label: 'Distance',
                    value: state.distanceKm.toStringAsFixed(2),
                    unit: 'km',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RecoveryMetric(
                    icon: Icons.timer_rounded,
                    label: 'Time',
                    value: _durationText(state.duration),
                    unit: '',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _RecoveryMetric(
                    icon: Icons.speed_rounded,
                    label: 'Avg',
                    value: state.averageSpeedKmh.toStringAsFixed(1),
                    unit: 'km/h',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onContinueRide();
                },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text(
                  'Continue ride',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onOpenMap();
                      },
                      icon: const Icon(Icons.map_rounded),
                      label: const Text('Open map'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onStopRide();
                      },
                      icon: const Icon(Icons.stop_rounded),
                      label: const Text('Stop'),
                    ),
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

class _RecoveryMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const _RecoveryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 18),
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
                    fontSize: 17,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
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
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 9,
              height: 1,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
