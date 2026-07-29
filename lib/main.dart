import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'widgets/live_hud_overlay.dart';
import 'widgets/home_live_ride_card.dart';
import 'widgets/ride_recovery_sheet.dart';
import 'widgets/active_products_strip.dart';
import 'services/ride_session_service.dart';
import 'services/ride_controller_service.dart';
import 'services/live_ride_bus.dart';
import 'services/background_ride_engine.dart';
import 'services/home_ai_engine.dart';
import 'models/live_ride_state.dart';
import 'providers/bike_provider.dart';
import 'providers/digital_twin_provider.dart';
import 'services/bluetooth/digital_twin_ble_service.dart';
import 'firebase_options.dart';

import 'widgets/wheel_navbar.dart';
import 'core/theme/munja_colors.dart';
import 'core/constants/app_constants.dart';
import 'core/localization/app_text.dart';
import 'models/munja_device.dart';
import 'models/trip.dart';
import 'models/user_profile.dart';
import 'widgets/munja_card.dart';
import 'widgets/stat_pill.dart';
import 'widgets/section_title.dart';
import 'widgets/menu_tile.dart';
import 'widgets/hero_badge.dart';
import 'widgets/avatar_mini_card.dart';
import 'widgets/product_hero_card.dart';
import 'services/ble_service.dart';
import 'services/storage_service.dart';
import 'services/voice_coach_service.dart';
import 'screens/auth_gate.dart';
import 'screens/brake_light_dashboard.dart';
import 'screens/main_navigation.dart';
import 'screens/ride_summary_screen.dart';
import 'screens/ride_analytics_screen.dart';
import 'screens/smart_route_planner_screen.dart';
import 'screens/smart_ride_coach_screen.dart';
import 'screens/ride_history_screen.dart';

final ValueNotifier<bool> munjaRideActiveNotifier = ValueNotifier<bool>(false);

class MunjaStatus {
  final bool brake;
  final int? pwm;
  final double? bs;

  const MunjaStatus({required this.brake, this.pwm, this.bs});

  static MunjaStatus? tryParse(String raw) {
    final parts = raw.split(';');
    final map = <String, String>{};
    for (final p in parts) {
      if (!p.contains('=')) continue;
      final s = p.split('=');
      if (s.length == 2) map[s[0]] = s[1];
    }
    if (!map.containsKey('BRAKE')) return null;
    return MunjaStatus(
      brake: map['BRAKE'] == '1',
      pwm: int.tryParse(map['PWM'] ?? ''),
      bs: double.tryParse(map['BS'] ?? ''),
    );
  }
}

class MonthlyStats {
  final String label;
  final double km;
  final double co2Kg;

  const MonthlyStats({
    required this.label,
    required this.km,
    required this.co2Kg,
  });
}

class AvatarOption {
  final int id;
  final String emoji;
  final String label;

  const AvatarOption({
    required this.id,
    required this.emoji,
    required this.label,
  });
}

class BgLocationMessage {
  final double latitude;
  final double longitude;
  final double speedMps;
  final double distanceM;
  final bool tripActive;
  final int? tripStartMs;
  final List<List<double>> path;

  const BgLocationMessage({
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    required this.distanceM,
    required this.tripActive,
    required this.tripStartMs,
    required this.path,
  });

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'speedMps': speedMps,
    'distanceM': distanceM,
    'tripActive': tripActive,
    'tripStartMs': tripStartMs,
    'path': path,
  };

  factory BgLocationMessage.fromJson(Map<String, dynamic> json) {
    return BgLocationMessage(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speedMps: (json['speedMps'] as num).toDouble(),
      distanceM: (json['distanceM'] as num).toDouble(),
      tripActive: json['tripActive'] as bool,
      tripStartMs: json['tripStartMs'] as int?,
      path: (json['path'] as List? ?? const [])
          .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
          .where((e) => e.length >= 2)
          .map((e) => <double>[e[0], e[1]])
          .toList(),
    );
  }
}

const List<AvatarOption> avatarOptions = [
  AvatarOption(id: 0, emoji: '🚴', label: 'Classic Rider'),
  AvatarOption(id: 1, emoji: '⚡', label: 'Speed Mode'),
  AvatarOption(id: 2, emoji: '🌿', label: 'Eco Mode'),
  AvatarOption(id: 3, emoji: '🔥', label: 'Challenge Mode'),
  AvatarOption(id: 4, emoji: '🌙', label: 'Night Ride'),
  AvatarOption(id: 5, emoji: '🛡️', label: 'Safe Rider'),
];

AvatarOption avatarById(int id) {
  return avatarOptions.firstWhere(
    (a) => a.id == id,
    orElse: () => avatarOptions.first,
  );
}

Future<void> initForegroundTask() async {
  FlutterForegroundTask.initCommunicationPort();

  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'munja_tracking_channel',
      channelName: 'Munja Background Tracking',
      channelDescription: 'Tracks rides in the background',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      enableVibration: false,
      playSound: false,
      showWhen: true,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );
}

Future<bool> requestTrackingPermissions() async {
  final notificationPermission =
      await FlutterForegroundTask.checkNotificationPermission();
  if (notificationPermission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }

  final enabled = await Geolocator.isLocationServiceEnabled();
  if (!enabled) return false;

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return false;
  }

  if (defaultTargetPlatform == TargetPlatform.android &&
      permission != LocationPermission.always) {
    final bg = await Permission.locationAlways.request();
    if (!bg.isGranted) {
      return false;
    }
  }

  return true;
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(MunjaTrackingTaskHandler());
}

class MunjaTrackingTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSub;

  Position? _lastPos;
  bool _tripActive = false;
  int? _tripStartMs;
  double _tripDistanceM = 0;
  final List<List<double>> _tripPath = [];

  int _movingSamples = 0;
  DateTime? _belowStopThresholdSince;

  static const double autoStartKmh = 6.0;
  static const double autoStopKmh = 2.0;
  static const int startSamplesNeeded = 3;
  static const int stopAfterStillSeconds = 30;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await _restoreState();

    const fallbackSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
    );

    final androidSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
      intervalDuration: const Duration(seconds: 3),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: 'Munja Auto Ride',
        notificationText: 'Munja is tracking your ride in background',
        enableWakeLock: true,
      ),
    );

    final locationSettings = defaultTargetPlatform == TargetPlatform.android
        ? androidSettings
        : fallbackSettings;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(_onPosition);
  }

  Future<void> _restoreState() async {
    final saved = await StorageService.loadBgTripState();
    if (saved == null) return;

    _tripActive = saved['tripActive'] == true;
    _tripStartMs = saved['tripStartMs'] as int?;
    _tripDistanceM = ((saved['tripDistanceM'] as num?) ?? 0).toDouble();

    final savedPath = (saved['tripPath'] as List? ?? const [])
        .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
        .where((e) => e.length >= 2)
        .map((e) => <double>[e[0], e[1]])
        .toList();

    _tripPath
      ..clear()
      ..addAll(savedPath);
  }

  Future<void> _persistState() async {
    await StorageService.saveBgTripState({
      'tripActive': _tripActive,
      'tripStartMs': _tripStartMs,
      'tripDistanceM': _tripDistanceM,
      'tripPath': _tripPath,
    });
  }

  Future<void> _onPosition(Position pos) async {
    final speedMps = pos.speed >= 0 ? pos.speed : 0.0;
    final speedKmh = speedMps * 3.6;

    if (speedKmh >= autoStartKmh) {
      _movingSamples++;
      _belowStopThresholdSince = null;
    }

    if (!_tripActive && _movingSamples >= startSamplesNeeded) {
      _tripActive = true;
      _tripStartMs = DateTime.now().millisecondsSinceEpoch;
      _tripDistanceM = 0;
      _tripPath
        ..clear()
        ..add([pos.latitude, pos.longitude]);
      _lastPos = pos;
      await _persistState();
    }

    if (_tripActive) {
      if (_lastPos != null) {
        final segment = Geolocator.distanceBetween(
          _lastPos!.latitude,
          _lastPos!.longitude,
          pos.latitude,
          pos.longitude,
        );

        if (segment > 0 && segment < 250) {
          _tripDistanceM += segment;
        }
      }

      _lastPos = pos;

      final point = <double>[pos.latitude, pos.longitude];
      if (_tripPath.isEmpty ||
          _tripPath.last[0] != point[0] ||
          _tripPath.last[1] != point[1]) {
        _tripPath.add(point);
      }

      if (speedKmh <= autoStopKmh) {
        _belowStopThresholdSince ??= DateTime.now();
      } else {
        _belowStopThresholdSince = null;
      }

      final autoStopByStillness =
          _belowStopThresholdSince != null &&
          DateTime.now().difference(_belowStopThresholdSince!).inSeconds >=
              stopAfterStillSeconds;

      if (autoStopByStillness) {
        await _saveCompletedTrip();
        _tripActive = false;
        _tripStartMs = null;
        _tripDistanceM = 0;
        _tripPath.clear();
        _movingSamples = 0;
        _belowStopThresholdSince = null;
        await _persistState();
      } else {
        await _persistState();
      }
    } else {
      _lastPos = pos;
    }

    FlutterForegroundTask.sendDataToMain(
      BgLocationMessage(
        latitude: pos.latitude,
        longitude: pos.longitude,
        speedMps: speedMps,
        distanceM: _tripDistanceM,
        tripActive: _tripActive,
        tripStartMs: _tripStartMs,
        path: List<List<double>>.from(_tripPath),
      ).toJson(),
    );

    final km = (_tripDistanceM / 1000).toStringAsFixed(2);
    await FlutterForegroundTask.updateService(
      notificationTitle: _tripActive ? 'Munja ride active' : 'Munja monitoring',
      notificationText: _tripActive
          ? 'Distance: $km km · ${speedKmh.toStringAsFixed(1)} km/h'
          : 'Waiting for movement...',
    );
  }

  Future<void> _saveCompletedTrip() async {
    if (_tripStartMs == null) return;

    final trips = await StorageService.loadTrips();

    final trip = Trip(
      startedAtMs: _tripStartMs!,
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
      distanceM: _tripDistanceM,
      brakes: 0,
      hardBrakes: 0,
      path: List<List<double>>.from(_tripPath),
      source: 'software',
    );

    trips.insert(0, trip);
    await StorageService.saveTrips(trips);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _positionSub?.cancel();
    _positionSub = null;
  }

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await AppText.loadSavedLocale();
  await VoiceCoachService.instance.initialize();
  await initForegroundTask();

  await RideControllerService.instance.initialize();
  await BackgroundRideEngine.instance.initialize();
  await BackgroundRideEngine.instance.recoverIfNeeded();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<BikeProvider>(create: (_) => BikeProvider()),
        ChangeNotifierProvider<DigitalTwinProvider>(
          create: (_) => DigitalTwinProvider(),
        ),
        ChangeNotifierProxyProvider<DigitalTwinProvider, DigitalTwinBleService>(
          create: (context) => DigitalTwinBleService(
            digitalTwinProvider: context.read<DigitalTwinProvider>(),
          ),
          update: (_, digitalTwinProvider, bleService) {
            return bleService ??
                DigitalTwinBleService(digitalTwinProvider: digitalTwinProvider);
          },
        ),
      ],
      child: const MunjaApp(),
    ),
  );
}

class MunjaApp extends StatelessWidget {
  const MunjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppText.localeNotifier,
      builder: (context, locale, _) {
        return MaterialApp(
          key: ValueKey(locale.languageCode),
          debugShowCheckedModeBanner: false,
          title: AppText.t('appTitle'),
          locale: locale,
          supportedLocales: const [Locale('da'), Locale('en'), Locale('bs')],

          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: MunjaColors.bg,
            colorScheme: ColorScheme.fromSeed(
              seedColor: MunjaColors.mint,
              brightness: Brightness.dark,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              foregroundColor: Colors.white,
              titleTextStyle: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            sliderTheme: const SliderThemeData(
              showValueIndicator: ShowValueIndicator.always,
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: MunjaColors.panelSoft,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: MunjaColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: MunjaColors.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: MunjaColors.mintStrong),
              ),
            ),
          ),
          home: const AuthGate(authenticatedChild: AppEntryScreen()),
        );
      },
    );
  }
}

class AppEntryScreen extends StatefulWidget {
  const AppEntryScreen({super.key});

  @override
  State<AppEntryScreen> createState() => _AppEntryScreenState();
}

class _AppEntryScreenState extends State<AppEntryScreen> {
  bool loading = true;
  bool onboardingDone = false;
  bool recoverySheetShown = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    onboardingDone = await StorageService.isOnboardingDone();
    if (!mounted) return;

    setState(() => loading = false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowRideRecoverySheet();
    });
  }

  Future<void> _maybeShowRideRecoverySheet() async {
    if (!mounted || recoverySheetShown || !onboardingDone) return;

    final state = LiveRideBus.instance.state.value;

    if (!state.isActive) return;

    recoverySheetShown = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return RideRecoverySheet(
          state: state,
          onContinueRide: () async {
            munjaRideActiveNotifier.value = true;
            await BackgroundRideEngine.instance.recoverIfNeeded();
          },
          onOpenMap: () async {
            munjaRideActiveNotifier.value = true;
            await BackgroundRideEngine.instance.recoverIfNeeded();

            if (!mounted) return;

            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AutoRideScreen()));
          },
          onStopRide: () async {
            munjaRideActiveNotifier.value = false;
            await BackgroundRideEngine.instance.stop();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return onboardingDone ? const MainNavigation() : const OnboardingScreen();
  }
}

class AppShell extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;

  const AppShell({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF071C18), Color(0xFF04110F), Color(0xFF020A09)],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(child: child),
      ),
    );
  }
}

Future<void> openMunjaWebsite() async {
  final uri = Uri.parse(munjaWebsite);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

double weeklyKmFromTrips(List<Trip> trips) {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final startOfWeek = DateTime(monday.year, monday.month, monday.day);
  return trips
      .where((t) {
        final d = DateTime.fromMillisecondsSinceEpoch(t.startedAtMs);
        return !d.isBefore(startOfWeek);
      })
      .fold(0.0, (sum, t) => sum + (t.distanceM / 1000));
}

int streakFromTrips(List<Trip> trips) {
  if (trips.isEmpty) return 0;

  final rideDays =
      trips
          .map((t) => DateTime.fromMillisecondsSinceEpoch(t.startedAtMs))
          .map((d) => DateTime(d.year, d.month, d.day))
          .toSet()
          .toList()
        ..sort((a, b) => b.compareTo(a));

  int streak = 0;
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day);

  for (int i = 0; i < 365; i++) {
    final day = base.subtract(Duration(days: i));
    if (rideDays.contains(day)) {
      streak++;
    } else {
      if (i == 0) continue;
      break;
    }
  }
  return streak;
}

String formatTripDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  return '${seconds}s';
}

String greetingFromHour() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

List<MonthlyStats> buildMonthlyStats(List<Trip> trips) {
  final now = DateTime.now();
  final months = <DateTime>[];
  for (int i = 5; i >= 0; i--) {
    months.add(DateTime(now.year, now.month - i, 1));
  }

  return months.map((monthStart) {
    final nextMonth = DateTime(monthStart.year, monthStart.month + 1, 1);
    final monthTrips = trips.where((t) {
      final d = DateTime.fromMillisecondsSinceEpoch(t.startedAtMs);
      return !d.isBefore(monthStart) && d.isBefore(nextMonth);
    }).toList();
    final km = monthTrips.fold<double>(
      0.0,
      (sum, t) => sum + t.distanceM / 1000,
    );
    return MonthlyStats(
      label:
          '${monthStart.month.toString().padLeft(2, '0')}/${monthStart.year.toString().substring(2)}',
      km: km,
      co2Kg: km * co2PerKmKg,
    );
  }).toList();
}

Widget buildMiniBarChart(List<MonthlyStats> stats) {
  final maxKm = stats.isEmpty
      ? 1.0
      : stats.map((e) => e.km).reduce(math.max).clamp(1.0, double.infinity);

  return SizedBox(
    height: 220,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: stats.map((item) {
        final ratio = item.km <= 0 ? 0.04 : (item.km / maxKm).clamp(0.04, 1.0);
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  item.km.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 12,
                    color: MunjaColors.textSoft,
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  height: 150 * ratio,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        MunjaColors.mintStrong,
                        MunjaColors.blueGlow.withOpacity(0.95),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MunjaColors.textSoft,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    ),
  );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final pageCtrl = PageController();
  int page = 0;

  final nameCtrl = TextEditingController();
  final ageCtrl = TextEditingController();
  final cityCtrl = TextEditingController(text: 'Copenhagen');
  int selectedAvatar = 0;

  @override
  void dispose() {
    pageCtrl.dispose();
    nameCtrl.dispose();
    ageCtrl.dispose();
    cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final age = int.tryParse(ageCtrl.text.trim()) ?? 24;
    await StorageService.saveUserProfile(
      UserProfile(
        name: nameCtrl.text.trim().isEmpty ? 'Rider' : nameCtrl.text.trim(),
        age: age,
        city: cityCtrl.text.trim().isEmpty
            ? 'Copenhagen'
            : cityCtrl.text.trim(),
        avatarIndex: selectedAvatar,
      ),
    );
    await StorageService.setOnboardingDone(true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: AppText.t('welcome'),
      child: Column(
        children: [
          Expanded(
            child: PageView(
              controller: pageCtrl,
              onPageChanged: (v) => setState(() => page = v),
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    MunjaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HeroBadge(
                            icon: Icons.waving_hand_rounded,
                            text: AppText.t('welcomeToMunja'),
                            color: MunjaColors.mint,
                          ),
                          SizedBox(height: 18),
                          Text(
                            AppText.t('howToUseApp'),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          SizedBox(height: 12),
                          Text(
                            AppText.t('howToUseAppBody'),
                            style: TextStyle(
                              color: MunjaColors.textSoft,
                              height: 1.55,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    MunjaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(
                            title: AppText.t('chooseAvatarMode'),
                            subtitle: AppText.t('avatarModeSubtitle'),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: avatarOptions.map((avatar) {
                              final selected = selectedAvatar == avatar.id;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => selectedAvatar = avatar.id),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: 106,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? MunjaColors.mint.withOpacity(0.16)
                                        : MunjaColors.panelSoft,
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(
                                      color: selected
                                          ? MunjaColors.mintStrong
                                          : Colors.white.withOpacity(0.06),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        avatar.emoji,
                                        style: const TextStyle(fontSize: 28),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        avatar.label,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    MunjaCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionTitle(
                            title: AppText.t('setupBeforeStart'),
                            subtitle: AppText.t('setupBeforeStartSubtitle'),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: AppText.t('name'),
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: ageCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: InputDecoration(
                              labelText: AppText.t('age'),
                              prefixIcon: Icon(Icons.cake_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: cityCtrl,
                            decoration: InputDecoration(
                              labelText: AppText.t('city'),
                              prefixIcon: Icon(Icons.location_city_rounded),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _finish,
                              icon: const Icon(Icons.rocket_launch_rounded),
                              label: Text(AppText.t('startApp')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Row(
              children: [
                ...List.generate(3, (index) {
                  final active = page == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.only(right: 8),
                    width: active ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: active ? MunjaColors.mintStrong : Colors.white24,
                    ),
                  );
                }),
                const Spacer(),
                if (page > 0)
                  TextButton(
                    onPressed: () => pageCtrl.previousPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: Text(AppText.t('back')),
                  ),
                const SizedBox(width: 8),
                if (page < 2)
                  FilledButton(
                    onPressed: () => pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: Text(AppText.t('next')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RideControllerService _rideController = RideControllerService.instance;

  List<MunjaDevice> nearbyDevices = [];
  List<Trip> trips = [];

  UserProfile profile = const UserProfile(
    name: 'Rider',
    age: 24,
    city: 'Copenhagen',
    avatarIndex: 0,
  );

  bool scanningBle = false;
  double weeklyGoalKm = 20;

  bool get hasBrakeLightNearby =>
      nearbyDevices.any((d) => d.type == MunjaProductType.brakeLight);

  @override
  void initState() {
    super.initState();

    _rideController.isRideActive.addListener(_onRideControllerChanged);
    _rideController.speedKmh.addListener(_onRideControllerChanged);
    _rideController.distanceKm.addListener(_onRideControllerChanged);
    _rideController.averageSpeedKmh.addListener(_onRideControllerChanged);
    _rideController.rideDuration.addListener(_onRideControllerChanged);

    _loadFast();
    _scanBleLater();
  }

  @override
  void dispose() {
    _rideController.isRideActive.removeListener(_onRideControllerChanged);
    _rideController.speedKmh.removeListener(_onRideControllerChanged);
    _rideController.distanceKm.removeListener(_onRideControllerChanged);
    _rideController.averageSpeedKmh.removeListener(_onRideControllerChanged);
    _rideController.rideDuration.removeListener(_onRideControllerChanged);
    super.dispose();
  }

  void _onRideControllerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  RideSessionData _homeRideData() {
    return RideSessionData(
      isRiding: _rideController.isRideActive.value,
      currentSpeedKmh: _rideController.speedKmh.value,
      averageSpeedKmh: _rideController.averageSpeedKmh.value,
      maxSpeedKmh: _rideController.speedKmh.value,
      distanceKm: _rideController.distanceKm.value,
      rideDuration: _rideController.rideDuration.value,
      calories: 0,
      altitude: null,
      gpsAccuracy: 0,
      lastUpdate: DateTime.now(),
      path: const [],
    );
  }

  Future<void> _loadFast() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final loadedTrips = await StorageService.loadTrips();
      final loadedProfile = await StorageService.loadUserProfile();

      if (!mounted) return;

      setState(() {
        trips = loadedTrips;
        profile = loadedProfile;
        weeklyGoalKm = sp.getDouble(weeklyGoalKmKey) ?? 20;
      });
    } catch (_) {
      // Keep Home usable even if storage fails.
    }
  }

  Future<void> _scanBleLater() async {
    if (!mounted) return;

    setState(() => scanningBle = true);

    try {
      final saved = await StorageService.loadSavedDevices();
      final nearby = await BleService.scanNearbyMunjaDevices(saved: saved);

      if (!mounted) return;

      setState(() {
        nearbyDevices = nearby;
        scanningBle = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => scanningBle = false);
    }
  }

  Future<void> _refreshHome() async {
    await _loadFast();
    await _scanBleLater();
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    await _refreshHome();
  }

  Future<void> _toggleRideFromHome() async {
    if (_rideController.isRideActive.value) {
      munjaRideActiveNotifier.value = false;

      final trip = await BackgroundRideEngine.instance.stop();

      await _loadFast();

      if (!mounted) return;

      if (trip != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RideSummaryScreen(trip: trip)),
        );
      }

      return;
    }

    munjaRideActiveNotifier.value = true;
    await BackgroundRideEngine.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    final rideData = _homeRideData();
    final monitoring = _rideController.isRideActive.value;
    return AppShell(
      title: AppText.t('appTitle'),
      actions: [
        IconButton(
          onPressed: openMunjaWebsite,
          icon: const Icon(Icons.public_rounded),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _refreshHome,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
          children: [
            HomeLiveRideCard(
              data: rideData,
              monitoring: monitoring,
              bleConnected: hasBrakeLightNearby,
              batteryPercent: hasBrakeLightNearby ? 82 : 64,
              onStartStop: _toggleRideFromHome,
              onOpenMap: () => _open(const AutoRideScreen()),
            ),

            const SizedBox(height: 14),

            _ProductFocusCard(
              hasBrakeLight: hasBrakeLightNearby,
              scanning: scanningBle,
              batteryPercent: hasBrakeLightNearby ? 82 : 64,
              onRefresh: _refreshHome,
              onOpenProducts: () => _open(const DevicesScreen()),
            ),

            const SizedBox(height: 14),

            _HomeMiniStatsRow(
              weeklyKm: weeklyKmFromTrips(trips),
              weeklyGoalKm: weeklyGoalKm,
            ),

            const SizedBox(height: 190),
          ],
        ),
      ),
    );
  }
}

class _ProductFocusCard extends StatelessWidget {
  final bool hasBrakeLight;
  final bool scanning;
  final int batteryPercent;
  final VoidCallback onRefresh;
  final VoidCallback onOpenProducts;

  const _ProductFocusCard({
    required this.hasBrakeLight,
    required this.scanning,
    required this.batteryPercent,
    required this.onRefresh,
    required this.onOpenProducts,
  });

  @override
  Widget build(BuildContext context) {
    final battery = batteryPercent.clamp(0, 100);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.82),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: hasBrakeLight
              ? MunjaColors.mint.withOpacity(0.30)
              : Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: hasBrakeLight
                ? MunjaColors.mint.withOpacity(0.16)
                : Colors.black.withOpacity(0.28),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                color: MunjaColors.mint,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                hasBrakeLight ? 'Dit produkt' : 'Produkt klar',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: scanning ? null : onRefresh,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: scanning
                      ? const Padding(
                          padding: EdgeInsets.all(7),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.refresh_rounded,
                          color: Colors.white54,
                          size: 22,
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasBrakeLight ? 'Smart Brake Light' : 'Smart Brake Light',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      hasBrakeLight
                          ? 'Forbundet • $battery%'
                          : scanning
                          ? 'Scanner efter hardware...'
                          : 'Ingen hardware fundet lige nu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasBrakeLight
                            ? MunjaColors.mint
                            : MunjaColors.textSoft,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: onOpenProducts,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.045),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.12),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Se detaljer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white70,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 14),

              Container(
                width: 112,
                height: 132,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.02),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MunjaColors.mint.withOpacity(0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 84,
                      height: 104,
                      decoration: BoxDecoration(
                        color: const Color(0xFF101816),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 32,
                      child: Container(
                        width: 70,
                        height: 16,
                        decoration: BoxDecoration(
                          color: hasBrakeLight
                              ? Colors.redAccent
                              : Colors.redAccent.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.redAccent.withOpacity(0.45),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 28,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.84),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              Column(
                children: [
                  _ProductInfoPill(
                    icon: Icons.battery_5_bar_rounded,
                    label: 'Batteri',
                    value: '$battery%',
                  ),
                  const SizedBox(height: 8),
                  const _ProductInfoPill(
                    icon: Icons.wb_sunny_rounded,
                    label: 'Tilstand',
                    value: 'Smart',
                  ),
                  const SizedBox(height: 8),
                  const _ProductInfoPill(
                    icon: Icons.check_circle_outline_rounded,
                    label: 'Status',
                    value: 'Optimal',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProductInfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProductInfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 94,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.045),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
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

class _HomeMiniStatsRow extends StatelessWidget {
  final double weeklyKm;
  final double weeklyGoalKm;

  const _HomeMiniStatsRow({required this.weeklyKm, required this.weeklyGoalKm});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _HomeMiniStatCard(
            icon: Icons.route_rounded,
            label: 'Denne uge',
            value: '${weeklyKm.toStringAsFixed(1)} km',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _HomeMiniStatCard(
            icon: Icons.flag_rounded,
            label: 'Ugentligt mål',
            value: '${weeklyGoalKm.toStringAsFixed(0)} km',
          ),
        ),
      ],
    );
  }
}

class _HomeMiniStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HomeMiniStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 118,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 24),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class AutoRideScreen extends StatefulWidget {
  const AutoRideScreen({super.key});

  @override
  State<AutoRideScreen> createState() => _AutoRideScreenState();
}

class _AutoRideScreenState extends State<AutoRideScreen> {
  final RideControllerService _rideController = RideControllerService.instance;
  final LiveRideBus _rideBus = LiveRideBus.instance;

  GoogleMapController? mapCtrl;

  bool mapsLocationOk = false;
  bool centeringToCurrentLocation = false;

  LatLng? currentCenter;
  List<Trip> trips = [];

  final Set<Factory<OneSequenceGestureRecognizer>> _mapGestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _initLocationAndCenter();
  }

  Future<void> _loadTrips() async {
    final loaded = await StorageService.loadTrips();
    if (!mounted) return;
    setState(() => trips = loaded);
  }

  Future<void> _refreshMapsLocationOk() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      var perm = await Geolocator.checkPermission();

      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      final ok =
          enabled &&
          (perm == LocationPermission.always ||
              perm == LocationPermission.whileInUse);

      if (!mounted) return;
      setState(() => mapsLocationOk = ok);
    } catch (_) {
      if (!mounted) return;
      setState(() => mapsLocationOk = false);
    }
  }

  Future<void> _initLocationAndCenter() async {
    await _refreshMapsLocationOk();
    if (!mapsLocationOk) return;
    await _moveToCurrentLocation(zoom: 17.5, animated: false);
  }

  Future<void> _moveToCurrentLocation({
    double zoom = 17.5,
    bool animated = true,
  }) async {
    if (centeringToCurrentLocation) return;

    setState(() => centeringToCurrentLocation = true);

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );

      final target = LatLng(pos.latitude, pos.longitude);
      currentCenter = target;

      final update = CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      );

      if (animated) {
        await mapCtrl?.animateCamera(update);
      } else {
        await mapCtrl?.moveCamera(update);
      }

      if (mounted) setState(() {});
    } catch (_) {}

    if (mounted) {
      setState(() => centeringToCurrentLocation = false);
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
      path: state.path.map((e) => [e.latitude, e.longitude]).toList(),
    );
  }

  Future<void> _toggleRide() async {
    if (_rideController.isRideActive.value) {
      munjaRideActiveNotifier.value = false;

      final trip = await BackgroundRideEngine.instance.stop();

      await _loadTrips();

      if (!mounted) return;

      if (trip != null) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => RideSummaryScreen(trip: trip)),
        );
      }

      return;
    }

    munjaRideActiveNotifier.value = true;
    await BackgroundRideEngine.instance.start();
  }

  LatLng _centerForState(LiveRideState state) {
    if (state.path.isNotEmpty) return state.path.last;
    if (currentCenter != null) return currentCenter!;
    return fallbackCenter;
  }

  Set<Marker> _markersForState(LiveRideState state) {
    final markers = <Marker>{};

    if (state.path.isNotEmpty) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_position'),
          position: state.path.last,
          infoWindow: InfoWindow(title: AppText.t('yourPosition')),
        ),
      );

      markers.add(
        Marker(
          markerId: const MarkerId('ride_start'),
          position: state.path.first,
          infoWindow: InfoWindow(title: AppText.t('start')),
        ),
      );
    } else if (currentCenter != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_position'),
          position: currentCenter!,
          infoWindow: InfoWindow(title: AppText.t('yourPosition')),
        ),
      );
    }

    return markers;
  }

  Set<Polyline> _polylinesForState(LiveRideState state) {
    final path = List<LatLng>.from(state.path);

    if (path.length < 2) return {};

    return {
      Polyline(
        polylineId: const PolylineId('live_ride_route'),
        points: path,
        width: 7,
        color: MunjaColors.mint,
      ),
    };
  }

  Future<void> _zoomIn() async {
    await mapCtrl?.animateCamera(CameraUpdate.zoomIn());
  }

  Future<void> _zoomOut() async {
    await mapCtrl?.animateCamera(CameraUpdate.zoomOut());
  }

  Future<void> _openCoach() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SmartRideCoachScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LiveRideState>(
      valueListenable: _rideBus.state,
      builder: (context, rideState, _) {
        final center = _centerForState(rideState);
        final rideHudData = _rideDataFromState(rideState);
        final isRiding = rideState.isActive;

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  gestureRecognizers: _mapGestureRecognizers,
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: 16.5,
                  ),
                  myLocationEnabled: mapsLocationOk,
                  myLocationButtonEnabled: false,
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                  buildingsEnabled: true,
                  indoorViewEnabled: true,
                  minMaxZoomPreference: const MinMaxZoomPreference(3, 21),
                  markers: _markersForState(rideState),
                  polylines: _polylinesForState(rideState),
                  onMapCreated: (controller) async {
                    mapCtrl = controller;

                    if (mapsLocationOk && currentCenter != null) {
                      await mapCtrl?.moveCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(target: currentCenter!, zoom: 16.5),
                        ),
                      );
                    }
                  },
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black.withOpacity(0.48),
                          Colors.black.withOpacity(0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.center,
                        colors: [
                          Colors.black.withOpacity(0.54),
                          Colors.black.withOpacity(0.12),
                          Colors.transparent,
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
                top: MediaQuery.of(context).padding.top + 12,
                left: 14,
                child: _RideGlassButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),

              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 14,
                child: Column(
                  children: [
                    _RideGlassButton(icon: Icons.add_rounded, onTap: _zoomIn),
                    const SizedBox(height: 10),
                    _RideGlassButton(
                      icon: Icons.remove_rounded,
                      onTap: _zoomOut,
                    ),
                  ],
                ),
              ),

              Positioned(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).padding.bottom + 16,
                child: _RideBottomDock(
                  isRiding: isRiding,
                  centering: centeringToCurrentLocation,
                  onStartStop: _toggleRide,
                  onCenterMap: mapsLocationOk
                      ? () => _moveToCurrentLocation(zoom: 17.5)
                      : null,
                  onOpenCoach: _openCoach,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RideBottomDock extends StatelessWidget {
  final bool isRiding;
  final bool centering;
  final VoidCallback onStartStop;
  final VoidCallback? onCenterMap;
  final VoidCallback onOpenCoach;

  const _RideBottomDock({
    required this.isRiding,
    required this.centering,
    required this.onStartStop,
    required this.onCenterMap,
    required this.onOpenCoach,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.36),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          _RideDockButton(
            icon: centering
                ? Icons.hourglass_top_rounded
                : Icons.my_location_rounded,
            label: 'Center',
            onTap: onCenterMap,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: onStartStop,
                icon: Icon(
                  isRiding
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded,
                ),
                label: Text(
                  isRiding ? 'Stop ride' : 'Start ride',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _RideDockButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Coach',
            onTap: onOpenCoach,
          ),
        ],
      ),
    );
  }
}

class _RideDockButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _RideDockButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.45,
        duration: const Duration(milliseconds: 180),
        child: Container(
          width: 58,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.055),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: MunjaColors.mint, size: 20),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 9,
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

class _RideGlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RideGlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.panel.withOpacity(0.84),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class TripMapScreen extends StatefulWidget {
  final Trip trip;

  const TripMapScreen({super.key, required this.trip});

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  GoogleMapController? mapCtrl;

  final Set<Factory<OneSequenceGestureRecognizer>> _mapGestureRecognizers = {
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
  };

  @override
  Widget build(BuildContext context) {
    final points = widget.trip.latLngPath;
    final start = points.isNotEmpty ? points.first : fallbackCenter;
    final end = points.isNotEmpty ? points.last : fallbackCenter;

    return AppShell(
      title: AppText.t('rideRoute'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title:
                      '${(widget.trip.distanceM / 1000).toStringAsFixed(2)} km',
                  subtitle:
                      '${formatTripDate(widget.trip.startedAtMs)} · ${formatDuration(widget.trip.duration)}',
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 460,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: GoogleMap(
                      gestureRecognizers: _mapGestureRecognizers,
                      initialCameraPosition: CameraPosition(
                        target: start,
                        zoom: 14,
                      ),
                      zoomGesturesEnabled: true,
                      scrollGesturesEnabled: true,
                      rotateGesturesEnabled: true,
                      tiltGesturesEnabled: true,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                      markers: {
                        Marker(
                          markerId: const MarkerId('trip_start'),
                          position: start,
                          infoWindow: InfoWindow(title: AppText.t('start')),
                        ),
                        Marker(
                          markerId: const MarkerId('trip_end'),
                          position: end,
                          infoWindow: InfoWindow(title: AppText.t('finish')),
                        ),
                      },
                      polylines: {
                        Polyline(
                          polylineId: const PolylineId('trip_route'),
                          points: points,
                          width: 6,
                        ),
                      },
                      onMapCreated: (controller) {
                        mapCtrl = controller;
                      },
                    ),
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

class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  DateTime? deadline;
  String plan = 'After work';
  bool accepted = false;
  double weeklyGoalKm = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(challengeDeadlineKey);
    if (!mounted) return;
    setState(() {
      deadline = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      plan = sp.getString(challengePlanKey) ?? 'After work';
      accepted = sp.getBool(challengeAcceptedKey) ?? false;
      weeklyGoalKm = sp.getDouble(weeklyGoalKmKey) ?? 20;
    });
  }

  Future<void> _save() async {
    await StorageService.saveChallenge(
      accepted: accepted,
      plan: plan,
      weeklyGoalKm: weeklyGoalKm,
      deadline: deadline,
    );
  }

  String _daysLeftText() {
    if (deadline == null) return AppText.t('setChallengeDate');
    final now = DateTime.now();
    final d = deadline!
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (d < 0) return AppText.t('deadlinePassed');
    if (d == 0) return AppText.t('itIsToday');
    return '$d ${AppText.t('daysLeft')}';
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final initial = deadline ?? now.add(const Duration(days: 30));
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
      initialDate: initial,
    );
    if (picked == null) return;
    setState(() => deadline = picked);
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: AppText.t('bikeChallenge'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title: AppText.t('yourChallenge'),
                  subtitle: AppText.t('yourChallengeSubtitle'),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MunjaColors.panelSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _daysLeftText(),
                    style: const TextStyle(
                      fontSize: 16,
                      color: MunjaColors.textSoft,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pickDeadline,
                        icon: const Icon(Icons.event_rounded),
                        label: Text(
                          deadline == null
                              ? AppText.t('setDate')
                              : AppText.t('changeDate'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          setState(() => accepted = !accepted);
                          await _save();
                        },
                        icon: Icon(
                          accepted
                              ? Icons.check_circle_rounded
                              : Icons.flag_rounded,
                        ),
                        label: Text(
                          accepted ? 'ACTIVE' : AppText.t('startChallenge'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title: AppText.t('planAndGoal'),
                  subtitle: AppText.t('planAndGoalSubtitle'),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: plan,
                  items: [
                    DropdownMenuItem(
                      value: 'Bike to work',
                      child: Text(AppText.t('bikeToWork')),
                    ),
                    DropdownMenuItem(
                      value: 'After work',
                      child: Text(AppText.t('afterWork')),
                    ),
                    DropdownMenuItem(
                      value: 'Weekend',
                      child: Text(AppText.t('weekend')),
                    ),
                    DropdownMenuItem(
                      value: 'Morning',
                      child: Text(AppText.t('morning')),
                    ),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => plan = v);
                    await _save();
                  },
                  decoration: InputDecoration(labelText: AppText.t('yourPlan')),
                ),
                const SizedBox(height: 16),
                Text(
                  '${AppText.t('weeklyGoal')}: ${weeklyGoalKm.toStringAsFixed(0)} km',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Slider(
                  min: 5,
                  max: 100,
                  divisions: 19,
                  value: weeklyGoalKm,
                  label: weeklyGoalKm.toStringAsFixed(0),
                  onChanged: (v) => setState(() => weeklyGoalKm = v),
                  onChangeEnd: (_) => _save(),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GuidesScreen()),
                    );
                  },
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(AppText.t('openGuide')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GuidesScreen extends StatelessWidget {
  const GuidesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: AppShell(
        title: AppText.t('challengeGuide'),
        child: Column(
          children: [
            TabBar(
              tabs: [
                Tab(text: AppText.t('start')),
                Tab(text: AppText.t('dailySteps')),
                Tab(text: AppText.t('mindset')),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _GuidePage(
                    title: AppText.t('startSetGoal'),
                    bullets: [
                      AppText.t('writeDownDate'),
                      AppText.t('chooseRideTime'),
                      AppText.t('makeStartEasy'),
                    ],
                  ),
                  _GuidePage(
                    title: AppText.t('dailySteps'),
                    bullets: [
                      AppText.t('findRoutineTime'),
                      AppText.t('takeShortRide'),
                      AppText.t('repeatHabit'),
                    ],
                  ),
                  _GuidePage(
                    title: AppText.t('mindset'),
                    bullets: [
                      AppText.t('focusProgress'),
                      AppText.t('holdSmallWins'),
                      AppText.t('importantAction'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  final String title;
  final List<String> bullets;

  _GuidePage({required this.title, required this.bullets});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        MunjaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              ...bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: TextStyle(color: MunjaColors.mint)),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(
                            color: MunjaColors.textSoft,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  bool loading = true;
  List<MunjaDevice> nearby = [];
  List<MunjaDevice> saved = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final savedDevices = await StorageService.loadSavedDevices();
    final nearbyDevices = await BleService.scanNearbyMunjaDevices(
      saved: savedDevices,
    );
    if (!mounted) return;
    setState(() {
      saved = savedDevices;
      nearby = nearbyDevices;
      loading = false;
    });
  }

  Future<void> _removeSaved(String id) async {
    final sp = await SharedPreferences.getInstance();
    final current = await StorageService.loadSavedDevices();
    current.removeWhere((e) => e.id == id);
    await sp.setString(
      savedDevicesKey,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
    _load();
  }

  Future<void> _saveNearby(MunjaDevice d) async {
    await StorageService.saveDevice(d);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${d.name} saved to My products')));
    _load();
  }

  Widget _deviceTile(MunjaDevice d, {required bool isSavedList}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MunjaColors.panelSoft,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isSavedList ? Icons.devices_rounded : Icons.bluetooth_rounded,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSavedList
                        ? d.id
                        : '${BleService.proximityLabel(d.rssi)} · RSSI ${d.rssi}',
                    style: const TextStyle(color: MunjaColors.textSoft),
                  ),
                ],
              ),
            ),
            if (isSavedList)
              IconButton(
                onPressed: () => _removeSaved(d.id),
                icon: const Icon(Icons.delete_outline_rounded),
              )
            else
              FilledButton(
                onPressed: d.isSaved ? null : () => _saveNearby(d),
                child: Text(d.isSaved ? AppText.t('saved') : AppText.t('save')),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: AppText.t('myProducts'),
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                MunjaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        title: AppText.t('nearby'),
                        subtitle: AppText.t('scanProductsSubtitle'),
                      ),
                      const SizedBox(height: 14),
                      if (nearby.isEmpty)
                        Text(
                          AppText.t('noProductsNearby'),
                          style: TextStyle(color: MunjaColors.textSoft),
                        )
                      else
                        ...nearby.map(
                          (d) => _deviceTile(d, isSavedList: false),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MunjaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionTitle(
                        title: AppText.t('savedProducts'),
                        subtitle: AppText.t('savedProductsSubtitle'),
                      ),
                      const SizedBox(height: 14),
                      if (saved.isEmpty)
                        Text(
                          AppText.t('noSavedProducts'),
                          style: TextStyle(color: MunjaColors.textSoft),
                        )
                      else
                        ...saved.map((d) => _deviceTile(d, isSavedList: true)),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class BrakeLightScreen extends StatefulWidget {
  const BrakeLightScreen({super.key});

  @override
  State<BrakeLightScreen> createState() => _BrakeLightScreenState();
}

class _BrakeLightScreenState extends State<BrakeLightScreen> {
  BluetoothDevice? device;
  BluetoothCharacteristic? statusChar;
  BluetoothCharacteristic? configChar;
  StreamSubscription<List<int>>? notifySub;
  StreamSubscription<BluetoothConnectionState>? connSub;

  bool connected = false;
  bool connecting = false;
  String connectStatus = '—';
  bool brakeActive = false;
  int pwm = 0;
  double bs = 0.0;
  double sensitivity = 1.8;

  @override
  void initState() {
    super.initState();
    _loadSensitivity();
    _connectSmart();
  }

  @override
  void dispose() {
    notifySub?.cancel();
    connSub?.cancel();
    device?.disconnect();
    super.dispose();
  }

  Future<void> _loadSensitivity() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getDouble(sensitivityKey);
    if (v != null && mounted) setState(() => sensitivity = v);
  }

  Future<void> _writeSensitivity(double value) async {
    if (configChar != null) {
      try {
        await configChar!.write(utf8.encode(value.toStringAsFixed(2)));
      } catch (_) {}
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setDouble(sensitivityKey, value);
  }

  Future<void> _connectSmart() async {
    final permOk = await BleService.ensureBlePermissions();
    if (!permOk) {
      if (!mounted) return;
      setState(() => connectStatus = AppText.t('bluetoothPermissionMissing'));
      return;
    }

    setState(() {
      connecting = true;
      connectStatus = AppText.t('tryingToConnect');
    });

    final sp = await SharedPreferences.getInstance();
    final id = sp.getString(lastDeviceKey);
    if (id == null) {
      if (!mounted) return;
      setState(() {
        connecting = false;
        connectStatus = AppText.t('noSavedDeviceYet');
      });
      return;
    }

    try {
      device = BluetoothDevice.fromId(id);
      await device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 7),
      );
      final services = await device!.discoverServices();

      for (final s in services) {
        if (s.uuid.toString() == serviceUuid) {
          for (final c in s.characteristics) {
            if (c.uuid.toString() == statusCharUuid) statusChar = c;
            if (c.uuid.toString() == configCharUuid) configChar = c;
          }
        }
      }

      if (statusChar != null) {
        await statusChar!.setNotifyValue(true);
        notifySub = statusChar!.lastValueStream.listen((value) {
          final raw = utf8.decode(value, allowMalformed: true);
          final s = MunjaStatus.tryParse(raw);
          if (s == null || !mounted) return;
          setState(() {
            brakeActive = s.brake;
            pwm = s.pwm ?? pwm;
            bs = s.bs ?? bs;
          });
        });
      }

      connSub = device!.connectionState.listen((state) {
        if (!mounted) return;
        setState(() {
          connected = state == BluetoothConnectionState.connected;
          connecting = false;
          connectStatus = connected
              ? AppText.t('connected')
              : AppText.t('disconnected');
        });
      });

      if (!mounted) return;
      setState(() {
        connected = true;
        connecting = false;
        connectStatus = AppText.t('connected');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connected = false;
        connecting = false;
        connectStatus = AppText.t('couldNotConnect');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: AppText.t('smartBrakeLight'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (connected
                                ? MunjaColors.success
                                : connecting
                                ? MunjaColors.warning
                                : MunjaColors.danger)
                            .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    connected
                        ? 'CONNECTED'
                        : (connecting
                              ? AppText.t('connecting')
                              : AppText.t('notConnected')),
                    style: TextStyle(
                      color: connected
                          ? MunjaColors.success
                          : (connecting
                                ? MunjaColors.warning
                                : MunjaColors.danger),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  brakeActive ? 'BRAKING' : 'RIDING',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: brakeActive
                        ? MunjaColors.danger
                        : MunjaColors.success,
                  ),
                ),
                const SizedBox(height: 10),
                Text('PWM: $pwm · BS: ${bs.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                Text(
                  connectStatus,
                  style: const TextStyle(color: MunjaColors.textSoft),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: connecting ? null : _connectSmart,
                  icon: const Icon(Icons.bluetooth_connected_rounded),
                  label: Text(AppText.t('connectNow')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  title: AppText.t('brakeLightSensitivity'),
                  subtitle: AppText.t('sensitivityHint'),
                ),
                const SizedBox(height: 16),
                Slider(
                  min: 0.5,
                  max: 5.0,
                  divisions: 45,
                  value: sensitivity,
                  label: sensitivity.toStringAsFixed(2),
                  onChanged: (v) => setState(() => sensitivity = v),
                  onChangeEnd: connected ? (v) => _writeSensitivity(v) : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    sensitivity.toStringAsFixed(2),
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
