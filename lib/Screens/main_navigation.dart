import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../Models/active_ride_plan.dart';
import '../Services/active_ride_plan_service.dart';
import '../Services/route_service.dart';
import '../Services/background_ride_engine.dart';
import '../Services/live_ride_bus.dart';
import '../core/localization/app_text.dart';
import '../main.dart' as app;
import '../services/voice_coach_service.dart';
import '../widgets/wheel_radial_menu.dart';

import 'garage_screen.dart';
import 'gear_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'ride_setup_screen.dart';

enum _MunjaWheelVisualMode {
  full,
  compact,
  overlay,
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  static const Duration _screenTransitionDuration =
      Duration(milliseconds: 420);

  static const Curve _screenTransitionCurve =
      Curves.easeOutCubic;

  static const Duration _wheelAnimationDuration =
      Duration(milliseconds: 360);

  static const Curve _wheelAnimationCurve =
      Curves.easeOutCubic;

  int index = 0;

  _MunjaWheelVisualMode _wheelMode =
      _MunjaWheelVisualMode.full;

  bool _handlingRideState = false;
  bool _activeRidePlanReady = false;

  @override
  void initState() {
    super.initState();

    VoiceCoachService.instance.initialize();

    AppText.localeNotifier.addListener(_onLanguageChanged);

    Future.microtask(_initializeActiveRidePlan);
  }

  Future<void> _initializeActiveRidePlan() async {
    try {
      await ActiveRidePlanService.instance.initialize();

      debugPrint(
        'MAIN NAVIGATION ACTIVE PLAN INITIALIZED: '
        '${ActiveRidePlanService.instance.current}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MAIN NAVIGATION ACTIVE PLAN INIT ERROR: $error',
      );
      debugPrint('$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _activeRidePlanReady = true;
        });
      } else {
        _activeRidePlanReady = true;
      }
    }
  }

  void _onLanguageChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  double get _wheelScale {
    switch (_wheelMode) {
      case _MunjaWheelVisualMode.full:
        return 1.0;
      case _MunjaWheelVisualMode.compact:
        return 0.60;
      case _MunjaWheelVisualMode.overlay:
        return 0.25;
    }
  }

  double get _wheelOpacity {
    switch (_wheelMode) {
      case _MunjaWheelVisualMode.full:
        return 1.0;
      case _MunjaWheelVisualMode.compact:
        return 0.72;
      case _MunjaWheelVisualMode.overlay:
        return 0.28;
    }
  }

  bool get _wheelIgnoresPointer =>
      _wheelMode == _MunjaWheelVisualMode.overlay;

  _MunjaWheelVisualMode _modeForMainTab(int tabIndex) {
    return tabIndex == 0
        ? _MunjaWheelVisualMode.full
        : _MunjaWheelVisualMode.compact;
  }

  void _setWheelMode(_MunjaWheelVisualMode mode) {
    if (!mounted || _wheelMode == mode) {
      return;
    }

    setState(() {
      _wheelMode = mode;
    });
  }

  Future<void> _startCentralRideEngine() async {
    if (_handlingRideState || app.munjaRideActiveNotifier.value) {
      return;
    }

    _handlingRideState = true;

    try {
      debugPrint('MAIN NAVIGATION START CENTRAL RIDE ENGINE');

      await BackgroundRideEngine.instance.start();

      final liveState = LiveRideBus.instance.state.value;

      if (!liveState.isActive) {
        debugPrint(
          'MAIN NAVIGATION: BackgroundRideEngine did not become active.',
        );

        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Turen kunne ikke startes. Kontrollér GPS og tilladelser.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }

        return;
      }

      app.munjaRideActiveNotifier.value = true;

      await VoiceCoachService.instance.speakEvent(
        VoiceCoachEvent.rideStarted,
      );
    } catch (error, stackTrace) {
      debugPrint('MAIN NAVIGATION CENTRAL START ERROR: $error');
      debugPrint('$stackTrace');

      app.munjaRideActiveNotifier.value = false;
    } finally {
      _handlingRideState = false;
    }
  }

  Future<void> _stopCentralRideEngine() async {
    if (_handlingRideState) {
      return;
    }

    _handlingRideState = true;

    try {
      debugPrint('MAIN NAVIGATION STOP CENTRAL RIDE ENGINE');

      await VoiceCoachService.instance.speakEvent(
        VoiceCoachEvent.rideStopped,
      );

      final completedTrip = await BackgroundRideEngine.instance.stop();

      app.munjaRideActiveNotifier.value = false;

      if (completedTrip != null) {
        debugPrint(
          'MAIN NAVIGATION CENTRAL TRIP COMPLETED: '
          '${completedTrip.distanceM.toStringAsFixed(1)} m | '
          'path=${completedTrip.path.length}',
        );

        await VoiceCoachService.instance.speakEvent(
          VoiceCoachEvent.rideSaved,
        );
      } else {
        debugPrint(
          'MAIN NAVIGATION: BackgroundRideEngine returned no completed trip.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('MAIN NAVIGATION CENTRAL STOP ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      app.munjaRideActiveNotifier.value = false;
      _handlingRideState = false;
    }
  }

  Future<void> _handleWheelRideAction() async {
    if (_handlingRideState) {
      return;
    }

    // If a ride is already active, the wheel keeps its Stop behavior.
    if (app.munjaRideActiveNotifier.value) {
      await _stopRideFromWheel();
      return;
    }

    // IMPORTANT:
    // When no ride is active, holding the wheel must NEVER auto-start a stale
    // planned route. It always opens the Ride planner so the rider consciously
    // chooses Destination / Rundtur / Forslag / Fri tur.
    //
    // Any previously persisted plan can still be reused by the planner flow,
    // but it must not start by itself from the wheel.
    if (mounted) {
      setState(() {
        index = 1;
        _wheelMode = _modeForMainTab(1);
      });
    }
  }

  void _onRideSetupStart(RideSetupResult result) {
    unawaited(_startRideFromPlanner(result));
  }

  Future<void> _startRideFromPlanner(
    RideSetupResult result,
  ) async {
    if (_handlingRideState ||
        app.munjaRideActiveNotifier.value) {
      return;
    }

    // Free ride must not depend on a planned route.
    // It starts the normal ride session directly and returns Home
    // where the live ride UI can take over.
    if (result.mode == RideSetupMode.freeRide) {
      debugPrint(
        'MAIN NAVIGATION START FREE RIDE: '
        'bikeType=${result.bikeType.name}, '
        'distanceKm=${result.distanceKm}',
      );

      try {
        await ActiveRidePlanService.instance.clear();
      } catch (error, stackTrace) {
        debugPrint(
          'MAIN NAVIGATION FREE RIDE CLEAR PLAN ERROR: $error',
        );
        debugPrint('$stackTrace');
      }

      await _startCentralRideEngine();

      if (!mounted || !app.munjaRideActiveNotifier.value) {
        return;
      }

      setState(() {
        index = 0;
      });

      return;
    }

    if (result.mode == RideSetupMode.roundTrip) {
      await _startRoundTripFromPlanner(result);
      return;
    }

    if (result.mode == RideSetupMode.suggestedRoute) {
      await _startSuggestedRouteFromPlanner(result);
      return;
    }

    if (!_activeRidePlanReady) {
      await ActiveRidePlanService.instance.initialize();
      _activeRidePlanReady = true;
    }

    var activePlan = ActiveRidePlanService.instance.current;

    // If the planner has returned a destination/round-trip/suggestion
    // but the service has not yet created a plan, create it here.
    // This keeps Destination working and prepares the same flow for
    // Rundtur and Forslag.
    if (activePlan == null) {
      try {
        activePlan =
            await ActiveRidePlanService.instance.createAndSave(
          mode: _toActiveRideMode(result.mode),
          bikeType: _toActiveRideBikeType(result.bikeType),
          distanceKm: result.distanceKm,
          destination: result.destination,
          destinationPlaceId: result.destinationPlaceId,
          destinationLatitude: result.destinationLatitude,
          destinationLongitude: result.destinationLongitude,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'MAIN NAVIGATION CREATE PLAN ERROR: $error',
        );
        debugPrint('$stackTrace');
      }
    }

    if (activePlan == null) {
      debugPrint(
        'MAIN NAVIGATION: RideSetup finished without an active plan.',
      );

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Turen kunne ikke startes. Prøv at planlægge den igen.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }

      return;
    }

    debugPrint(
      'MAIN NAVIGATION PLANNER READY: '
      'mode=${result.mode.name}, '
      'destination=${result.destination}, '
      'plan=${activePlan.id}',
    );

    await _startPlannedRide(activePlan);
  }

  Future<void> _startSuggestedRouteFromPlanner(
    RideSetupResult result,
  ) async {
    debugPrint(
      'MAIN NAVIGATION PREPARE SUGGESTED ROUTE: '
      'distanceKm=${result.distanceKm}, '
      'bikeType=${result.bikeType.name}, '
      'hasRoute=${result.hasSuggestedRoute}',
    );

    if (!result.hasSuggestedRoute ||
        result.suggestedRouteDistanceMeters == null ||
        result.suggestedRouteDurationSeconds == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Vælg et ruteforslag først.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
      return;
    }

    if (!_activeRidePlanReady) {
      await ActiveRidePlanService.instance.initialize();
      _activeRidePlanReady = true;
    }

    try {
      final position = await _getPlannerCurrentPosition();

      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Munja kunne ikke finde din GPS-position. '
                  'Kontrollér placeringstilladelsen og prøv igen.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
        return;
      }

      await ActiveRidePlanService.instance.clear();

      var activePlan =
          await ActiveRidePlanService.instance.createAndSave(
        mode: ActiveRideMode.suggestedRoute,
        bikeType: _toActiveRideBikeType(result.bikeType),
        distanceKm: result.distanceKm,
        destination: 'Munja ruteforslag',
        destinationLatitude: position.latitude,
        destinationLongitude: position.longitude,
      );

      await ActiveRidePlanService.instance.updateStartPosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await ActiveRidePlanService.instance.updateCalculatedRoute(
        routeDistanceMeters:
            result.suggestedRouteDistanceMeters!,
        routeDurationSeconds:
            result.suggestedRouteDurationSeconds!,
        encodedPolyline:
            result.suggestedRouteEncodedPolyline!,
      );

      activePlan =
          ActiveRidePlanService.instance.current ?? activePlan;

      debugPrint(
        'MAIN NAVIGATION SUGGESTED ROUTE READY: '
        'id=${activePlan.id}, '
        'requested=${result.distanceKm.toStringAsFixed(1)}km, '
        'actual=${(result.suggestedRouteDistanceMeters! / 1000).toStringAsFixed(1)}km, '
        'duration=${result.suggestedRouteDurationSeconds}s',
      );

      await _startPlannedRide(activePlan);
    } catch (error, stackTrace) {
      debugPrint(
        'MAIN NAVIGATION SUGGESTED ROUTE ERROR: $error',
      );
      debugPrint('$stackTrace');

      try {
        await ActiveRidePlanService.instance.clear();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Ruteforslaget kunne ikke startes. Prøv igen.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
  }

  Future<void> _startRoundTripFromPlanner(
    RideSetupResult result,
  ) async {
    debugPrint(
      'MAIN NAVIGATION PREPARE ROUND TRIP: '
      'distanceKm=${result.distanceKm}, '
      'bikeType=${result.bikeType.name}',
    );

    if (!_activeRidePlanReady) {
      await ActiveRidePlanService.instance.initialize();
      _activeRidePlanReady = true;
    }

    try {
      final position = await _getPlannerCurrentPosition();

      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                content: Text(
                  'Munja kunne ikke finde din GPS-position. '
                  'Kontrollér placeringstilladelsen og prøv igen.',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Munja laver en rundtur på ca. '
                '${result.distanceKm.toStringAsFixed(0)} km...',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      }

      await ActiveRidePlanService.instance.clear();

      var activePlan =
          await ActiveRidePlanService.instance.createAndSave(
        mode: ActiveRideMode.roundTrip,
        bikeType: _toActiveRideBikeType(result.bikeType),
        distanceKm: result.distanceKm,
        destination: 'Rundtur',
        destinationLatitude: position.latitude,
        destinationLongitude: position.longitude,
      );

      final route =
          await RouteService.instance.calculateRoundTrip(
        originLatitude: position.latitude,
        originLongitude: position.longitude,
        targetDistanceKm: result.distanceKm,
      );

      await ActiveRidePlanService.instance.updateStartPosition(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await ActiveRidePlanService.instance.updateCalculatedRoute(
        routeDistanceMeters: route.distanceMeters,
        routeDurationSeconds: route.durationSeconds,
        encodedPolyline: route.encodedPolyline,
      );

      activePlan =
          ActiveRidePlanService.instance.current ?? activePlan;

      debugPrint(
        'MAIN NAVIGATION ROUND TRIP READY: '
        'id=${activePlan.id}, '
        'requested=${result.distanceKm.toStringAsFixed(1)}km, '
        'actual=${(route.distanceMeters / 1000).toStringAsFixed(1)}km, '
        'duration=${route.durationSeconds}s, '
        'steps=${route.navigationSteps.length}',
      );

      await _startPlannedRide(activePlan);
    } on RouteServiceException catch (error, stackTrace) {
      debugPrint(
        'MAIN NAVIGATION ROUND TRIP ROUTE ERROR: $error',
      );
      debugPrint('$stackTrace');

      try {
        await ActiveRidePlanService.instance.clear();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Munja kunne ikke finde en rundtur i området. '
                '${error.message}',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    } catch (error, stackTrace) {
      debugPrint(
        'MAIN NAVIGATION ROUND TRIP ERROR: $error',
      );
      debugPrint('$stackTrace');

      try {
        await ActiveRidePlanService.instance.clear();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Rundturen kunne ikke oprettes. Prøv igen.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
      }
    }
  }

  Future<Position?> _getPlannerCurrentPosition() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint(
          'MAIN NAVIGATION ROUND TRIP: '
          'location service disabled',
        );
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint(
          'MAIN NAVIGATION ROUND TRIP: '
          'location permission=$permission',
        );
        return null;
      }

      final lastKnown =
          await Geolocator.getLastKnownPosition();

      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (error) {
        debugPrint(
          'MAIN NAVIGATION ROUND TRIP CURRENT POSITION '
          'FALLBACK: $error',
        );
        return lastKnown;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'MAIN NAVIGATION ROUND TRIP POSITION ERROR: $error',
      );
      debugPrint('$stackTrace');
      return null;
    }
  }

  ActiveRideMode _toActiveRideMode(
    RideSetupMode mode,
  ) {
    switch (mode) {
      case RideSetupMode.destination:
        return ActiveRideMode.destination;
      case RideSetupMode.roundTrip:
        return ActiveRideMode.roundTrip;
      case RideSetupMode.suggestedRoute:
        return ActiveRideMode.suggestedRoute;
      case RideSetupMode.freeRide:
        return ActiveRideMode.freeRide;
    }
  }

  ActiveRideBikeType _toActiveRideBikeType(
    RideBikeType bikeType,
  ) {
    switch (bikeType) {
      case RideBikeType.mtb:
        return ActiveRideBikeType.mtb;
      case RideBikeType.road:
        return ActiveRideBikeType.road;
      case RideBikeType.family:
        return ActiveRideBikeType.family;
      case RideBikeType.nature:
        return ActiveRideBikeType.nature;
      case RideBikeType.quietRoads:
        return ActiveRideBikeType.quietRoads;
    }
  }

  Future<void> _startPlannedRide(
    ActiveRidePlan activePlan,
  ) async {
    if (app.munjaRideActiveNotifier.value) {
      return;
    }

    debugPrint(
      'WHEEL START PLANNED RIDE: '
      'id=${activePlan.id}, '
      'mode=${activePlan.mode.name}, '
      'destination=${activePlan.destination}, '
      'latitude=${activePlan.destinationLatitude}, '
      'longitude=${activePlan.destinationLongitude}',
    );

    await _startCentralRideEngine();

    if (!mounted || !app.munjaRideActiveNotifier.value) {
      return;
    }

    setState(() {
      index = 0;
    });
  }

  Future<void> _stopRideFromWheel() async {
    debugPrint('WHEEL STOP RIDE');

    await _stopCentralRideEngine();

    if (mounted) {
      setState(() {
        index = 0;
      });
    }

    try {
      await ActiveRidePlanService.instance.clear();
    } catch (error, stackTrace) {
      debugPrint('WHEEL CLEAR ACTIVE PLAN ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  void _changeTab(int value) {
    if (value == index) {
      return;
    }

    setState(() {
      index = value;
      _wheelMode = _modeForMainTab(value);
    });
  }

  Widget _screenForIndex(int value) {
    late final Widget child;

    switch (value) {
      case 0:
        child = HomeScreen(
          onOpenGarage: () => _changeTab(2),
        );
        break;
      case 1:
        child = RideSetupScreen(
          onStartRide: _onRideSetupStart,
          onBackToHome: () => _changeTab(0),
        );
        break;
      case 2:
        child = const GarageScreen();
        break;
      case 3:
        child = const GearScreen();
        break;
      case 4:
        child = const ProfileScreen();
        break;
      default:
        child = HomeScreen(
          onOpenGarage: () => _changeTab(2),
        );
    }

    // Each main tab owns a nested Navigator.
    // This is important for Munja's global wheel: Garage subpages such as
    // BikeCustomizeScreen are pushed inside this content navigator instead
    // of on top of MainNavigation. The global WheelRadialMenu therefore
    // remains visible and interactive on every pushed subpage.
    return Navigator(
      key: ValueKey<String>('munja-content-navigator-$value'),
      observers: <NavigatorObserver>[
        _wheelNavigatorObserver(value),
      ],
      onGenerateRoute: (settings) {
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => child,
        );
      },
    );
  }

  NavigatorObserver _wheelNavigatorObserver(int tabIndex) {
    return _WheelDepthObserver(
      onDepthChanged: (depth) {
        if (!mounted || tabIndex != index) {
          return;
        }

        if (depth > 1) {
          _setWheelMode(_MunjaWheelVisualMode.overlay);
        } else {
          _setWheelMode(_modeForMainTab(tabIndex));
        }
      },
    );
  }

  Widget _buildScreenTransition(
    Widget child,
    Animation<double> animation,
  ) {
    final fadeAnimation = CurvedAnimation(
      parent: animation,
      curve: _screenTransitionCurve,
      reverseCurve: Curves.easeInCubic,
    );

    final slideAnimation = Tween<Offset>(
      begin: const Offset(0.035, 0),
      end: Offset.zero,
    ).animate(fadeAnimation);

    final scaleAnimation = Tween<double>(
      begin: 0.992,
      end: 1,
    ).animate(fadeAnimation);

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: ScaleTransition(
          scale: scaleAnimation,
          child: child,
        ),
      ),
    );
  }

  @override
  void dispose() {
    AppText.localeNotifier.removeListener(_onLanguageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: app.munjaRideActiveNotifier,
      builder: (context, isRiding, _) {
        return ValueListenableBuilder(
          valueListenable: LiveRideBus.instance.state,
          builder: (context, liveRideState, _) {
            return Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: true,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // IMPORTANT:
              // Do not use AnimatedSwitcher for screens that can host the native
              // Digital Twin. AnimatedSwitcher deliberately keeps previousChildren
              // alive during the transition, which briefly creates two owners of
              // the same native texture. A keyed direct child gives Flutter one
              // active content Navigator at a time.
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey<String>('munja-main-tab-$index'),
                  child: _screenForIndex(index),
                ),
              ),
              // Global Munja wheel.
              //
              // Keep the wheel slightly lower so it sits in the same calm
              // bottom area as on Profile and interferes less with page
              // actions such as the Ride Planner summary/start button.
              // SafeArea still protects it from the Android system gesture bar.
              Positioned(
                left: 0,
                right: 0,
                bottom: -12,
                child: SafeArea(
                  top: false,
                  child: IgnorePointer(
                    ignoring: _wheelIgnoresPointer,
                    child: AnimatedOpacity(
                      duration: _wheelAnimationDuration,
                      curve: _wheelAnimationCurve,
                      opacity: _wheelOpacity,
                      child: AnimatedScale(
                        duration: _wheelAnimationDuration,
                        curve: _wheelAnimationCurve,
                        scale: _wheelScale,
                        alignment: Alignment.bottomCenter,
                        child: WheelRadialMenu(
                          size: 118,
                          isRiding: isRiding,
                          liveSpeedKmh:
                              liveRideState.speedKmh,
                          onWheelTap:
                              _handleWheelRideAction,
                          items: [
                            WheelRadialMenuItem(
                              icon: Icons.home_rounded,
                              label: AppText.t('home'),
                              onTap: () =>
                                  _changeTab(0),
                            ),
                            WheelRadialMenuItem(
                              icon: Icons
                                  .directions_bike_rounded,
                              label: AppText.t('ride'),
                              onTap: () {
                                if (isRiding) {
                                  _changeTab(0);
                                } else {
                                  _changeTab(1);
                                }
                              },
                            ),
                            WheelRadialMenuItem(
                              icon:
                                  Icons.pedal_bike_rounded,
                              label:
                                  AppText.t('garage'),
                              onTap: () =>
                                  _changeTab(2),
                            ),
                            WheelRadialMenuItem(
                              icon: Icons
                                  .inventory_2_rounded,
                              label: AppText.t('gear'),
                              onTap: () =>
                                  _changeTab(3),
                            ),
                            WheelRadialMenuItem(
                              icon: Icons.person_rounded,
                              label:
                                  AppText.t('profile'),
                              onTap: () =>
                                  _changeTab(4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
            );
          },
        );
      },
    );
  }

}


class _WheelDepthObserver extends NavigatorObserver {
  _WheelDepthObserver({
    required this.onDepthChanged,
  });

  final ValueChanged<int> onDepthChanged;

  int _depth = 0;

  void _notify() {
    onDepthChanged(_depth);
  }

  @override
  void didPush(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    super.didPush(route, previousRoute);
    _depth += 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notify();
    });
  }

  @override
  void didPop(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    super.didPop(route, previousRoute);
    _depth = (_depth - 1).clamp(0, 999);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notify();
    });
  }

  @override
  void didRemove(
    Route<dynamic> route,
    Route<dynamic>? previousRoute,
  ) {
    super.didRemove(route, previousRoute);
    _depth = (_depth - 1).clamp(0, 999);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notify();
    });
  }

  @override
  void didReplace({
    Route<dynamic>? newRoute,
    Route<dynamic>? oldRoute,
  }) {
    super.didReplace(
      newRoute: newRoute,
      oldRoute: oldRoute,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notify();
    });
  }
}
