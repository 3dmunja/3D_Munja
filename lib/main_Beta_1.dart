import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const String appTitle = 'Munja';
const String munjaWebsite = 'https://3dmunja.dk';
const String bicycleWheelAsset = 'assets/Bicycle_Tires_1.png';
const String brakeLightAsset = 'assets/brake_light.jpeg';

const String deviceName = 'MunjaBrakeLight-01';
const String serviceUuid = '6b6b0001-8e2f-4b3a-9c8a-111111111111';
const String statusCharUuid = '6b6b0002-8e2f-4b3a-9c8a-222222222222';
const String configCharUuid = '6b6b0003-8e2f-4b3a-9c8a-333333333333';

const String lastDeviceKey = 'last_ble_device';
const String savedDevicesKey = 'saved_ble_devices_v1';
const String tripsKey = 'trips_v3';
const String challengeAcceptedKey = 'challenge_accepted';
const String challengePlanKey = 'challenge_plan';
const String challengeDeadlineKey = 'challenge_deadline_ms';
const String weeklyGoalKmKey = 'weekly_goal_km_v1';
const String sensitivityKey = 'sensitivity';
const String userNameKey = 'profile_name_v1';
const String userAgeKey = 'profile_age_v1';
const String userCityKey = 'profile_city_v1';
const String userAvatarKey = 'profile_avatar_v1';
const String onboardingDoneKey = 'onboarding_done_v1';

const LatLng fallbackCenter = LatLng(55.6761, 12.5683);

enum MunjaProductType { brakeLight, unknown }
enum TripSource { software, hardware }

class MunjaDevice {
  final String id;
  final String name;
  final MunjaProductType type;
  final int rssi;
  final bool isNearby;
  final bool isSaved;

  const MunjaDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.rssi,
    required this.isNearby,
    required this.isSaved,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
      };

  factory MunjaDevice.fromJson(Map<String, dynamic> json) {
    return MunjaDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] == 'brakeLight'
          ? MunjaProductType.brakeLight
          : MunjaProductType.unknown,
      rssi: -100,
      isNearby: false,
      isSaved: true,
    );
  }
}

class Trip {
  final int startedAtMs;
  final int endedAtMs;
  final double distanceM;
  final int brakes;
  final int hardBrakes;
  final List<List<double>> path;
  final String source;

  const Trip({
    required this.startedAtMs,
    required this.endedAtMs,
    required this.distanceM,
    required this.brakes,
    required this.hardBrakes,
    required this.path,
    required this.source,
  });

  TripSource get tripSource =>
      source == 'hardware' ? TripSource.hardware : TripSource.software;

  Map<String, dynamic> toJson() => {
        'startedAtMs': startedAtMs,
        'endedAtMs': endedAtMs,
        'distanceM': distanceM,
        'brakes': brakes,
        'hardBrakes': hardBrakes,
        'path': path,
        'source': source,
      };

  factory Trip.fromJson(Map<String, dynamic> json) {
    return Trip(
      startedAtMs: json['startedAtMs'] as int,
      endedAtMs: json['endedAtMs'] as int,
      distanceM: (json['distanceM'] as num).toDouble(),
      brakes: (json['brakes'] as int?) ?? 0,
      hardBrakes: (json['hardBrakes'] as int?) ?? 0,
      path: (json['path'] as List? ?? const [])
          .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
          .where((e) => e.length >= 2)
          .map((e) => <double>[e[0], e[1]])
          .toList(),
      source: (json['source'] as String?) ?? 'software',
    );
  }
}

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

class UserProfile {
  final String name;
  final int age;
  final String city;
  final int avatarIndex;

  const UserProfile({
    required this.name,
    required this.age,
    required this.city,
    required this.avatarIndex,
  });

  String get firstLine {
    final hasName = name.trim().isNotEmpty;
    final hasAge = age > 0;
    if (hasName && hasAge) return '$name · $age år';
    if (hasName) return name;
    if (hasAge) return '$age år';
    return 'Rytter';
  }

  String get secondLine {
    if (city.trim().isNotEmpty) return city;
    return 'Klar til næste tur';
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

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MunjaApp());
}

class MunjaColors {
  static const bg = Color(0xFF04110F);
  static const panel = Color(0xFF0B1916);
  static const panelSoft = Color(0xFF10221E);
  static const line = Color(0x1FFFFFFF);
  static const mint = Color(0xFF93E0C1);
  static const mintStrong = Color(0xFF67D7A7);
  static const textSoft = Color(0xB3FFFFFF);
  static const danger = Color(0xFFFF6B6B);
  static const success = Color(0xFF6BE39B);
  static const warning = Color(0xFFFFC857);
  static const blueGlow = Color(0xFF7AC7FF);
}

class MunjaApp extends StatelessWidget {
  const MunjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appTitle,
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
      home: const AppEntryScreen(),
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    onboardingDone = sp.getBool(onboardingDoneKey) ?? false;
    if (!mounted) return;
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return onboardingDone ? const HomeScreen() : const OnboardingScreen();
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

class MunjaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const MunjaCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.045),
            Colors.white.withOpacity(0.015),
          ],
        ),
        color: MunjaColors.panel,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: const TextStyle(color: MunjaColors.textSoft, height: 1.4),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MunjaColors.panelSoft,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor ?? MunjaColors.mint),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(color: MunjaColors.textSoft)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  const MenuTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MunjaColors.panelSoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.14),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: MunjaColors.mint),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: MunjaColors.textSoft)),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class HeroBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const HeroBadge({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class AvatarMiniCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;

  const AvatarMiniCard({super.key, required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatar = avatarById(profile.avatarIndex);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MunjaColors.panelSoft,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [MunjaColors.mintStrong, MunjaColors.blueGlow],
                ),
              ),
              child: Text(
                avatar.emoji,
                style: const TextStyle(fontSize: 28),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.firstLine,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.secondLine} · ${avatar.label}',
                    style: const TextStyle(color: MunjaColors.textSoft),
                  ),
                ],
              ),
            ),
            const Icon(Icons.tune_rounded),
          ],
        ),
      ),
    );
  }
}

Future<void> openMunjaWebsite() async {
  final uri = Uri.parse(munjaWebsite);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String proximityLabel(int rssi) {
  if (rssi >= -55) return 'Meget tæt på';
  if (rssi >= -70) return 'I nærheden';
  return 'Længere væk';
}

bool isMunjaDeviceName(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('munja') ||
      lower.contains('brakelight') ||
      lower == deviceName.toLowerCase();
}

MunjaProductType detectProductType(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('brake')) return MunjaProductType.brakeLight;
  return MunjaProductType.unknown;
}

Future<List<Trip>> loadTripsShared() async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(tripsKey);
  if (raw == null) return [];

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => Trip.fromJson(e.cast<String, dynamic>()))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveTripsShared(List<Trip> trips) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString(
    tripsKey,
    jsonEncode(trips.map((e) => e.toJson()).toList()),
  );
}

Future<List<MunjaDevice>> loadSavedDevicesShared() async {
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getString(savedDevicesKey);
  if (raw == null) return [];

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => MunjaDevice.fromJson(e.cast<String, dynamic>()))
        .toList();
  } catch (_) {
    return [];
  }
}

Future<void> saveDeviceShared(MunjaDevice device) async {
  final sp = await SharedPreferences.getInstance();
  final current = await loadSavedDevicesShared();
  final index = current.indexWhere((d) => d.id == device.id);
  if (index >= 0) {
    current[index] = device;
  } else {
    current.add(device);
  }

  await sp.setString(
    savedDevicesKey,
    jsonEncode(current.map((e) => e.toJson()).toList()),
  );
  await sp.setString(lastDeviceKey, device.id);
}

Future<UserProfile> loadUserProfileShared() async {
  final sp = await SharedPreferences.getInstance();
  return UserProfile(
    name: sp.getString(userNameKey) ?? 'Rytter',
    age: sp.getInt(userAgeKey) ?? 24,
    city: sp.getString(userCityKey) ?? 'København',
    avatarIndex: sp.getInt(userAvatarKey) ?? 0,
  );
}

Future<void> saveUserProfileShared(UserProfile profile) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString(userNameKey, profile.name.trim());
  await sp.setInt(userAgeKey, profile.age);
  await sp.setString(userCityKey, profile.city.trim());
  await sp.setInt(userAvatarKey, profile.avatarIndex);
}

Future<bool> ensureBlePermissions() async {
  final scan = await Permission.bluetoothScan.request();
  final connect = await Permission.bluetoothConnect.request();
  final loc = await Permission.locationWhenInUse.request();
  return scan.isGranted && connect.isGranted && loc.isGranted;
}

Future<List<MunjaDevice>> scanNearbyMunjaDevices({
  Duration timeout = const Duration(seconds: 4),
  List<MunjaDevice> saved = const [],
}) async {
  final ok = await ensureBlePermissions();
  if (!ok) return [];

  try {
    await FlutterBluePlus.stopScan();
  } catch (_) {}

  final found = <String, MunjaDevice>{};
  final completer = Completer<List<MunjaDevice>>();
  StreamSubscription<List<ScanResult>>? sub;

  try {
    await FlutterBluePlus.startScan(timeout: timeout);
  } catch (_) {
    return [];
  }

  sub = FlutterBluePlus.scanResults.listen((results) {
    for (final r in results) {
      final name = r.device.advName.trim();
      if (name.isEmpty || !isMunjaDeviceName(name)) continue;
      final savedMatch = saved.any((d) => d.id == r.device.remoteId.str);
      found[r.device.remoteId.str] = MunjaDevice(
        id: r.device.remoteId.str,
        name: name,
        type: detectProductType(name),
        rssi: r.rssi,
        isNearby: true,
        isSaved: savedMatch,
      );
    }
  });

  Future.delayed(timeout + const Duration(milliseconds: 700), () async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await sub?.cancel();
    if (!completer.isCompleted) {
      completer.complete(
        found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)),
      );
    }
  });

  return completer.future;
}

double weeklyKmFromTrips(List<Trip> trips) {
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final startOfWeek = DateTime(monday.year, monday.month, monday.day);
  return trips.where((t) {
    final d = DateTime.fromMillisecondsSinceEpoch(t.startedAtMs);
    return !d.isBefore(startOfWeek);
  }).fold(0.0, (sum, t) => sum + (t.distanceM / 1000));
}

int streakFromTrips(List<Trip> trips) {
  if (trips.isEmpty) return 0;

  final rideDays = trips
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

String greetingFromHour() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Godmorgen';
  if (hour < 18) return 'Goddag';
  return 'Godaften';
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
    final km = monthTrips.fold<double>(0.0, (sum, t) => sum + t.distanceM / 1000);
    return MonthlyStats(
      label: '${monthStart.month.toString().padLeft(2, '0')}/${monthStart.year.toString().substring(2)}',
      km: km,
      co2Kg: km * 0.12,
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
                  style: const TextStyle(fontSize: 12, color: MunjaColors.textSoft),
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
                  style: const TextStyle(fontSize: 12, color: MunjaColors.textSoft),
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
  final cityCtrl = TextEditingController(text: 'København');
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
    await saveUserProfileShared(
      UserProfile(
        name: nameCtrl.text.trim().isEmpty ? 'Rytter' : nameCtrl.text.trim(),
        age: age,
        city: cityCtrl.text.trim().isEmpty ? 'København' : cityCtrl.text.trim(),
        avatarIndex: selectedAvatar,
      ),
    );
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(onboardingDoneKey, true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Velkommen',
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
                        children: const [
                          HeroBadge(
                            icon: Icons.waving_hand_rounded,
                            text: 'Velkommen til Munja',
                            color: MunjaColors.mint,
                          ),
                          SizedBox(height: 18),
                          Text(
                            'Sådan bruger du appen',
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 12),
                          Text(
                            '''1. Brug Auto Ride til automatisk tracking.
2. Brug Challenge til mål og vane.
3. Brug Hardware hvis du har Smart Brake Light.
4. Se din grønne effekt og månedlige udvikling på forsiden.''',
                            style: TextStyle(color: MunjaColors.textSoft, height: 1.55),
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
                          const SectionTitle(
                            title: 'Vælg din avatar mode',
                            subtitle: 'Gør appen mere personlig før du går i gang.',
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: avatarOptions.map((avatar) {
                              final selected = selectedAvatar == avatar.id;
                              return GestureDetector(
                                onTap: () => setState(() => selectedAvatar = avatar.id),
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
                                      Text(avatar.emoji, style: const TextStyle(fontSize: 28)),
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
                          const SectionTitle(
                            title: 'Settings før start',
                            subtitle: 'Udfyld dine oplysninger før du går ind i appen.',
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Navn',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: ageCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Alder',
                              prefixIcon: Icon(Icons.cake_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: cityCtrl,
                            decoration: const InputDecoration(
                              labelText: 'By',
                              prefixIcon: Icon(Icons.location_city_rounded),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _finish,
                              icon: const Icon(Icons.rocket_launch_rounded),
                              label: const Text('Start appen'),
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
                    child: const Text('Tilbage'),
                  ),
                const SizedBox(width: 8),
                if (page < 2)
                  FilledButton(
                    onPressed: () => pageCtrl.nextPage(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: const Text('Næste'),
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

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wheelCtrl;

  List<MunjaDevice> nearbyDevices = [];
  List<MunjaDevice> savedDevices = [];
  List<Trip> trips = [];
  UserProfile profile =
      const UserProfile(name: 'Rytter', age: 24, city: 'København', avatarIndex: 0);

  bool loading = true;
  bool challengeAccepted = false;
  double weeklyGoalKm = 20;

  bool get hasBrakeLightNearby =>
      nearbyDevices.any((d) => d.type == MunjaProductType.brakeLight);

  @override
  void initState() {
    super.initState();
    _wheelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _load();
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final loadedTrips = await loadTripsShared();
    final loadedSaved = await loadSavedDevicesShared();
    final loadedProfile = await loadUserProfileShared();
    final nearby = await scanNearbyMunjaDevices(saved: loadedSaved);

    if (!mounted) return;
    setState(() {
      trips = loadedTrips;
      savedDevices = loadedSaved;
      nearbyDevices = nearby;
      profile = loadedProfile;
      challengeAccepted = sp.getBool(challengeAcceptedKey) ?? false;
      weeklyGoalKm = sp.getDouble(weeklyGoalKmKey) ?? 20;
      loading = false;
    });
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final weeklyKm = weeklyKmFromTrips(trips);
    final streak = streakFromTrips(trips);
    final progress = weeklyGoalKm <= 0
        ? 0.0
        : (weeklyKm / weeklyGoalKm).clamp(0.0, 1.0);
    final co2SavedKg = weeklyKm * 0.12;
    final carKmAvoided = weeklyKm;
    final monthly = buildMonthlyStats(trips);
    final totalCo2SixMonths = monthly.fold<double>(0, (sum, e) => sum + e.co2Kg);
    final totalKmSixMonths = monthly.fold<double>(0, (sum, e) => sum + e.km);

    return AppShell(
      title: appTitle,
      actions: [
        IconButton(
          onPressed: openMunjaWebsite,
          icon: const Icon(Icons.public_rounded),
        ),
      ],
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  MunjaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            const HeroBadge(
                              icon: Icons.auto_graph_rounded,
                              text: 'Software first',
                              color: MunjaColors.mint,
                            ),
                            HeroBadge(
                              icon: hasBrakeLightNearby
                                  ? Icons.bluetooth_connected_rounded
                                  : Icons.bluetooth_disabled_rounded,
                              text: hasBrakeLightNearby ? 'Hardware fundet' : 'Kun app-mode',
                              color: hasBrakeLightNearby
                                  ? MunjaColors.success
                                  : MunjaColors.warning,
                            ),
                            const HeroBadge(
                              icon: Icons.eco_rounded,
                              text: 'Grønnere transport',
                              color: MunjaColors.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${greetingFromHour()}, ${profile.name.isEmpty ? 'Rytter' : profile.name}',
                                    style: const TextStyle(
                                      color: MunjaColors.mint,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Cykeltracking med mere personlighed og bedre flow',
                                    style: TextStyle(
                                      fontSize: 28,
                                      height: 1.05,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    challengeAccepted
                                        ? '🔥 $streak dages streak · ${weeklyKm.toStringAsFixed(1)}/${weeklyGoalKm.toStringAsFixed(0)} km denne uge'
                                        : 'Din app starter med tracking, kort og historik. Nu uden genveje på forsiden.',
                                    style: const TextStyle(
                                      color: MunjaColors.textSoft,
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(28),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    MunjaColors.mint.withOpacity(0.18),
                                    MunjaColors.blueGlow.withOpacity(0.10),
                                  ],
                                ),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                              ),
                              child: AnimatedBuilder(
                                animation: _wheelCtrl,
                                builder: (_, child) => Transform.rotate(
                                  angle: _wheelCtrl.value * 2 * math.pi,
                                  child: child,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Image.asset(
                                    bicycleWheelAsset,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) =>
                                        const Icon(Icons.tire_repair_rounded),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ugemål ${weeklyGoalKm.toStringAsFixed(0)} km',
                          style: const TextStyle(color: MunjaColors.textSoft),
                        ),
                        const SizedBox(height: 16),
                        AvatarMiniCard(
                          profile: profile,
                          onTap: () => _open(const ProfileScreen()),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _open(const AutoRideScreen()),
                                icon: const Icon(Icons.directions_bike_rounded),
                                label: const Text('Åbn Auto Ride'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _open(const ChallengeScreen()),
                                icon: const Icon(Icons.flag_rounded),
                                label: const Text('Challenge'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      StatPill(
                        icon: Icons.local_fire_department_rounded,
                        iconColor: Colors.orange,
                        label: 'Streak',
                        value: '$streak dage',
                      ),
                      const SizedBox(width: 10),
                      StatPill(
                        icon: Icons.route_rounded,
                        label: 'Denne uge',
                        value: '${weeklyKm.toStringAsFixed(1)} km',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  MunjaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          title: 'Din grønne effekt',
                          subtitle: 'Når du vælger cyklen i stedet for bilen, sparer du både CO₂ og unødige bilture.',
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            StatPill(
                              icon: Icons.eco_rounded,
                              iconColor: MunjaColors.success,
                              label: 'Sparet CO₂',
                              value: '${co2SavedKg.toStringAsFixed(2)} kg',
                            ),
                            const SizedBox(width: 10),
                            StatPill(
                              icon: Icons.directions_car_filled_rounded,
                              iconColor: MunjaColors.warning,
                              label: 'Bil-km undgået',
                              value: '${carKmAvoided.toStringAsFixed(1)} km',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MunjaColors.panelSoft,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: Text(
                            weeklyKm > 0
                                ? 'Du har allerede gjort en forskel denne uge. Hver cykeltur hjælper med at reducere trafik, brændstofforbrug og CO₂-udledning.'
                                : 'Start din første tur og se hvor meget CO₂ du kan spare ved at vælge cyklen frem for bilen.',
                            style: const TextStyle(
                              color: MunjaColors.textSoft,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  MunjaCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(
                          title: 'Månedlig oversigt',
                          subtitle: 'Se din udvikling måned for måned med kilometer og grønnere transport.',
                        ),
                        const SizedBox(height: 14),
                        buildMiniBarChart(monthly),
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MunjaColors.panelSoft,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Samlet 6 mdr.',
                                      style: TextStyle(color: MunjaColors.textSoft),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${totalKmSixMonths.toStringAsFixed(1)} km',
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Samlet CO₂ sparet',
                                      style: TextStyle(color: MunjaColors.textSoft),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${totalCo2SixMonths.toStringAsFixed(2)} kg',
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
                          title: 'Hardware',
                          subtitle: hasBrakeLightNearby
                              ? 'Din Smart Brake Light er fundet i nærheden.'
                              : 'Ingen hardware fundet lige nu. Software-delen virker stadig alene.',
                          trailing: TextButton(
                            onPressed: () => _open(const DevicesScreen()),
                            child: const Text('Alle produkter'),
                          ),
                        ),
                        const SizedBox(height: 14),
                        MenuTile(
                          icon: hasBrakeLightNearby
                              ? Icons.light_mode_rounded
                              : Icons.bluetooth_searching_rounded,
                          title: hasBrakeLightNearby ? 'Smart Brake Light' : 'Mine produkter',
                          subtitle: hasBrakeLightNearby
                              ? 'Åbn status, følsomhed og forbindelsesinfo'
                              : 'Scan, gem og administrér dine Munja-enheder',
                          onTap: () => _open(
                            hasBrakeLightNearby
                                ? const BrakeLightScreen()
                                : const DevicesScreen(),
                          ),
                          trailing: hasBrakeLightNearby
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: Image.asset(
                                      brakeLightAsset,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(Icons.light_mode_rounded),
                                    ),
                                  ),
                                )
                              : const Icon(Icons.chevron_right_rounded),
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

class AutoRideScreen extends StatefulWidget {
  const AutoRideScreen({super.key});

  @override
  State<AutoRideScreen> createState() => _AutoRideScreenState();
}

class _AutoRideScreenState extends State<AutoRideScreen> {
  StreamSubscription<Position>? gpsSub;
  GoogleMapController? mapCtrl;

  bool monitoring = false;
  bool tripActive = false;
  bool mapsLocationOk = false;
  bool centeringToCurrentLocation = false;

  DateTime? tripStart;
  Position? lastPos;
  Position? currentPos;
  double tripDistanceM = 0;
  final List<LatLng> tripPath = [];
  List<Trip> trips = [];

  int movingSamples = 0;
  int lowSpeedSamples = 0;
  DateTime? lastMovementAt;
  double currentSpeedKmh = 0;

  static const double autoStartKmh = 6.0;
  static const double autoStopKmh = 2.0;
  static const int startSamplesNeeded = 3;
  static const int stopSamplesNeeded = 8;

  @override
  void initState() {
    super.initState();
    _loadTrips();
    _initLocationAndCenter();
  }

  @override
  void dispose() {
    gpsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTrips() async {
    final loaded = await loadTripsShared();
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
      final ok = enabled &&
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
      currentPos = pos;
      final target = LatLng(pos.latitude, pos.longitude);
      if (animated) {
        await mapCtrl?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: zoom),
          ),
        );
      } else {
        await mapCtrl?.moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: target, zoom: zoom),
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (_) {}
    if (mounted) setState(() => centeringToCurrentLocation = false);
  }

  Future<void> _toggleMonitoring() async {
    if (monitoring) {
      await gpsSub?.cancel();
      gpsSub = null;
      if (tripActive) await _stopTrip(autoStopped: false);
      if (!mounted) return;
      setState(() {
        monitoring = false;
        currentSpeedKmh = 0;
      });
      return;
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    movingSamples = 0;
    lowSpeedSamples = 0;
    lastMovementAt = null;
    lastPos = null;

    await _moveToCurrentLocation();

    gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen(_onPosition);

    if (!mounted) return;
    setState(() => monitoring = true);
    _refreshMapsLocationOk();
  }

  void _onPosition(Position pos) async {
    currentPos = pos;
    final speedMps = pos.speed >= 0 ? pos.speed : 0.0;
    final speedKmh = speedMps * 3.6;
    if (mounted) setState(() => currentSpeedKmh = speedKmh);

    if (speedKmh >= autoStartKmh) {
      movingSamples++;
      lowSpeedSamples = 0;
      lastMovementAt = DateTime.now();
    } else if (speedKmh <= autoStopKmh) {
      lowSpeedSamples++;
    }

    if (!tripActive && movingSamples >= startSamplesNeeded) {
      await _startTripFromPosition(pos);
    }

    if (tripActive) {
      if (lastPos != null) {
        tripDistanceM += Geolocator.distanceBetween(
          lastPos!.latitude,
          lastPos!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }

      lastPos = pos;
      final ll = LatLng(pos.latitude, pos.longitude);
      tripPath.add(ll);

      try {
        await mapCtrl?.animateCamera(CameraUpdate.newLatLng(ll));
      } catch (_) {}

      if (mounted) setState(() {});

      final autoStopBySamples = lowSpeedSamples >= stopSamplesNeeded;
      final autoStopByTime = lastMovementAt != null &&
          DateTime.now().difference(lastMovementAt!).inMinutes >= 2;

      if (autoStopBySamples || autoStopByTime) {
        await _stopTrip(autoStopped: true);
        movingSamples = 0;
        lowSpeedSamples = 0;
      }
    } else {
      lastPos = pos;
      if (mounted) setState(() {});
    }
  }

  Future<void> _startTripFromPosition(Position first) async {
    if (!mounted) return;
    setState(() {
      tripActive = true;
      tripStart = DateTime.now();
      tripDistanceM = 0;
      tripPath
        ..clear()
        ..add(LatLng(first.latitude, first.longitude));
      lastPos = first;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🚴 Tur startet automatisk')),
    );
  }

  Future<void> _stopTrip({required bool autoStopped}) async {
    final start = tripStart;
    if (start == null) return;

    final allTrips = await loadTripsShared();
    final trip = Trip(
      startedAtMs: start.millisecondsSinceEpoch,
      endedAtMs: DateTime.now().millisecondsSinceEpoch,
      distanceM: tripDistanceM,
      brakes: 0,
      hardBrakes: 0,
      path: tripPath.map((p) => <double>[p.latitude, p.longitude]).toList(),
      source: 'software',
    );

    allTrips.insert(0, trip);
    await saveTripsShared(allTrips);

    if (!mounted) return;
    final km = (trip.distanceM / 1000).toStringAsFixed(2);

    setState(() {
      tripActive = false;
      tripStart = null;
      tripDistanceM = 0;
      tripPath.clear();
      lastPos = null;
      trips = allTrips;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          autoStopped ? '✅ Tur gemt automatisk · $km km' : '✅ Tur stoppet · $km km',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLng center = tripPath.isNotEmpty
        ? tripPath.last
        : currentPos != null
            ? LatLng(currentPos!.latitude, currentPos!.longitude)
            : fallbackCenter;

    return AppShell(
      title: 'Auto Ride',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  title: 'Software-only tracking',
                  subtitle:
                      'Auto Ride centrerer nu på din aktuelle placering ved start og kortet kan zoomes frit.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    StatPill(
                      icon: monitoring
                          ? Icons.radar_rounded
                          : Icons.pause_circle_outline_rounded,
                      label: 'Overvågning',
                      value: monitoring ? 'AKTIV' : 'SLUKKET',
                    ),
                    const SizedBox(width: 10),
                    StatPill(
                      icon: tripActive
                          ? Icons.play_circle_fill_rounded
                          : Icons.not_started_rounded,
                      label: 'Tur',
                      value: tripActive ? 'I GANG' : 'IKKE STARTET',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatPill(
                      icon: Icons.speed_rounded,
                      label: 'Fart',
                      value: '${currentSpeedKmh.toStringAsFixed(1)} km/t',
                    ),
                    const SizedBox(width: 10),
                    StatPill(
                      icon: Icons.route_rounded,
                      label: 'Distance',
                      value: '${(tripDistanceM / 1000).toStringAsFixed(2)} km',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _toggleMonitoring,
                        icon: Icon(
                          monitoring ? Icons.stop_circle_outlined : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          monitoring ? 'Stop overvågning' : 'Start auto mode',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: tripActive
                            ? () => _stopTrip(autoStopped: false)
                            : null,
                        icon: const Icon(Icons.flag_rounded),
                        label: const Text('Stop tur'),
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
                Row(
                  children: [
                    const Expanded(
                      child: SectionTitle(
                        title: 'Kort',
                        subtitle:
                            'Kortet bruger standard gestures. Brug to fingre til zoom og knappen til at hoppe til din position.',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Min position',
                      onPressed: mapsLocationOk ? _moveToCurrentLocation : null,
                      icon: const Icon(Icons.my_location_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  height: 420,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: CameraPosition(target: center, zoom: 16),
                        myLocationEnabled: mapsLocationOk,
                        myLocationButtonEnabled: false,
                        zoomGesturesEnabled: true,
                        scrollGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        zoomControlsEnabled: false,
                        compassEnabled: true,
                        mapToolbarEnabled: false,
                        buildingsEnabled: true,
                        indoorViewEnabled: true,
                        minMaxZoomPreference: const MinMaxZoomPreference(3, 21),
                        markers: currentPos == null
                            ? {}
                            : {
                                Marker(
                                  markerId: const MarkerId('current_position'),
                                  position: LatLng(currentPos!.latitude, currentPos!.longitude),
                                  infoWindow: const InfoWindow(title: 'Din position'),
                                ),
                              },
                        polylines: {
                          Polyline(
                            polylineId: const PolylineId('software_trip'),
                            points: List<LatLng>.from(tripPath),
                            width: 6,
                          ),
                        },
                        onMapCreated: (controller) async {
                          mapCtrl = controller;
                          if (mapsLocationOk) {
                            await _moveToCurrentLocation(animated: false);
                          }
                        },
                      ),
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'zoom_in_btn',
                              onPressed: () => mapCtrl?.animateCamera(CameraUpdate.zoomIn()),
                              child: const Icon(Icons.add),
                            ),
                            const SizedBox(height: 10),
                            FloatingActionButton.small(
                              heroTag: 'zoom_out_btn',
                              onPressed: () => mapCtrl?.animateCamera(CameraUpdate.zoomOut()),
                              child: const Icon(Icons.remove),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  title: 'Seneste ture',
                  subtitle: 'De nyeste software-ture gemmes automatisk.',
                ),
                const SizedBox(height: 14),
                if (trips.isEmpty)
                  const Text(
                    'Ingen ture gemt endnu.',
                    style: TextStyle(color: MunjaColors.textSoft),
                  )
                else
                  ...trips.take(5).map(
                    (trip) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: MunjaColors.panelSoft,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: MunjaColors.mint.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.directions_bike_rounded),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${(trip.distanceM / 1000).toStringAsFixed(2)} km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatTripDate(trip.startedAtMs),
                                    style: const TextStyle(color: MunjaColors.textSoft),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              trip.source,
                              style: const TextStyle(color: MunjaColors.textSoft),
                            ),
                          ],
                        ),
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
  String plan = 'Efter arbejde';
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
      plan = sp.getString(challengePlanKey) ?? 'Efter arbejde';
      accepted = sp.getBool(challengeAcceptedKey) ?? false;
      weeklyGoalKm = sp.getDouble(weeklyGoalKmKey) ?? 20;
    });
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(challengeAcceptedKey, accepted);
    await sp.setString(challengePlanKey, plan);
    await sp.setDouble(weeklyGoalKmKey, weeklyGoalKm);
    if (deadline == null) {
      await sp.remove(challengeDeadlineKey);
    } else {
      await sp.setInt(challengeDeadlineKey, deadline!.millisecondsSinceEpoch);
    }
  }

  String _daysLeftText() {
    if (deadline == null) return 'Sæt en dato for din udfordring.';
    final now = DateTime.now();
    final d = deadline!
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (d < 0) return 'Deadline er passeret – sæt en ny dato 💪';
    if (d == 0) return 'Det er i dag! 🚴';
    return '$d dage tilbage';
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
      title: 'Bicycle Challenge',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  title: 'Din udfordring',
                  subtitle: 'Sæt en deadline og gør cykling til en fast vane.',
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
                    style: const TextStyle(fontSize: 16, color: MunjaColors.textSoft),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pickDeadline,
                        icon: const Icon(Icons.event_rounded),
                        label: Text(deadline == null ? 'Sæt dato' : 'Skift dato'),
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
                          accepted ? Icons.check_circle_rounded : Icons.flag_rounded,
                        ),
                        label: Text(accepted ? 'AKTIV' : 'Start udfordring'),
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
                const SectionTitle(
                  title: 'Plan og mål',
                  subtitle: 'Vælg hvornår du typisk vil cykle og justér ugemålet.',
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: plan,
                  items: const [
                    DropdownMenuItem(
                      value: 'Cykle til arbejde',
                      child: Text('Cykle til arbejde'),
                    ),
                    DropdownMenuItem(
                      value: 'Efter arbejde',
                      child: Text('Efter arbejde'),
                    ),
                    DropdownMenuItem(value: 'Weekend', child: Text('Weekend')),
                    DropdownMenuItem(value: 'Morgen', child: Text('Morgen')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => plan = v);
                    await _save();
                  },
                  decoration: const InputDecoration(labelText: 'Din plan'),
                ),
                const SizedBox(height: 16),
                Text(
                  'Ugemål: ${weeklyGoalKm.toStringAsFixed(0)} km',
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
                  label: const Text('Åbn guide'),
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
        title: 'Challenge Guide',
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(text: 'Start'),
                Tab(text: 'Daglige steps'),
                Tab(text: 'Mindset'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _GuidePage(
                    title: 'Start – sæt dit mål',
                    bullets: [
                      'Skriv en dato ned.',
                      'Vælg hvornår i hverdagen du vil cykle.',
                      'Gør starten så nem som muligt.',
                    ],
                  ),
                  _GuidePage(
                    title: 'Daglige steps',
                    bullets: [
                      'Find 10–20 min i din rutine.',
                      'Sig til dig selv: jeg tager bare en kort tur i dag.',
                      'Gentag, så bliver det til en vane.',
                    ],
                  ),
                  _GuidePage(
                    title: 'Mindset',
                    bullets: [
                      'Fokuser på fremskridt, ikke perfektion.',
                      'Hold fast i små wins.',
                      'Det vigtigste er at tage handling.',
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

  const _GuidePage({required this.title, required this.bullets});

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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              ...bullets.map(
                (b) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  ', style: TextStyle(color: MunjaColors.mint)),
                      Expanded(
                        child: Text(
                          b,
                          style: const TextStyle(color: MunjaColors.textSoft, height: 1.4),
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

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final nameCtrl = TextEditingController();
  final ageCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  int selectedAvatar = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await loadUserProfileShared();
    nameCtrl.text = profile.name;
    ageCtrl.text = profile.age > 0 ? '${profile.age}' : '';
    cityCtrl.text = profile.city;
    selectedAvatar = profile.avatarIndex;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final age = int.tryParse(ageCtrl.text.trim()) ?? 0;
    final profile = UserProfile(
      name: nameCtrl.text.trim().isEmpty ? 'Rytter' : nameCtrl.text.trim(),
      age: age,
      city: cityCtrl.text.trim().isEmpty ? 'København' : cityCtrl.text.trim(),
      avatarIndex: selectedAvatar,
    );
    await saveUserProfileShared(profile);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Avatar og profil gemt')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Avatar & settings',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  title: 'Din rider-identitet',
                  subtitle: 'Vælg avatar mode og opdater dine oplysninger.',
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: avatarOptions.map((avatar) {
                    final selected = selectedAvatar == avatar.id;
                    return GestureDetector(
                      onTap: () => setState(() => selectedAvatar = avatar.id),
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
                            Text(avatar.emoji, style: const TextStyle(fontSize: 28)),
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
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Navn',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ageCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Alder',
                    prefixIcon: Icon(Icons.cake_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'By',
                    prefixIcon: Icon(Icons.location_city_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Gem avatar & profil'),
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
    final savedDevices = await loadSavedDevicesShared();
    final nearbyDevices = await scanNearbyMunjaDevices(saved: savedDevices);
    if (!mounted) return;
    setState(() {
      saved = savedDevices;
      nearby = nearbyDevices;
      loading = false;
    });
  }

  Future<void> _removeSaved(String id) async {
    final sp = await SharedPreferences.getInstance();
    final current = await loadSavedDevicesShared();
    current.removeWhere((e) => e.id == id);
    await sp.setString(
      savedDevicesKey,
      jsonEncode(current.map((e) => e.toJson()).toList()),
    );
    _load();
  }

  Future<void> _saveNearby(MunjaDevice d) async {
    await saveDeviceShared(d);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${d.name} gemt i Mine produkter')),
    );
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
              child: Icon(isSavedList ? Icons.devices_rounded : Icons.bluetooth_rounded),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSavedList ? d.id : '${proximityLabel(d.rssi)} · RSSI ${d.rssi}',
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
                child: Text(d.isSaved ? 'Gemt' : 'Gem'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Mine produkter',
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
                      const SectionTitle(
                        title: 'I nærheden',
                        subtitle: 'Scan efter Munja-produkter i nærheden.',
                      ),
                      const SizedBox(height: 14),
                      if (nearby.isEmpty)
                        const Text(
                          'Ingen produkter fundet i nærheden.',
                          style: TextStyle(color: MunjaColors.textSoft),
                        )
                      else
                        ...nearby.map((d) => _deviceTile(d, isSavedList: false)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                MunjaCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(
                        title: 'Gemte produkter',
                        subtitle: 'Enheder du tidligere har gemt.',
                      ),
                      const SizedBox(height: 14),
                      if (saved.isEmpty)
                        const Text(
                          'Ingen gemte produkter endnu.',
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
    final permOk = await ensureBlePermissions();
    if (!permOk) {
      if (!mounted) return;
      setState(() => connectStatus = 'Mangler Bluetooth/Location tilladelse');
      return;
    }

    setState(() {
      connecting = true;
      connectStatus = 'Prøver at forbinde…';
    });

    final sp = await SharedPreferences.getInstance();
    final id = sp.getString(lastDeviceKey);
    if (id == null) {
      if (!mounted) return;
      setState(() {
        connecting = false;
        connectStatus = 'Ingen gemt enhed endnu';
      });
      return;
    }

    try {
      device = BluetoothDevice.fromId(id);
      await device!.connect(autoConnect: false, timeout: const Duration(seconds: 7));
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
          connectStatus = connected ? 'Forbundet' : 'Afbrudt';
        });
      });

      if (!mounted) return;
      setState(() {
        connected = true;
        connecting = false;
        connectStatus = 'Forbundet';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        connected = false;
        connecting = false;
        connectStatus = 'Kunne ikke forbinde';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Smart Brake Light',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          MunjaCard(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: (connected
                                ? MunjaColors.success
                                : connecting
                                    ? MunjaColors.warning
                                    : MunjaColors.danger)
                            .withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    connected ? 'FORBINDET' : (connecting ? 'FORBINDER…' : 'IKKE FORBINDET'),
                    style: TextStyle(
                      color: connected
                          ? MunjaColors.success
                          : (connecting ? MunjaColors.warning : MunjaColors.danger),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  brakeActive ? 'BREMSER' : 'KØRER',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: brakeActive ? MunjaColors.danger : MunjaColors.success,
                  ),
                ),
                const SizedBox(height: 10),
                Text('PWM: $pwm · BS: ${bs.toStringAsFixed(2)}'),
                const SizedBox(height: 6),
                Text(connectStatus, style: const TextStyle(color: MunjaColors.textSoft)),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: connecting ? null : _connectSmart,
                  icon: const Icon(Icons.bluetooth_connected_rounded),
                  label: const Text('Forbind nu'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MunjaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  title: 'Bremselys-følsomhed',
                  subtitle: 'Lav = reagerer hurtigt · Høj = kræver hårdere opbremsning',
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
