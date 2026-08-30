import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../Models/route_result.dart';
import '../Services/munja_pro_service.dart';
import '../Services/route_service.dart';
import '../core/constants/app_constants.dart';
import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/ride_route_plan.dart';
import '../services/active_route_service.dart';
import '../widgets/munja_card.dart';
import '../widgets/section_title.dart';

enum _PlannerMode { destination, proLoop }

enum _ProRouteFocus { easy, fast, scenic, training }

class SmartRoutePlannerScreen extends StatefulWidget {
  const SmartRoutePlannerScreen({super.key});

  @override
  State<SmartRoutePlannerScreen> createState() =>
      _SmartRoutePlannerScreenState();
}

class _SmartRoutePlannerScreenState extends State<SmartRoutePlannerScreen> {
  final TextEditingController _addressController = TextEditingController();

  static const List<double> _distanceOptions = <double>[10, 20, 30, 50];

  bool loadingLocation = true;
  bool generating = false;
  bool searchingAddress = false;

  LatLng center = fallbackCenter;
  LatLng? destination;

  RideRoutePlan? selectedPlan;
  List<RideRoutePlan> plans = <RideRoutePlan>[];

  GoogleMapController? mapController;

  _PlannerMode _mode = _PlannerMode.destination;
  _ProRouteFocus _proFocus = _ProRouteFocus.easy;
  double _targetDistanceKm = 20;

  bool get _isPro => MunjaProService.instance.hasFeature(
        MunjaProFeature.advancedRoutePlanner,
      );

  @override
  void initState() {
    super.initState();
    _initializePlanner();
  }

  @override
  void dispose() {
    _addressController.dispose();
    mapController?.dispose();
    super.dispose();
  }

  Future<void> _initializePlanner() async {
    await MunjaProService.instance.initialize();
    await _loadCurrentLocation();

    if (!mounted) return;

    setState(() {
      loadingLocation = false;
    });
  }

  Future<void> _loadCurrentLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (!enabled) {
        center = fallbackCenter;
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        center = fallbackCenter;
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
        ),
      );

      center = LatLng(pos.latitude, pos.longitude);
    } catch (error, stackTrace) {
      debugPrint('SMART ROUTE LOCATION ERROR: $error');
      debugPrint('$stackTrace');
      center = fallbackCenter;
    }
  }

  Future<void> _searchAddressAndGenerate() async {
    final address = _addressController.text.trim();

    if (address.isEmpty) {
      _showMessage(AppText.t('enterAddressFirst'));
      return;
    }

    if (searchingAddress || generating) return;

    setState(() => searchingAddress = true);

    try {
      final results = await locationFromAddress(address);

      if (results.isEmpty) {
        _showMessage(AppText.t('addressNotFound'));
        return;
      }

      final first = results.first;

      destination = LatLng(first.latitude, first.longitude);

      await _generateDestinationRoute();

      _showMessage('${AppText.t('routeGenerated')} $address');
    } catch (error, stackTrace) {
      debugPrint('SMART ROUTE ADDRESS ERROR: $error');
      debugPrint('$stackTrace');
      _showMessage(AppText.t('couldNotFindAddress'));
    } finally {
      if (mounted) {
        setState(() => searchingAddress = false);
      }
    }
  }

  Future<void> _generateDestinationRoute() async {
    final target = destination;
    if (target == null) return;

    setState(() {
      generating = true;
      plans = <RideRoutePlan>[];
      selectedPlan = null;
    });

    try {
      final route = await RouteService.instance.calculateBicycleRoute(
        originLatitude: center.latitude,
        originLongitude: center.longitude,
        destinationLatitude: target.latitude,
        destinationLongitude: target.longitude,
      );

      final plan = _planFromRouteResult(
        route: route,
        type: RideRouteType.commute,
        title: 'Bike route',
        subtitle: 'Google bicycle route to your destination.',
        difficulty: 2,
        safetyScore: 82,
        scenicScore: 55,
        fitnessScore: 60,
        tags: const <String>[
          'Bicycle',
          'Destination',
          'Turn-by-turn',
        ],
      );

      if (!mounted) return;

      setState(() {
        plans = <RideRoutePlan>[plan];
        selectedPlan = plan;
      });

      await _fitSelectedPlan();
    } on RouteServiceException catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('SMART ROUTE DESTINATION ERROR: $error');
      debugPrint('$stackTrace');
      _showMessage('Route could not be generated.');
    } finally {
      if (mounted) {
        setState(() => generating = false);
      }
    }
  }

  Future<void> _generateProRoutes() async {
    if (!_isPro) {
      _showProMessage();
      return;
    }

    if (generating) return;

    setState(() {
      generating = true;
      plans = <RideRoutePlan>[];
      selectedPlan = null;
    });

    try {
      final results = await RouteService.instance.calculateSuggestedRoutes(
        originLatitude: center.latitude,
        originLongitude: center.longitude,
        targetDistanceKm: _targetDistanceKm,
        suggestionCount: 3,
      );

      if (results.isEmpty) {
        throw const RouteServiceException(
          'No route suggestions were found.',
        );
      }

      final generated = <RideRoutePlan>[
        for (var i = 0; i < results.length; i++)
          _planForProSuggestion(
            route: results[i],
            index: i,
          ),
      ];

      if (!mounted) return;

      setState(() {
        plans = generated;
        selectedPlan = _selectPreferredProPlan(generated);
      });

      await _fitSelectedPlan();
    } on RouteServiceException catch (error) {
      _showMessage(error.message);
    } catch (error, stackTrace) {
      debugPrint('SMART ROUTE PRO ERROR: $error');
      debugPrint('$stackTrace');
      _showMessage('MUNJA PRO could not generate route suggestions.');
    } finally {
      if (mounted) {
        setState(() => generating = false);
      }
    }
  }

  RideRoutePlan _planForProSuggestion({
    required RouteResult route,
    required int index,
  }) {
    final actualKm = route.distanceMeters / 1000;

    switch (_proFocus) {
      case _ProRouteFocus.easy:
        return _planFromRouteResult(
          route: route,
          type: RideRouteType.easy,
          title: index == 0 ? 'Easy Loop' : 'Easy Loop ${index + 1}',
          subtitle: 'A balanced round trip close to your selected distance.',
          difficulty: 1,
          safetyScore: 88,
          scenicScore: 68,
          fitnessScore: 50,
          tags: <String>[
            'Loop',
            '${actualKm.toStringAsFixed(0)} km',
            'Balanced',
          ],
        );

      case _ProRouteFocus.fast:
        return _planFromRouteResult(
          route: route,
          type: RideRouteType.commute,
          title: index == 0 ? 'Fast Loop' : 'Fast Loop ${index + 1}',
          subtitle: 'A time-focused suggestion from the available bicycle loops.',
          difficulty: 2,
          safetyScore: 78,
          scenicScore: 50,
          fitnessScore: 72,
          tags: <String>[
            'Loop',
            'Tempo',
            '${actualKm.toStringAsFixed(0)} km',
          ],
        );

      case _ProRouteFocus.scenic:
        return _planFromRouteResult(
          route: route,
          type: RideRouteType.scenic,
          title: index == 0 ? 'Scenic Loop' : 'Scenic Loop ${index + 1}',
          subtitle: 'An alternative loop direction for a more varied ride.',
          difficulty: 2,
          safetyScore: 82,
          scenicScore: 86,
          fitnessScore: 58,
          tags: <String>[
            'Loop',
            'Alternative',
            '${actualKm.toStringAsFixed(0)} km',
          ],
        );

      case _ProRouteFocus.training:
        return _planFromRouteResult(
          route: route,
          type: RideRouteType.fitness,
          title: index == 0 ? 'Training Loop' : 'Training Loop ${index + 1}',
          subtitle: 'A distance-controlled loop for a structured session.',
          difficulty: 4,
          safetyScore: 76,
          scenicScore: 62,
          fitnessScore: 92,
          tags: <String>[
            'Training',
            'Loop',
            '${actualKm.toStringAsFixed(0)} km',
          ],
        );
    }
  }

  RideRoutePlan _selectPreferredProPlan(List<RideRoutePlan> items) {
    if (items.isEmpty) {
      throw StateError('No route plans available.');
    }

    switch (_proFocus) {
      case _ProRouteFocus.fast:
        return items.reduce(
          (a, b) => a.estimatedDuration <= b.estimatedDuration ? a : b,
        );

      case _ProRouteFocus.training:
        return items.reduce(
          (a, b) => a.estimatedDuration >= b.estimatedDuration ? a : b,
        );

      case _ProRouteFocus.easy:
      case _ProRouteFocus.scenic:
        return items.reduce((a, b) {
          final aDifference = (a.distanceKm - _targetDistanceKm).abs();
          final bDifference = (b.distanceKm - _targetDistanceKm).abs();

          return aDifference <= bDifference ? a : b;
        });
    }
  }

  RideRoutePlan _planFromRouteResult({
    required RouteResult route,
    required RideRouteType type,
    required String title,
    required String subtitle,
    required int difficulty,
    required int safetyScore,
    required int scenicScore,
    required int fitnessScore,
    required List<String> tags,
  }) {
    return RideRoutePlan(
      id: 'google_${type.name}_${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      subtitle: subtitle,
      type: type,
      distanceKm: route.distanceMeters / 1000,
      estimatedDuration: Duration(seconds: route.durationSeconds),
      difficulty: difficulty,
      safetyScore: safetyScore,
      scenicScore: scenicScore,
      fitnessScore: fitnessScore,
      tags: tags,
      previewPath: route.points
          .map(
            (point) => LatLng(
              point.latitude,
              point.longitude,
            ),
          )
          .toList(growable: false),
    );
  }

  void _setPlannerMode(_PlannerMode mode) {
    if (mode == _PlannerMode.proLoop && !_isPro) {
      _showProMessage();
      return;
    }

    setState(() {
      _mode = mode;
      plans = <RideRoutePlan>[];
      selectedPlan = null;

      if (mode == _PlannerMode.proLoop) {
        destination = null;
      }
    });
  }

  void _setProFocus(_ProRouteFocus focus) {
    if (!_isPro) {
      _showProMessage();
      return;
    }

    setState(() => _proFocus = focus);
  }

  void _setTargetDistance(double value) {
    if (!_isPro) {
      _showProMessage();
      return;
    }

    setState(() => _targetDistanceKm = value);
  }

  void _selectPlan(RideRoutePlan plan) {
    setState(() => selectedPlan = plan);
    _fitSelectedPlan();
  }

  Future<void> _fitSelectedPlan() async {
    final plan = selectedPlan;
    final controller = mapController;

    if (plan == null ||
        controller == null ||
        plan.previewPath.isEmpty) {
      return;
    }

    final points = plan.previewPath;

    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 14.5),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;

    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!mounted) return;

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(minLat, minLng),
            northeast: LatLng(maxLat, maxLng),
          ),
          54,
        ),
      );
    } catch (error) {
      debugPrint('SMART ROUTE FIT ERROR: $error');
    }
  }

  Set<Polyline> _polylines() {
    final plan = selectedPlan;

    if (plan == null || plan.previewPath.length < 2) {
      return <Polyline>{};
    }

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('smart_route_preview_shadow'),
        points: plan.previewPath,
        width: 10,
        color: Colors.black.withOpacity(0.45),
        zIndex: 1,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
      Polyline(
        polylineId: const PolylineId('smart_route_preview'),
        points: plan.previewPath,
        width: 6,
        color: MunjaColors.mint,
        zIndex: 2,
        jointType: JointType.round,
        startCap: Cap.roundCap,
        endCap: Cap.roundCap,
      ),
    };
  }

  Set<Marker> _markers() {
    final plan = selectedPlan;

    if (plan == null || plan.previewPath.isEmpty) {
      return <Marker>{};
    }

    return <Marker>{
      Marker(
        markerId: const MarkerId('route_start'),
        position: plan.previewPath.first,
        infoWindow: InfoWindow(title: AppText.t('start')),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          BitmapDescriptor.hueGreen,
        ),
      ),
      Marker(
        markerId: const MarkerId('route_finish'),
        position: plan.previewPath.last,
        infoWindow: InfoWindow(
          title: _mode == _PlannerMode.proLoop
              ? 'Loop finish'
              : AppText.t('finish'),
        ),
      ),
    };
  }

  Future<void> _useRoute() async {
    final plan = selectedPlan;
    if (plan == null) return;

    await ActiveRouteService.instance.setActiveRoute(plan);

    debugPrint(
      'ACTIVE ROUTE SAVED: '
      '${plan.title} | '
      '${plan.distanceKm.toStringAsFixed(1)} km | '
      '${plan.difficultyText}',
    );

    _showMessage('${plan.title} ${AppText.t('selectedAndSaved')}');
  }

  void _showProMessage() {
    _showMessage(
      'Advanced route planning is included with MUNJA PRO.',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 180),
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final plan = selectedPlan;

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        child: loadingLocation
            ? const Center(
                child: CircularProgressIndicator(
                  color: MunjaColors.mint,
                ),
              )
            : RefreshIndicator(
                onRefresh: _initializePlanner,
                color: MunjaColors.mint,
                backgroundColor: const Color(0xFF07110E),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 520),
                  children: [
                    _PlannerHeader(isPro: _isPro),
                    const SizedBox(height: 14),
                    Text(
                      AppText.t('smartRoutePlanner'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isPro
                          ? 'Destination routing plus advanced MUNJA PRO loops.'
                          : AppText.t('smartRoutePlannerSubtitle'),
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _ModeSelector(
                      selected: _mode,
                      isPro: _isPro,
                      onSelected: _setPlannerMode,
                    ),
                    const SizedBox(height: 16),

                    if (_mode == _PlannerMode.destination)
                      _DestinationCard(
                        controller: _addressController,
                        searching: searchingAddress,
                        generating: generating,
                        onSearch: _searchAddressAndGenerate,
                      )
                    else
                      _ProLoopSetupCard(
                        focus: _proFocus,
                        targetDistanceKm: _targetDistanceKm,
                        generating: generating,
                        onFocus: _setProFocus,
                        onDistance: _setTargetDistance,
                        onGenerate: _generateProRoutes,
                      ),

                    if (_mode == _PlannerMode.proLoop &&
                        plans.length > 1) ...[
                      const SizedBox(height: 16),
                      _SuggestionSelector(
                        plans: plans,
                        selected: selectedPlan,
                        onSelected: _selectPlan,
                      ),
                    ],

                    if (plan != null) ...[
                      const SizedBox(height: 16),
                      _RouteHeroCard(
                        plan: plan,
                        generating: generating,
                        onRegenerate: _mode == _PlannerMode.proLoop
                            ? _generateProRoutes
                            : _searchAddressAndGenerate,
                      ),
                    ],

                    const SizedBox(height: 16),

                    MunjaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(
                            title: AppText.t('routePreview'),
                            subtitle: plan == null
                                ? 'Generate a route to preview it here.'
                                : 'Real Google bicycle route preview.',
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: SizedBox(
                              height: 360,
                              child: GoogleMap(
                                initialCameraPosition: CameraPosition(
                                  target: center,
                                  zoom: 13.8,
                                ),
                                zoomControlsEnabled: false,
                                myLocationButtonEnabled: false,
                                mapToolbarEnabled: false,
                                compassEnabled: false,
                                myLocationEnabled: true,
                                markers: _markers(),
                                polylines: _polylines(),
                                onMapCreated: (controller) {
                                  mapController = controller;
                                  _fitSelectedPlan();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (plan != null) ...[
                      const SizedBox(height: 16),
                      _RouteScoreCard(plan: plan),
                    ],

                    const SizedBox(height: 18),

                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed:
                            plan == null || generating ? null : _useRoute,
                        icon: const Icon(Icons.navigation_rounded),
                        label: Text(
                          AppText.t('useThisRoute'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
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

class _PlannerHeader extends StatelessWidget {
  const _PlannerHeader({required this.isPro});

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: MunjaColors.mint.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.30),
            ),
          ),
          child: Text(
            isPro ? 'MUNJA PRO ROUTES' : AppText.t('smartRouteAi'),
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const Spacer(),
        Text(
          isPro ? 'PRO ACTIVE' : AppText.t('wheelNavigation'),
          style: TextStyle(
            color: isPro ? MunjaColors.mint : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({
    required this.selected,
    required this.isPro,
    required this.onSelected,
  });

  final _PlannerMode selected;
  final bool isPro;
  final ValueChanged<_PlannerMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModeButton(
            title: 'DESTINATION',
            subtitle: 'A → B bicycle route',
            icon: Icons.place_rounded,
            selected: selected == _PlannerMode.destination,
            locked: false,
            onTap: () => onSelected(_PlannerMode.destination),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ModeButton(
            title: 'PRO LOOP',
            subtitle: isPro ? 'Distance-based routes' : 'MUNJA PRO',
            icon: Icons.loop_rounded,
            selected: selected == _PlannerMode.proLoop,
            locked: !isPro,
            onTap: () => onSelected(_PlannerMode.proLoop),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          height: 76,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withOpacity(0.14)
                : MunjaColors.panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? MunjaColors.mint.withOpacity(0.55)
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Row(
            children: [
              Icon(
                locked ? Icons.lock_rounded : icon,
                color: locked ? Colors.white30 : MunjaColors.mint,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.controller,
    required this.searching,
    required this.generating,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool searching;
  final bool generating;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final busy = searching || generating;

    return MunjaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: AppText.t('destination'),
            subtitle: AppText.t('enterWhereYouWantToRide'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (!busy) onSearch();
            },
            decoration: InputDecoration(
              hintText: AppText.t('searchAddress'),
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: MunjaColors.mint,
              ),
              filled: true,
              fillColor: MunjaColors.panelSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: busy ? null : onSearch,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.route_rounded),
              label: Text(
                busy
                    ? AppText.t('generating')
                    : AppText.t('generateRoute'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProLoopSetupCard extends StatelessWidget {
  const _ProLoopSetupCard({
    required this.focus,
    required this.targetDistanceKm,
    required this.generating,
    required this.onFocus,
    required this.onDistance,
    required this.onGenerate,
  });

  final _ProRouteFocus focus;
  final double targetDistanceKm;
  final bool generating;
  final ValueChanged<_ProRouteFocus> onFocus;
  final ValueChanged<double> onDistance;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: MunjaColors.mint,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'MUNJA PRO ROUTE',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Route focus',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _ProRouteFocus.values.map((item) {
              final selected = item == focus;

              return ChoiceChip(
                selected: selected,
                onSelected: (_) => onFocus(item),
                avatar: Icon(
                  _focusIcon(item),
                  size: 16,
                  color: selected ? Colors.black : MunjaColors.mint,
                ),
                label: Text(_focusLabel(item)),
                selectedColor: MunjaColors.mint,
                backgroundColor: MunjaColors.panelSoft,
                side: BorderSide(
                  color: selected
                      ? MunjaColors.mint
                      : Colors.white.withOpacity(0.06),
                ),
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text(
                'Target distance',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Text(
                '${targetDistanceKm.toStringAsFixed(0)} KM',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _SmartRoutePlannerScreenState._distanceOptions.map((distance) {
              final selected = distance == targetDistanceKm;

              return ChoiceChip(
                selected: selected,
                onSelected: (_) => onDistance(distance),
                label: Text('${distance.toStringAsFixed(0)} km'),
                selectedColor: MunjaColors.mint,
                backgroundColor: MunjaColors.panelSoft,
                side: BorderSide(
                  color: selected
                      ? MunjaColors.mint
                      : Colors.white.withOpacity(0.06),
                ),
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: generating ? null : onGenerate,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(
                generating ? 'GENERATING...' : 'GENERATE 3 ROUTES',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Munja uses real Google bicycle loops and ranks the available suggestions by your selected focus.',
            style: TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 9.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _focusLabel(_ProRouteFocus focus) {
    switch (focus) {
      case _ProRouteFocus.easy:
        return 'EASY';
      case _ProRouteFocus.fast:
        return 'FAST';
      case _ProRouteFocus.scenic:
        return 'SCENIC';
      case _ProRouteFocus.training:
        return 'TRAINING';
    }
  }

  static IconData _focusIcon(_ProRouteFocus focus) {
    switch (focus) {
      case _ProRouteFocus.easy:
        return Icons.self_improvement_rounded;
      case _ProRouteFocus.fast:
        return Icons.bolt_rounded;
      case _ProRouteFocus.scenic:
        return Icons.landscape_rounded;
      case _ProRouteFocus.training:
        return Icons.fitness_center_rounded;
    }
  }
}

class _SuggestionSelector extends StatelessWidget {
  const _SuggestionSelector({
    required this.plans,
    required this.selected,
    required this.onSelected,
  });

  final List<RideRoutePlan> plans;
  final RideRoutePlan? selected;
  final ValueChanged<RideRoutePlan> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: plans.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final plan = plans[index];
          final active = selected?.id == plan.id;

          return GestureDetector(
            onTap: () => onSelected(plan),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 142,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: active
                    ? MunjaColors.mint.withOpacity(0.15)
                    : MunjaColors.panel,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: active
                      ? MunjaColors.mint.withOpacity(0.55)
                      : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ROUTE ${index + 1}',
                    style: TextStyle(
                      color: active ? MunjaColors.mint : Colors.white38,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${plan.distanceKm.toStringAsFixed(1)} km',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    plan.durationText,
                    style: const TextStyle(
                      color: MunjaColors.textSoft,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RouteHeroCard extends StatelessWidget {
  const _RouteHeroCard({
    required this.plan,
    required this.generating,
    required this.onRegenerate,
  });

  final RideRoutePlan plan;
  final bool generating;
  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.type.emoji} ${plan.type.title}',
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            plan.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            plan.subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MiniRouteStat(
                  icon: Icons.route_rounded,
                  label: AppText.t('distance'),
                  value: plan.distanceKm.toStringAsFixed(1),
                  unit: 'km',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniRouteStat(
                  icon: Icons.timer_rounded,
                  label: AppText.t('time'),
                  value: plan.durationText,
                  unit: '',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniRouteStat(
                  icon: Icons.trending_up_rounded,
                  label: AppText.t('level'),
                  value: plan.difficultyText,
                  unit: '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: plan.tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MunjaColors.mint.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: generating ? null : onRegenerate,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(
                generating
                    ? AppText.t('generating')
                    : AppText.t('generateNewSuggestions'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRouteStat extends StatelessWidget {
  const _MiniRouteStat({
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
      height: 78,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MunjaColors.panelSoft,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 17),
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
                    fontSize: 14.5,
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
                      color: Colors.white38,
                      fontSize: 8,
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteScoreCard extends StatelessWidget {
  const _RouteScoreCard({required this.plan});

  final RideRoutePlan plan;

  @override
  Widget build(BuildContext context) {
    return MunjaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            title: AppText.t('whyThisRoute'),
            subtitle: 'Munja route profile',
          ),
          const SizedBox(height: 14),
          _ScoreRow(
            icon: Icons.shield_rounded,
            label: AppText.t('safety'),
            value: plan.safetyScore,
          ),
          const SizedBox(height: 12),
          _ScoreRow(
            icon: Icons.landscape_rounded,
            label: AppText.t('scenic'),
            value: plan.scenicScore,
          ),
          const SizedBox(height: 12),
          _ScoreRow(
            icon: Icons.fitness_center_rounded,
            label: AppText.t('fitness'),
            value: plan.fitnessScore,
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final progress = (value / 100).clamp(0.0, 1.0);

    return Row(
      children: [
        Icon(icon, color: MunjaColors.mint, size: 20),
        const SizedBox(width: 10),
        SizedBox(
          width: 68,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white12,
              color: MunjaColors.mint,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          '$value',
          style: const TextStyle(
            color: MunjaColors.mint,
            fontWeight: FontWeight.w900,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
