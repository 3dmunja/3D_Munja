import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../Models/place_suggestion.dart';
import '../Models/route_result.dart';
import '../Services/place_search_service.dart';
import '../Services/route_service.dart';
import '../Services/munja_pro_service.dart';
import 'munja_pro_screen.dart';
import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

enum RideSetupMode {
  destination,
  roundTrip,
  suggestedRoute,
  freeRide,
}

enum RideBikeType {
  mtb,
  road,
  family,
  nature,
  quietRoads,
}

class RideSetupResult {
  const RideSetupResult({
    required this.mode,
    required this.bikeType,
    required this.distanceKm,
    required this.destination,
    this.destinationPlaceId,
    this.destinationLatitude,
    this.destinationLongitude,
    this.suggestedRouteDistanceMeters,
    this.suggestedRouteDurationSeconds,
    this.suggestedRouteEncodedPolyline,
  });

  final RideSetupMode mode;
  final RideBikeType bikeType;
  final double distanceKm;
  final String destination;

  final String? destinationPlaceId;
  final double? destinationLatitude;
  final double? destinationLongitude;

  final double? suggestedRouteDistanceMeters;
  final int? suggestedRouteDurationSeconds;
  final String? suggestedRouteEncodedPolyline;

  bool get hasDestinationCoordinates {
    return destinationLatitude != null && destinationLongitude != null;
  }

  bool get hasSuggestedRoute {
    return suggestedRouteEncodedPolyline != null &&
        suggestedRouteEncodedPolyline!.trim().isNotEmpty;
  }
}

class RideSetupScreen extends StatefulWidget {
  const RideSetupScreen({
    super.key,
    this.onStartRide,
    this.onBackToHome,
  });

  final ValueChanged<RideSetupResult>? onStartRide;

  /// Used when RideSetupScreen is hosted as the permanent Ride tab inside
  /// MainNavigation. In that case Navigator.maybePop() has nowhere meaningful
  /// to go, so the top back button should switch back to Home instead.
  final VoidCallback? onBackToHome;

  @override
  State<RideSetupScreen> createState() => _RideSetupScreenState();
}

class _RideSetupScreenState extends State<RideSetupScreen> {
  final TextEditingController _destinationController =
      TextEditingController();

  final FocusNode _destinationFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _destinationSectionKey = GlobalKey();

  Timer? _searchDebounce;

  RideSetupMode _selectedMode = RideSetupMode.destination;
  RideBikeType _selectedBikeType = RideBikeType.nature;

  double _selectedDistanceKm = 10;

  bool _starting = false;
  bool _searchingPlaces = false;
  bool _loadingRouteSuggestions = false;

  // The planner opens in a deliberately clean state. Detailed controls are
  // revealed only after the rider chooses how they want to ride.
  bool _detailsOpen = false;

  List<PlaceSuggestion> _placeSuggestions =
      const <PlaceSuggestion>[];

  PlaceSuggestion? _selectedPlace;
  String? _placeSearchMessage;

  List<RouteResult> _routeSuggestions = const <RouteResult>[];
  int? _selectedRouteSuggestionIndex;
  String? _routeSuggestionMessage;

  static const List<double> _distanceOptions = <double>[
    5,
    10,
    20,
    30,
  ];

  @override
  void initState() {
    super.initState();

    _destinationFocusNode.addListener(
      _onDestinationFocusChanged,
    );

    Future.microtask(
      MunjaProService.instance.initialize,
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();

    _destinationController.dispose();

    _destinationFocusNode
      ..removeListener(_onDestinationFocusChanged)
      ..dispose();

    _scrollController.dispose();

    super.dispose();
  }

  bool get _hasAdvancedRoutePlanner =>
      MunjaProService.instance.hasFeature(
        MunjaProFeature.advancedRoutePlanner,
      );

  bool _isProRouteMode(
    RideSetupMode mode,
  ) {
    return mode == RideSetupMode.roundTrip ||
        mode == RideSetupMode.suggestedRoute;
  }

  Future<void> _openMunjaPro() async {
    FocusScope.of(context).unfocus();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MunjaProScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await MunjaProService.instance.refresh();

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<bool> _ensureRouteModeAccess(
    RideSetupMode mode,
  ) async {
    if (!_isProRouteMode(mode) ||
        _hasAdvancedRoutePlanner) {
      return true;
    }

    await _openMunjaPro();

    if (!mounted) {
      return false;
    }

    return _hasAdvancedRoutePlanner;
  }

  bool get _requiresDestination {
    return _selectedMode == RideSetupMode.destination;
  }

  bool get _showDistanceControls {
    return _selectedMode == RideSetupMode.roundTrip ||
        _selectedMode == RideSetupMode.suggestedRoute;
  }

  bool get _showBikeTypeControls {
    return _selectedMode != RideSetupMode.freeRide;
  }

  bool get _primaryActionEnabled {
    if (_starting || _loadingRouteSuggestions) {
      return false;
    }

    if (_selectedMode == RideSetupMode.destination) {
      return _selectedPlace != null;
    }

    return true;
  }

  bool get _showSuggestions {
    return _requiresDestination &&
        _destinationFocusNode.hasFocus &&
        (_searchingPlaces || _placeSuggestions.isNotEmpty);
  }

  String get _modeTitle {
    switch (_selectedMode) {
      case RideSetupMode.destination:
        return AppText.t('rideSetupSearchDestination');
      case RideSetupMode.roundTrip:
        return AppText.t('rideSetupCreateRoundTrip');
      case RideSetupMode.suggestedRoute:
        return AppText.t('rideSetupGetRouteSuggestions');
      case RideSetupMode.freeRide:
        return AppText.t('rideSetupStartFreeRide');
    }
  }

  String get _startButtonText {
    switch (_selectedMode) {
      case RideSetupMode.destination:
        return AppText.t('rideSetupUseDestination');
      case RideSetupMode.roundTrip:
        return AppText.t('rideSetupCreateRoundTripButton');
      case RideSetupMode.suggestedRoute:
        return _selectedRouteSuggestionIndex == null
            ? AppText.t('rideSetupShowSuggestions')
            : AppText.t('rideSetupUseSelectedSuggestion');
      case RideSetupMode.freeRide:
        return AppText.t('rideSetupStartFreeRide');
    }
  }

  void _onDestinationFocusChanged() {
    if (!mounted) {
      return;
    }

    setState(() {});

    if (_destinationFocusNode.hasFocus) {
      _scrollDestinationIntoView();
    }
  }

  void _scrollDestinationIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final destinationContext =
          _destinationSectionKey.currentContext;

      if (destinationContext == null) {
        return;
      }

      Scrollable.ensureVisible(
        destinationContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  Future<void> _onModeSelected(
    RideSetupMode mode,
  ) async {
    FocusScope.of(context).unfocus();

    final allowed =
        await _ensureRouteModeAccess(mode);

    if (!allowed || !mounted) {
      return;
    }

    setState(() {
      _selectedMode = mode;
      _detailsOpen = true;

      if (mode != RideSetupMode.destination) {
        _placeSuggestions = const <PlaceSuggestion>[];
        _placeSearchMessage = null;
      }

      if (mode != RideSetupMode.suggestedRoute) {
        _routeSuggestions = const <RouteResult>[];
        _selectedRouteSuggestionIndex = null;
        _routeSuggestionMessage = null;
        _loadingRouteSuggestions = false;
      }
    });

    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _closeModeDetails() {
    FocusScope.of(context).unfocus();

    setState(() {
      _detailsOpen = false;
      _placeSuggestions = const <PlaceSuggestion>[];
      _placeSearchMessage = null;
      _routeSuggestions = const <RouteResult>[];
      _selectedRouteSuggestionIndex = null;
      _routeSuggestionMessage = null;
      _loadingRouteSuggestions = false;
    });

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _onDestinationChanged(String value) {
    _searchDebounce?.cancel();

    _selectedPlace = null;

    final query = value.trim();

    if (query.length < 2) {
      setState(() {
        _searchingPlaces = false;
        _placeSuggestions = const <PlaceSuggestion>[];
        _placeSearchMessage = null;
      });

      return;
    }

    setState(() {
      _searchingPlaces = true;
      _placeSearchMessage = null;
    });

    _searchDebounce = Timer(
      const Duration(milliseconds: 320),
      () async {
        List<PlaceSuggestion> suggestions =
            const <PlaceSuggestion>[];
        String? message;

        try {
          suggestions =
              await PlaceSearchService.instance.search(query);
        } on PlaceSearchException catch (error) {
          debugPrint(
            'RIDE SETUP PLACE SEARCH ERROR: $error',
          );

          // Keep the UI useful even if Google Places is temporarily
          // unavailable or disabled. This is especially useful in debug
          // builds while the Google Cloud API configuration is being fixed.
          suggestions = _localFallbackSuggestions(query);

          message = suggestions.isEmpty
              ? AppText.t('rideSetupAddressSuggestionsUnavailable')
              : AppText.t('rideSetupGooglePlacesLocalFallback');
        } catch (error, stackTrace) {
          debugPrint(
            'RIDE SETUP PLACE SEARCH UNKNOWN ERROR: $error',
          );
          debugPrint('$stackTrace');

          suggestions = _localFallbackSuggestions(query);

          message = suggestions.isEmpty
              ? AppText.t('rideSetupAddressSuggestionsUnavailable')
              : AppText.t('rideSetupShowingLocalSuggestions');
        }

        if (!mounted ||
            _destinationController.text.trim() != query) {
          return;
        }

        setState(() {
          _searchingPlaces = false;
          _placeSuggestions = suggestions;
          _placeSearchMessage = message;
        });

        _scrollDestinationIntoView();
      },
    );
  }

  List<PlaceSuggestion> _localFallbackSuggestions(
    String query,
  ) {
    const places = <PlaceSuggestion>[
      PlaceSuggestion(
        placeId: 'fallback_odense',
        primaryText: 'Odense',
        secondaryText: 'Odense Kommune, Danmark',
        latitude: 55.4038,
        longitude: 10.4024,
      ),
      PlaceSuggestion(
        placeId: 'fallback_odense_banegaard',
        primaryText: 'Odense Banegård Center',
        secondaryText: 'Østre Stationsvej 27, 5000 Odense C',
        latitude: 55.4019,
        longitude: 10.3877,
      ),
      PlaceSuggestion(
        placeId: 'fallback_odense_zoo',
        primaryText: 'Odense ZOO',
        secondaryText: 'Søndre Boulevard 306, 5000 Odense C',
        latitude: 55.3785,
        longitude: 10.3709,
      ),
      PlaceSuggestion(
        placeId: 'fallback_sdu',
        primaryText: 'Syddansk Universitet',
        secondaryText: 'Campusvej 55, 5230 Odense M',
        latitude: 55.3682,
        longitude: 10.4281,
      ),
      PlaceSuggestion(
        placeId: 'fallback_ouh',
        primaryText: 'Odense Universitetshospital',
        secondaryText: 'J.B. Winsløws Vej 4, 5000 Odense C',
        latitude: 55.3831,
        longitude: 10.3707,
      ),
      PlaceSuggestion(
        placeId: 'fallback_agedrup',
        primaryText: 'Agedrup',
        secondaryText: '5320 Agedrup',
        latitude: 55.4317,
        longitude: 10.4920,
      ),
      PlaceSuggestion(
        placeId: 'fallback_bullerup',
        primaryText: 'Bullerup',
        secondaryText: '5320 Agedrup',
        latitude: 55.4287,
        longitude: 10.4636,
      ),
      PlaceSuggestion(
        placeId: 'fallback_kerteminde',
        primaryText: 'Kerteminde',
        secondaryText: '5300 Kerteminde',
        latitude: 55.4497,
        longitude: 10.6570,
      ),
      PlaceSuggestion(
        placeId: 'fallback_nyborg',
        primaryText: 'Nyborg',
        secondaryText: '5800 Nyborg',
        latitude: 55.3127,
        longitude: 10.7896,
      ),
    ];

    final normalized = query.toLowerCase();

    return places
        .where(
          (place) =>
              place.primaryText
                  .toLowerCase()
                  .contains(normalized) ||
              place.secondaryText
                  .toLowerCase()
                  .contains(normalized),
        )
        .take(6)
        .toList(growable: false);
  }

  Future<void> _selectPlace(
    PlaceSuggestion suggestion,
  ) async {
    setState(() {
      _selectedPlace = suggestion;
      _destinationController.text = suggestion.fullText;
      _destinationController.selection = TextSelection.collapsed(
        offset: _destinationController.text.length,
      );
      _searchingPlaces = true;
      _placeSuggestions = const <PlaceSuggestion>[];
    });

    PlaceSuggestion resolved = suggestion;

    try {
      resolved =
          await PlaceSearchService.instance.getDetails(
            suggestion,
          );
    } on PlaceSearchException catch (error) {
      debugPrint(
        'RIDE SETUP PLACE DETAILS ERROR: $error',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'RIDE SETUP PLACE DETAILS UNKNOWN ERROR: $error',
      );
      debugPrint('$stackTrace');
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedPlace = resolved;
      _searchingPlaces = false;
      _placeSuggestions = const <PlaceSuggestion>[];
      _placeSearchMessage = null;
    });

    _destinationFocusNode.unfocus();
  }

  void _clearDestination() {
    _searchDebounce?.cancel();

    setState(() {
      _destinationController.clear();
      _selectedPlace = null;
      _placeSuggestions = const <PlaceSuggestion>[];
      _searchingPlaces = false;
      _placeSearchMessage = null;
    });

    _destinationFocusNode.requestFocus();
  }

  Future<Position?> _getSuggestionPosition() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
      } catch (_) {
        return lastKnown;
      }
    } catch (error, stackTrace) {
      debugPrint(
        'RIDE SETUP SUGGESTION POSITION ERROR: $error',
      );
      debugPrint('$stackTrace');
      return null;
    }
  }

  Future<void> _loadSuggestedRoutes() async {
    if (_loadingRouteSuggestions) {
      return;
    }

    final allowed =
        await _ensureRouteModeAccess(
      RideSetupMode.suggestedRoute,
    );

    if (!allowed || !mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _loadingRouteSuggestions = true;
      _routeSuggestionMessage = null;
      _routeSuggestions = const <RouteResult>[];
      _selectedRouteSuggestionIndex = null;
    });

    try {
      final position = await _getSuggestionPosition();

      if (!mounted) {
        return;
      }

      if (position == null) {
        setState(() {
          _loadingRouteSuggestions = false;
          _routeSuggestionMessage =
              AppText.t('rideSetupGpsUnavailable');
        });
        return;
      }

      final routes =
          await RouteService.instance.calculateSuggestedRoutes(
        originLatitude: position.latitude,
        originLongitude: position.longitude,
        targetDistanceKm: _selectedDistanceKm,
        suggestionCount: 3,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRouteSuggestions = false;
        _routeSuggestions = routes;
        _selectedRouteSuggestionIndex =
            routes.isEmpty ? null : 0;
        _routeSuggestionMessage = routes.isEmpty
            ? AppText.t('rideSetupNoGoodSuggestions')
            : AppText.t('rideSetupChooseBestRoute');
      });
    } on RouteServiceException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRouteSuggestions = false;
        _routeSuggestionMessage =
            '${AppText.t('rideSetupSuggestionsLoadFailed')} ${error.message}';
      });
    } catch (error, stackTrace) {
      debugPrint(
        'RIDE SETUP SUGGESTED ROUTES ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRouteSuggestions = false;
        _routeSuggestionMessage =
            AppText.t('rideSetupSuggestionsLoadFailedRetry');
      });
    }
  }

  void _selectRouteSuggestion(int index) {
    if (index < 0 || index >= _routeSuggestions.length) {
      return;
    }

    setState(() {
      _selectedRouteSuggestionIndex = index;
    });
  }

  Future<void> _startRide() async {
    if (_starting) {
      return;
    }

    final allowed =
        await _ensureRouteModeAccess(
      _selectedMode,
    );

    if (!allowed || !mounted) {
      return;
    }

    final destination = _destinationController.text.trim();

    if (_selectedMode == RideSetupMode.suggestedRoute &&
        _routeSuggestions.isEmpty) {
      await _loadSuggestedRoutes();
      return;
    }

    if (_selectedMode == RideSetupMode.suggestedRoute &&
        _selectedRouteSuggestionIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppText.t('rideSetupChooseSuggestionFirst'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_requiresDestination && destination.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppText.t('rideSetupEnterAndChooseDestination'),
          ),
        ),
      );

      return;
    }

    if (_requiresDestination && _selectedPlace == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppText.t('rideSetupChooseAddressFromSuggestions'),
          ),
        ),
      );

      _destinationFocusNode.requestFocus();

      return;
    }

    FocusScope.of(context).unfocus();

    setState(() => _starting = true);

    final selectedPlace = _selectedPlace;

    RouteResult? selectedSuggestedRoute;
    final selectedSuggestionIndex =
        _selectedRouteSuggestionIndex;

    if (_selectedMode == RideSetupMode.suggestedRoute &&
        selectedSuggestionIndex != null &&
        selectedSuggestionIndex >= 0 &&
        selectedSuggestionIndex < _routeSuggestions.length) {
      selectedSuggestedRoute =
          _routeSuggestions[selectedSuggestionIndex];
    }

    final result = RideSetupResult(
      mode: _selectedMode,
      bikeType: _selectedBikeType,
      distanceKm: _selectedDistanceKm,
      destination: _requiresDestination
          ? selectedPlace?.fullText ?? destination
          : '',
      destinationPlaceId: selectedPlace?.placeId,
      destinationLatitude: selectedPlace?.latitude,
      destinationLongitude: selectedPlace?.longitude,
      suggestedRouteDistanceMeters:
          selectedSuggestedRoute?.distanceMeters,
      suggestedRouteDurationSeconds:
          selectedSuggestedRoute?.durationSeconds,
      suggestedRouteEncodedPolyline:
          selectedSuggestedRoute?.encodedPolyline,
    );

    try {
      final callback = widget.onStartRide;

      if (callback != null) {
        callback(result);
      } else if (mounted) {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen =
        MediaQuery.viewInsetsOf(context).bottom > 0;

    return ValueListenableBuilder<MunjaProState>(
      valueListenable:
          MunjaProService.instance.state,
      builder: (
        context,
        proState,
        _,
      ) {
        final hasAdvancedPlanner =
            proState.hasActivePro &&
            _hasAdvancedRoutePlanner;

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 4,
        title: Text(
          AppText.t('rideSetupTitle'),
          style: TextStyle(
            color: MunjaColors.text,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        leading: IconButton(
          onPressed: () {
            if (_detailsOpen) {
              _closeModeDetails();
              return;
            }

            final onBackToHome = widget.onBackToHome;

            if (onBackToHome != null) {
              onBackToHome();
              return;
            }

            Navigator.of(context).maybePop();
          },
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: MunjaColors.text,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          controller: _scrollController,
          keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            keyboardOpen ? 42 : 320,
          ),
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _detailsOpen
                  ? _SelectedModeHeader(
                      key: ValueKey<RideSetupMode>(_selectedMode),
                      mode: _selectedMode,
                      onChangeMode: _closeModeDetails,
                    )
                  : _PlannerIntro(
                      key: ValueKey<String>('planner-intro'),
                    ),
            ),
            const SizedBox(height: 18),

            if (!_detailsOpen) ...[
              _SectionHeader(
                title: AppText.t('rideSetupHowRide'),
                subtitle:
                    AppText.t('rideSetupChooseOneOption'),
              ),
              const SizedBox(height: 12),
              _ModeGrid(
                selectedMode: null,
                hasAdvancedPlanner:
                    hasAdvancedPlanner,
                onSelected: _onModeSelected,
              ),
              const SizedBox(height: 18),
              const _CleanPlannerHint(),
            ] else ...[
              if (_isProRouteMode(_selectedMode)) ...[
                _PlannerProStatus(
                  active: hasAdvancedPlanner,
                  onTap: _openMunjaPro,
                ),
                const SizedBox(height: 14),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _ModeControls(
                  key: ValueKey<RideSetupMode>(_selectedMode),
                  mode: _selectedMode,
                  destinationSectionKey: _destinationSectionKey,
                  destinationController: _destinationController,
                  destinationFocusNode: _destinationFocusNode,
                  searchingPlaces: _searchingPlaces,
                  placeSuggestions: _placeSuggestions,
                  placeSearchMessage: _placeSearchMessage,
                  selectedPlace: _selectedPlace,
                  showSuggestions: _showSuggestions,
                  googleEnabled:
                      PlaceSearchService.instance.hasApiKey,
                  onDestinationChanged: _onDestinationChanged,
                  onClearDestination: _clearDestination,
                  onSuggestionSelected: _selectPlace,
                ),
              ),

              if (_showDistanceControls) ...[
                const SizedBox(height: 22),
                _SectionHeader(
                  title: AppText.t('rideSetupHowFar'),
                  subtitle:
                      AppText.t('rideSetupChooseApproxDistance'),
                ),
                const SizedBox(height: 12),
                _DistanceSelector(
                  values: _distanceOptions,
                  selectedValue: _selectedDistanceKm,
                  onSelected: (value) {
                    setState(() {
                      _selectedDistanceKm = value;
                      _routeSuggestions =
                          const <RouteResult>[];
                      _selectedRouteSuggestionIndex = null;
                      _routeSuggestionMessage = null;
                    });
                  },
                ),
              ],

              if (_showBikeTypeControls) ...[
                const SizedBox(height: 22),
                _SectionHeader(
                  title: AppText.t('rideSetupHowRouteFeel'),
                  subtitle:
                      AppText.t('rideSetupRouteStyleSubtitle'),
                ),
                const SizedBox(height: 12),
                _BikeTypeSelector(
                  selectedType: _selectedBikeType,
                  onSelected: (type) {
                    setState(() {
                      _selectedBikeType = type;
                      _routeSuggestions =
                          const <RouteResult>[];
                      _selectedRouteSuggestionIndex = null;
                      _routeSuggestionMessage = null;
                    });
                  },
                ),
              ],

              if (_selectedMode ==
                  RideSetupMode.suggestedRoute) ...[
                const SizedBox(height: 24),
                _SuggestedRoutesPanel(
                  loading: _loadingRouteSuggestions,
                  routes: _routeSuggestions,
                  selectedIndex: _selectedRouteSuggestionIndex,
                  message: _routeSuggestionMessage,
                  targetDistanceKm: _selectedDistanceKm,
                  onSelected: _selectRouteSuggestion,
                  onRefresh: _loadSuggestedRoutes,
                ),
              ],

              const SizedBox(height: 24),
              _PlannerPrimaryAction(
                mode: _selectedMode,
                loading:
                    _starting || _loadingRouteSuggestions,
                enabled: _primaryActionEnabled,
                label: _loadingRouteSuggestions
                    ? AppText.t('rideSetupFindingSuggestions')
                    : _starting
                        ? AppText.t('rideSetupPreparing')
                        : _startButtonText,
                onPressed: _startRide,
              ),
              const SizedBox(height: 14),
              _WheelCockpitHint(mode: _selectedMode),
            ],
          ],
        ),
          ),
        );
      },
    );
  }
}

class _PlannerProStatus extends StatelessWidget {
  const _PlannerProStatus({
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? null : onTap,
        borderRadius:
            BorderRadius.circular(20),
        child: Ink(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            color: MunjaColors.mint
                .withValues(alpha: 0.07),
            borderRadius:
                BorderRadius.circular(20),
            border: Border.all(
              color: MunjaColors.mint
                  .withValues(alpha: 0.17),
            ),
          ),
          child: Row(
            children: [
              Icon(
                active
                    ? Icons.verified_rounded
                    : Icons.lock_rounded,
                color: MunjaColors.mint,
                size: 18,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  active
                      ? AppText.t('rideSetupProPlannerActive')
                      : AppText.t('rideSetupProRequired'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
              if (!active)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: MunjaColors.mint,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlannerIntro extends StatelessWidget {
  _PlannerIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 21),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MunjaColors.mint.withValues(alpha: 0.11),
            MunjaColors.panel.withValues(alpha: 0.58),
            Colors.transparent,
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.055),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.route_rounded,
              color: MunjaColors.mint,
              size: 28,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppText.t('rideSetupIntroTitle'),
                  style: TextStyle(
                    color: MunjaColors.text,
                    fontSize: 21,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.35,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  AppText.t('rideSetupIntroSubtitle'),
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
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

class _SelectedModeHeader extends StatelessWidget {
  const _SelectedModeHeader({
    super.key,
    required this.mode,
    required this.onChangeMode,
  });

  final RideSetupMode mode;
  final VoidCallback onChangeMode;

  ({IconData icon, String title, String subtitle}) get _content {
    switch (mode) {
      case RideSetupMode.destination:
        return (
          icon: Icons.location_searching_rounded,
          title: AppText.t('rideSetupDestination'),
          subtitle: AppText.t('rideSetupDestinationSubtitle'),
        );
      case RideSetupMode.roundTrip:
        return (
          icon: Icons.loop_rounded,
          title: AppText.t('rideSetupRoundTrip'),
          subtitle: AppText.t('rideSetupRoundTripSubtitle'),
        );
      case RideSetupMode.suggestedRoute:
        return (
          icon: Icons.auto_awesome_rounded,
          title: AppText.t('rideSetupMunjaSuggestions'),
          subtitle: AppText.t('rideSetupMunjaSuggestionsSubtitle'),
        );
      case RideSetupMode.freeRide:
        return (
          icon: Icons.explore_rounded,
          title: AppText.t('rideSetupFreeRide'),
          subtitle: AppText.t('rideSetupFreeRideSubtitle'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _content;

    return Container(
      padding: const EdgeInsets.fromLTRB(17, 15, 12, 15),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.17),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              content.icon,
              color: MunjaColors.mint,
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  content.title,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  content.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onChangeMode,
            style: TextButton.styleFrom(
              foregroundColor: MunjaColors.mint,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
            child: Text(
                      AppText.t('rideSetupChange'),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeControls extends StatelessWidget {
  const _ModeControls({
    super.key,
    required this.mode,
    required this.destinationSectionKey,
    required this.destinationController,
    required this.destinationFocusNode,
    required this.searchingPlaces,
    required this.placeSuggestions,
    required this.placeSearchMessage,
    required this.selectedPlace,
    required this.showSuggestions,
    required this.googleEnabled,
    required this.onDestinationChanged,
    required this.onClearDestination,
    required this.onSuggestionSelected,
  });

  final RideSetupMode mode;
  final GlobalKey destinationSectionKey;
  final TextEditingController destinationController;
  final FocusNode destinationFocusNode;
  final bool searchingPlaces;
  final List<PlaceSuggestion> placeSuggestions;
  final String? placeSearchMessage;
  final PlaceSuggestion? selectedPlace;
  final bool showSuggestions;
  final bool googleEnabled;
  final ValueChanged<String> onDestinationChanged;
  final VoidCallback onClearDestination;
  final ValueChanged<PlaceSuggestion> onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    switch (mode) {
      case RideSetupMode.destination:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
              title: AppText.t('rideSetupWhereTo'),
              subtitle:
                  AppText.t('rideSetupSearchAddressOrDestination'),
            ),
            const SizedBox(height: 12),
            _DestinationSearchCard(
              sectionKey: destinationSectionKey,
              controller: destinationController,
              focusNode: destinationFocusNode,
              searching: searchingPlaces,
              suggestions: placeSuggestions,
              searchMessage: placeSearchMessage,
              selectedPlace: selectedPlace,
              showSuggestions: showSuggestions,
              googleEnabled: googleEnabled,
              onChanged: onDestinationChanged,
              onClear: onClearDestination,
              onSuggestionSelected: onSuggestionSelected,
            ),
          ],
        );

      case RideSetupMode.roundTrip:
        return _ModeInfoCard(
          mode: RideSetupMode.roundTrip,
        );

      case RideSetupMode.suggestedRoute:
        return _ModeInfoCard(
          mode: RideSetupMode.suggestedRoute,
        );

      case RideSetupMode.freeRide:
        return _FreeRideHero();
    }
  }
}

class _FreeRideHero extends StatelessWidget {
  _FreeRideHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MunjaColors.mint.withValues(alpha: 0.12),
            MunjaColors.panel.withValues(alpha: 0.55),
          ],
        ),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.explore_rounded,
            color: MunjaColors.mint,
            size: 37,
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppText.t('rideSetupFreeHeroTitle'),
                  style: TextStyle(
                    color: MunjaColors.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  AppText.t('rideSetupFreeHeroBody'),
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
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

class _PlannerPrimaryAction extends StatelessWidget {
  const _PlannerPrimaryAction({
    required this.mode,
    required this.loading,
    required this.enabled,
    required this.label,
    required this.onPressed,
  });

  final RideSetupMode mode;
  final bool loading;
  final bool enabled;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      RideSetupMode.destination => Icons.navigation_rounded,
      RideSetupMode.roundTrip => Icons.loop_rounded,
      RideSetupMode.suggestedRoute => Icons.auto_awesome_rounded,
      RideSetupMode.freeRide => Icons.play_arrow_rounded,
    };

    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton.icon(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: MunjaColors.mint,
          foregroundColor: const Color(0xFF03130F),
          disabledBackgroundColor:
              MunjaColors.mint.withValues(alpha: 0.16),
          disabledForegroundColor:
              Colors.white.withValues(alpha: 0.30),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        icon: loading
            ? const SizedBox(
                width: 19,
                height: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : Icon(icon),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _CleanPlannerHint extends StatelessWidget {
  const _CleanPlannerHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.touch_app_rounded,
          color: Colors.white.withValues(alpha: 0.24),
          size: 15,
        ),
        const SizedBox(width: 7),
        Text(
          AppText.t('rideSetupChooseRideTypeContinue'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _WheelCockpitHint extends StatelessWidget {
  const _WheelCockpitHint({
    required this.mode,
  });

  final RideSetupMode mode;

  @override
  Widget build(BuildContext context) {
    final label = mode == RideSetupMode.freeRide
        ? AppText.t('rideSetupWheelReadyFree')
        : AppText.t('rideSetupWheelReadyPlanning');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.radio_button_checked_rounded,
          color: MunjaColors.mint.withValues(alpha: 0.42),
          size: 11,
        ),
        const SizedBox(width: 7),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.28),
            fontSize: 8.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: MunjaColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.46),
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ModeGrid extends StatelessWidget {
  const _ModeGrid({
    required this.selectedMode,
    required this.hasAdvancedPlanner,
    required this.onSelected,
  });

  final RideSetupMode? selectedMode;
  final bool hasAdvancedPlanner;
  final ValueChanged<RideSetupMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <_ModeOption>[
      _ModeOption(
        mode: RideSetupMode.destination,
        icon: Icons.search_rounded,
        title: AppText.t('rideSetupDestination'),
        subtitle: AppText.t('rideSetupSearchAddress'),
      ),
      _ModeOption(
        mode: RideSetupMode.roundTrip,
        icon: Icons.loop_rounded,
        title: AppText.t('rideSetupRoundTrip'),
        subtitle: AppText.t('rideSetupBackToStart'),
        proOnly: true,
      ),
      _ModeOption(
        mode: RideSetupMode.suggestedRoute,
        icon: Icons.auto_awesome_rounded,
        title: AppText.t('rideSetupSuggestions'),
        subtitle: AppText.t('rideSetupMunjaRecommends'),
        proOnly: true,
      ),
      _ModeOption(
        mode: RideSetupMode.freeRide,
        icon: Icons.explore_rounded,
        title: AppText.t('rideSetupFreeRide'),
        subtitle: AppText.t('rideSetupNoPlannedRoute'),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: options.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.42,
          ),
      itemBuilder: (context, index) {
        final option = options[index];

        return _ModeTile(
          option: option,
          selected:
              selectedMode == option.mode,
          locked:
              option.proOnly &&
              !hasAdvancedPlanner,
          onTap: () =>
              onSelected(option.mode),
        );
      },
    );
  }
}

class _ModeOption {
  _ModeOption({
    required this.mode,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.proOnly = false,
  });

  final RideSetupMode mode;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool proOnly;
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.option,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final _ModeOption option;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted =
        selected && !locked;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(23),
        child: AnimatedContainer(
          duration:
              const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: highlighted
                ? MunjaColors.mint
                    .withValues(alpha: 0.13)
                : MunjaColors.panel
                    .withValues(alpha: 0.66),
            borderRadius:
                BorderRadius.circular(23),
            border: Border.all(
              color: highlighted
                  ? MunjaColors.mintStrong
                  : locked
                      ? MunjaColors.mint
                          .withValues(alpha: 0.16)
                      : Colors.white
                          .withValues(alpha: 0.07),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    option.icon,
                    color: highlighted
                        ? MunjaColors.mint
                        : locked
                            ? Colors.white38
                            : Colors.white60,
                    size: 25,
                  ),
                  const Spacer(),
                  if (option.proOnly)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: MunjaColors.mint
                            .withValues(
                          alpha: locked
                              ? 0.09
                              : 0.16,
                        ),
                        borderRadius:
                            BorderRadius.circular(999),
                        border: Border.all(
                          color: MunjaColors.mint
                              .withValues(
                            alpha: locked
                                ? 0.18
                                : 0.34,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Icon(
                            locked
                                ? Icons.lock_rounded
                                : Icons
                                    .verified_rounded,
                            color: MunjaColors.mint,
                            size: 10,
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'PRO',
                            style: TextStyle(
                              color:
                                  MunjaColors.mint,
                              fontSize: 8,
                              fontWeight:
                                  FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                option.title,
                style: TextStyle(
                  color: locked
                      ? Colors.white60
                      : MunjaColors.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                locked
                    ? AppText.t('rideSetupRequiresPro')
                    : option.subtitle,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted ||
                          (option.proOnly &&
                              !locked)
                      ? MunjaColors.mint
                      : Colors.white
                          .withValues(alpha: 0.40),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DestinationSearchCard extends StatelessWidget {
  const _DestinationSearchCard({
    super.key,
    required this.sectionKey,
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.suggestions,
    required this.searchMessage,
    required this.selectedPlace,
    required this.showSuggestions,
    required this.googleEnabled,
    required this.onChanged,
    required this.onClear,
    required this.onSuggestionSelected,
  });

  final GlobalKey sectionKey;
  final TextEditingController controller;
  final FocusNode focusNode;

  final bool searching;
  final bool showSuggestions;
  final bool googleEnabled;

  final List<PlaceSuggestion> suggestions;
  final PlaceSuggestion? selectedPlace;
  final String? searchMessage;

  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  final ValueChanged<PlaceSuggestion>
      onSuggestionSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText:
                  AppText.t('rideSetupAddressHint'),
              prefixIcon: const Icon(
                Icons.location_on_outlined,
              ),
              suffixIcon: controller.text.trim().isEmpty
                  ? null
                  : IconButton(
                      tooltip: AppText.t('rideSetupClear'),
                      onPressed: onClear,
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                    ),
            ),
          ),
          if (searching) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              minHeight: 2,
              color: MunjaColors.mint,
            ),
          ],
          if (searchMessage != null &&
              searchMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: MunjaColors.mint,
                  size: 17,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    searchMessage!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 10,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (selectedPlace != null &&
              !showSuggestions &&
              !searching) ...[
            const SizedBox(height: 12),
            _SelectedPlaceRow(place: selectedPlace!),
          ],
          if (showSuggestions && !searching) ...[
            const SizedBox(height: 12),
            if (suggestions.isEmpty)
              _EmptySuggestionState(
                googleEnabled: googleEnabled,
              )
            else
              _SuggestionList(
                suggestions: suggestions,
                onSelected: onSuggestionSelected,
              ),
          ],
          if (!googleEnabled) ...[
            const SizedBox(height: 10),
            Text(
              AppText.t('rideSetupLocalTestMode'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.34),
                fontSize: 9,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.suggestions,
    required this.onSelected,
  });

  final List<PlaceSuggestion> suggestions;

  final ValueChanged<PlaceSuggestion> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (
            var index = 0;
            index < suggestions.length;
            index++
          ) ...[
            InkWell(
              onTap: () => onSelected(
                suggestions[index],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: MunjaColors.mint.withValues(
                          alpha: 0.10,
                        ),
                        borderRadius:
                            BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.place_rounded,
                        color: MunjaColors.mint,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestions[index]
                                .primaryText,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MunjaColors.text,
                              fontSize: 13,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                          if (suggestions[index]
                              .secondaryText
                              .isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              suggestions[index]
                                  .secondaryText,
                              maxLines: 2,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white
                                    .withValues(
                                      alpha: 0.42,
                                    ),
                                fontSize: 10,
                                height: 1.3,
                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.north_west_rounded,
                      color: Colors.white30,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            if (index < suggestions.length - 1)
              Divider(
                height: 1,
                color: Colors.white.withValues(
                  alpha: 0.05,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SelectedPlaceRow extends StatelessWidget {
  const _SelectedPlaceRow({
    required this.place,
  });

  final PlaceSuggestion place;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: MunjaColors.mint,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              place.fullText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MunjaColors.text,
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySuggestionState extends StatelessWidget {
  const _EmptySuggestionState({
    required this.googleEnabled,
  });

  final bool googleEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          const Icon(
            Icons.search_off_rounded,
            color: Colors.white38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              googleEnabled
                  ? AppText.t('rideSetupNoAddresses')
                  : AppText.t('rideSetupNoLocalAddresses'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeInfoCard extends StatelessWidget {
  _ModeInfoCard({
    super.key,
    required this.mode,
  });

  final RideSetupMode mode;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String title;
    late final String body;

    switch (mode) {
      case RideSetupMode.destination:
        icon = Icons.location_on_outlined;
        title = AppText.t('rideSetupChooseDestination');
        body = AppText.t('rideSetupEnterAddressRoute');
        break;
      case RideSetupMode.roundTrip:
        icon = Icons.loop_rounded;
        title = AppText.t('rideSetupAutomaticRoundTrip');
        body =
            AppText.t('rideSetupRoundTripInfo');
        break;
      case RideSetupMode.suggestedRoute:
        icon = Icons.auto_awesome_rounded;
        title = AppText.t('rideSetupSuggestions');
        body =
            AppText.t('rideSetupSuggestionsInfo');
        break;
      case RideSetupMode.freeRide:
        icon = Icons.explore_rounded;
        title = AppText.t('rideSetupFreeRide');
        body =
            AppText.t('rideSetupFreeRideInfo');
        break;
    }

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              icon,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: 0.47),
                    fontSize: 11,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
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

class _SuggestedRoutesPanel extends StatelessWidget {
  const _SuggestedRoutesPanel({
    required this.loading,
    required this.routes,
    required this.selectedIndex,
    required this.message,
    required this.targetDistanceKm,
    required this.onSelected,
    required this.onRefresh,
  });

  final bool loading;
  final List<RouteResult> routes;
  final int? selectedIndex;
  final String? message;
  final double targetDistanceKm;
  final ValueChanged<int> onSelected;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.13),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: MunjaColors.mint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Munja ruteforslag',
                      style: TextStyle(
                        color: MunjaColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${AppText.t('rideSetupAround')} ${targetDistanceKm.toStringAsFixed(0)} km',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.43),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (routes.isNotEmpty && !loading)
                IconButton(
                  tooltip: AppText.t('rideSetupFindNewSuggestions'),
                  onPressed: onRefresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: MunjaColors.mint,
                  ),
                ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(
              color: MunjaColors.mint,
              minHeight: 2,
            ),
            const SizedBox(height: 10),
            Text(
              AppText.t('rideSetupAnalyzingRoads'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (message != null && message!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              message!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 10,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (routes.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (var index = 0; index < routes.length; index++) ...[
              _SuggestedRouteCard(
                index: index,
                route: routes[index],
                selected: selectedIndex == index,
                targetDistanceKm: targetDistanceKm,
                onTap: () => onSelected(index),
              ),
              if (index < routes.length - 1)
                const SizedBox(height: 9),
            ],
          ],
        ],
      ),
    );
  }
}

class _SuggestedRouteCard extends StatelessWidget {
  const _SuggestedRouteCard({
    required this.index,
    required this.route,
    required this.selected,
    required this.targetDistanceKm,
    required this.onTap,
  });

  final int index;
  final RouteResult route;
  final bool selected;
  final double targetDistanceKm;
  final VoidCallback onTap;

  String get _durationLabel {
    final minutes = (route.durationSeconds / 60).round();

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;

    return restMinutes == 0
        ? '${hours}t'
        : '${hours}t ${restMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = route.distanceMeters / 1000;
    final differenceKm =
        (distanceKm - targetDistanceKm).abs();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? MunjaColors.mintStrong
                  : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? MunjaColors.mint.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: selected
                        ? MunjaColors.mint
                        : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${AppText.t('rideSetupRoute')} ${index + 1}',
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${distanceKm.toStringAsFixed(1)} km  •  $_durationLabel',
                      style: TextStyle(
                        color: selected
                            ? MunjaColors.mint
                            : Colors.white.withValues(alpha: 0.50),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      differenceKm <= 0.5
                          ? AppText.t('rideSetupVeryCloseDistance')
                          : '${differenceKm.toStringAsFixed(1)} ${AppText.t('rideSetupKmFromGoal')}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.34),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected
                    ? MunjaColors.mint
                    : Colors.white24,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistanceSelector extends StatelessWidget {
  const _DistanceSelector({
    required this.values,
    required this.selectedValue,
    required this.onSelected,
  });

  final List<double> values;
  final double selectedValue;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (
          var index = 0;
          index < values.length;
          index++
        ) ...[
          Expanded(
            child: _DistanceTile(
              value: values[index],
              selected:
                  values[index] == selectedValue,
              onTap: () =>
                  onSelected(values[index]),
            ),
          ),
          if (index < values.length - 1)
            const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _DistanceTile extends StatelessWidget {
  const _DistanceTile({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 58,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withValues(alpha: 0.13)
                : MunjaColors.panel.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected
                  ? MunjaColors.mintStrong
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Text(
            '${value.toStringAsFixed(0)} km',
            style: TextStyle(
              color: selected
                  ? MunjaColors.mint
                  : MunjaColors.textSoft,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _BikeTypeSelector extends StatelessWidget {
  const _BikeTypeSelector({
    required this.selectedType,
    required this.onSelected,
  });

  final RideBikeType selectedType;
  final ValueChanged<RideBikeType> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = <_BikeTypeOption>[
      _BikeTypeOption(
        type: RideBikeType.mtb,
        icon: Icons.terrain_rounded,
        label: 'MTB',
      ),
      _BikeTypeOption(
        type: RideBikeType.road,
        icon: Icons.speed_rounded,
        label: AppText.t('rideSetupBikeRoad'),
      ),
      _BikeTypeOption(
        type: RideBikeType.family,
        icon: Icons.family_restroom_rounded,
        label: AppText.t('rideSetupBikeFamily'),
      ),
      _BikeTypeOption(
        type: RideBikeType.nature,
        icon: Icons.forest_rounded,
        label: AppText.t('rideSetupBikeNature'),
      ),
      _BikeTypeOption(
        type: RideBikeType.quietRoads,
        icon: Icons.route_rounded,
        label: AppText.t('rideSetupBikeQuiet'),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final selected =
            selectedType == option.type;

        return ChoiceChip(
          selected: selected,
          onSelected: (_) =>
              onSelected(option.type),
          avatar: Icon(
            option.icon,
            size: 17,
            color: selected
                ? const Color(0xFF03130F)
                : Colors.white60,
          ),
          label: Text(option.label),
          selectedColor: MunjaColors.mint,
          backgroundColor:
              MunjaColors.panel.withValues(alpha: 0.72),
          side: BorderSide(
            color: selected
                ? MunjaColors.mint
                : Colors.white.withValues(alpha: 0.07),
          ),
          labelStyle: TextStyle(
            color: selected
                ? const Color(0xFF03130F)
                : Colors.white70,
            fontWeight: FontWeight.w900,
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _BikeTypeOption {
  _BikeTypeOption({
    required this.type,
    required this.icon,
    required this.label,
  });

  final RideBikeType type;
  final IconData icon;
  final String label;
}

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({
    required this.mode,
    required this.bikeType,
    required this.distanceKm,
    required this.destination,
    required this.selectedPlace,
  });

  final RideSetupMode mode;
  final RideBikeType bikeType;
  final double distanceKm;
  final String destination;
  final PlaceSuggestion? selectedPlace;

  String get _modeLabel {
    switch (mode) {
      case RideSetupMode.destination:
        return AppText.t('rideSetupDestination');
      case RideSetupMode.roundTrip:
        return AppText.t('rideSetupRoundTrip');
      case RideSetupMode.suggestedRoute:
        return AppText.t('rideSetupSuggestions');
      case RideSetupMode.freeRide:
        return AppText.t('rideSetupFreeRide');
    }
  }

  String get _bikeTypeLabel {
    switch (bikeType) {
      case RideBikeType.mtb:
        return 'MTB';
      case RideBikeType.road:
        return AppText.t('rideSetupBikeRoad');
      case RideBikeType.family:
        return AppText.t('rideSetupBikeFamily');
      case RideBikeType.nature:
        return AppText.t('rideSetupBikeNature');
      case RideBikeType.quietRoads:
        return AppText.t('rideSetupBikeQuietRoads');
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeDescription =
        mode == RideSetupMode.destination &&
            destination.isNotEmpty
        ? destination
        : '$_modeLabel · '
            '${distanceKm.toStringAsFixed(0)} km';

    final selected = mode != RideSetupMode.destination ||
        selectedPlace != null;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
          color: selected
              ? MunjaColors.mint.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.navigation_rounded
                : Icons.location_searching_rounded,
            color: selected
                ? MunjaColors.mint
                : Colors.white38,
            size: 25,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                      AppText.t('rideSetupSelectedRide'),
                  style: TextStyle(
                    color: MunjaColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  routeDescription,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color:
                        Colors.white.withValues(alpha: 0.52),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _bikeTypeLabel,
                  style: TextStyle(
                    color: selected
                        ? MunjaColors.mint
                        : Colors.white38,
                    fontSize: 11,
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
