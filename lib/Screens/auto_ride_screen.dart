import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/live_ride_state.dart';
import '../services/live_ride_bus.dart';
import '../services/ride_session_service.dart';
import '../widgets/live_hud_overlay.dart';

class AutoRideScreen extends StatefulWidget {
  const AutoRideScreen({super.key});

  @override
  State<AutoRideScreen> createState() => _AutoRideScreenState();
}

class _AutoRideScreenState extends State<AutoRideScreen> {
  GoogleMapController? _mapController;

  bool _showMap = true;

  static const double bottomWheelSafePadding = 260;

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(55.6761, 12.5683),
    zoom: 15.5,
  );

  String t(String key) => AppText.t(key);

  RideSessionData _rideDataFromState(LiveRideState state) {
    return RideSessionData(
      isRiding: state.isActive,
      currentSpeedKmh: state.speedKmh,
      averageSpeedKmh: state.averageSpeedKmh,
      maxSpeedKmh: state.maxSpeedKmh,
      distanceKm: state.distanceKm,
      rideDuration: state.duration,
      calories: state.calories.toDouble(),
      altitude: state.altitude,
      gpsAccuracy: state.gpsAccuracy,
      lastUpdate: state.lastUpdate,
      path: state.path
          .map((point) => <double>[point.latitude, point.longitude])
          .toList(),
    );
  }

  void _centerMap(LiveRideState ride) {
    if (ride.path.isNotEmpty) {
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: ride.path.last, zoom: 17.0),
        ),
      );
      return;
    }

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(_initialCamera),
    );
  }

  void _toggleMapMode() {
    setState(() {
      _showMap = !_showMap;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: ValueListenableBuilder<LiveRideState>(
        valueListenable: LiveRideBus.instance.state,
        builder: (context, ride, _) {
          final rideHudData = _rideDataFromState(ride);

          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: _showMap
                      ? GoogleMap(
                          key: const ValueKey('map'),
                          initialCameraPosition: _initialCamera,
                          myLocationEnabled: true,
                          myLocationButtonEnabled: false,
                          compassEnabled: false,
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          markers: _markersForRide(ride),
                          polylines: _polylinesForRide(ride),
                          onMapCreated: (controller) {
                            _mapController = controller;

                            if (ride.path.isNotEmpty) {
                              controller.moveCamera(
                                CameraUpdate.newCameraPosition(
                                  CameraPosition(
                                    target: ride.path.last,
                                    zoom: 17.0,
                                  ),
                                ),
                              );
                            }
                          },
                        )
                      : const _DarkRideBackground(key: ValueKey('dark')),
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.58),
                          Colors.black.withOpacity(0.18),
                          Colors.transparent,
                          Colors.black.withOpacity(0.72),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LiveHudOverlay(
                  data: rideHudData,
                  bleConnected: false,
                  batteryPercent: 64,
                ),
              ),

              Positioned(
                left: 20,
                right: 20,
                top: 126,
                child: _LiveSpeedHero(
                  speedKmh: ride.speedKmh,
                  distanceKm: ride.distanceKm,
                  duration: ride.duration,
                  averageSpeedKmh: ride.averageSpeedKmh,
                  maxSpeedKmh: ride.maxSpeedKmh,
                  active: ride.isActive,
                ),
              ),

              Positioned(
                left: 20,
                right: 20,
                bottom: bottomWheelSafePadding,
                child: _RideStatusPanel(
                  isActive: ride.isActive,
                  calories: ride.calories,
                  altitude: ride.altitude ?? 0.0,
                  gpsAccuracy: ride.gpsAccuracy,
                  showMap: _showMap,
                  onCenterMap: () => _centerMap(ride),
                  onToggleMap: _toggleMapMode,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Set<Marker> _markersForRide(LiveRideState ride) {
    if (ride.path.isEmpty) return {};

    return {
      Marker(markerId: const MarkerId('ride_start'), position: ride.path.first),
      Marker(
        markerId: const MarkerId('ride_current'),
        position: ride.path.last,
      ),
    };
  }

  Set<Polyline> _polylinesForRide(LiveRideState ride) {
    if (ride.path.length < 2) return {};

    return {
      Polyline(
        polylineId: const PolylineId('ride_path'),
        points: ride.path,
        color: MunjaColors.mint,
        width: 6,
      ),
    };
  }
}

class _LiveSpeedHero extends StatelessWidget {
  final double speedKmh;
  final double distanceKm;
  final Duration duration;
  final double averageSpeedKmh;
  final double maxSpeedKmh;
  final bool active;

  const _LiveSpeedHero({
    required this.speedKmh,
    required this.distanceKm,
    required this.duration,
    required this.averageSpeedKmh,
    required this.maxSpeedKmh,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final rideScore = _rideScore(distanceKm, duration);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.76),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(active ? 0.26 : 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(active ? 0.18 : 0.08),
            blurRadius: 40,
            spreadRadius: 1,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _LiveDot(active: active),
              const SizedBox(width: 9),
              Text(
                active
                    ? AppText.t('liveRide').toUpperCase()
                    : AppText.t('ready').toUpperCase(),
                style: TextStyle(
                  color: active ? MunjaColors.mint : Colors.white54,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const Spacer(),
              Text(
                '${AppText.t('score').toUpperCase()} $rideScore',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                speedKmh.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 76,
                  height: 0.92,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -4,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'KM/H',
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _RideMetric(
                  label: AppText.t('distance'),
                  value: distanceKm.toStringAsFixed(2),
                  unit: 'km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RideMetric(
                  label: AppText.t('time'),
                  value: _durationText(duration),
                  unit: '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _RideMetric(
                  label: AppText.t('avg'),
                  value: averageSpeedKmh.toStringAsFixed(1),
                  unit: 'km/t',
                  compact: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RideMetric(
                  label: AppText.t('max'),
                  value: maxSpeedKmh.toStringAsFixed(1),
                  unit: 'km/t',
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _rideScore(double km, Duration duration) {
    final minutes = duration.inMinutes.clamp(1, 999);
    final base = (km * 5).round();
    final timeBonus = (minutes / 4).round();

    return (base + timeBonus).clamp(10, 100);
  }

  String _durationText(Duration duration) {
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);

    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }

    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class _RideMetric extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool compact;

  const _RideMetric({
    required this.label,
    required this.value,
    required this.unit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 70 : 82,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 21 : 27,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: const TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _RideStatusPanel extends StatelessWidget {
  final bool isActive;
  final int calories;
  final double altitude;
  final double gpsAccuracy;
  final bool showMap;
  final VoidCallback onCenterMap;
  final VoidCallback onToggleMap;

  const _RideStatusPanel({
    required this.isActive,
    required this.calories,
    required this.altitude,
    required this.gpsAccuracy,
    required this.showMap,
    required this.onCenterMap,
    required this.onToggleMap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _premiumDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.local_fire_department_rounded,
                  label: 'KCAL',
                  value: '$calories',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  icon: Icons.terrain_rounded,
                  label: 'ALT',
                  value: '${altitude.toStringAsFixed(0)} m',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  icon: Icons.gps_fixed_rounded,
                  label: 'GPS',
                  value: gpsAccuracy <= 0
                      ? 'OK'
                      : '${gpsAccuracy.toStringAsFixed(0)} m',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionPill(
                  icon: showMap
                      ? Icons.dashboard_customize_rounded
                      : Icons.map_rounded,
                  label: showMap ? AppText.t('hud') : AppText.t('map'),
                  onTap: onToggleMap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionPill(
                  icon: Icons.my_location_rounded,
                  label: AppText.t('centerMap'),
                  onTap: onCenterMap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isActive
                ? AppText.t('stopRideFromWheel')
                : AppText.t('startRideFromWheel'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
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

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.mint.withOpacity(0.12),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MunjaColors.mint.withOpacity(0.26)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: MunjaColors.mint, size: 18),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  final bool active;

  const _LiveDot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: active ? MunjaColors.mint : Colors.white30,
        shape: BoxShape.circle,
        boxShadow: active
            ? [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(0.48),
                  blurRadius: 14,
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
    );
  }
}

class _DarkRideBackground extends StatelessWidget {
  const _DarkRideBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MunjaColors.bg,
      child: Stack(
        children: [
          Positioned(
            top: 140,
            left: -80,
            child: _GlowBlob(size: 220, opacity: 0.14),
          ),
          Positioned(
            bottom: 170,
            right: -70,
            child: _GlowBlob(size: 240, opacity: 0.12),
          ),
          Positioned.fill(child: CustomPaint(painter: _RideGridPainter())),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final double opacity;

  const _GlowBlob({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(opacity),
            blurRadius: 120,
            spreadRadius: 45,
          ),
        ],
      ),
    );
  }
}

class _RideGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;

    const spacing = 34.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RideGridPainter oldDelegate) => false;
}

BoxDecoration _premiumDecoration() {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.84),
    borderRadius: BorderRadius.circular(30),
    border: Border.all(color: Colors.white.withOpacity(0.075)),
    boxShadow: [
      BoxShadow(
        color: MunjaColors.mint.withOpacity(0.10),
        blurRadius: 28,
        spreadRadius: 1,
        offset: const Offset(0, 12),
      ),
    ],
  );
}
