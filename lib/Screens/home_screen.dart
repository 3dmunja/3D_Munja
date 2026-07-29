import 'dart:async';

import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/bike_profile.dart';
import '../models/munja_device.dart';
import '../models/ride_route_plan.dart';
import '../services/active_route_service.dart';
import '../services/ai_ride_coach_service.dart';
import '../services/bike_garage_service.dart';
import '../services/ble_service.dart';
import '../services/ride_session_service.dart';
import '../services/storage_service.dart';
import '../services/voice_coach_service.dart';
import '../widgets/munja_3d_bike_viewer.dart';
import 'garage_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RideSessionService _rideSessionService = RideSessionService();
  final AiRideCoachService _aiCoachService = AiRideCoachService();
  final BikeGarageService _bikeGarageService = const BikeGarageService();

  StreamSubscription<RideSessionData>? _rideSub;
  StreamSubscription<RideRoutePlan?>? _routeSub;

  RideSessionData rideData = RideSessionData.initial();
  RideRoutePlan? activeRoute;
  CoachInsight? coachInsight;
  BikeProfile? activeBike;

  List<MunjaDevice> nearbyDevices = [];

  bool monitoring = false;
  bool loadingBike = true;

  bool get hasBrakeLightNearby =>
      nearbyDevices.any((d) => d.type == MunjaProductType.brakeLight);

  int get brakeLightBattery => hasBrakeLightNearby ? 82 : 64;

  bool get isLive => rideData.isRiding || monitoring;

  @override
  void initState() {
    super.initState();

    VoiceCoachService.instance.initialize();

    rideData = _rideSessionService.current;
    monitoring = rideData.isRiding;

    ActiveRouteService.instance.load();
    activeRoute = ActiveRouteService.instance.current;

    _loadActiveBike();

    _routeSub = ActiveRouteService.instance.stream.listen((route) {
      if (!mounted) return;
      setState(() => activeRoute = route);
    });

    coachInsight = _aiCoachService.analyze(
      data: rideData,
      bleConnected: hasBrakeLightNearby,
      batteryPercent: brakeLightBattery,
    );

    _rideSub = _rideSessionService.stream.listen((data) {
      if (!mounted) return;

      final insight = _aiCoachService.analyze(
        data: data,
        bleConnected: hasBrakeLightNearby,
        batteryPercent: brakeLightBattery,
      );

      setState(() {
        rideData = data;
        monitoring = data.isRiding;
        coachInsight = insight;
      });
    });

    _scanBleLater();
  }

  @override
  void dispose() {
    _rideSub?.cancel();
    _routeSub?.cancel();
    super.dispose();
  }

  Future<void> _loadActiveBike() async {
    try {
      final bike = await _bikeGarageService.loadActiveBike();

      if (!mounted) return;

      setState(() {
        activeBike = bike;
        loadingBike = false;
      });
    } catch (e) {
      debugPrint('HOME LOAD ACTIVE BIKE ERROR: $e');

      if (!mounted) return;

      setState(() {
        activeBike = null;
        loadingBike = false;
      });
    }
  }

  Future<void> _scanBleLater() async {
    try {
      final saved = await StorageService.loadSavedDevices();

      final nearby = await BleService.scanNearbyMunjaDevices(saved: saved);

      if (!mounted) return;

      setState(() {
        nearbyDevices = nearby;

        coachInsight = _aiCoachService.analyze(
          data: rideData,
          bleConnected: hasBrakeLightNearby,
          batteryPercent: brakeLightBattery,
        );
      });
    } catch (e) {
      debugPrint('BLE SCAN ERROR: $e');
    }
  }

  Future<void> _refreshHome() async {
    await ActiveRouteService.instance.load();
    await _loadActiveBike();
    await _scanBleLater();
  }

  Future<void> _openGarage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GarageScreen()));

    await _loadActiveBike();
  }

  void _openBrakeLightPanel() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MunjaColors.panel,
      barrierColor: Colors.black.withOpacity(0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) {
        return _ProductBottomSheet(
          batteryPercent: brakeLightBattery,
          connected: hasBrakeLightNearby,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final batteryPercent = brakeLightBattery;
    final bike = activeBike;

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refreshHome,
          color: MunjaColors.mint,
          backgroundColor: MunjaColors.panel,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 360),
            children: [
              _MunjaTopBar(
                batteryPercent: batteryPercent,
                bleConnected: hasBrakeLightNearby,
                onOpenGarage: _openGarage,
              ),
              const SizedBox(height: 22),
              if (loadingBike)
                const _BikeLoadingCard()
              else
                Munja3DBikeViewer(
                  height: 430,
                  isLive: isLive,
                  modelPath:
                      bike?.modelPath ?? Munja3DBikeViewer.defaultModelPath,
                  brakeLightMounted: bike?.hasRearLight ?? hasBrakeLightNearby,
                  onOpenGarage: _openGarage,
                  onBikeTap: _openGarage,
                ),
              const SizedBox(height: 24),
              _HomeStatusTitle(isLive: isLive, bikeName: bike?.name),
              const SizedBox(height: 18),
              if (isLive)
                _LiveRideMinimal(
                  distanceKm: rideData.distanceKm,
                  speedKmh: rideData.currentSpeedKmh,
                  duration: rideData.rideDuration,
                )
              else
                _SystemStatusPanel(
                  gpsActive: true,
                  bleConnected: hasBrakeLightNearby,
                  batteryPercent: batteryPercent,
                ),
              if (bike != null) ...[
                const SizedBox(height: 18),
                _ActiveBikeMiniCard(bike: bike, onOpenGarage: _openGarage),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MunjaTopBar extends StatelessWidget {
  final int batteryPercent;
  final bool bleConnected;
  final VoidCallback onOpenGarage;

  const _MunjaTopBar({
    required this.batteryPercent,
    required this.bleConnected,
    required this.onOpenGarage,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _MiniCrystalIcon(),
        const SizedBox(width: 12),
        const Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'MUNJA',
              maxLines: 1,
              style: TextStyle(
                color: MunjaColors.text,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 7,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _TopStatusChip(
          icon: Icons.bluetooth_rounded,
          text: AppText.t('ble').toUpperCase(),
          active: bleConnected,
        ),
        const SizedBox(width: 7),
        _TopStatusChip(
          icon: Icons.battery_5_bar_rounded,
          text: '$batteryPercent%',
          active: batteryPercent > 20,
        ),
      ],
    );
  }
}

class _MiniCrystalIcon extends StatelessWidget {
  const _MiniCrystalIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: const _MiniCrystalPainter(),
    );
  }
}

class _MiniCrystalPainter extends CustomPainter {
  const _MiniCrystalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 4)
      ..lineTo(size.width - 5, size.height * 0.34)
      ..lineTo(size.width * 0.72, size.height - 5)
      ..lineTo(size.width * 0.28, size.height - 5)
      ..lineTo(5, size.height * 0.34)
      ..close();

    final fill = Paint()
      ..color = MunjaColors.mint.withOpacity(0.22)
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = MunjaColors.mint.withOpacity(0.95)
      ..strokeWidth = 1.7
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);

    canvas.drawLine(
      Offset(size.width / 2, 4),
      Offset(size.width / 2, size.height - 5),
      outline,
    );

    canvas.drawLine(
      Offset(5, size.height * 0.34),
      Offset(size.width * 0.72, size.height - 5),
      outline,
    );

    canvas.drawLine(
      Offset(size.width - 5, size.height * 0.34),
      Offset(size.width * 0.28, size.height - 5),
      outline,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniCrystalPainter oldDelegate) => false;
}

class _TopStatusChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool active;

  const _TopStatusChip({
    required this.icon,
    required this.text,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.13)
            : Colors.white.withOpacity(0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.40)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeStatusTitle extends StatelessWidget {
  final bool isLive;
  final String? bikeName;

  const _HomeStatusTitle({required this.isLive, required this.bikeName});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          isLive ? AppText.t('live') : AppText.t('ready'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isLive ? MunjaColors.mint : MunjaColors.text,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            letterSpacing: 5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          bikeName ?? AppText.t('digital_twin_ready'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.42),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _SystemStatusPanel extends StatelessWidget {
  final bool gpsActive;
  final bool bleConnected;
  final int batteryPercent;

  const _SystemStatusPanel({
    required this.gpsActive,
    required this.bleConnected,
    required this.batteryPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SystemStatusLine(
          label: AppText.t('gps'),
          value: gpsActive ? AppText.t('active') : AppText.t('inactive'),
          active: gpsActive,
        ),
        _SystemStatusLine(
          label: AppText.t('bluetooth'),
          value: bleConnected ? AppText.t('connected') : AppText.t('searching'),
          active: bleConnected,
        ),
        _SystemStatusLine(
          label: AppText.t('battery'),
          value: '$batteryPercent%',
          active: batteryPercent > 20,
        ),
      ],
    );
  }
}

class _SystemStatusLine extends StatelessWidget {
  final String label;
  final String value;
  final bool active;

  const _SystemStatusLine({
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$label  ',
            style: TextStyle(
              color: Colors.white.withOpacity(0.46),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveRideMinimal extends StatelessWidget {
  final double distanceKm;
  final double speedKmh;
  final Duration duration;

  const _LiveRideMinimal({
    required this.distanceKm,
    required this.speedKmh,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours.toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RideMetric(
          label: AppText.t('distance'),
          value: '${distanceKm.toStringAsFixed(2)} km',
        ),
        const SizedBox(width: 22),
        _RideMetric(
          label: AppText.t('speed'),
          value: '${speedKmh.toStringAsFixed(0)} km/h',
        ),
        const SizedBox(width: 22),
        _RideMetric(
          label: AppText.t('time'),
          value: '$hours:$minutes:$seconds',
        ),
      ],
    );
  }
}

class _RideMetric extends StatelessWidget {
  final String label;
  final String value;

  const _RideMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: MunjaColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.42),
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ActiveBikeMiniCard extends StatelessWidget {
  final BikeProfile bike;
  final VoidCallback onOpenGarage;

  const _ActiveBikeMiniCard({required this.bike, required this.onOpenGarage});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.panel.withOpacity(0.56),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onOpenGarage,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.garage_rounded,
                color: MunjaColors.mint,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${AppText.t('activeBike')}: ${bike.name}',
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _BikeLoadingCard extends StatelessWidget {
  const _BikeLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 430,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.62),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: const CircularProgressIndicator(color: MunjaColors.mint),
    );
  }
}

class _ProductBottomSheet extends StatelessWidget {
  final int batteryPercent;
  final bool connected;

  const _ProductBottomSheet({
    required this.batteryPercent,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
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
            const SizedBox(height: 24),
            Text(
              AppText.t('smart_lighting_brake'),
              style: const TextStyle(
                color: MunjaColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            _ProductLine(AppText.t('battery'), '$batteryPercent%'),
            _ProductLine(
              AppText.t('connection'),
              connected ? AppText.t('active') : AppText.t('searching'),
            ),
            _ProductLine(AppText.t('night_mode'), AppText.t('active')),
            _ProductLine(AppText.t('auto_brake'), AppText.t('active')),
            _ProductLine(AppText.t('visibilityBoost'), '+40%'),
          ],
        ),
      ),
    );
  }
}

class _ProductLine extends StatelessWidget {
  final String label;
  final String value;

  const _ProductLine(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.52),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
