import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/theme/munja_colors.dart';
import '../services/ride_session_service.dart';

class HomeLiveRideCard extends StatelessWidget {
  final RideSessionData data;
  final bool monitoring;
  final bool bleConnected;
  final int batteryPercent;
  final VoidCallback onStartStop;
  final VoidCallback? onOpenMap;

  final String routeLevel;
  final double? plannedRouteKm;
  final List<LatLng>? plannedRoutePath;

  const HomeLiveRideCard({
    super.key,
    required this.data,
    required this.monitoring,
    required this.onStartStop,
    this.onOpenMap,
    this.bleConnected = false,
    this.batteryPercent = 64,
    this.routeLevel = 'Flat',
    this.plannedRouteKm,
    this.plannedRoutePath,
  });

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<List<double>> _plannedPathAsList() {
    final path = plannedRoutePath;

    if (path == null || path.isEmpty) return [];

    return path.map((p) => [p.latitude, p.longitude]).toList();
  }

  @override
  Widget build(BuildContext context) {
    final active = monitoring || data.isRiding;
    final speed = data.currentSpeedKmh;
    final progress = (speed / 45).clamp(0.0, 1.0);
    final battery = batteryPercent.clamp(0, 100);

    final routePreviewPath = data.path.length >= 2
        ? data.path
        : _plannedPathAsList();

    final distanceText = active || data.distanceKm > 0
        ? '${data.distanceKm.toStringAsFixed(2)} km'
        : plannedRouteKm == null
        ? '0.00 km'
        : '${plannedRouteKm!.toStringAsFixed(1)} km';

    return SizedBox(
      height: 650,
      child: Stack(
        children: [
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            child: _TopRow(
              active: active,
              bleConnected: bleConnected,
              batteryPercent: battery,
              onOpenMap: onOpenMap,
            ),
          ),
          Positioned(
            top: 76,
            left: 0,
            right: 0,
            child: SizedBox(
              height: 355,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SpeedArcPainter(
                        progress: progress,
                        active: active,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 34,
                    left: 28,
                    child: _ArcMetric(
                      icon: Icons.route_rounded,
                      value: distanceText,
                      label: active ? 'Distance' : 'Route',
                    ),
                  ),
                  Positioned(
                    top: 8,
                    child: _ArcMetric(
                      icon: Icons.timer_rounded,
                      value: _durationText(data.rideDuration),
                      label: 'Time',
                    ),
                  ),
                  Positioned(
                    top: 34,
                    right: 28,
                    child: _ArcMetric(
                      icon: Icons.trending_up_rounded,
                      value: routeLevel,
                      label: 'Level',
                    ),
                  ),
                  Positioned(
                    top: 98,
                    left: 18,
                    right: 18,
                    child: SizedBox(
                      height: 205,
                      child: CustomPaint(
                        painter: _RoutePreviewPainter(
                          path: routePreviewPath,
                          active: active,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 178,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        Text(
                          speed.toStringAsFixed(0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 74,
                            height: 0.88,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -3,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'km/h',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 104,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: MunjaColors.mint.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        active ? 'Live' : 'Ready',
                        style: const TextStyle(
                          color: MunjaColors.mint,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 440,
            left: 10,
            right: 10,
            child: _MiniProductRow(bleConnected: bleConnected, active: active),
          ),
        ],
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  final bool active;
  final bool bleConnected;
  final int batteryPercent;
  final VoidCallback? onOpenMap;

  const _TopRow({
    required this.active,
    required this.bleConnected,
    required this.batteryPercent,
    required this.onOpenMap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatusChip(
          icon: Icons.circle,
          label: active ? 'LIVE' : 'READY',
          active: active,
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
          label: '$batteryPercent%',
          active: batteryPercent > 20,
        ),
        if (onOpenMap != null) ...[
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onOpenMap,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.035),
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
      ],
    );
  }
}

class _SpeedArcPainter extends CustomPainter {
  final double progress;
  final bool active;

  _SpeedArcPainter({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(18, 20, size.width - 36, size.height * 1.28);

    const startAngle = math.pi * 1.03;
    const sweepAngle = math.pi * 0.94;

    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.07)
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(active ? 0.32 : 0.18)
      ..strokeWidth = 30
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);

    final activePaint = Paint()
      ..color = MunjaColors.mint
      ..strokeWidth = 16
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final dividerPaint = Paint()
      ..color = const Color(0xFF020806)
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    final activeSweep = sweepAngle * progress.clamp(0.14, 1.0);
    canvas.drawArc(rect, startAngle, activeSweep, false, glowPaint);
    canvas.drawArc(rect, startAngle, activeSweep, false, activePaint);

    final split1 = startAngle + sweepAngle / 3;
    final split2 = startAngle + (sweepAngle / 3) * 2;

    canvas.drawArc(rect, split1 - 0.012, 0.024, false, dividerPaint);
    canvas.drawArc(rect, split2 - 0.012, 0.024, false, dividerPaint);

    final innerPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(0.10)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final innerRect = Rect.fromLTWH(
      58,
      82,
      size.width - 116,
      size.height * 0.92,
    );

    canvas.drawArc(
      innerRect,
      math.pi * 1.05,
      math.pi * 0.90,
      false,
      innerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedArcPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}

class _RoutePreviewPainter extends CustomPainter {
  final List<List<double>> path;
  final bool active;

  _RoutePreviewPainter({required this.path, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(0.035)
      ..style = PaintingStyle.fill;

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.045)
      ..strokeWidth = 1.2;

    final routeGlowPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(active ? 0.46 : 0.38)
      ..strokeWidth = 13
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);

    final routePaint = Paint()
      ..color = MunjaColors.mint
      ..strokeWidth = 5.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final roadPaint = Paint()
      ..color = Colors.white.withOpacity(0.035)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(
      Offset(size.width * 0.50, size.height * 0.58),
      size.width * 0.45,
      bgPaint,
    );

    for (var i = 0; i < 6; i++) {
      final y = size.height * (0.18 + i * 0.13);
      canvas.drawLine(
        Offset(size.width * 0.05, y),
        Offset(size.width * 0.95, y + (i.isEven ? 16 : -12)),
        gridPaint,
      );
    }

    for (var i = 0; i < 5; i++) {
      final x = size.width * (0.15 + i * 0.18);
      canvas.drawLine(
        Offset(x, size.height * 0.05),
        Offset(x + (i.isEven ? 28 : -24), size.height * 0.95),
        roadPaint,
      );
    }

    final route = path.length >= 2
        ? _buildPathFromGps(size, path)
        : _buildFallbackRoute(size);

    canvas.drawPath(route, routeGlowPaint);
    canvas.drawPath(route, routePaint);

    final markerPoint = _getStartPoint(size, path);

    final markerGlow = Paint()
      ..color = MunjaColors.mint.withOpacity(0.35)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final marker = Paint()
      ..color = MunjaColors.mint
      ..style = PaintingStyle.fill;

    final markerInner = Paint()
      ..color = const Color(0xFF020806)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(markerPoint, 18, markerGlow);
    canvas.drawCircle(markerPoint, 13, marker);
    canvas.drawCircle(markerPoint, 7, markerInner);
    canvas.drawCircle(markerPoint, 4, marker);
  }

  Path _buildFallbackRoute(Size size) {
    return Path()
      ..moveTo(size.width * 0.21, size.height * 0.70)
      ..lineTo(size.width * 0.30, size.height * 0.78)
      ..lineTo(size.width * 0.44, size.height * 0.76)
      ..lineTo(size.width * 0.57, size.height * 0.70)
      ..lineTo(size.width * 0.68, size.height * 0.79)
      ..lineTo(size.width * 0.82, size.height * 0.61)
      ..lineTo(size.width * 0.78, size.height * 0.38)
      ..lineTo(size.width * 0.64, size.height * 0.28)
      ..lineTo(size.width * 0.51, size.height * 0.31)
      ..lineTo(size.width * 0.43, size.height * 0.24)
      ..lineTo(size.width * 0.31, size.height * 0.35)
      ..lineTo(size.width * 0.28, size.height * 0.49)
      ..lineTo(size.width * 0.18, size.height * 0.58)
      ..lineTo(size.width * 0.21, size.height * 0.70);
  }

  Path _buildPathFromGps(Size size, List<List<double>> points) {
    final lats = points.map((p) => p[0]).toList();
    final lngs = points.map((p) => p[1]).toList();

    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    final latRange = (maxLat - minLat).abs() < 0.00001
        ? 0.00001
        : maxLat - minLat;
    final lngRange = (maxLng - minLng).abs() < 0.00001
        ? 0.00001
        : maxLng - minLng;

    final route = Path();

    for (var i = 0; i < points.length; i++) {
      final lat = points[i][0];
      final lng = points[i][1];

      final x =
          ((lng - minLng) / lngRange) * size.width * 0.70 + size.width * 0.15;
      final y =
          size.height * 0.82 - ((lat - minLat) / latRange) * size.height * 0.58;

      if (i == 0) {
        route.moveTo(x, y);
      } else {
        route.lineTo(x, y);
      }
    }

    return route;
  }

  Offset _getStartPoint(Size size, List<List<double>> points) {
    if (points.length < 2) {
      return Offset(size.width * 0.21, size.height * 0.70);
    }

    final lats = points.map((p) => p[0]).toList();
    final lngs = points.map((p) => p[1]).toList();

    final minLat = lats.reduce(math.min);
    final maxLat = lats.reduce(math.max);
    final minLng = lngs.reduce(math.min);
    final maxLng = lngs.reduce(math.max);

    final latRange = (maxLat - minLat).abs() < 0.00001
        ? 0.00001
        : maxLat - minLat;
    final lngRange = (maxLng - minLng).abs() < 0.00001
        ? 0.00001
        : maxLng - minLng;

    final lat = points.first[0];
    final lng = points.first[1];

    final x =
        ((lng - minLng) / lngRange) * size.width * 0.70 + size.width * 0.15;
    final y =
        size.height * 0.82 - ((lat - minLat) / latRange) * size.height * 0.58;

    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    return oldDelegate.path != path || oldDelegate.active != active;
  }
}

class _ArcMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _ArcMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      child: Column(
        children: [
          Icon(icon, color: MunjaColors.mint, size: 23),
          const SizedBox(height: 7),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniProductRow extends StatelessWidget {
  final bool bleConnected;
  final bool active;

  const _MiniProductRow({required this.bleConnected, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MiniHudIcon(
          icon: Icons.light_mode_rounded,
          label: bleConnected ? 'Brake' : 'No brake',
          active: bleConnected,
        ),
        _MiniHudIcon(icon: Icons.hub_rounded, label: 'Products', active: true),
        _MiniHudIcon(
          icon: Icons.psychology_rounded,
          label: 'Coach',
          active: active,
        ),
      ],
    );
  }
}

class _MiniHudIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _MiniHudIcon({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: active
                  ? MunjaColors.mint.withOpacity(0.10)
                  : Colors.white.withOpacity(0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
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
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.105)
            : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: icon == Icons.circle ? 8 : 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
