import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/munja_colors.dart';
import '../core/localization/app_text.dart';
import '../models/ride_route_plan.dart';
import '../services/active_route_service.dart';
import '../widgets/munja_card.dart';
import '../widgets/section_title.dart';

class SmartRoutePlannerScreen extends StatefulWidget {
  const SmartRoutePlannerScreen({super.key});

  @override
  State<SmartRoutePlannerScreen> createState() =>
      _SmartRoutePlannerScreenState();
}

class _SmartRoutePlannerScreenState extends State<SmartRoutePlannerScreen> {
  final TextEditingController _addressController = TextEditingController();

  RideRouteType selectedType = RideRouteType.easy;

  bool loadingLocation = true;
  bool generating = false;
  bool searchingAddress = false;

  LatLng center = fallbackCenter;
  LatLng? destination;

  RideRoutePlan? selectedPlan;
  List<RideRoutePlan> plans = [];

  GoogleMapController? mapController;

  @override
  void initState() {
    super.initState();
    _loadLocationAndGenerate();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadLocationAndGenerate() async {
    setState(() => loadingLocation = true);

    try {
      final enabled = await Geolocator.isLocationServiceEnabled();

      if (enabled) {
        var permission = await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
          );

          center = LatLng(pos.latitude, pos.longitude);
        }
      }
    } catch (_) {
      center = fallbackCenter;
    }

    await _generatePlans();

    if (!mounted) return;
    setState(() => loadingLocation = false);
  }

  Future<void> _searchAddressAndGenerate() async {
    final address = _addressController.text.trim();

    if (address.isEmpty) {
      _showMessage(AppText.t('enterAddressFirst'));
      return;
    }

    setState(() => searchingAddress = true);

    try {
      final results = await locationFromAddress(address);

      if (results.isEmpty) {
        _showMessage(AppText.t('addressNotFound'));
        return;
      }

      final first = results.first;

      destination = LatLng(first.latitude, first.longitude);
      center = destination!;

      await _generatePlans();

      await mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: destination!, zoom: 13.8),
        ),
      );

      _showMessage('${AppText.t('routeGenerated')} $address');
    } catch (e) {
      debugPrint('ADDRESS SEARCH ERROR: $e');
      _showMessage(AppText.t('couldNotFindAddress'));
    } finally {
      if (mounted) {
        setState(() => searchingAddress = false);
      }
    }
  }

  Future<void> _generatePlans() async {
    setState(() => generating = true);

    await Future.delayed(const Duration(milliseconds: 350));

    final routeCenter = destination ?? center;

    final generated = RideRouteType.values
        .map((type) => RideRoutePlan.mock(type: type, center: routeCenter))
        .toList();

    if (!mounted) return;

    setState(() {
      plans = generated;
      selectedPlan = generated.firstWhere(
        (p) => p.type == selectedType,
        orElse: () => generated.first,
      );
      generating = false;
    });

    await _moveMapToPlan();
  }

  void _selectType(RideRouteType type) {
    setState(() {
      selectedType = type;
      selectedPlan = plans.firstWhere(
        (p) => p.type == type,
        orElse: () =>
            RideRoutePlan.mock(type: type, center: destination ?? center),
      );
    });

    _moveMapToPlan();
  }

  Future<void> _moveMapToPlan() async {
    final plan = selectedPlan;
    if (plan == null || plan.previewPath.isEmpty) return;

    await mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: plan.previewPath.first, zoom: 13.8),
      ),
    );
  }

  Set<Polyline> _polylines() {
    final plan = selectedPlan;

    if (plan == null || plan.previewPath.length < 2) return {};

    return {
      Polyline(
        polylineId: const PolylineId('smart_route_preview'),
        points: plan.previewPath,
        width: 6,
        color: MunjaColors.mint,
      ),
    };
  }

  Set<Marker> _markers() {
    final plan = selectedPlan;

    if (plan == null || plan.previewPath.isEmpty) return {};

    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('route_start'),
        position: plan.previewPath.first,
        infoWindow: InfoWindow(title: AppText.t('start')),
      ),
      Marker(
        markerId: const MarkerId('route_finish'),
        position: plan.previewPath.last,
        infoWindow: InfoWindow(title: AppText.t('finish')),
      ),
    };

    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destination!,
          infoWindow: InfoWindow(title: AppText.t('destination')),
        ),
      );
    }

    return markers;
  }

  Future<void> _useRoute() async {
    final plan = selectedPlan;
    if (plan == null) return;

    await ActiveRouteService.instance.setActiveRoute(plan);

    debugPrint(
      'ACTIVE ROUTE SAVED: ${plan.title} | ${plan.distanceKm} km | ${plan.difficultyText}',
    );

    _showMessage('${plan.title} ${AppText.t('selectedAndSaved')}');
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
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
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 520),
                children: [
                  Row(
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
                            color: MunjaColors.mint.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          AppText.t('smartRouteAi'),
                          style: TextStyle(
                            color: MunjaColors.mint,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        AppText.t('wheelNavigation'),
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppText.t('smartRoutePlanner'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppText.t('smartRoutePlannerSubtitle'),
                    style: TextStyle(
                      color: MunjaColors.textSoft,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  MunjaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(
                          title: AppText.t('destination'),
                          subtitle: AppText.t('enterWhereYouWantToRide'),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _addressController,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _searchAddressAndGenerate(),
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
                            onPressed: searchingAddress
                                ? null
                                : _searchAddressAndGenerate,
                            icon: searchingAddress
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.route_rounded),
                            label: Text(
                              searchingAddress
                                  ? AppText.t('searching')
                                  : AppText.t('generateRoute'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 104,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: RideRouteType.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final type = RideRouteType.values[index];
                        final active = type == selectedType;

                        return GestureDetector(
                          onTap: () => _selectType(type),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 240),
                            width: 138,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: active
                                  ? MunjaColors.mint.withOpacity(0.16)
                                  : MunjaColors.panel,
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: active
                                    ? MunjaColors.mint.withOpacity(0.65)
                                    : Colors.white.withOpacity(0.07),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  type.emoji,
                                  style: const TextStyle(fontSize: 24),
                                ),
                                const Spacer(),
                                Text(
                                  type.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  type.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: MunjaColors.textSoft,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (plan != null)
                    _RouteHeroCard(
                      plan: plan,
                      generating: generating,
                      onRegenerate: _generatePlans,
                    ),
                  const SizedBox(height: 16),
                  MunjaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SectionTitle(
                          title: AppText.t('routePreview'),
                          subtitle: AppText.t('addressSearchNow'),
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
                              myLocationEnabled: true,
                              markers: _markers(),
                              polylines: _polylines(),
                              onMapCreated: (controller) {
                                mapController = controller;
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (plan != null)
                    MunjaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(
                            title: AppText.t('whyThisRoute'),
                            subtitle: AppText.t('munjaScoresRoute'),
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
                    ),
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: plan == null ? null : _useRoute,
                      icon: const Icon(Icons.navigation_rounded),
                      label: Text(
                        AppText.t('useThisRoute'),
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _RouteHeroCard extends StatelessWidget {
  final RideRoutePlan plan;
  final bool generating;
  final VoidCallback onRegenerate;

  const _RouteHeroCard({
    required this.plan,
    required this.generating,
    required this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${plan.type.emoji} ${plan.type.title}',
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            plan.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            plan.subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
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
              const SizedBox(width: 10),
              Expanded(
                child: _MiniRouteStat(
                  icon: Icons.timer_rounded,
                  label: AppText.t('time'),
                  value: plan.durationText,
                  unit: '',
                ),
              ),
              const SizedBox(width: 10),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: plan.tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: MunjaColors.mint.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: generating ? null : onRegenerate,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
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
  final IconData icon;
  final String label;
  final String value;
  final String unit;

  const _MiniRouteStat({
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
        color: MunjaColors.panelSoft,
        borderRadius: BorderRadius.circular(24),
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
                    fontSize: 16,
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

class _ScoreRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;

  const _ScoreRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (value / 100).clamp(0.0, 1.0);

    return Row(
      children: [
        Icon(icon, color: MunjaColors.mint),
        const SizedBox(width: 12),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white12,
              color: MunjaColors.mint,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$value',
          style: const TextStyle(
            color: MunjaColors.mint,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
