import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../Models/active_ride_plan.dart';
import '../Models/navigation_instruction.dart';
import '../Models/navigation_arrow.dart';
import '../Models/reroute_result.dart';
import '../Services/active_ride_plan_service.dart';
import '../Services/arrival_service.dart';
import '../Services/navigation_service.dart';
import '../Services/navigation_arrow_service.dart';
import '../Services/reroute_service.dart';
import '../Services/route_service.dart';
import '../Services/voice_navigation_service.dart';
import '../core/localization/app_text.dart';
import '../main.dart' as app;
import '../core/theme/munja_colors.dart';
import '../models/live_ride_state.dart';
import '../Services/live_ride_bus.dart';
import '../services/ride_session_service.dart';
import '../services/ai_ride_coach_service.dart';
import '../Services/munja_pro_service.dart';
import '../services/storage_service.dart';
import '../services/xp_service.dart';
import '../widgets/live_hud_overlay.dart';

class AutoRideScreen extends StatefulWidget {
  const AutoRideScreen({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<AutoRideScreen> createState() => _AutoRideScreenState();
}

class _AutoRideScreenState extends State<AutoRideScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSubscription;

  bool _showMap = true;
  bool _loadingPosition = true;
  bool _didFitInitialRoute = false;

  LatLng? _currentPosition;
  double _currentHeading = 0;

  double? _lastNavigationLatitude;
  double? _lastNavigationLongitude;
  String? _configuredNavigationPlanId;
  String? _configuredArrowPlanId;
  String? _configuredRouteSignature;
  RerouteStatus? _lastVoiceRerouteStatus;
  String? _voiceRouteSignature;
  bool _handlingConfirmedArrival = false;
  bool _sideEffectsRunning = false;
  bool _sideEffectsPending = false;
  DateTime? _lastSideEffectRun;
  DateTime? _lastCameraFollowAt;
  DateTime? _lastAppliedRerouteFinishedAt;
  bool _applyingSuccessfulReroute = false;

  // LOOP / ROUND-TRIP ARRIVAL GUARD
  //
  // A round trip starts and ends at the same GPS coordinate. A normal
  // destination engine therefore sees the rider as "arrived" at second 0.
  // We arm arrival only after the rider has actually left the start area and
  // completed most of the planned loop.
  String? _loopProgressPlanId;
  bool _loopHasDepartedStart = false;
  bool _loopArrivalArmed = false;
  double _loopMaxDistanceFromStartMeters = 0;

  static const double _loopDepartureRadiusMeters = 120;
  static const double _loopArrivalArmFraction = 0.72;
  static const double _loopArrivalArmRemainingBufferMeters = 350;

  final AiRideCoachService _aiCoach = AiRideCoachService();
  CoachInsight? _coachInsight;
  DateTime? _lastCoachEvaluationAt;
  double? _historicAverageSpeedKmh;
  double? _historicAverageDistanceKm;

  BitmapDescriptor? _routeArrowIcon;
  BitmapDescriptor? _activeArrowIcon;
  BitmapDescriptor? _passedArrowIcon;
  String? _cachedRouteSignature;
  List<LatLng> _cachedRoutePoints = const <LatLng>[];

  static const double bottomWheelSafePadding = 248;

  static const CameraPosition _fallbackCamera = CameraPosition(
    target: LatLng(55.4038, 10.4024),
    zoom: 13.5,
  );

  @override
  void initState() {
    super.initState();

    ActiveRidePlanService.instance.notifier.addListener(
      _onActivePlanChanged,
    );
    LiveRideBus.instance.state.addListener(
      _onLiveRideChanged,
    );
    NavigationService.instance.state.addListener(
      _onNavigationStateChanged,
    );
    RerouteService.instance.status.addListener(
      _onRerouteStatusChanged,
    );

    Future.microtask(_initializeScreen);
    Future.microtask(_prepareArrowIcons);
    Future.microtask(_initializeVoiceNavigation);
    Future.microtask(_initializeArrivalService);
    Future.microtask(_loadCoachHistory);
  }

  Future<void> _loadCoachHistory() async {
    try {
      final trips = await StorageService.loadTrips();

      if (trips.isEmpty) {
        return;
      }

      final totalDistance =
          XpService.totalDistanceKm(trips);

      final avgDistance =
          totalDistance / trips.length;

      if (!mounted) {
        return;
      }

      setState(() {
        _historicAverageDistanceKm = avgDistance;
        _historicAverageSpeedKmh = null;
      });
    } catch (error, stackTrace) {
      debugPrint('AUTO RIDE COACH HISTORY ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  bool _isLoopPlan(ActiveRidePlan? plan) {
    return plan != null &&
        (plan.isRoundTrip || plan.isSuggestedRoute);
  }

  void _resetLoopProgressForPlan(ActiveRidePlan? plan) {
    _loopProgressPlanId = plan?.id;
    _loopHasDepartedStart = false;
    _loopArrivalArmed = false;
    _loopMaxDistanceFromStartMeters = 0;

    if (_isLoopPlan(plan)) {
      // Never inherit an arrival timer/state from a previous route.
      ArrivalService.instance.reset();

      debugPrint(
        'AUTO RIDE LOOP GUARD RESET: '
        'plan=${plan?.id} mode=${plan?.mode.name}',
      );
    }
  }

  LatLng? _loopStartPosition(ActiveRidePlan? plan) {
    if (plan == null) {
      return null;
    }

    if (plan.hasStartCoordinates) {
      return LatLng(
        plan.startLatitude!,
        plan.startLongitude!,
      );
    }

    final points = _routePointsForPlan(plan);

    if (points.isEmpty) {
      return null;
    }

    return points.first;
  }

  void _updateLoopProgress({
    required ActiveRidePlan? plan,
    required LiveRideState ride,
    required LatLng? position,
  }) {
    if (!_isLoopPlan(plan)) {
      if (_loopProgressPlanId != null) {
        _resetLoopProgressForPlan(null);
      }
      return;
    }

    if (_loopProgressPlanId != plan!.id) {
      _resetLoopProgressForPlan(plan);
    }

    if (position == null) {
      return;
    }

    final start = _loopStartPosition(plan);

    if (start == null) {
      return;
    }

    final distanceFromStart =
        Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      position.latitude,
      position.longitude,
    );

    if (distanceFromStart >
        _loopMaxDistanceFromStartMeters) {
      _loopMaxDistanceFromStartMeters =
          distanceFromStart;
    }

    if (!_loopHasDepartedStart &&
        _loopMaxDistanceFromStartMeters >=
            _loopDepartureRadiusMeters) {
      _loopHasDepartedStart = true;

      debugPrint(
        'AUTO RIDE LOOP DEPARTED: '
        '${_loopMaxDistanceFromStartMeters.toStringAsFixed(0)}m from start',
      );
    }

    final routeDistanceMeters =
        plan.routeDistanceMeters ??
            (plan.distanceKm * 1000);

    final riddenMeters = ride.distanceKm * 1000;

    final fractionThreshold =
        routeDistanceMeters *
            _loopArrivalArmFraction;

    final finishBufferThreshold =
        math.max(
      0.0,
      routeDistanceMeters -
          _loopArrivalArmRemainingBufferMeters,
    );

    // Use the less strict of the two "near finish" thresholds.
    // For short routes the percentage dominates; for long routes the rider
    // can arm arrival shortly before the planned finish.
    final armThreshold = math.min(
      fractionThreshold,
      finishBufferThreshold,
    );

    final shouldArm =
        _loopHasDepartedStart &&
        riddenMeters >= armThreshold;

    if (shouldArm && !_loopArrivalArmed) {
      _loopArrivalArmed = true;
      ArrivalService.instance.reset();

      debugPrint(
        'AUTO RIDE LOOP ARRIVAL ARMED: '
        'ridden=${riddenMeters.toStringAsFixed(0)}m '
        'planned=${routeDistanceMeters.toStringAsFixed(0)}m '
        'threshold=${armThreshold.toStringAsFixed(0)}m',
      );
    }
  }

  bool _allowArrivalForPlan(
    ActiveRidePlan? plan,
  ) {
    if (!_isLoopPlan(plan)) {
      return true;
    }

    return _loopArrivalArmed;
  }

  Future<void> _initializeScreen() async {
    await ActiveRidePlanService.instance.initialize();
    await _loadCurrentPosition();
    await _startPositionStream();

    final initialPlan =
        ActiveRidePlanService.instance.current;

    _resetLoopProgressForPlan(initialPlan);
    _updateLoopProgress(
      plan: initialPlan,
      ride: LiveRideBus.instance.state.value,
      position: _currentPosition,
    );

    _configureNavigationForPlan(initialPlan);

    _updateNavigationFromPosition(_currentPosition);

    if (!mounted) {
      return;
    }

    setState(() {});

    _fitMapToPlan();
  }


  String get _voiceNavigationLanguageCode {
    switch (AppText.currentLanguageCode) {
      case 'en':
        return 'en-US';
      case 'bs':
        return 'bs-BA';
      case 'da':
      default:
        return 'da-DK';
    }
  }

  Future<void> _initializeVoiceNavigation() async {
    await VoiceNavigationService.instance.initialize();

    // Keep spoken navigation in sync with the language selected in Munja.
    await VoiceNavigationService.instance.setLanguageCode(
      _voiceNavigationLanguageCode,
    );
    await VoiceNavigationService.instance.setEnabled(true);
  }

  Future<void> _initializeArrivalService() async {
    ArrivalService.instance.configure(
      onArrivalConfirmed: _handleConfirmedArrival,
    );
  }

  Future<void> _handleConfirmedArrival() async {
    if (_handlingConfirmedArrival) {
      return;
    }

    final plan =
        ActiveRidePlanService.instance.current;

    if (!_allowArrivalForPlan(plan)) {
      debugPrint(
        'AUTO RIDE ARRIVAL IGNORED: '
        'loop has not completed enough progress yet.',
      );
      ArrivalService.instance.reset();
      return;
    }

    _handlingConfirmedArrival = true;

    try {
      debugPrint('AUTO RIDE ARRIVAL CONFIRMED');

      RerouteService.instance.cancelPendingConfirmation();

      await VoiceNavigationService.instance.stop();

      if (app.munjaRideActiveNotifier.value) {
        app.munjaRideActiveNotifier.value = false;
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppText.t('autoRideArrivedSaved'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'AUTO RIDE ARRIVAL HANDLER ERROR: $error',
      );
      debugPrint('$stackTrace');
    } finally {
      _handlingConfirmedArrival = false;
    }
  }

  Future<void> _prepareArrowIcons() async {
    try {
      final routeIcon = await _createArrowIcon(
        fillColor: const Color(0xFFF5F7F6),
        borderColor: const Color(0xFF10201B),
      );

      final activeIcon = await _createArrowIcon(
        fillColor: MunjaColors.mint,
        borderColor: const Color(0xFF03130F),
      );

      final passedIcon = await _createArrowIcon(
        fillColor: const Color(0xFF6F7774),
        borderColor: const Color(0xFF252B29),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _routeArrowIcon = routeIcon;
        _activeArrowIcon = activeIcon;
        _passedArrowIcon = passedIcon;
      });
    } catch (error, stackTrace) {
      debugPrint('AUTO RIDE ARROW ICON ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<BitmapDescriptor> _createArrowIcon({
    required Color fillColor,
    required Color borderColor,
  }) async {
    const logicalSize = 52.0;
    const pixelRatio = 2.0;
    const canvasSize = logicalSize * pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(
        0,
        0,
        canvasSize,
        canvasSize,
      ),
    );

    canvas.scale(pixelRatio);

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.32)
      ..maskFilter = const ui.MaskFilter.blur(
        ui.BlurStyle.normal,
        3,
      );

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final shadowPath = Path()
      ..moveTo(26, 5)
      ..lineTo(46, 43)
      ..lineTo(26, 35)
      ..lineTo(6, 43)
      ..close();

    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(shadowPath, shadowPaint);
    canvas.restore();

    final borderPath = Path()
      ..moveTo(26, 3)
      ..lineTo(48, 46)
      ..lineTo(26, 37)
      ..lineTo(4, 46)
      ..close();

    canvas.drawPath(borderPath, borderPaint);

    final fillPath = Path()
      ..moveTo(26, 8)
      ..lineTo(42, 39)
      ..lineTo(26, 32)
      ..lineTo(10, 39)
      ..close();

    canvas.drawPath(fillPath, fillPaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      canvasSize.toInt(),
      canvasSize.toInt(),
    );
    final byteData = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );

    if (byteData == null) {
      throw StateError('Arrow icon could not be encoded.');
    }

    final bytes = Uint8List.view(byteData.buffer);

    return BitmapDescriptor.fromBytes(bytes);
  }

  Future<void> _loadCurrentPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        if (mounted) {
          setState(() => _loadingPosition = false);
        }
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _loadingPosition = false);
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _currentPosition = LatLng(
          position.latitude,
          position.longitude,
        );
        _currentHeading = _safeHeading(position.heading);
        _loadingPosition = false;
      });
    } catch (error, stackTrace) {
      debugPrint('AUTO RIDE POSITION ERROR: $error');
      debugPrint('$stackTrace');

      if (mounted) {
        setState(() => _loadingPosition = false);
      }
    }
  }

  Future<void> _startPositionStream() async {
    await _positionSubscription?.cancel();

    final enabled = await Geolocator.isLocationServiceEnabled();

    if (!enabled) {
      return;
    }

    final permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _handlePositionUpdate,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('AUTO RIDE POSITION STREAM ERROR: $error');
        debugPrint('$stackTrace');
      },
    );
  }

  void _handlePositionUpdate(Position position) {
    if (!mounted) {
      return;
    }

    final nextPosition = LatLng(
      position.latitude,
      position.longitude,
    );
    final nextHeading = _safeHeading(position.heading);

    setState(() {
      _currentPosition = nextPosition;
      _currentHeading = nextHeading;
      _loadingPosition = false;
    });

    final ride = LiveRideBus.instance.state.value;
    final plan = _activePlan;

    _updateLoopProgress(
      plan: plan,
      ride: ride,
      position: nextPosition,
    );

    _configureNavigationForPlan(plan);
    _updateNavigationFromPosition(
      nextPosition,
      allowReroute: ride.isActive,
    );

    unawaited(
      _followMapPosition(
        position: nextPosition,
        heading: nextHeading,
        force: false,
      ),
    );
  }

  double _safeHeading(double heading) {
    if (!heading.isFinite || heading < 0) {
      return _currentHeading;
    }

    return heading % 360;
  }

  LatLng _cameraTargetAhead(
    LatLng position,
    double headingDegrees,
  ) {
    // Put the rider slightly below the visual center so more of the
    // road ahead remains visible above the 3D handlebar.
    const distanceMeters = 34.0;
    const earthRadiusMeters = 6378137.0;

    final bearing = headingDegrees * math.pi / 180;
    final latitude1 = position.latitude * math.pi / 180;
    final longitude1 = position.longitude * math.pi / 180;
    final angularDistance =
        distanceMeters / earthRadiusMeters;

    final latitude2 = math.asin(
      math.sin(latitude1) * math.cos(angularDistance) +
          math.cos(latitude1) *
              math.sin(angularDistance) *
              math.cos(bearing),
    );

    final longitude2 = longitude1 +
        math.atan2(
          math.sin(bearing) *
              math.sin(angularDistance) *
              math.cos(latitude1),
          math.cos(angularDistance) -
              math.sin(latitude1) * math.sin(latitude2),
        );

    return LatLng(
      latitude2 * 180 / math.pi,
      longitude2 * 180 / math.pi,
    );
  }

  void _onActivePlanChanged() {
    _didFitInitialRoute = false;
    _cachedRouteSignature = null;
    _cachedRoutePoints = const <LatLng>[];

    final plan = ActiveRidePlanService.instance.current;
    final ride = LiveRideBus.instance.state.value;
    final current = _bestCurrentPosition(ride);

    if (_loopProgressPlanId != plan?.id) {
      _resetLoopProgressForPlan(plan);
    }

    _updateLoopProgress(
      plan: plan,
      ride: ride,
      position: current,
    );

    _configureNavigationForPlan(plan);
    _updateNavigationFromPosition(
      current,
      allowReroute: false,
    );

    if (!mounted) {
      return;
    }

    setState(() {});

    if (current != null && ride.isActive) {
      unawaited(
        _followMapPosition(
          position: current,
          heading: _currentHeading,
          force: true,
        ),
      );
    } else {
      _fitMapToPlan();
    }
  }

  void _onLiveRideChanged() {
    final ride = LiveRideBus.instance.state.value;

    _updateLoopProgress(
      plan: _activePlan,
      ride: ride,
      position: _bestCurrentPosition(ride),
    );

    _updateLiveNavigation(ride);
    _followCurrentPosition(ride);
    _scheduleNavigationSideEffects();
    _evaluateAiCoach(ride);
  }

  void _evaluateAiCoach(
    LiveRideState ride,
  ) {
    final now = DateTime.now();

    if (_lastCoachEvaluationAt != null &&
        now.difference(_lastCoachEvaluationAt!) <
            const Duration(seconds: 3)) {
      return;
    }

    _lastCoachEvaluationAt = now;

    final isPro = MunjaProService.instance.hasFeature(
      MunjaProFeature.aiRideCoach,
    );

    final insight = _aiCoach.analyze(
      data: _rideDataFromState(ride),
      bleConnected: false,
      batteryPercent: 64,
      tier: isPro
          ? AiCoachTier.pro
          : AiCoachTier.free,
      historicAverageSpeedKmh:
          _historicAverageSpeedKmh,
      historicAverageDistanceKm:
          _historicAverageDistanceKm,
    );

    final current = _coachInsight;

    final changed = current == null ||
        current.state != insight.state ||
        current.title != insight.title ||
        current.message != insight.message;

    if (!changed || !mounted) {
      return;
    }

    setState(() {
      _coachInsight = insight;
    });

    debugPrint(
      'AUTO RIDE AI COACH: '
      'tier=${isPro ? 'pro' : 'free'} '
      'state=${insight.state.name} '
      'title=${insight.title}',
    );
  }

  void _onNavigationStateChanged() {
    _scheduleNavigationSideEffects();
  }

  void _onRerouteStatusChanged() {
    _scheduleNavigationSideEffects();

    if (RerouteService.instance.status.value ==
        RerouteStatus.success) {
      unawaited(_applySuccessfulReroute());
    }
  }

  Future<void> _applySuccessfulReroute() async {
    if (_applyingSuccessfulReroute || !mounted) {
      return;
    }

    final result = RerouteService.instance.lastResult.value;

    if (result == null ||
        result.status != RerouteStatus.success ||
        result.finishedAt == null ||
        result.finishedAt == _lastAppliedRerouteFinishedAt) {
      return;
    }

    _applyingSuccessfulReroute = true;
    _lastAppliedRerouteFinishedAt = result.finishedAt;

    try {
      // ActiveRidePlanService has already published the new polyline.
      // Clear every local route cache/signature so the navigation engine,
      // arrows, HUD and map all consume that new route immediately.
      _configuredNavigationPlanId = null;
      _configuredArrowPlanId = null;
      _configuredRouteSignature = null;
      _cachedRouteSignature = null;
      _cachedRoutePoints = const <LatLng>[];
      _lastNavigationLatitude = null;
      _lastNavigationLongitude = null;
      _didFitInitialRoute = false;

      final plan = ActiveRidePlanService.instance.current;
      final current = _currentPosition ??
          LatLng(
            result.originLatitude,
            result.originLongitude,
          );

      _configureNavigationForPlan(plan);
      _updateNavigationFromPosition(
        current,
        allowReroute: false,
      );

      if (mounted) {
        setState(() {});
      }

      await _followMapPosition(
        position: current,
        heading: _currentHeading,
        force: true,
      );

      debugPrint(
        'AUTO RIDE APPLIED REROUTE: '
        'distance=${result.routeDistanceMeters}, '
        'duration=${result.routeDurationSeconds}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'AUTO RIDE APPLY REROUTE ERROR: $error',
      );
      debugPrint('$stackTrace');
    } finally {
      _applyingSuccessfulReroute = false;
    }
  }

  void _scheduleNavigationSideEffects() {
    if (!mounted) {
      return;
    }

    final now = DateTime.now();
    final lastRun = _lastSideEffectRun;

    if (lastRun != null &&
        now.difference(lastRun) <
            const Duration(milliseconds: 350)) {
      if (_sideEffectsPending) {
        return;
      }

      _sideEffectsPending = true;

      Future<void>.delayed(
        const Duration(milliseconds: 350),
        () {
          _sideEffectsPending = false;

          if (mounted) {
            _runNavigationSideEffects();
          }
        },
      );
      return;
    }

    _runNavigationSideEffects();
  }

  Future<void> _runNavigationSideEffects() async {
    if (_sideEffectsRunning || !mounted) {
      _sideEffectsPending = true;
      return;
    }

    _sideEffectsRunning = true;
    _lastSideEffectRun = DateTime.now();

    try {
      await _updateVoiceNavigation(
        ride: LiveRideBus.instance.state.value,
        navigationState:
            NavigationService.instance.state.value,
        rerouteStatus:
            RerouteService.instance.status.value,
        activePlan:
            ActiveRidePlanService.instance.current,
      );
    } finally {
      _sideEffectsRunning = false;

      if (_sideEffectsPending && mounted) {
        _sideEffectsPending = false;
        _scheduleNavigationSideEffects();
      }
    }
  }

  ActiveRidePlan? get _activePlan {
    return ActiveRidePlanService.instance.current;
  }

  LatLng? get _destinationPosition {
    final plan = _activePlan;

    if (plan == null || !plan.hasDestinationCoordinates) {
      return null;
    }

    return LatLng(
      plan.destinationLatitude!,
      plan.destinationLongitude!,
    );
  }


  List<LatLng> _routePointsForPlan(
    ActiveRidePlan? plan,
  ) {
    final routeSignature = _routeSignatureForPlan(plan);

    if (routeSignature == null) {
      _cachedRouteSignature = null;
      _cachedRoutePoints = const <LatLng>[];
      return _cachedRoutePoints;
    }

    if (_cachedRouteSignature == routeSignature) {
      return _cachedRoutePoints;
    }

    try {
      _cachedRoutePoints = RouteService.instance
          .decodePolyline(plan!.encodedPolyline!)
          .map(
            (point) => LatLng(
              point.latitude,
              point.longitude,
            ),
          )
          .toList(growable: false);

      _cachedRouteSignature = routeSignature;

      return _cachedRoutePoints;
    } catch (error, stackTrace) {
      debugPrint(
        'AUTO RIDE POLYLINE DECODE ERROR: $error',
      );
      debugPrint('$stackTrace');

      _cachedRouteSignature = null;
      _cachedRoutePoints = const <LatLng>[];

      return _cachedRoutePoints;
    }
  }


  String? _routeSignatureForPlan(
    ActiveRidePlan? plan,
  ) {
    final encodedPolyline = plan?.encodedPolyline;

    if (plan == null ||
        encodedPolyline == null ||
        encodedPolyline.trim().isEmpty ||
        plan.routeDistanceMeters == null ||
        plan.routeDurationSeconds == null) {
      return null;
    }

    return '${plan.id}|'
        '${encodedPolyline.hashCode}|'
        '${plan.routeDistanceMeters}|'
        '${plan.routeDurationSeconds}';
  }

  void _configureNavigationForPlan(
    ActiveRidePlan? plan,
  ) {
    final routeSignature = _routeSignatureForPlan(plan);

    if (plan == null ||
        !plan.hasCalculatedRoute ||
        routeSignature == null) {
      _configuredNavigationPlanId = null;
      _configuredArrowPlanId = null;
      _configuredRouteSignature = null;

      NavigationService.instance.clear();
      NavigationArrowService.instance.clear();
      RerouteService.instance.cancelPendingConfirmation();

      _voiceRouteSignature = null;
      VoiceNavigationService.instance.reset();
      ArrivalService.instance.reset();
      return;
    }

    if (_configuredNavigationPlanId == plan.id &&
        _configuredArrowPlanId == plan.id &&
        _configuredRouteSignature == routeSignature &&
        NavigationService.instance.hasRoute &&
        NavigationArrowService.instance.hasRoute) {
      return;
    }

    try {
      final routePoints = RouteService.instance.decodePolyline(
        plan.encodedPolyline!,
      );

      final navigationSteps =
          plan.navigationSteps.isNotEmpty
              ? plan.navigationSteps
              : RouteService.instance.lastNavigationSteps;

      NavigationService.instance.setRoute(
        points: routePoints,
        totalDistanceMeters: plan.routeDistanceMeters!,
        totalDurationSeconds: plan.routeDurationSeconds!,
        navigationSteps: navigationSteps,
      );

      NavigationArrowService.instance.setRoute(
        points: routePoints,
        spacingMeters: 110,
        maxArrowCount: 36,
      );

      _configuredNavigationPlanId = plan.id;
      _configuredArrowPlanId = plan.id;
      _configuredRouteSignature = routeSignature;

      if (_voiceRouteSignature != routeSignature) {
        _voiceRouteSignature = routeSignature;
        ArrivalService.instance.reset();

        Future.microtask(
          () => VoiceNavigationService.instance.startRoute(
            routeSignature,
          ),
        );
      }

      debugPrint(
        'AUTO RIDE NAVIGATION CONFIGURED: '
        'plan=${plan.id}, '
        'points=${routePoints.length}, '
        'googleSteps=${navigationSteps.length}, '
        'source=${navigationSteps.isNotEmpty ? 'google' : 'geometry-fallback'}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'AUTO RIDE NAVIGATION CONFIG ERROR: $error',
      );
      debugPrint('$stackTrace');

      _configuredNavigationPlanId = null;
      _configuredArrowPlanId = null;
      _configuredRouteSignature = null;
      _voiceRouteSignature = null;

      NavigationService.instance.clear();
      NavigationArrowService.instance.clear();
      VoiceNavigationService.instance.reset();
      ArrivalService.instance.reset();
    }
  }

  void _updateNavigationFromPosition(
    LatLng? position, {
    bool allowReroute = false,
  }) {
    if (position == null ||
        !NavigationService.instance.hasRoute) {
      return;
    }

    final samePosition =
        _lastNavigationLatitude == position.latitude &&
        _lastNavigationLongitude == position.longitude;

    if (samePosition) {
      return;
    }

    _lastNavigationLatitude = position.latitude;
    _lastNavigationLongitude = position.longitude;

    final navigationState =
        NavigationService.instance.updatePosition(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    NavigationArrowService.instance.updateProgress(
      latitude: position.latitude,
      longitude: position.longitude,
      activeRoutePointIndex:
          navigationState?.nearestRoutePointIndex,
    );

    if (allowReroute && navigationState != null) {
      RerouteService.instance.handleNavigationState(
        isOffRoute: navigationState.isOffRoute,
        distanceFromRouteMeters:
            navigationState.distanceFromRouteMeters,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } else {
      RerouteService.instance.cancelPendingConfirmation();
    }
  }

  void _updateLiveNavigation(
    LiveRideState ride,
  ) {
    final position = _bestCurrentPosition(ride);

    _configureNavigationForPlan(_activePlan);
    _updateNavigationFromPosition(
      position,
      allowReroute: ride.isActive,
    );
  }

  Future<void> _updateVoiceNavigation({
    required LiveRideState ride,
    required NavigationState? navigationState,
    required RerouteStatus rerouteStatus,
    required ActiveRidePlan? activePlan,
  }) async {
    if (!ride.isActive) {
      if (ArrivalService.instance.isConfirming) {
        ArrivalService.instance.cancelPendingConfirmation();
      }
      return;
    }

    final routeSignature = _routeSignatureForPlan(activePlan);

    if (routeSignature != null &&
        routeSignature != _voiceRouteSignature) {
      _voiceRouteSignature = routeSignature;

      await VoiceNavigationService.instance.startRoute(
        routeSignature,
      );
    }

    final instruction = navigationState?.currentInstruction;
    final arrivalAllowed =
        _allowArrivalForPlan(activePlan);

    if (arrivalAllowed) {
      ArrivalService.instance.handleNavigationInstruction(
        instruction: instruction,
        rideIsActive: ride.isActive,
      );
    } else {
      // A loop starts at its own destination. Do not let the normal
      // destination arrival engine complete the ride before the rider leaves.
      ArrivalService.instance.cancelPendingConfirmation();
    }

    final suppressPrematureLoopArrival =
        !arrivalAllowed &&
        instruction?.maneuver ==
            NavigationManeuver.arrive;

    if (instruction != null &&
        !suppressPrematureLoopArrival) {
      await VoiceNavigationService.instance.handleInstruction(
        instruction: instruction,
        rideIsActive: ride.isActive,
        routeId: routeSignature,
      );
    }

    if (_lastVoiceRerouteStatus == rerouteStatus) {
      return;
    }

    _lastVoiceRerouteStatus = rerouteStatus;

    if (rerouteStatus == RerouteStatus.rerouting) {
      await VoiceNavigationService.instance.announceRerouting(
        rideIsActive: ride.isActive,
      );
      return;
    }

    if (rerouteStatus == RerouteStatus.success) {
      await VoiceNavigationService.instance.announceRouteReady(
        rideIsActive: ride.isActive,
      );
    }
  }

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
          .map(
            (point) => <double>[
              point.latitude,
              point.longitude,
            ],
          )
          .toList(),
    );
  }

  LatLng? _bestCurrentPosition(LiveRideState ride) {
    // The direct Geolocator stream is configured for navigation and is
    // normally newer than the persisted ride path. Using ride.path first
    // could repeatedly feed an old on-route point into RerouteService and
    // cancel a valid off-route confirmation.
    if (_currentPosition != null) {
      return _currentPosition;
    }

    if (ride.path.isNotEmpty) {
      return ride.path.last;
    }

    return null;
  }

  Future<void> _followCurrentPosition(
    LiveRideState ride,
  ) async {
    if (!ride.isActive) {
      return;
    }

    final current = _bestCurrentPosition(ride);

    if (current == null) {
      return;
    }

    await _followMapPosition(
      position: current,
      heading: _currentHeading,
      force: false,
    );
  }

  Future<void> _followMapPosition({
    required LatLng position,
    required double heading,
    required bool force,
  }) async {
    if (!_showMap) {
      return;
    }

    final controller = _mapController;

    if (controller == null) {
      return;
    }

    final now = DateTime.now();
    final lastFollow = _lastCameraFollowAt;

    if (!force &&
        lastFollow != null &&
        now.difference(lastFollow) <
            const Duration(milliseconds: 700)) {
      return;
    }

    _lastCameraFollowAt = now;

    final target = widget.embedded
        ? _cameraTargetAhead(position, heading)
        : position;

    try {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: target,
            zoom: widget.embedded ? 18.7 : 17.5,
            tilt: widget.embedded ? 52.0 : 38.0,
            bearing: heading,
          ),
        ),
      );
    } catch (error) {
      debugPrint(
        'AUTO RIDE CAMERA FOLLOW ERROR: $error',
      );
    }
  }

  Future<void> _fitMapToPlan({
    LiveRideState? ride,
    bool force = false,
  }) async {
    final controller = _mapController;

    if (controller == null) {
      return;
    }

    if (_didFitInitialRoute && !force) {
      return;
    }

    final plan = _activePlan;
    final routePoints = _routePointsForPlan(plan);
    final destination = _destinationPosition;
    final current = ride == null
        ? _currentPosition
        : _bestCurrentPosition(ride);

    if (widget.embedded && current != null) {
      await Future<void>.delayed(
        const Duration(milliseconds: 180),
      );

      if (!mounted) {
        return;
      }

      await _followMapPosition(
        position: current,
        heading: _currentHeading,
        force: true,
      );

      _didFitInitialRoute = true;
      return;
    }

    final pointsForBounds = <LatLng>[
      ...routePoints,
      if (current != null) current,
      if (destination != null) destination,
    ];

    if (pointsForBounds.length >= 2) {
      var minLatitude = pointsForBounds.first.latitude;
      var maxLatitude = pointsForBounds.first.latitude;
      var minLongitude = pointsForBounds.first.longitude;
      var maxLongitude = pointsForBounds.first.longitude;

      for (final point in pointsForBounds.skip(1)) {
        if (point.latitude < minLatitude) {
          minLatitude = point.latitude;
        }

        if (point.latitude > maxLatitude) {
          maxLatitude = point.latitude;
        }

        if (point.longitude < minLongitude) {
          minLongitude = point.longitude;
        }

        if (point.longitude > maxLongitude) {
          maxLongitude = point.longitude;
        }
      }

      await Future<void>.delayed(
        const Duration(milliseconds: 260),
      );

      if (!mounted) {
        return;
      }

      try {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(
                minLatitude,
                minLongitude,
              ),
              northeast: LatLng(
                maxLatitude,
                maxLongitude,
              ),
            ),
            82,
          ),
        );

        _didFitInitialRoute = true;
        return;
      } catch (error) {
        debugPrint(
          'AUTO RIDE ROUTE BOUNDS ERROR: $error',
        );
      }
    }

    if (destination != null) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: destination,
            zoom: 15.5,
          ),
        ),
      );

      _didFitInitialRoute = true;
      return;
    }

    if (current != null) {
      await controller.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: current,
            zoom: 16.5,
          ),
        ),
      );

      _didFitInitialRoute = true;
    }
  }

  Future<void> _centerMap(LiveRideState ride) async {
    _didFitInitialRoute = false;

    await _fitMapToPlan(
      ride: ride,
      force: true,
    );
  }

  void _toggleMapMode() {
    setState(() {
      _showMap = !_showMap;
    });
  }

  @override
  void dispose() {
    ActiveRidePlanService.instance.notifier.removeListener(
      _onActivePlanChanged,
    );
    LiveRideBus.instance.state.removeListener(
      _onLiveRideChanged,
    );
    NavigationService.instance.state.removeListener(
      _onNavigationStateChanged,
    );
    RerouteService.instance.status.removeListener(
      _onRerouteStatusChanged,
    );

    _positionSubscription?.cancel();
    _mapController?.dispose();
    NavigationService.instance.clear();
    NavigationArrowService.instance.clear();
    RerouteService.instance.reset();

    VoiceNavigationService.instance.stop();
    VoiceNavigationService.instance.reset();
    ArrivalService.instance.reset();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = ValueListenableBuilder<ActiveRidePlan?>(
        valueListenable: ActiveRidePlanService.instance.notifier,
        builder: (context, activePlan, _) {
          return ValueListenableBuilder<LiveRideState>(
            valueListenable: LiveRideBus.instance.state,
            builder: (context, ride, _) {
              final rideHudData = _rideDataFromState(ride);

              return ValueListenableBuilder<NavigationState?>(
                valueListenable: NavigationService.instance.state,
                builder: (context, navigationState, _) {
                  return ValueListenableBuilder<List<NavigationArrow>>(
                    valueListenable:
                        NavigationArrowService.instance.arrows,
                    builder: (context, navigationArrows, _) {
                      return ValueListenableBuilder<RerouteStatus>(
                        valueListenable:
                            RerouteService.instance.status,
                        builder: (context, rerouteStatus, _) {
                          return ValueListenableBuilder<ArrivalState>(
                            valueListenable:
                                ArrivalService.instance.state,
                            builder: (context, arrivalState, _) {
                              return Stack(
                children: [
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      child: _showMap
                          ? GoogleMap(
                              key: const ValueKey<String>(
                                'active_ride_map',
                              ),
                              initialCameraPosition:
                                  _initialCameraForPlan(
                                activePlan,
                                ride,
                              ),
                              myLocationEnabled: true,
                              myLocationButtonEnabled: false,
                              compassEnabled: false,
                              zoomControlsEnabled: false,
                              mapToolbarEnabled: false,
                              rotateGesturesEnabled:
                                  !widget.embedded,
                              tiltGesturesEnabled:
                                  !widget.embedded,
                              scrollGesturesEnabled:
                                  !widget.embedded,
                              markers: _markersForRide(
                                ride,
                                activePlan,
                                navigationArrows,
                              ),
                              polylines: _polylinesForRide(
                                ride,
                                activePlan,
                              ),
                              onMapCreated: (controller) {
                                _mapController = controller;
                                _didFitInitialRoute = false;

                                _fitMapToPlan(
                                  ride: ride,
                                  force: true,
                                );

                                final current =
                                    _bestCurrentPosition(ride);

                                if (current != null) {
                                  unawaited(
                                    _followMapPosition(
                                      position: current,
                                      heading:
                                          _currentHeading,
                                      force: true,
                                    ),
                                  );
                                }
                              },
                            )
                          : const _DarkRideBackground(
                              key: ValueKey<String>(
                                'dark_ride_background',
                              ),
                            ),
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
                              Colors.black.withOpacity(0.54),
                              Colors.black.withOpacity(0.12),
                              Colors.transparent,
                              Colors.black.withOpacity(0.78),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  if (!widget.embedded)
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
                    left: widget.embedded ? 12 : 18,
                    right: widget.embedded ? 12 : 18,
                    top: widget.embedded ? 10 : 116,
                    child: _NavigationCockpitCard(
                      compact: widget.embedded,
                      plan: activePlan,
                      ride: ride,
                      loadingPosition: _loadingPosition,
                      navigationState: navigationState,
                      rerouteStatus: rerouteStatus,
                      arrivalState: arrivalState,
                      loopArrivalArmed:
                          !_isLoopPlan(activePlan) ||
                              _loopArrivalArmed,
                    ),
                  ),

                  if (!widget.embedded &&
                      _coachInsight != null)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: bottomWheelSafePadding + 94,
                      child: _AiCoachCard(
                        insight: _coachInsight!,
                        isPro:
                            MunjaProService.instance.hasFeature(
                          MunjaProFeature.aiRideCoach,
                        ),
                      ),
                    ),

                  if (!widget.embedded)
                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: bottomWheelSafePadding,
                      child: _RideStatusPanel(
                      isActive: ride.isActive,
                      calories: ride.calories,
                      altitude: ride.altitude ?? 0.0,
                      gpsAccuracy: ride.gpsAccuracy,
                      showMap: _showMap,
                      hasPlan: activePlan != null,
                      onCenterMap: () => _centerMap(ride),
                      onToggleMap: _toggleMapMode,
                    ),
                  ),
                ],
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );

    if (widget.embedded) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: content,
    );
  }

  CameraPosition _initialCameraForPlan(
    ActiveRidePlan? plan,
    LiveRideState ride,
  ) {
    final current = _bestCurrentPosition(ride);

    if (current != null) {
      return CameraPosition(
        target: widget.embedded
            ? _cameraTargetAhead(
                current,
                _currentHeading,
              )
            : current,
        zoom: widget.embedded ? 18.7 : 17.0,
        tilt: widget.embedded ? 52.0 : 34.0,
        bearing: _currentHeading,
      );
    }

    if (plan != null && plan.hasDestinationCoordinates) {
      return CameraPosition(
        target: LatLng(
          plan.destinationLatitude!,
          plan.destinationLongitude!,
        ),
        zoom: 14.5,
      );
    }

    return _fallbackCamera;
  }

  Set<Marker> _markersForRide(
    LiveRideState ride,
    ActiveRidePlan? plan,
    List<NavigationArrow> navigationArrows,
  ) {
    final markers = <Marker>{};

    if (ride.path.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('ride_start'),
          position: ride.path.first,
          infoWindow: InfoWindow(
            title: AppText.t('start'),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
        ),
      );

      markers.add(
        Marker(
          markerId: const MarkerId('ride_current'),
          position: ride.path.last,
          infoWindow: InfoWindow(
            title: AppText.t('yourPosition'),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    } else if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_position'),
          position: _currentPosition!,
          infoWindow: InfoWindow(
            title: AppText.t('yourPosition'),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    }

    if (plan != null && plan.hasDestinationCoordinates) {
      markers.add(
        Marker(
          markerId: const MarkerId('ride_destination'),
          position: LatLng(
            plan.destinationLatitude!,
            plan.destinationLongitude!,
          ),
          infoWindow: InfoWindow(
            title: AppText.t('destination'),
            snippet: plan.destination,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
        ),
      );
    }

    if (_routeArrowIcon != null &&
        _activeArrowIcon != null) {
      final visibleArrows = navigationArrows
          .where((arrow) => !arrow.isPassed)
          .take(widget.embedded ? 5 : 12);

      for (final arrow in visibleArrows) {
        final icon = arrow.isActive
            ? _activeArrowIcon!
            : _routeArrowIcon!;

        markers.add(
          Marker(
            markerId: MarkerId(arrow.id),
            position: LatLng(
              arrow.latitude,
              arrow.longitude,
            ),
            icon: icon,
            rotation: arrow.headingDegrees,
            flat: true,
            anchor: const Offset(0.5, 0.5),
            zIndexInt: arrow.isActive ? 8 : 4,
            alpha: arrow.isActive ? 1.0 : 0.82,
            consumeTapEvents: false,
          ),
        );
      }
    }

    return markers;
  }

  Set<Polyline> _polylinesForRide(
    LiveRideState ride,
    ActiveRidePlan? plan,
  ) {
    final polylines = <Polyline>{};
    final routePoints = _routePointsForPlan(plan);

    if (routePoints.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId(
            'planned_bicycle_route_shadow',
          ),
          points: routePoints,
          color: Colors.black.withOpacity(0.55),
          width: 10,
          zIndex: 1,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );

      polylines.add(
        Polyline(
          polylineId: const PolylineId(
            'planned_bicycle_route',
          ),
          points: routePoints,
          color: MunjaColors.mint,
          width: 6,
          zIndex: 2,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    if (ride.path.length >= 2) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId('ridden_path'),
          points: ride.path,
          color: Colors.white.withOpacity(0.90),
          width: 4,
          zIndex: 3,
          geodesic: true,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      );
    }

    final current = _bestCurrentPosition(ride);

    if (routePoints.isEmpty &&
        current != null &&
        plan != null &&
        plan.hasDestinationCoordinates) {
      polylines.add(
        Polyline(
          polylineId: const PolylineId(
            'destination_preview',
          ),
          points: <LatLng>[
            current,
            LatLng(
              plan.destinationLatitude!,
              plan.destinationLongitude!,
            ),
          ],
          color: MunjaColors.mint.withOpacity(0.42),
          width: 4,
          zIndex: 1,
          patterns: <PatternItem>[
            PatternItem.dash(14),
            PatternItem.gap(10),
          ],
        ),
      );
    }

    return polylines;
  }

}

class _AiCoachCard extends StatelessWidget {
  const _AiCoachCard({
    required this.insight,
    required this.isPro,
  });

  final CoachInsight insight;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF061611)
            .withOpacity(0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: insight.color.withOpacity(0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: insight.color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              insight.icon,
              color: insight.color,
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isPro
                          ? 'AI COACH PRO'
                          : 'AI COACH',
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Spacer(),
                    if (!isPro)
                      Text(
                        AppText.t('free'),
                        style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  insight.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  insight.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
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

class _NavigationCockpitCard extends StatelessWidget {
  const _NavigationCockpitCard({
    required this.compact,
    required this.plan,
    required this.ride,
    required this.loadingPosition,
    required this.navigationState,
    required this.rerouteStatus,
    required this.arrivalState,
    required this.loopArrivalArmed,
  });

  final bool compact;
  final ActiveRidePlan? plan;
  final LiveRideState ride;
  final bool loadingPosition;
  final NavigationState? navigationState;
  final RerouteStatus rerouteStatus;
  final ArrivalState arrivalState;
  final bool loopArrivalArmed;

  String? _formatDuration(Duration? duration) {
    if (duration == null) {
      return null;
    }

    final totalMinutes = duration.inMinutes;

    if (totalMinutes < 60) {
      return '$totalMinutes min';
    }

    final hours = duration.inHours;
    final minutes = totalMinutes.remainder(60);

    if (minutes == 0) {
      return '$hours ${AppText.t('hourShort')}';
    }

    return '$hours ${AppText.t('hourShort')} $minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final activePlan = plan;
    final destination = activePlan?.destination.trim() ?? '';
    final instruction = navigationState?.currentInstruction;

    final isCheckingRoute =
        rerouteStatus == RerouteStatus.waitingForConfirmation;
    final isRerouting =
        rerouteStatus == RerouteStatus.rerouting;
    final rerouteSucceeded =
        rerouteStatus == RerouteStatus.success;
    final rerouteFailed =
        rerouteStatus == RerouteStatus.failed;
    final confirmingArrival =
        arrivalState.status ==
            ArrivalStatus.waitingForConfirmation;
    final arrivalConfirmed =
        arrivalState.status == ArrivalStatus.confirmed;

    final prematureLoopArrival =
        activePlan != null &&
        (activePlan.isRoundTrip ||
            activePlan.isSuggestedRoute) &&
        !loopArrivalArmed &&
        instruction?.maneuver ==
            NavigationManeuver.arrive;

    final statusTitle = prematureLoopArrival
        ? AppText.t('autoRideLoopStarted')
        : arrivalConfirmed
        ? AppText.t('autoRideArrived')
        : confirmingArrival
            ? AppText.t('autoRideConfirmingArrival')
            : isRerouting
        ? AppText.t('autoRideRecalculating')
        : isCheckingRoute
            ? AppText.t('autoRideCheckingRoute')
            : rerouteSucceeded
                ? AppText.t('autoRideNewRouteReady')
                : rerouteFailed
                    ? AppText.t('autoRideCouldNotRecalculate')
                    : instruction?.title ??
                        (destination.isEmpty
                            ? AppText.t('autoRideChooseDestinationHome')
                            : destination);

    final statusDistance = prematureLoopArrival
        ? AppText.t('autoRideRouteActive')
        : arrivalConfirmed
        ? AppText.t('autoRideThere')
        : confirmingArrival
            ? '${(arrivalState.confirmationProgress * 100).round()} %'
            : isRerouting
        ? AppText.t('autoRideWait')
        : isCheckingRoute
            ? AppText.t('autoRideOffRoute')
            : rerouteSucceeded
                ? AppText.t('autoRideUpdated')
                : rerouteFailed
                    ? AppText.t('autoRideError')
                    : instruction?.distanceToInstructionLabel ??
                        (activePlan == null
                            ? AppText.t('autoRideNoActiveRoute')
                            : AppText.t('autoRideNavigationActive'));

    if (compact) {
      final remainingDistance =
          instruction?.remainingDistanceLabel ??
              activePlan?.distanceLabel ??
              '—';

      final remainingDuration =
          instruction?.remainingDurationLabel ??
              _formatDuration(activePlan?.routeDuration) ??
              '—';

      return Container(
        padding: const EdgeInsets.fromLTRB(
          14,
          13,
          14,
          13,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF061611).withOpacity(0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: MunjaColors.mint.withOpacity(
              activePlan == null ? 0.12 : 0.30,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.14),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                arrivalConfirmed
                    ? Icons.flag_rounded
                    : confirmingArrival
                        ? Icons.location_searching_rounded
                        : isRerouting
                            ? Icons.sync_rounded
                            : isCheckingRoute
                                ? Icons.warning_amber_rounded
                                : activePlan == null
                                    ? Icons.route_outlined
                                    : Icons.navigation_rounded,
                color: rerouteFailed
                    ? Colors.redAccent
                    : isCheckingRoute
                        ? Colors.orangeAccent
                        : MunjaColors.mint,
                size: 27,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    statusDistance,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      height: 1.08,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: [
                _CompactNavigationValue(
                  icon: Icons.route_rounded,
                  value: remainingDistance,
                ),
                const SizedBox(height: 7),
                _CompactNavigationValue(
                  icon: Icons.schedule_rounded,
                  value: remainingDuration,
                ),
              ],
            ),
          ],
        ),
      );
    }


    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(
            plan == null ? 0.10 : 0.30,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.14),
            blurRadius: 34,
            spreadRadius: 1,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  arrivalConfirmed
                      ? Icons.flag_rounded
                      : confirmingArrival
                          ? Icons.location_searching_rounded
                          : isRerouting
                      ? Icons.sync_rounded
                      : isCheckingRoute
                          ? Icons.warning_amber_rounded
                          : rerouteFailed
                              ? Icons.error_outline_rounded
                              : activePlan == null
                                  ? Icons.route_outlined
                                  : Icons.navigation_rounded,
                  color: rerouteFailed
                      ? Colors.redAccent
                      : isCheckingRoute
                          ? Colors.orangeAccent
                          : MunjaColors.mint,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusDistance,
                      style: TextStyle(
                        color: activePlan == null
                            ? Colors.white54
                            : MunjaColors.mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      statusTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        height: 1.18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CockpitMetric(
                  icon: Icons.speed_rounded,
                  label: AppText.t('autoRideSpeed'),
                  value: ride.speedKmh.toStringAsFixed(1),
                  unit: AppText.t('speedUnitShort'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _CockpitMetric(
                  icon: Icons.route_rounded,
                  label: AppText.t('autoRideRide'),
                  value: instruction?.remainingDistanceLabel ??
                      activePlan?.distanceLabel ??
                      '—',
                  unit: '',
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _CockpitMetric(
                  icon: instruction == null
                      ? Icons.gps_fixed_rounded
                      : Icons.schedule_rounded,
                  label: instruction == null ? 'GPS' : 'ETA',
                  value: instruction == null
                      ? (loadingPosition ? '...' : 'OK')
                      : instruction.remainingDurationLabel,
                  unit: '',
                ),
              ),
            ],
          ),
          if (activePlan != null &&
              activePlan.hasCalculatedRoute) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  arrivalConfirmed
                      ? Icons.flag_rounded
                      : confirmingArrival
                          ? Icons.location_searching_rounded
                          : isRerouting
                      ? Icons.sync_rounded
                      : (isCheckingRoute ||
                              navigationState?.isOffRoute == true)
                          ? Icons.warning_amber_rounded
                          : rerouteFailed
                              ? Icons.error_outline_rounded
                              : Icons.check_circle_rounded,
                  color: rerouteFailed
                      ? Colors.redAccent
                      : (isCheckingRoute ||
                              navigationState?.isOffRoute == true)
                          ? Colors.orangeAccent
                          : MunjaColors.mint,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    arrivalConfirmed
                        ? AppText.t('autoRideArrivalBody')
                        : confirmingArrival
                            ? AppText.t('autoRideConfirmArrivalBody')
                            : isRerouting
                        ? AppText.t('autoRideReroutingBody')
                        : isCheckingRoute
                            ? AppText.t('autoRideCheckingDeviationBody')
                            : rerouteSucceeded
                                ? AppText.t('autoRideRerouteSuccessBody')
                                : rerouteFailed
                                    ? AppText.t('autoRideRerouteFailedBody')
                                    : navigationState?.isOffRoute == true
                                        ? AppText.t('autoRideOffRouteBody')
                                        : navigationState == null
                                            ? AppText.t('autoRideRouteCalculatedBody')
                                            : '${AppText.t('autoRideRouteProgress')}: '
                                                '${(navigationState!.progress * 100).round()} %',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.58),
                      fontSize: 10,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (activePlan != null &&
              activePlan.hasDestinationCoordinates) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white38,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppText.t('autoRideDestinationNotSaved'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.48),
                      fontSize: 10,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactNavigationValue extends StatelessWidget {
  const _CompactNavigationValue({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: MunjaColors.mint,
          size: 14,
        ),
        const SizedBox(width: 5),
        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 76,
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _CockpitMetric extends StatelessWidget {
  const _CockpitMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 67,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: MunjaColors.mint,
                size: 15,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
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
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1,
                    fontWeight: FontWeight.w900,
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
                      color: MunjaColors.mint,
                      fontSize: 8,
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
  const _RideStatusPanel({
    required this.isActive,
    required this.calories,
    required this.altitude,
    required this.gpsAccuracy,
    required this.showMap,
    required this.hasPlan,
    required this.onCenterMap,
    required this.onToggleMap,
  });

  final bool isActive;
  final int calories;
  final double altitude;
  final double gpsAccuracy;
  final bool showMap;
  final bool hasPlan;
  final VoidCallback onCenterMap;
  final VoidCallback onToggleMap;

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
                  label: AppText.t('altitudeShort'),
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
                  label: showMap
                      ? AppText.t('hud')
                      : AppText.t('map'),
                  onTap: onToggleMap,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionPill(
                  icon: Icons.zoom_out_map_rounded,
                  label: hasPlan
                      ? AppText.t('showFullRoute')
                      : AppText.t('centerMap'),
                  onTap: onCenterMap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isActive
                ? AppText.t('stopRideFromWheel')
                : hasPlan
                    ? AppText.t('routeStartedFromWheel')
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
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
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
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

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
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.26),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: MunjaColors.mint,
                size: 18,
              ),
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
            child: _GlowBlob(
              size: 220,
              opacity: 0.14,
            ),
          ),
          Positioned(
            bottom: 170,
            right: -70,
            child: _GlowBlob(
              size: 240,
              opacity: 0.12,
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _RideGridPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.size,
    required this.opacity,
  });

  final double size;
  final double opacity;

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
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _RideGridPainter oldDelegate,
  ) {
    return false;
  }
}

BoxDecoration _premiumDecoration() {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.84),
    borderRadius: BorderRadius.circular(30),
    border: Border.all(
      color: Colors.white.withOpacity(0.075),
    ),
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
