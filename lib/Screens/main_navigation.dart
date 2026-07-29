import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/localization/app_text.dart';
import '../main.dart' as app;
import '../models/trip.dart';
import '../services/ride_session_service.dart';
import '../services/storage_service.dart';
import '../services/voice_coach_service.dart';
import '../widgets/wheel_radial_menu.dart';

import 'garage_screen.dart';
import 'gear_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int index = 0;

  final RideSessionService _rideSessionService = RideSessionService();

  StreamSubscription<RideSessionData>? _rideSub;

  RideSessionData rideData = RideSessionData.initial();

  bool _handlingRideState = false;
  bool _lastRideState = false;

  DateTime? _rideStartedAt;

  final List<Widget> screens = const [
    HomeScreen(),
    app.AutoRideScreen(),
    GarageScreen(),
    GearScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();

    VoiceCoachService.instance.initialize();

    rideData = _rideSessionService.current;
    _lastRideState = app.munjaRideActiveNotifier.value || rideData.isRiding;

    if (_lastRideState && !rideData.isRiding) {
      _rideStartedAt = DateTime.now();

      Future.microtask(() async {
        try {
          await WakelockPlus.enable();
          await _rideSessionService.start();
        } catch (e) {
          debugPrint('MAIN NAVIGATION INIT START ERROR: $e');
        }
      });
    }

    AppText.localeNotifier.addListener(_onLanguageChanged);
    app.munjaRideActiveNotifier.addListener(_onRideNotifierChanged);

    _rideSub = _rideSessionService.stream.listen((data) {
      if (!mounted) return;

      setState(() {
        rideData = data;
      });
    });
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onRideNotifierChanged() {
    _handleRideState(app.munjaRideActiveNotifier.value);
  }

  Future<void> _handleRideState(bool isRiding) async {
    if (_handlingRideState) return;
    if (_lastRideState == isRiding) return;

    _handlingRideState = true;
    _lastRideState = isRiding;

    try {
      if (isRiding) {
        debugPrint('MAIN NAVIGATION START RIDE');

        _rideStartedAt = DateTime.now();

        await WakelockPlus.enable();
        await _rideSessionService.start();

        await VoiceCoachService.instance.speakEvent(
          VoiceCoachEvent.rideStarted,
        );

        return;
      }

      debugPrint('MAIN NAVIGATION STOP RIDE');

      await VoiceCoachService.instance.speakEvent(VoiceCoachEvent.rideStopped);

      final finishedRide = await _rideSessionService.stop();

      await WakelockPlus.disable();

      if (finishedRide == null) {
        debugPrint('MAIN NAVIGATION: finishedRide is null');
        _rideStartedAt = null;
        return;
      }

      debugPrint(
        'MAIN NAVIGATION FINISHED RIDE: '
        '${finishedRide.distanceKm} km | '
        'duration=${finishedRide.rideDuration.inSeconds}s | '
        'path=${finishedRide.path.length}',
      );

      if (finishedRide.distanceKm < 0.005) {
        debugPrint(
          'MAIN NAVIGATION: trip too short, not saved '
          '(${finishedRide.distanceKm} km)',
        );

        _rideStartedAt = null;
        return;
      }

      final endedAt = DateTime.now();
      final startedAt =
          _rideStartedAt ?? endedAt.subtract(finishedRide.rideDuration);

      final trip = Trip(
        startedAtMs: startedAt.millisecondsSinceEpoch,
        endedAtMs: endedAt.millisecondsSinceEpoch,
        distanceM: finishedRide.distanceKm * 1000,
        brakes: 0,
        hardBrakes: 0,
        path: finishedRide.path,
        source: 'software',
      );

      await StorageService.saveTrip(trip);

      final savedTrips = await StorageService.loadTrips();

      debugPrint(
        'MAIN NAVIGATION TRIP SAVED: '
        '${trip.distanceM.toStringAsFixed(1)} m | '
        'TOTAL=${savedTrips.length}',
      );

      await VoiceCoachService.instance.speakEvent(VoiceCoachEvent.rideSaved);

      _rideStartedAt = null;
    } catch (e, st) {
      debugPrint('MAIN NAVIGATION RIDE STATE ERROR: $e');
      debugPrint('$st');
    } finally {
      _handlingRideState = false;

      if (mounted) {
        setState(() {
          rideData = _rideSessionService.current;
        });
      }
    }
  }

  void _toggleRideFromWheel() {
    final nextValue = !app.munjaRideActiveNotifier.value;

    debugPrint('WHEEL TOGGLE RIDE: $nextValue');

    app.munjaRideActiveNotifier.value = nextValue;
  }

  void _changeTab(int value) {
    if (value == index) return;

    setState(() {
      index = value;
    });
  }

  @override
  void dispose() {
    AppText.localeNotifier.removeListener(_onLanguageChanged);
    app.munjaRideActiveNotifier.removeListener(_onRideNotifierChanged);
    _rideSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: app.munjaRideActiveNotifier,
      builder: (context, isRiding, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              IndexedStack(index: index, children: screens),
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: SafeArea(
                  top: false,
                  child: WheelRadialMenu(
                    size: 118,
                    isRiding: isRiding,
                    liveSpeedKmh: rideData.currentSpeedKmh,
                    onWheelTap: _toggleRideFromWheel,
                    items: [
                      WheelRadialMenuItem(
                        icon: Icons.home_rounded,
                        label: AppText.t('home'),
                        onTap: () => _changeTab(0),
                      ),
                      WheelRadialMenuItem(
                        icon: Icons.directions_bike_rounded,
                        label: AppText.t('ride'),
                        onTap: () => _changeTab(1),
                      ),
                      WheelRadialMenuItem(
                        icon: Icons.garage_rounded,
                        label: AppText.t('garage'),
                        onTap: () => _changeTab(2),
                      ),
                      WheelRadialMenuItem(
                        icon: Icons.inventory_2_rounded,
                        label: AppText.t('gear'),
                        onTap: () => _changeTab(3),
                      ),
                      WheelRadialMenuItem(
                        icon: Icons.person_rounded,
                        label: AppText.t('profile'),
                        onTap: () => _changeTab(4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
