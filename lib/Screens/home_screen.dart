import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/firestore_bike.dart';
import '../models/munja_device.dart';
import '../models/trip.dart';
import '../models/user_profile.dart';
import '../models/live_ride_state.dart';
import '../models/social_rider_profile.dart';
import '../providers/bike_provider.dart';
import '../providers/digital_twin_provider.dart';
import '../services/ble_service.dart';
import '../Services/live_ride_bus.dart';
import '../services/ride_session_service.dart';
import '../services/storage_service.dart';
import '../services/xp_service.dart';
import '../services/challenge_service.dart';
import '../services/social_rider_service.dart';
import '../Services/munja_pro_service.dart';
import '../services/monthly_special_service.dart';
import '../widgets/munja_navigation_bike_viewer.dart';
import '../widgets/munja_3d_bike_viewer.dart';
import '../widgets/munja_crystal_balance_badge.dart';
import 'auto_ride_screen.dart';
import 'garage_screen.dart';
import 'active_challenges_screen.dart';
import 'crystal_shop_screen.dart';
import 'munja_pro_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onOpenGarage,
  });

  /// When Home is hosted by MainNavigation, use the main Garage tab instead
  /// of pushing a second GarageScreen on top of Home. This keeps ownership of
  /// the persistent native Digital Twin deterministic.
  final VoidCallback? onOpenGarage;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  RideSessionData _rideData = RideSessionData.initial();
  List<MunjaDevice> _nearbyDevices = const <MunjaDevice>[];
  UserProfile? _userProfile;
  List<Trip> _trips = const <Trip>[];
  MunjaChallenge? _activeChallenge;
  SocialRiderProfile? _challengeOpponent;
  MonthlySpecialActivation? _monthlyActivation;
  bool _loadingChallenge = false;
  bool _loadingMonthlySpecial = false;

  // Live Home data: active challenge progress + canonical account XP.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _createdActiveChallengesSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _receivedActiveChallengesSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _accountUserSubscription;

  final Map<String, MunjaChallenge> _liveCreatedChallenges =
      <String, MunjaChallenge>{};
  final Map<String, MunjaChallenge> _liveReceivedChallenges =
      <String, MunjaChallenge>{};

  int? _accountTotalXp;
  String? _loadedOpponentUid;
  bool _wasRideActive = false;

  // Incremented every time a live ride finishes.
  // This forces a fresh showroom Digital Twin instance after leaving navigation
  // mode, ensuring the native camera/transform is restored to the normal Home
  // presentation instead of inheriting the live cockpit position.
  int _home3dResetEpoch = 0;

  String? _lastSyncedBikeSignature;
  bool _digitalTwinSyncScheduled = false;
  bool _scanningBle = false;

  // Native Interactive3d / Filament must not stay alive underneath another
  // screen that is about to create its own native 3D renderer.
  //
  // When opening Garage we first replace Home's 3D widget with a lightweight
  // placeholder, wait for Flutter to dispose the native texture, and only then
  // push Garage.
  bool _suspendHome3d = false;

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  bool get _hasBrakeLightNearby {
    return _nearbyDevices.any(
      (device) => device.type == MunjaProductType.brakeLight,
    );
  }

  int get _batteryPercent => _hasBrakeLightNearby ? 82 : 64;

  Future<void> _setHome3dSuspended(bool value) async {
    if (!mounted || _suspendHome3d == value) {
      return;
    }

    setState(() {
      _suspendHome3d = value;
    });

    // endOfFrame ensures the conditional 3D child has actually been removed
    // from the widget tree before another route can create a new renderer.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      return;
    }

    // The interactive_3d Android plugin releases Filament resources on the
    // native/UI thread. Give that cleanup a short deterministic window before
    // another FEngine is created.
    if (value) {
      await Future<void>.delayed(
        const Duration(milliseconds: 350),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    // IMPORTANT:
    // The central ride engine publishes the real active-ride state through
    // LiveRideBus. Home must use that bus as its source of truth.
    //
    // RideSessionService is still used elsewhere for ride/session data, but it
    // must not decide whether Home is in live navigation mode.
    _rideData = RideSessionService.instance.current;

    _wasRideActive = LiveRideBus.instance.state.value.isActive;
    LiveRideBus.instance.state.addListener(_handleLiveRideChanged);

    Future.microtask(() async {
      await MunjaProService.instance.initialize();

      if (!mounted) {
        return;
      }

      _startLiveHomeData();
      await _initializeHome();
      await _loadMonthlySpecial();
    });
  }

  Future<void> _initializeHome() async {
    final bikeProvider = context.read<BikeProvider>();

    if (!bikeProvider.isInitialized) {
      await bikeProvider.refresh();
    }

    await Future.wait<void>([
      _scanBle(),
      _loadRiderProgress(),
      _loadActiveChallenge(),
      _loadMonthlySpecial(),
    ]);
  }

  @override
  void dispose() {
    LiveRideBus.instance.state.removeListener(_handleLiveRideChanged);

    unawaited(_createdActiveChallengesSubscription?.cancel());
    unawaited(_receivedActiveChallengesSubscription?.cancel());
    unawaited(_accountUserSubscription?.cancel());

    super.dispose();
  }

  void _handleLiveRideChanged() {
    final live = LiveRideBus.instance.state.value;
    final isActive = live.isActive;

    // Update ride count / ride XP immediately when a ride finishes.
    if (_wasRideActive && !isActive) {
      if (mounted) {
        setState(() {
          _home3dResetEpoch += 1;
        });
      }

      Future.microtask(() async {
        await _loadRiderProgress();
        await _loadMonthlySpecial();
      });
    }

    _wasRideActive = isActive;
  }

  void _startLiveHomeData() {
    final uid = _currentUserId;

    if (uid.isEmpty) {
      return;
    }

    unawaited(_createdActiveChallengesSubscription?.cancel());
    unawaited(_receivedActiveChallengesSubscription?.cancel());
    unawaited(_accountUserSubscription?.cancel());

    final challenges =
        FirebaseFirestore.instance.collection('challenges');

    _createdActiveChallengesSubscription = challenges
        .where('creatorUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen(
      (snapshot) {
        _liveCreatedChallenges
          ..clear()
          ..addEntries(
            snapshot.docs.map((doc) {
              final challenge = MunjaChallenge.fromFirestore(doc);
              return MapEntry<String, MunjaChallenge>(
                challenge.id,
                challenge,
              );
            }),
          );

        _rebuildLiveActiveChallenge();
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('HOME LIVE CREATED CHALLENGES ERROR: $error');
        debugPrint('$stackTrace');
      },
    );

    _receivedActiveChallengesSubscription = challenges
        .where('opponentUid', isEqualTo: uid)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen(
      (snapshot) {
        _liveReceivedChallenges
          ..clear()
          ..addEntries(
            snapshot.docs.map((doc) {
              final challenge = MunjaChallenge.fromFirestore(doc);
              return MapEntry<String, MunjaChallenge>(
                challenge.id,
                challenge,
              );
            }),
          );

        _rebuildLiveActiveChallenge();
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('HOME LIVE RECEIVED CHALLENGES ERROR: $error');
        debugPrint('$stackTrace');
      },
    );

    // Firestore users/{uid}.totalXp is the same durable account XP that
    // Profile uses. Home listens to it directly so Home and Profile can never
    // disagree after reinstall, login or a live XP reward.
    _accountUserSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) {
          return;
        }

        final data = snapshot.data() ?? const <String, dynamic>{};
        final totalXp = _readInt(data['totalXp']);

        if (!mounted || totalXp == _accountTotalXp) {
          return;
        }

        setState(() {
          _accountTotalXp = totalXp;
        });

        debugPrint('HOME LIVE ACCOUNT XP: $_accountTotalXp');
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('HOME LIVE ACCOUNT XP ERROR: $error');
        debugPrint('$stackTrace');
      },
    );
  }

  void _rebuildLiveActiveChallenge() {
    final combined = <String, MunjaChallenge>{
      ..._liveCreatedChallenges,
      ..._liveReceivedChallenges,
    }.values.toList();

    combined.sort((a, b) {
      final aDate =
          a.startedAt ??
          a.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bDate =
          b.startedAt ??
          b.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });

    final selected = combined.isEmpty ? null : combined.first;

    if (mounted) {
      setState(() {
        _activeChallenge = selected;

        if (selected == null) {
          _challengeOpponent = null;
          _loadedOpponentUid = null;
        }
      });
    }

    if (selected != null) {
      unawaited(_loadLiveChallengeOpponent(selected));
    }
  }

  Future<void> _loadLiveChallengeOpponent(
    MunjaChallenge challenge,
  ) async {
    final currentUid = ChallengeService.instance.currentUid ?? '';
    final opponentUid = challenge.otherUidFor(currentUid).trim();

    if (opponentUid.isEmpty || opponentUid == _loadedOpponentUid) {
      return;
    }

    _loadedOpponentUid = opponentUid;

    try {
      final opponent =
          await SocialRiderService.instance.getProfileByUid(opponentUid);

      if (!mounted ||
          _activeChallenge?.id != challenge.id ||
          _loadedOpponentUid != opponentUid) {
        return;
      }

      setState(() {
        _challengeOpponent = opponent;
      });
    } catch (error, stackTrace) {
      debugPrint('HOME LIVE CHALLENGE OPPONENT ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  static int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  String _bikeSignature(FirestoreBike bike) {
    return <Object?>[
      bike.id,
      bike.name,
      bike.brand,
      bike.model,
      bike.type,
      bike.color,
      bike.imageUrl,
      bike.glbModelUrl,
      bike.digitalTwinEnabled,
      bike.effectiveActiveSkin,
      bike.effectiveActiveFrameId,
      bike.effectiveFrameColor,
      bike.firmwareVersion,
      bike.updatedAt,
    ].join('|');
  }

  void _scheduleDigitalTwinSync({
    required FirestoreBike? activeBike,
    required DigitalTwinProvider digitalTwinProvider,
  }) {
    final signature =
        activeBike == null ? null : _bikeSignature(activeBike);

    if (_digitalTwinSyncScheduled ||
        signature == _lastSyncedBikeSignature) {
      return;
    }

    _digitalTwinSyncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _digitalTwinSyncScheduled = false;

      if (!mounted) {
        return;
      }

      final currentBike = context.read<BikeProvider>().activeBike;

      if (currentBike == null) {
        digitalTwinProvider.reset();
        _lastSyncedBikeSignature = null;
        return;
      }

      final currentSignature = _bikeSignature(currentBike);

      if (currentSignature == _lastSyncedBikeSignature) {
        return;
      }

      final currentTwin = digitalTwinProvider.digitalTwin;

      if (currentTwin == null || currentTwin.bike.id != currentBike.id) {
        await digitalTwinProvider.initializeEmpty(
          bike: currentBike,
        );
      } else {
        digitalTwinProvider.updateBike(currentBike);
      }

      _lastSyncedBikeSignature = currentSignature;
    });
  }

  Future<void> _scanBle() async {
    if (_scanningBle) {
      return;
    }

    _scanningBle = true;

    try {
      final saved = await StorageService.loadSavedDevices();

      final nearby = await BleService.scanNearbyMunjaDevices(
        saved: saved,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _nearbyDevices = nearby;
      });
    } catch (error, stackTrace) {
      debugPrint('HOME BLE SCAN ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      _scanningBle = false;
    }
  }

  Future<void> _loadRiderProgress() async {
    try {
      final profile = await StorageService.loadUserProfile();
      final trips = await StorageService.loadTrips();

      if (!mounted) {
        return;
      }

      setState(() {
        _userProfile = profile;
        _trips = trips;
      });
    } catch (error, stackTrace) {
      debugPrint('HOME RIDER PROGRESS ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _loadMonthlySpecial() async {
    if (_loadingMonthlySpecial) {
      return;
    }

    _loadingMonthlySpecial = true;

    try {
      if (!MunjaProService.instance.isPro) {
        if (mounted && _monthlyActivation != null) {
          setState(() {
            _monthlyActivation = null;
          });
        }
        return;
      }

      final activation =
          await MonthlySpecialService.instance.getActiveActivation();

      if (!mounted) {
        return;
      }

      setState(() {
        _monthlyActivation = activation;
      });
    } catch (error, stackTrace) {
      debugPrint('HOME MONTHLY SPECIAL ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      _loadingMonthlySpecial = false;
    }
  }

  Future<void> _loadActiveChallenge() async {
    if (_loadingChallenge) {
      return;
    }

    _loadingChallenge = true;

    try {
      final challenges =
          await ChallengeService.instance.getActiveChallenges();

      MunjaChallenge? selected;
      SocialRiderProfile? opponentProfile;

      if (challenges.isNotEmpty) {
        selected = challenges.first;

        final currentUid = ChallengeService.instance.currentUid ?? '';
        final opponentUid = selected.otherUidFor(currentUid);

        if (opponentUid.isNotEmpty) {
          opponentProfile =
              await SocialRiderService.instance.getProfileByUid(
            opponentUid,
          );
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _activeChallenge = selected;
        _challengeOpponent = opponentProfile;
      });
    } catch (error, stackTrace) {
      debugPrint('HOME ACTIVE CHALLENGE ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _activeChallenge = null;
        _challengeOpponent = null;
      });
    } finally {
      _loadingChallenge = false;
    }
  }

  Future<void> _openActiveChallenges() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ActiveChallengesScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadActiveChallenge();
  }

  Future<void> _openMunjaPro() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MunjaProScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    await _loadMonthlySpecial();
  }

  Future<void> _refreshHome() async {
    await context.read<BikeProvider>().refresh();
    await Future.wait<void>([
      _scanBle(),
      _loadRiderProgress(),
      _loadActiveChallenge(),
    ]);
  }

  Future<void> _openCrystalShop() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CrystalShopScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    // The Crystal badge listens live to Firestore already, so no explicit
    // balance refresh is required here. Keeping this hook makes the flow
    // future-proof if Home later needs to refresh additional shop state.
    setState(() {});
  }

  Future<void> _openGarage() async {
    // Preferred path inside MainNavigation: change to the real Garage tab.
    // This avoids mounting a second GarageScreen over Home.
    final openGarageTab = widget.onOpenGarage;
    if (openGarageTab != null) {
      openGarageTab();
      return;
    }

    // Fallback for any standalone HomeScreen usage.
    await _setHome3dSuspended(true);

    if (!mounted) {
      return;
    }

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const GarageScreen(),
        ),
      );
    } finally {
      if (mounted) {
        await _setHome3dSuspended(false);
      }
    }

    if (!mounted) {
      return;
    }

    await context.read<BikeProvider>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveRideState>(
      valueListenable: LiveRideBus.instance.state,
      builder: (context, liveRide, _) {
        final isLive = liveRide.isActive;

        debugPrint(
          'HOME LIVE BUS: '
          'isActive=${liveRide.isActive} '
          'paused=${liveRide.isPaused} '
          'speed=${liveRide.speedKmh.toStringAsFixed(1)} '
          'distance=${liveRide.distanceKm.toStringAsFixed(3)} '
          'path=${liveRide.path.length}',
        );

        return Consumer2<BikeProvider, DigitalTwinProvider>(
          builder: (
            context,
            bikeProvider,
            digitalTwinProvider,
            _,
          ) {
            final activeBike = bikeProvider.activeBike;

        _scheduleDigitalTwinSync(
          activeBike: activeBike,
          digitalTwinProvider: digitalTwinProvider,
        );

        final initialLoading =
            !bikeProvider.isInitialized ||
            (bikeProvider.isLoading && bikeProvider.bikes.isEmpty);

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
                padding: const EdgeInsets.fromLTRB(
                  18,
                  16,
                  18,
                  250,
                ),
                children: [
                  ValueListenableBuilder<MunjaProState>(
                    valueListenable: MunjaProService.instance.state,
                    builder: (
                      context,
                      proState,
                      _,
                    ) {
                      return _MinimalHomeHeader(
                        userId: _currentUserId,
                        isPro: proState.hasActivePro,
                        onOpenCrystalShop: _openCrystalShop,
                        onOpenGarage: _openGarage,
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  if (bikeProvider.hasError && !initialLoading) ...[
                    _HomeErrorCard(
                      message: bikeProvider.errorMessage ??
                          'Cyklen kunne ikke indlæses.',
                      onRetry: _refreshHome,
                      onDismiss: bikeProvider.clearError,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (initialLoading)
                    const _HomeLoadingCard()
                  else if (activeBike == null)
                    _NoActiveBikeCard(
                      onOpenGarage: _openGarage,
                    )
                  else ...[
                    _MinimalDigitalTwinHero(
                      bike: activeBike,
                      isLive: isLive,
                      speedKmh: liveRide.speedKmh,
                      brakeLightConnected: _hasBrakeLightNearby,
                      suspend3d: _suspendHome3d,
                      home3dResetEpoch: _home3dResetEpoch,
                      onOpenGarage: _openGarage,
                    ),
                    const SizedBox(height: 16),
                    _MinimalStatusStrip(
                      gpsActive: true,
                      bleConnected: _hasBrakeLightNearby,
                      batteryPercent: _batteryPercent,
                      profile: _userProfile,
                      trips: _trips,
                      accountTotalXp: _accountTotalXp,
                      monthlyActivation: _monthlyActivation,
                      activeChallenge: _activeChallenge,
                      challengeOpponent: _challengeOpponent,
                      currentUid:
                          ChallengeService.instance.currentUid ?? '',
                      onOpenMonthlySpecial: _openMunjaPro,
                      onOpenChallenge: _openActiveChallenges,
                    ),
                  ],
                ],
              ),
            ),
          ),
          );
        },
      );
      },
    );
  }
}

class _MinimalHomeHeader extends StatelessWidget {
  const _MinimalHomeHeader({
    required this.userId,
    required this.isPro,
    required this.onOpenCrystalShop,
    required this.onOpenGarage,
  });

  final String userId;
  final bool isPro;
  final VoidCallback onOpenCrystalShop;
  final VoidCallback onOpenGarage;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'MUNJA',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 27,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 6.2,
                    ),
                  ),
                  if (isPro)
                    const TextSpan(
                      text: '  PRO',
                      style: TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 3.0,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),

        // Crystal balance belongs on Home only. Keeping it inside the header
        // prevents it from covering content on Ride, Garage, Gear, Profile or
        // pushed pages while keeping the rider's balance immediately visible.
        if (userId.isNotEmpty) ...[
          MunjaCrystalBalanceBadge(
            uid: userId,
            compact: true,
            showLabel: false,
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 7,
            ),
            onTap: onOpenCrystalShop,
          ),
          const SizedBox(width: 9),
        ],

        Material(
          color: Colors.white.withOpacity(0.055),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: AppText.t('gear'),
            onPressed: onOpenGarage,
            icon: const Icon(
              Icons.pedal_bike_rounded,
              color: MunjaColors.mint,
              size: 23,
            ),
          ),
        ),
      ],
    );
  }
}

class _MinimalDigitalTwinHero extends StatelessWidget {
  const _MinimalDigitalTwinHero({
    required this.bike,
    required this.isLive,
    required this.speedKmh,
    required this.brakeLightConnected,
    required this.suspend3d,
    required this.home3dResetEpoch,
    required this.onOpenGarage,
  });

  final FirestoreBike bike;
  final bool isLive;
  final double speedKmh;
  final bool brakeLightConnected;
  final bool suspend3d;
  final int home3dResetEpoch;
  final VoidCallback onOpenGarage;

  @override
  Widget build(BuildContext context) {
    debugPrint('HOME HERO BUILD: isLive=$isLive');

    return Container(
      height: 500,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(
            isLive ? 0.24 : 0.12,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(
              isLive ? 0.12 : 0.08,
            ),
            blurRadius: isLive ? 36 : 28,
            spreadRadius: 1,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isLive && !suspend3d)
            const AutoRideScreen(
              key: ValueKey<String>('home-live-google-map'),
              embedded: true,
            ),

          if (suspend3d)
            const Positioned.fill(
              child: _Home3dSuspendedPlaceholder(),
            )
          else
            Positioned.fill(
              child: isLive
                  ? IgnorePointer(
                      child: MunjaNavigationBikeViewer(
                        key: const ValueKey<String>(
                          'home-live-navigation-bike',
                        ),
                        navigationMode: true,
                        rideSpeedKmh: speedKmh,
                        enableTouch: false,
                        height: 500,
                        modelPath:
                            MunjaNavigationBikeViewer.defaultModelPath,

                        // Keep live navigation/cockpit synchronized with the
                        // exact Digital Twin setup selected in Customize.
                        activeSkinId: bike.effectiveActiveSkin.isEmpty
                            ? 'standard'
                            : bike.effectiveActiveSkin,
                        activeFrameId:
                            bike.effectiveActiveFrameId.isEmpty
                                ? 'frame_1'
                                : bike.effectiveActiveFrameId,
                        activeFrameColor: bike.effectiveFrameColor.isEmpty
                            ? '#9AA2A0'
                            : bike.effectiveFrameColor,

                        borderRadius: 34,
                        showGrid: false,
                        showGlow: false,
                        backgroundColor: Colors.transparent,
                        homeCameraOrbit: '0deg 72deg 105%',
                        homeCameraTarget: 'auto auto auto',
                        homeFieldOfView: '38deg',
                        navigationCameraOrbit:
                            '180deg 72deg 105%',
                        navigationCameraTarget:
                            '0m 0.72m 0m',
                        navigationFieldOfView: '32deg',
                      ),
                    )
                  : Munja3DBikeViewer(
                      key: ValueKey<String>(
                        'home-digital-twin-${bike.id}-'
                        '${bike.effectiveActiveFrameId}-'
                        '${bike.effectiveActiveSkin}-'
                        '${bike.effectiveFrameColor}-'
                        'reset-$home3dResetEpoch',
                      ),
                      height: 500,
                      isLive: false,
                      enableTouch: true,
                      showControls: false,
                      showSkinTester: false,
                      showBadges: false,
                      showBottomInfo: false,
                      showProductHotspot: false,
                      useDigitalTwinMaterials: true,

                      // Native Filament showroom motion.
                      // Home gets the same stronger premium movement as Garage.
                      showroomSwing: true,
                      showroomSwingDegrees: 16.0,
                      showroomSwingDuration:
                          const Duration(milliseconds: 2600),
                      showroomSwingResumeDelay:
                          const Duration(seconds: 2),

                      activeSkinId: bike.effectiveActiveSkin.isEmpty
                          ? 'standard'
                          : bike.effectiveActiveSkin,
                      activeFrameId:
                          bike.effectiveActiveFrameId.isEmpty
                              ? 'frame_1'
                              : bike.effectiveActiveFrameId,
                      frameColor: bike.effectiveFrameColor.isEmpty
                          ? '#9AA2A0'
                          : bike.effectiveFrameColor,
                      onBikeTap: onOpenGarage,
                    ),
            ),
        ],
      ),
    );
  }
}

class _Home3dSuspendedPlaceholder extends StatelessWidget {
  const _Home3dSuspendedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MunjaColors.panel,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MunjaColors.mint.withOpacity(0.08),
                border: Border.all(
                  color: MunjaColors.mint.withOpacity(0.16),
                ),
              ),
              child: const Icon(
                Icons.pedal_bike_rounded,
                color: MunjaColors.mint,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
                AppText.t('homeOpeningGear'),
              style: TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinimalStatusStrip extends StatefulWidget {
  const _MinimalStatusStrip({
    required this.gpsActive,
    required this.bleConnected,
    required this.batteryPercent,
    required this.profile,
    required this.trips,
    required this.accountTotalXp,
    required this.monthlyActivation,
    required this.activeChallenge,
    required this.challengeOpponent,
    required this.currentUid,
    required this.onOpenMonthlySpecial,
    required this.onOpenChallenge,
  });

  final bool gpsActive;
  final bool bleConnected;
  final int batteryPercent;
  final UserProfile? profile;
  final List<Trip> trips;
  final int? accountTotalXp;
  final MonthlySpecialActivation? monthlyActivation;
  final MunjaChallenge? activeChallenge;
  final SocialRiderProfile? challengeOpponent;
  final String currentUid;
  final VoidCallback onOpenMonthlySpecial;
  final VoidCallback onOpenChallenge;

  @override
  State<_MinimalStatusStrip> createState() =>
      _MinimalStatusStripState();
}

class _MinimalStatusStripState extends State<_MinimalStatusStrip> {
  static const String _compactPreferenceKey =
      'munja_home_status_compact_v1';

  bool _hideTechnicalStatus = false;
  bool _preferenceLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hidden =
          prefs.getBool(_compactPreferenceKey) ?? false;

      if (!mounted) {
        return;
      }

      setState(() {
        _hideTechnicalStatus = hidden;
        _preferenceLoaded = true;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'HOME STATUS STRIP PREF LOAD ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (mounted) {
        setState(() {
          _preferenceLoaded = true;
        });
      }
    }
  }

  Future<void> _toggleTechnicalStatus() async {
    final next = !_hideTechnicalStatus;

    setState(() {
      _hideTechnicalStatus = next;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        _compactPreferenceKey,
        next,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'HOME STATUS STRIP PREF SAVE ERROR: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keep the exact same strip height and outer styling.
    // Only the internal width allocation changes.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.52),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.065),
        ),
      ),
      child: Row(
        children: [
          // Small persistent toggle. In expanded-info mode it sits on the left,
          // leaving the carousel almost the full width.
          _StatusExpandButton(
            expanded: _hideTechnicalStatus,
            onTap: _toggleTechnicalStatus,
          ),

          const SizedBox(width: 6),

          Expanded(
            flex: _hideTechnicalStatus ? 8 : 2,
            child: _HomeStatusCarousel(
              profile: widget.profile,
              trips: widget.trips,
              accountTotalXp: widget.accountTotalXp,
              monthlyActivation: widget.monthlyActivation,
              activeChallenge: widget.activeChallenge,
              challengeOpponent: widget.challengeOpponent,
              currentUid: widget.currentUid,
              onOpenMonthlySpecial:
                  widget.onOpenMonthlySpecial,
              onOpenChallenge:
                  widget.onOpenChallenge,
            ),
          ),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _hideTechnicalStatus
                ? const SizedBox.shrink(
                    key: ValueKey<String>(
                      'home-tech-hidden',
                    ),
                  )
                : Row(
                    key: const ValueKey<String>(
                      'home-tech-visible',
                    ),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _StatusDivider(),
                      SizedBox(
                        width: 52,
                        child: _MinimalStatusItem(
                          icon:
                              Icons.gps_fixed_rounded,
                          label: 'GPS',
                          value: widget.gpsActive
                              ? AppText.t('active')
                              : AppText.t('inactive'),
                          active:
                              widget.gpsActive,
                        ),
                      ),
                      const _StatusDivider(),
                      SizedBox(
                        width: 52,
                        child: _MinimalStatusItem(
                          icon:
                              Icons.bluetooth_rounded,
                          label: 'BLE',
                          value: widget.bleConnected
                              ? AppText.t('connected')
                              : AppText.t('searching'),
                          active:
                              widget.bleConnected,
                        ),
                      ),
                      const _StatusDivider(),
                      SizedBox(
                        width: 58,
                        child: _MinimalStatusItem(
                          icon:
                              Icons.battery_5_bar_rounded,
                          label:
                              AppText.t('battery'),
                          value:
                              '${widget.batteryPercent}%',
                          active:
                              widget.batteryPercent > 20,
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

class _StatusExpandButton extends StatelessWidget {
  const _StatusExpandButton({
    required this.expanded,
    required this.onTap,
  });

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 28,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: MunjaColors.mint.withOpacity(
              expanded ? 0.11 : 0.055,
            ),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(
                expanded ? 0.22 : 0.10,
              ),
            ),
          ),
          child: AnimatedRotation(
            turns: expanded ? 0.5 : 0.0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: const Icon(
              Icons.chevron_right_rounded,
              color: MunjaColors.mint,
              size: 21,
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeStatusCarousel extends StatefulWidget {
  const _HomeStatusCarousel({
    required this.profile,
    required this.trips,
    required this.accountTotalXp,
    required this.monthlyActivation,
    required this.activeChallenge,
    required this.challengeOpponent,
    required this.currentUid,
    required this.onOpenMonthlySpecial,
    required this.onOpenChallenge,
  });

  final UserProfile? profile;
  final List<Trip> trips;
  final int? accountTotalXp;
  final MonthlySpecialActivation? monthlyActivation;
  final MunjaChallenge? activeChallenge;
  final SocialRiderProfile? challengeOpponent;
  final String currentUid;
  final VoidCallback onOpenMonthlySpecial;
  final VoidCallback onOpenChallenge;

  @override
  State<_HomeStatusCarousel> createState() =>
      _HomeStatusCarouselState();
}

class _HomeStatusCarouselState extends State<_HomeStatusCarousel> {
  static const Duration _slideDuration = Duration(seconds: 4);

  late final PageController _pageController;
  Timer? _slideTimer;
  Timer? _countdownTimer;
  int _page = 0;

  int get _slideCount {
    var count = 1; // Level is always present.
    if (widget.monthlyActivation != null) {
      count += 1;
    }
    if (widget.activeChallenge != null) {
      count += 1;
    }
    return count;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _restartSlideTimer();

    _countdownTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted && widget.monthlyActivation != null) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant _HomeStatusCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final slidesChanged =
        oldWidget.monthlyActivation?.id !=
                widget.monthlyActivation?.id ||
            oldWidget.activeChallenge?.id !=
                widget.activeChallenge?.id;

    if (slidesChanged) {
      _page = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      _restartSlideTimer();
    }
  }

  @override
  void dispose() {
    _slideTimer?.cancel();
    _countdownTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _restartSlideTimer() {
    _slideTimer?.cancel();

    _slideTimer = Timer.periodic(
      _slideDuration,
      (_) {
        if (!mounted || !_pageController.hasClients) {
          return;
        }

        final count = _slideCount;
        if (count <= 1) {
          return;
        }

        final next = (_page + 1) % count;
        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final slides = <Widget>[
      _LevelStatusSlide(
        profile: widget.profile,
        trips: widget.trips,
        accountTotalXp: widget.accountTotalXp,
      ),
      if (widget.monthlyActivation != null)
        _MonthlySpecialStatusSlide(
          activation: widget.monthlyActivation!,
          onTap: widget.onOpenMonthlySpecial,
        ),
      if (widget.activeChallenge != null)
        _FriendChallengeStatusSlide(
          challenge: widget.activeChallenge!,
          opponent: widget.challengeOpponent,
          currentUid: widget.currentUid,
          onTap: widget.onOpenChallenge,
        ),
    ];

    if (_page >= slides.length) {
      _page = 0;
    }

    return SizedBox(
      height: 48,
      child: PageView.builder(
        controller: _pageController,
        itemCount: slides.length,
        onPageChanged: (value) {
          _page = value;
          _restartSlideTimer();
        },
        itemBuilder: (context, index) => slides[index],
      ),
    );
  }
}

class _LevelStatusSlide extends StatelessWidget {
  const _LevelStatusSlide({
    required this.profile,
    required this.trips,
    required this.accountTotalXp,
  });

  final UserProfile? profile;
  final List<Trip> trips;
  final int? accountTotalXp;

  @override
  Widget build(BuildContext context) {
    final localRideXp = XpService.totalXp(trips);
    final totalXp = XpService.resolveTotalXp(
      localXp: localRideXp,
      accountXp: accountTotalXp,
    );
    final level = XpService.levelForTotalXp(totalXp);
    final xp = XpService.xpIntoCurrentLevel(totalXp);
    final xpForNextLevel = XpService.xpNeededForNextLevel(totalXp);
    final progress = XpService.levelProgress(totalXp);

    final photoPath = profile?.photoPath;
    final photoFile =
        photoPath == null || photoPath.trim().isEmpty
            ? null
            : File(photoPath);
    final hasPhoto =
        photoFile != null && photoFile.existsSync();

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MunjaColors.mint.withOpacity(0.10),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.28),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasPhoto
              ? Image.file(
                  photoFile,
                  fit: BoxFit.cover,
                )
              : const Icon(
                  Icons.person_rounded,
                  color: MunjaColors.mint,
                  size: 23,
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LVL $level',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor:
                      Colors.white.withOpacity(0.08),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(
                    MunjaColors.mint,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$xp / $xpForNextLevel XP',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MonthlySpecialStatusSlide extends StatelessWidget {
  const _MonthlySpecialStatusSlide({
    required this.activation,
    required this.onTap,
  });

  final MonthlySpecialActivation activation;
  final VoidCallback onTap;

  String get _timeLabel {
    if (activation.isCompleted) {
      return activation.rewardClaimed
          ? 'CLAIMED'
          : 'REWARD READY';
    }

    final remaining = activation.timeRemaining();

    if (remaining <= Duration.zero) {
      return 'EXPIRED';
    }

    if (remaining.inHours < 24) {
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes.remainder(60);
      return '${hours}H ${minutes}M';
    }

    final days =
        (remaining.inSeconds / Duration.secondsPerDay).ceil();
    return '${days}D LEFT';
  }

  @override
  Widget build(BuildContext context) {
    final special =
        MonthlySpecialService.instance.specialForActivation(
      activation,
    );
    final progress = activation.progressRatio(special);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: MunjaColors.mint.withOpacity(0.10),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: MunjaColors.mint,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          special.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _timeLabel,
                        style: const TextStyle(
                          color: MunjaColors.mint,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor:
                          Colors.white.withOpacity(0.08),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(
                        MunjaColors.mint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_compactProgress(activation.progressValue)} / '
                    '${special.goalLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MunjaColors.textSoft,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compactProgress(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _FriendChallengeStatusSlide extends StatelessWidget {
  const _FriendChallengeStatusSlide({
    required this.challenge,
    required this.opponent,
    required this.currentUid,
    required this.onTap,
  });

  final MunjaChallenge challenge;
  final SocialRiderProfile? opponent;
  final String currentUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUid = challenge.otherUidFor(currentUid);
    final myProgress =
        challenge.genericProgressFor(currentUid).toDouble();
    final otherProgress =
        challenge.genericProgressFor(otherUid).toDouble();
    final myRatio = challenge.progressRatioFor(currentUid);
    final opponentLabel =
        opponent?.usernameWithAt ?? 'Munja rider';
    final unit = _CompactActiveChallengeCard._challengeUnit(
      challenge.type,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: MunjaColors.mint.withOpacity(0.10),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: MunjaColors.mint,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VS $opponentLabel',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: myRatio,
                      minHeight: 4,
                      backgroundColor:
                          Colors.white.withOpacity(0.08),
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(
                        MunjaColors.mint,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_compact(myProgress)} vs '
                    '${_compact(otherProgress)} $unit',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MunjaColors.textSoft,
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _compact(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1);
  }
}

class _MinimalStatusItem extends StatelessWidget {
  const _MinimalStatusItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: color,
          size: 18,
        ),
        const SizedBox(height: 6),
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MunjaColors.textSoft,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.07),
    );
  }
}


class _CompactActiveChallengeCard extends StatelessWidget {
  const _CompactActiveChallengeCard({
    required this.challenge,
    required this.opponent,
    required this.currentUid,
    required this.onTap,
  });

  final MunjaChallenge challenge;
  final SocialRiderProfile? opponent;
  final String currentUid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final otherUid = challenge.otherUidFor(currentUid);
    final myProgress =
        challenge.genericProgressFor(currentUid).toDouble();
    final otherProgress =
        challenge.genericProgressFor(otherUid).toDouble();
    final target = challenge.genericTarget.toDouble();

    final myRatio = challenge.progressRatioFor(currentUid);
    final otherRatio = challenge.progressRatioFor(otherUid);

    final opponentLabel =
        opponent?.usernameWithAt ?? 'Munja rider';
    final unit = _challengeUnit(challenge.type);
    final title = _challengeTitle(
      challenge: challenge,
      target: target,
    );

    final daysLeft = _daysLeft(challenge.endsAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: MunjaColors.panel.withOpacity(0.50),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.16),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: MunjaColors.mint,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                AppText.t('homeActiveChallenge'),
                          style: TextStyle(
                            color: MunjaColors.mint,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const Spacer(),
                        if (daysLeft != null)
                          Text(
                            '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
                            style: const TextStyle(
                              color: MunjaColors.textSoft,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$title · vs $opponentLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          '${_progressText(myProgress)} $unit',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: Stack(
                              children: [
                                Container(
                                  height: 6,
                                  color: Colors.white.withOpacity(0.07),
                                ),
                                FractionallySizedBox(
                                  widthFactor: myRatio,
                                  child: Container(
                                    height: 6,
                                    color: MunjaColors.mint,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_progressText(otherProgress)} $unit',
                          style: const TextStyle(
                            color: MunjaColors.textSoft,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(myRatio * 100).round()}% · ${AppText.t('homeOpponent')} ${(otherRatio * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white30,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: MunjaColors.mint,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static int? _daysLeft(DateTime? endsAt) {
    if (endsAt == null) {
      return null;
    }

    final difference = endsAt.difference(DateTime.now());

    if (difference.isNegative) {
      return 0;
    }

    final hours = difference.inHours;

    if (hours <= 24) {
      return 1;
    }

    return (hours / 24).ceil();
  }

  static String _challengeUnit(MunjaChallengeType type) {
    switch (type) {
      case MunjaChallengeType.distance:
        return 'km';
      case MunjaChallengeType.rideCount:
        return 'rides';
      case MunjaChallengeType.rideTime:
        return 'min';
      case MunjaChallengeType.streak:
        return 'days';
    }
  }

  static String _challengeTitle({
    required MunjaChallenge challenge,
    required double target,
  }) {
    switch (challenge.type) {
      case MunjaChallengeType.distance:
        return '${_progressText(target)} KM';
      case MunjaChallengeType.rideCount:
        return '${_progressText(target)} RIDES';
      case MunjaChallengeType.rideTime:
        if (target % 60 == 0) {
          return '${(target / 60).round()} H RIDE TIME';
        }
        return '${_progressText(target)} MIN';
      case MunjaChallengeType.streak:
        return '${_progressText(target)} DAY STREAK';
    }
  }

  static String _progressText(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }

    return value.toStringAsFixed(1);
  }
}

class _LiveRideStrip extends StatelessWidget {
  const _LiveRideStrip({
    required this.rideData,
  });

  final RideSessionData rideData;

  @override
  Widget build(BuildContext context) {
    final hours = rideData.rideDuration.inHours
        .toString()
        .padLeft(2, '0');

    final minutes = rideData.rideDuration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    final seconds = rideData.rideDuration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _LiveMetric(
              label: AppText.t('speed'),
              value:
                  '${rideData.currentSpeedKmh.toStringAsFixed(1)} km/t',
            ),
          ),
          Expanded(
            child: _LiveMetric(
              label: AppText.t('distance'),
              value: '${rideData.distanceKm.toStringAsFixed(2)} km',
            ),
          ),
          Expanded(
            child: _LiveMetric(
              label: AppText.t('time'),
              value: '$hours:$minutes:$seconds',
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: MunjaColors.mint,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _NoActiveBikeCard extends StatelessWidget {
  const _NoActiveBikeCard({
    required this.onOpenGarage,
  });

  final VoidCallback onOpenGarage;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        22,
        42,
        22,
        42,
      ),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.66),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MunjaColors.mint.withOpacity(0.10),
            ),
            child: const Icon(
              Icons.pedal_bike_rounded,
              color: MunjaColors.mint,
              size: 34,
            ),
          ),
          const SizedBox(height: 18),
          Text(
                AppText.t('homeNoActiveBike'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          Text(
                AppText.t('homeNoActiveBikeBody'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpenGarage,
            style: FilledButton.styleFrom(
              backgroundColor: MunjaColors.mint,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 14,
              ),
            ),
            icon: const Icon(
              Icons.pedal_bike_rounded,
            ),
            label: Text(
                AppText.t('homeOpenGear'),
              style: TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeLoadingCard extends StatelessWidget {
  const _HomeLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 500,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.62),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: const CircularProgressIndicator(
        color: MunjaColors.mint,
      ),
    );
  }
}

class _HomeErrorCard extends StatelessWidget {
  const _HomeErrorCard({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.09),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.redAccent.withOpacity(0.22),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              onRetry();
            },
            icon: const Icon(
              Icons.refresh_rounded,
              color: MunjaColors.mint,
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}
