import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

/// ================= BLE KONSTANTER =================
const String deviceName = "MunjaBrakeLight-01";
const String serviceUuid = "6b6b0001-8e2f-4b3a-9c8a-111111111111";
const String statusCharUuid = "6b6b0002-8e2f-4b3a-9c8a-222222222222";
const String configCharUuid = "6b6b0003-8e2f-4b3a-9c8a-333333333333";

const String lastDeviceKey = "last_ble_device";
const String sensitivityKey = "sensitivity";
const String brakeEventsKey = "brake_events";
const String tripsKey = "trips_v1";

/// ================= ASSETS =================
/// pubspec.yaml (assets):
///  - assets/brake_light.jpeg
///  - assets/Bicycle_Tires_1.png
const String brakeLightAsset = "assets/brake_light.jpeg";
const String bicycleWheelAsset = "assets/Bicycle_Tires_1.png";

/// ================= WEBSITE =================
const String munjaWebsite = "https://3dmunja.dk";

Future<void> openMunjaWebsite() async {
  final uri = Uri.parse(munjaWebsite);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok) throw "Kunne ikke åbne $munjaWebsite";
}

void main() => runApp(const MunjaApp());

class MunjaApp extends StatelessWidget {
  const MunjaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Munja',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E0A4),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

/// ================= FORSIDE (NYT DESIGN) =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wheelCtrl;

  @override
  void initState() {
    super.initState();
    _wheelCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    super.dispose();
  }

  Widget _heroCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Bicycle Challenge",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Kom i gang i dag",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "Små skridt hver dag → stærkere vane → mere energi. 💪🚴",
                      style: TextStyle(color: Colors.white70, height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 86,
                height: 86,
                child: AnimatedBuilder(
                  animation: _wheelCtrl,
                  builder: (_, child) => Transform.rotate(
                    angle: _wheelCtrl.value * 2 * math.pi,
                    child: child,
                  ),
                  child: Image.asset(
                    bicycleWheelAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported, size: 32),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.flag),
              label: const Text("Åbn Challenge Guide"),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GuidesScreen(initialTab: 0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Munja"),
        actions: [
          IconButton(
            tooltip: "Åbn 3dmunja.dk",
            icon: const Icon(Icons.public),
            onPressed: () async {
              try {
                await openMunjaWebsite();
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Kunne ikke åbne hjemmesiden.")),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard(context),
          const SizedBox(height: 18),
          const Text(
            "Mine gadgets",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _GadgetTile(
                title: "Smart Brake Light",
                subtitle: "Status • Kort • Historik",
                imageAsset: brakeLightAsset,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DeviceScreen()),
                ),
              ),
              _GadgetTile(
                title: "Bicycle Challenge",
                subtitle: "Motivation & steps",
                icon: Icons.flag,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChallengeScreen()),
                ),
              ),
              _GadgetTile(
                title: "Gadget #2",
                subtitle: "Kommer snart",
                icon: Icons.widgets,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Gadget #2 (kommer snart)")),
                  );
                },
              ),
              _GadgetTile(
                title: "Tilføj gadget",
                subtitle: "Opret ny",
                icon: Icons.add_circle,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GadgetTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? imageAsset;
  final IconData? icon;
  final VoidCallback onTap;

  const _GadgetTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageAsset,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: (imageAsset != null)
                    ? Image.asset(
                        imageAsset!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        errorBuilder: (_, __, ___) => Container(
                          alignment: Alignment.center,
                          color: const Color(0xFF111111),
                          child:
                              const Icon(Icons.image_not_supported, size: 42),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        alignment: Alignment.center,
                        color: const Color(0xFF111111),
                        child: Icon(icon ?? Icons.device_unknown, size: 42),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

/// ================= GUIDES SIDE (NYT INDHOLD FRA PDF) =================
class GuidesScreen extends StatelessWidget {
  final int initialTab;
  const GuidesScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Challenge Guide"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "Start"),
              Tab(text: "Daglige steps"),
              Tab(text: "Mindset"),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _GuidePage(
              title: "Start – sæt dit mål",
              subtitle:
                  "Du er ét skridt tættere på at nå dit mål. Nu gør vi det simpelt.",
              bullets: [
                "Skriv en dato ned for hvornår du har gennemført udfordringen.",
                "Vælg din plan: cykle til arbejde, efter arbejde eller i weekenden.",
                "Vælg en cykel (budget er op til dig – mindset er vigtigst).",
                "Gør cyklen unik (fx en 3D-printet detalje med dit navn).",
              ],
              callout:
                  "Når du tvivler: kig på datoen du skrev ned. Det er dit bevis på, at det er ægte.",
            ),
            _GuidePage(
              title: "Daglige steps – gør det let",
              subtitle: "Små handlinger hver dag gør det muligt.",
              bullets: [
                "Find 10–20 min i din rutine (se hvor der er plads).",
                "Lav en mini-aftale med dig selv: 'i dag cykler jeg bare lidt'.",
                "Hold det så nemt, at du ikke kan sige nej.",
                "Gentag → vane. Efter noget tid føles det naturligt.",
                "Hvis du misser en dag: ingen drama — fortsæt næste dag.",
              ],
              callout:
                  "Du skal ikke være perfekt. Du skal være konsistent.",
            ),
            _GuidePage(
              title: "Mindset – hold fokus",
              subtitle:
                  "Målet er simpelt: bliv komfortabel med det, der føles ukomfortabelt.",
              bullets: [
                "Spørg dig selv: 'Hvorfor gør jeg dette på denne måde?'",
                "Skift mønstre ved at forstå dit 'hvorfor' og 'hvordan'.",
                "Fokuser på fremskridt i små trin – det giver motivation med det samme.",
                "Systemet virker for alle, der tager handling og holder fast.",
                "Brug udfordringen som start på et sundere liv – ét skridt ad gangen.",
              ],
              callout:
                  "Den eneste fejl du kan begå, er ikke at tage handling.",
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidePage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<String> bullets;
  final String? callout;

  const _GuidePage({
    required this.title,
    required this.bullets,
    this.subtitle,
    this.callout,
  });

  Widget _calloutCard(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF101010),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E0A4).withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
          Text(subtitle!, style: const TextStyle(color: Colors.white70)),
        ],
        const SizedBox(height: 14),
        ...bullets.map(
          (b) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("•  "),
                Expanded(child: Text(b)),
              ],
            ),
          ),
        ),
        if (callout != null) ...[
          const SizedBox(height: 8),
          _calloutCard(callout!),
        ],
      ],
    );
  }
}

/// ================= CHALLENGE =================
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  static const _kDeadlineMs = "challenge_deadline_ms";
  static const _kPlan = "challenge_plan";
  static const _kAccepted = "challenge_accepted";

  DateTime? deadline;
  String plan = "Efter arbejde";
  bool accepted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final ms = sp.getInt(_kDeadlineMs);
    final p = sp.getString(_kPlan);
    final a = sp.getBool(_kAccepted);

    if (!mounted) return;
    setState(() {
      deadline = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
      if (p != null) plan = p;
      accepted = a ?? false;
    });
  }

  Future<void> _save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kAccepted, accepted);
    await sp.setString(_kPlan, plan);
    if (deadline != null) {
      await sp.setInt(_kDeadlineMs, deadline!.millisecondsSinceEpoch);
    } else {
      await sp.remove(_kDeadlineMs);
    }
  }

  String _daysLeftText() {
    if (deadline == null) return "Sæt en dato for din udfordring.";
    final now = DateTime.now();
    final d = deadline!.difference(DateTime(now.year, now.month, now.day)).inDays;
    if (d < 0) return "Deadline er passeret – sæt en ny dato 💪";
    if (d == 0) return "Det er i dag! 🚴";
    return "$d dage tilbage";
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
      initialDate: deadline ??
          DateTime(now.year, now.month, now.day).add(const Duration(days: 30)),
    );
    if (picked == null) return;
    setState(() => deadline = picked);
    await _save();
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Bicycle Challenge"),
        actions: [
          IconButton(
            tooltip: "Åbn 3dmunja.dk",
            icon: const Icon(Icons.public),
            onPressed: () async {
              try {
                await openMunjaWebsite();
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Kunne ikke åbne hjemmesiden.")),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Din udfordring",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_daysLeftText(),
                    style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _pickDeadline,
                        child: Text(deadline == null ? "Sæt dato" : "Skift dato"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          setState(() => accepted = !accepted);
                          await _save();
                        },
                        child: Text(
                            accepted ? "Udfordring: AKTIV" : "Start udfordring"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("1) Planlæg dit tidspunkt",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: plan,
                  items: const [
                    DropdownMenuItem(
                        value: "Cykle til arbejde",
                        child: Text("Cykle til arbejde")),
                    DropdownMenuItem(
                        value: "Efter arbejde", child: Text("Efter arbejde")),
                    DropdownMenuItem(value: "Weekend", child: Text("Weekend")),
                    DropdownMenuItem(value: "Morgen", child: Text("Morgen")),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => plan = v);
                    await _save();
                  },
                  decoration: const InputDecoration(
                    labelText: "Din plan",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                const Text("Små handlinger hver dag gør det muligt. 🚴",
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.menu_book),
                    label: const Text("Åbn Challenge Guide"),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const GuidesScreen(initialTab: 0),
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

/// ================= MODEL: TRIP =================
class Trip {
  final int startedAtMs;
  final int endedAtMs;
  final double distanceM;
  final int brakes;
  final int hardBrakes;
  final List<List<double>> path;

  Trip({
    required this.startedAtMs,
    required this.endedAtMs,
    required this.distanceM,
    required this.brakes,
    required this.hardBrakes,
    required this.path,
  });

  Map<String, dynamic> toJson() => {
        "startedAtMs": startedAtMs,
        "endedAtMs": endedAtMs,
        "distanceM": distanceM,
        "brakes": brakes,
        "hardBrakes": hardBrakes,
        "path": path,
      };

  static Trip fromJson(Map<String, dynamic> j) => Trip(
        startedAtMs: j["startedAtMs"] as int,
        endedAtMs: j["endedAtMs"] as int,
        distanceM: (j["distanceM"] as num).toDouble(),
        brakes: j["brakes"] as int,
        hardBrakes: (j["hardBrakes"] as int?) ?? 0,
        path: (j["path"] as List)
            .map((e) => (e as List).map((v) => (v as num).toDouble()).toList())
            .map((e) => <double>[e[0], e[1]])
            .toList(),
      );
}

/// ================= DEVICE SCREEN =================
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  // ===== BLE =====
  BluetoothDevice? device;
  BluetoothCharacteristic? statusChar;
  BluetoothCharacteristic? configChar;

  StreamSubscription<List<int>>? notifySub;
  StreamSubscription<BluetoothConnectionState>? connSub;

  bool connected = false;
  bool connecting = false;
  String connectStatus = "—";

  // manual scan list
  final List<ScanResult> _found = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _scanTimer;

  // status fra ESP32
  bool brakeActive = false;
  int pwm = 0;
  double bs = 0.0;

  // sensitivity
  double sensitivity = 1.8;

  // stats
  bool _lastBrake = false;
  final List<int> brakeEventsMs = [];

  // ===== GPS / TRIP =====
  int _tab = 0;

  bool tripActive = false;
  DateTime? tripStart;
  double tripDistanceM = 0.0;
  int tripBrakes = 0;
  int tripHardBrakes = 0;

  Position? _lastPos;
  StreamSubscription<Position>? gpsSub;

  final List<LatLng> _tripPath = <LatLng>[];
  GoogleMapController? _mapCtrl;

  bool _mapsLocationOk = false;
  final List<Trip> trips = [];

  static const double presetEco = 2.6;
  static const double presetNormal = 1.8;
  static const double presetSport = 1.2;

  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _setupInProgress = false;
  bool _connectFlowInProgress = false;

  int _reconnectAttempt = 0;

  void safeSetState(VoidCallback fn) {
    if (!mounted || _disposed) return;
    setState(fn);
  }

  Future<bool> _ensureBlePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final loc = await Permission.locationWhenInUse.request();
    return scan.isGranted && connect.isGranted && loc.isGranted;
  }

  Duration _nextBackoff() {
    final s = [2, 4, 8, 15];
    final idx = _reconnectAttempt.clamp(0, s.length - 1);
    return Duration(seconds: s[idx]);
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();

    final delay = _nextBackoff();
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 99);

    _reconnectTimer = Timer(delay, () {
      if (!mounted || _disposed) return;
      _connectSmart();
    });
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

      if (!mounted || _disposed) return;
      setState(() => _mapsLocationOk = ok);
    } catch (_) {
      if (!mounted || _disposed) return;
      setState(() => _mapsLocationOk = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStoredEvents();
    _loadSensitivity();
    _loadTrips();
    _connectSmart();
    _refreshMapsLocationOk();
  }

  Future<void> _connectSmart() async {
    if (_disposed) return;
    if (_connectFlowInProgress) return;
    _connectFlowInProgress = true;

    final permOk = await _ensureBlePermissions();
    if (!permOk) {
      safeSetState(() {
        connecting = false;
        connected = false;
        connectStatus = "Mangler Bluetooth/Location tilladelse";
      });
      _connectFlowInProgress = false;
      return;
    }

    if (connected && device != null) {
      _connectFlowInProgress = false;
      return;
    }

    safeSetState(() {
      connecting = true;
      connected = false;
      connectStatus = "Prøver at forbinde…";
    });

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    bool ok = await _tryDirectReconnect(timeout: const Duration(seconds: 7));
    if (_disposed) {
      _connectFlowInProgress = false;
      return;
    }

    if (!ok) {
      safeSetState(() => connectStatus = "Scanner…");
      ok = await _scanAndAutoConnect(timeout: const Duration(seconds: 10));
      if (_disposed) {
        _connectFlowInProgress = false;
        return;
      }
    }

    safeSetState(() {
      connecting = false;
      connected = ok;
      connectStatus = ok ? "Forbundet" : "Ikke forbundet";
    });

    if (ok) {
      _reconnectAttempt = 0;
      _reconnectTimer?.cancel();
    }

    _connectFlowInProgress = false;
  }

  Future<bool> _tryDirectReconnect(
      {Duration timeout = const Duration(seconds: 8)}) async {
    final sp = await SharedPreferences.getInstance();
    final id = sp.getString(lastDeviceKey);
    if (id == null || id.isEmpty) return false;

    try {
      device = BluetoothDevice.fromId(id);
      await device!.connect(autoConnect: false, timeout: timeout);
      await _setupServices();
      return connected;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _scanAndAutoConnect(
      {Duration timeout = const Duration(seconds: 8)}) async {
    _found.clear();
    safeSetState(() {});

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (_) {
      return false;
    }

    final completer = Completer<bool>();

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      if (_disposed) return;

      for (final r in results) {
        final idx =
            _found.indexWhere((e) => e.device.remoteId == r.device.remoteId);
        if (idx >= 0) {
          _found[idx] = r;
        } else {
          _found.add(r);
        }
      }
      safeSetState(() {});

      final match =
          _found.where((r) => r.device.advName == deviceName).toList();
      if (match.isNotEmpty) {
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        try {
          await _scanSub?.cancel();
        } catch (_) {}

        final ok = await _connectToDevice(match.first.device);
        if (!completer.isCompleted) completer.complete(ok);
      }
    }, onError: (_) {
      if (!completer.isCompleted) completer.complete(false);
    });

    _scanTimer?.cancel();
    _scanTimer = Timer(timeout + const Duration(seconds: 1), () async {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      try {
        await _scanSub?.cancel();
      } catch (_) {}
      if (!completer.isCompleted) completer.complete(false);
    });

    return completer.future;
  }

  Future<bool> _connectToDevice(BluetoothDevice d) async {
    safeSetState(() {
      connectStatus =
          "Forbinder til ${d.advName.isEmpty ? d.remoteId.str : d.advName}…";
    });

    try {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}

      device = d;

      await device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 12),
      );

      final sp = await SharedPreferences.getInstance();
      await sp.setString(lastDeviceKey, device!.remoteId.str);

      await _setupServices();
      return connected;
    } catch (_) {
      safeSetState(() {
        connected = false;
        connectStatus = "Forbindelse fejlede";
      });
      return false;
    }
  }

  Future<void> _setupServices() async {
    if (_setupInProgress) return;
    _setupInProgress = true;

    try {
      if (device == null) {
        safeSetState(() {
          connected = false;
          connectStatus = "Ingen enhed";
        });
        return;
      }

      final services = await device!.discoverServices();

      statusChar = null;
      configChar = null;

      for (final s in services) {
        if (s.uuid.toString() == serviceUuid) {
          for (final c in s.characteristics) {
            if (c.uuid.toString() == statusCharUuid) {
              statusChar = c;
            } else if (c.uuid.toString() == configCharUuid) {
              configChar = c;
            }
          }
        }
      }

      if (statusChar == null || configChar == null) {
        safeSetState(() {
          connected = false;
          connectStatus = "Service/characteristic ikke fundet";
        });
        return;
      }

      await notifySub?.cancel();
      await connSub?.cancel();

      try {
        await statusChar!.setNotifyValue(false);
      } catch (_) {}
      try {
        await statusChar!.setNotifyValue(true);
      } catch (_) {}

      notifySub = statusChar!.value.listen(_onBleNotify, onError: (_) {});

      connSub = device!.connectionState.listen((state) {
        if (_disposed) return;

        if (state == BluetoothConnectionState.connected) {
          safeSetState(() {
            connected = true;
            connecting = false;
            connectStatus = "Forbundet";
          });
          _reconnectAttempt = 0;
          _reconnectTimer?.cancel();
        }

        if (state == BluetoothConnectionState.disconnected) {
          safeSetState(() {
            connected = false;
            connecting = false;
            connectStatus = "Afbrudt – prøver igen…";
          });
          _scheduleReconnect();
        }
      }, onError: (_) {});

      safeSetState(() {
        connected = true;
        connecting = false;
        connectStatus = "Forbundet";
      });

      await _writeSensitivity(sensitivity);
    } catch (_) {
      safeSetState(() {
        connected = false;
        connecting = false;
        connectStatus = "Service-setup fejlede";
      });
      _scheduleReconnect();
    } finally {
      _setupInProgress = false;
    }
  }

  Future<void> _openConnectDialog() async {
    final permOk = await _ensureBlePermissions();
    if (!permOk) return;

    if (connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Du er allerede forbundet.")),
      );
      return;
    }

    _found.clear();
    safeSetState(() {});

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (_) {
      return;
    }

    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (_disposed) return;
      safeSetState(() {
        for (final r in results) {
          final name = r.device.advName;
          final ok = name.contains("Munja") ||
              name.contains("BrakeLight") ||
              name == deviceName;
          if (!ok) continue;

          final idx =
              _found.indexWhere((e) => e.device.remoteId == r.device.remoteId);
          if (idx >= 0) {
            _found[idx] = r;
          } else {
            _found.add(r);
          }
        }
        _found.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    }, onError: (_) {});

    if (!mounted || _disposed) return;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      "Vælg enhed",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      _found.clear();
                      safeSetState(() {});
                      try {
                        await FlutterBluePlus.stopScan();
                      } catch (_) {}
                      try {
                        await FlutterBluePlus.startScan(
                            timeout: const Duration(seconds: 10));
                      } catch (_) {}
                    },
                    child: const Text("Scan igen"),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _found.isEmpty
                    ? const Center(
                        child: Text("Scanner… (tænd ESP32 og hold den tæt på)"),
                      )
                    : ListView.separated(
                        itemCount: _found.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _found[i];
                          final name = r.device.advName.isEmpty
                              ? "Ukendt"
                              : r.device.advName;

                          return ListTile(
                            leading: Icon(
                              name == deviceName
                                  ? Icons.check_circle
                                  : Icons.bluetooth,
                              color: name == deviceName ? Colors.green : null,
                            ),
                            title: Text(name),
                            subtitle: Text(
                                "${r.device.remoteId.str}  •  RSSI ${r.rssi}"),
                            trailing: FilledButton(
                              onPressed: () async {
                                try {
                                  await FlutterBluePlus.stopScan();
                                } catch (_) {}

                                if (mounted) Navigator.pop(context);

                                safeSetState(() => connecting = true);
                                final ok = await _connectToDevice(r.device);
                                safeSetState(() {
                                  connecting = false;
                                  connected = ok;
                                  connectStatus =
                                      ok ? "Forbundet" : "Ikke forbundet";
                                });
                              },
                              child: const Text("Forbind"),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 8),
              Text(connectStatus,
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        );
      },
    ).whenComplete(() async {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
      try {
        await _scanSub?.cancel();
      } catch (_) {}
    });
  }

  void _onBleNotify(List<int> value) async {
    if (_disposed) return;

    MunjaStatus? s;
    try {
      final raw = utf8.decode(value, allowMalformed: true);
      s = MunjaStatus.tryParse(raw);
    } catch (_) {
      return;
    }
    if (s == null) return;

    safeSetState(() {
      brakeActive = s!.brake;
      pwm = s.pwm ?? pwm;
      bs = s.bs ?? bs;
    });

    if (!_lastBrake && s.brake) {
      brakeEventsMs.add(DateTime.now().millisecondsSinceEpoch);
      await _storeEvents();

      if (tripActive) {
        tripBrakes++;

        final isHard = (s.pwm ?? 0) >= 220;
        if (isHard) {
          tripHardBrakes++;
          if (mounted && !_disposed) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("⚠️ Hård bremsning registreret"),
                duration: Duration(milliseconds: 900),
              ),
            );
          }
        }
      }
    }
    _lastBrake = s.brake;
  }

  Future<void> _writeSensitivity(double value) async {
    if (configChar != null) {
      try {
        await configChar!.write(
          utf8.encode(value.toStringAsFixed(2)),
          withoutResponse: false,
        );
      } catch (_) {}
    }

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(sensitivityKey, value);
    } catch (_) {}
  }

  Future<void> _loadSensitivity() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getDouble(sensitivityKey);
      if (v != null) sensitivity = v;
      safeSetState(() {});
    } catch (_) {}
  }

  Future<void> _setPreset(double v) async {
    safeSetState(() => sensitivity = v);
    await _writeSensitivity(v);
  }

  Future<void> _startTrip() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted && !_disposed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Slå lokation til på telefonen.")),
        );
      }
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    safeSetState(() {
      tripActive = true;
      tripStart = DateTime.now();
      tripDistanceM = 0;
      tripBrakes = 0;
      tripHardBrakes = 0;
      _lastPos = null;
      _tripPath.clear();
    });

    try {
      final first = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPos = first;
      _tripPath.add(LatLng(first.latitude, first.longitude));
    } catch (_) {}

    await gpsSub?.cancel();
    gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((pos) {
      if (_disposed) return;

      if (_lastPos != null) {
        tripDistanceM += Geolocator.distanceBetween(
          _lastPos!.latitude,
          _lastPos!.longitude,
          pos.latitude,
          pos.longitude,
        );
      }
      _lastPos = pos;

      final ll = LatLng(pos.latitude, pos.longitude);
      _tripPath.add(ll);

      try {
        _mapCtrl?.animateCamera(CameraUpdate.newLatLng(ll));
      } catch (_) {}

      safeSetState(() {});
    }, onError: (_) {});

    safeSetState(() => _tab = 1);
    _refreshMapsLocationOk();
  }

  Future<void> _stopTrip() async {
    await gpsSub?.cancel();
    gpsSub = null;

    final start = tripStart;

    if (start != null) {
      final t = Trip(
        startedAtMs: start.millisecondsSinceEpoch,
        endedAtMs: DateTime.now().millisecondsSinceEpoch,
        distanceM: tripDistanceM,
        brakes: tripBrakes,
        hardBrakes: tripHardBrakes,
        path: _tripPath.map((p) => <double>[p.latitude, p.longitude]).toList(),
      );
      trips.insert(0, t);
      await _saveTrips();
    }

    safeSetState(() {
      tripActive = false;
      tripStart = null;
    });
  }

  Future<void> _loadStoredEvents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(brakeEventsKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      brakeEventsMs
        ..clear()
        ..addAll(decoded.whereType<num>().map((n) => n.toInt()));
      safeSetState(() {});
    } catch (_) {}
  }

  Future<void> _storeEvents() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(brakeEventsKey, jsonEncode(brakeEventsMs));
    } catch (_) {}
  }

  Future<void> _loadTrips() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(tripsKey);
      if (raw == null) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final loaded = decoded
          .whereType<Map>()
          .map((m) => Trip.fromJson(m.cast<String, dynamic>()))
          .toList();

      trips
        ..clear()
        ..addAll(loaded);

      safeSetState(() {});
    } catch (_) {}
  }

  Future<void> _saveTrips() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
        tripsKey,
        jsonEncode(trips.map((t) => t.toJson()).toList()),
      );
    } catch (_) {}
  }

  List<int> _brakesLast30Min() {
    final now = DateTime.now();
    final start = now.subtract(const Duration(minutes: 30));
    final bins = List<int>.filled(30, 0);

    for (final ms in brakeEventsMs) {
      final t = DateTime.fromMillisecondsSinceEpoch(ms);
      if (t.isBefore(start) || t.isAfter(now)) continue;
      final idx = 29 - now.difference(t).inMinutes;
      if (idx >= 0 && idx < 30) bins[idx]++;
    }
    return bins;
  }

  @override
  void dispose() {
    _disposed = true;

    _reconnectTimer?.cancel();
    _scanTimer?.cancel();

    notifySub?.cancel();
    connSub?.cancel();
    gpsSub?.cancel();
    _scanSub?.cancel();

    FlutterBluePlus.stopScan().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _dashboardPage(),
      _mapPage(),
      _historyPage(),
      _presetsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Munja Brake Light"),
        actions: [
          IconButton(
            tooltip: "Åbn 3dmunja.dk",
            icon: const Icon(Icons.public),
            onPressed: () async {
              try {
                await openMunjaWebsite();
              } catch (_) {}
            },
          ),
          IconButton(
            tooltip: "Forbind",
            onPressed: _openConnectDialog,
            icon: const Icon(Icons.bluetooth_searching),
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                "●",
                style: TextStyle(
                  color: connected
                      ? Colors.green
                      : (connecting ? Colors.orange : Colors.redAccent),
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          safeSetState(() => _tab = i);
          if (i == 1) _refreshMapsLocationOk();
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.speed), label: "Status"),
          NavigationDestination(icon: Icon(Icons.map), label: "Kort"),
          NavigationDestination(icon: Icon(Icons.history), label: "Historik"),
          NavigationDestination(icon: Icon(Icons.tune), label: "Presets"),
        ],
      ),
    );
  }

  Widget _dashboardPage() {
    final brakesToday = brakeEventsMs.where((ms) {
      final t = DateTime.fromMillisecondsSinceEpoch(ms);
      final n = DateTime.now();
      return t.year == n.year && t.month == n.month && t.day == n.day;
    }).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _statusCard(),
        const SizedBox(height: 12),
        _tripMiniCard(),
        const SizedBox(height: 12),
        _sensitivityCard(),
        const SizedBox(height: 12),
        _counterCard(brakesToday),
        const SizedBox(height: 12),
        _chartCard(),
      ],
    );
  }

  Widget _mapPage() {
    final hasPos = _tripPath.isNotEmpty;
    final center = hasPos ? _tripPath.last : const LatLng(55.6761, 12.5683);

    final polyline = Polyline(
      polylineId: const PolylineId("trip"),
      points: List<LatLng>.from(_tripPath),
      width: 6,
    );

    return Column(
      children: [
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: center, zoom: 16),
            myLocationEnabled: _mapsLocationOk,
            myLocationButtonEnabled: _mapsLocationOk,
            polylines: {polyline},
            onMapCreated: (c) => _mapCtrl = c,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tripActive ? "Tur kører" : "Ingen aktiv tur",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(
                          "Distance: ${(tripDistanceM / 1000).toStringAsFixed(2)} km"),
                      Text(
                          "Bremsninger: $tripBrakes (hård: $tripHardBrakes)"),
                      const SizedBox(height: 6),
                      Text(connectStatus,
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      if (!_mapsLocationOk)
                        const Text(
                          "Lokation er ikke aktiv/tilgængelig for kortet endnu.",
                          style: TextStyle(
                              color: Colors.orangeAccent, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: tripActive ? _stopTrip : _startTrip,
                child: Text(tripActive ? "Stop" : "Start"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _historyPage() {
    if (trips.isEmpty) {
      return const Center(
          child: Text("Ingen ture endnu. Start en tur under Kort."));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: trips.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final t = trips[i];
        final start = DateTime.fromMillisecondsSinceEpoch(t.startedAtMs);
        final end = DateTime.fromMillisecondsSinceEpoch(t.endedAtMs);
        final durMin = end.difference(start).inMinutes;
        final km = (t.distanceM / 1000).toStringAsFixed(2);

        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${start.day}/${start.month} "
                "${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')} "
                "• ${durMin} min",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text("Distance: $km km"),
              Text("Bremsninger: ${t.brakes} (hård: ${t.hardBrakes})"),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: () => _openTripOnMap(t),
                    child: const Text("Vis på kort"),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () async {
                      trips.removeAt(i);
                      await _saveTrips();
                      safeSetState(() {});
                    },
                    child: const Text("Slet"),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _openTripOnMap(Trip t) {
    _tripPath
      ..clear()
      ..addAll(t.path.map((p) => LatLng(p[0], p[1])));
    tripActive = false;
    tripDistanceM = t.distanceM;
    tripBrakes = t.brakes;
    tripHardBrakes = t.hardBrakes;
    tripStart = DateTime.fromMillisecondsSinceEpoch(t.startedAtMs);
    safeSetState(() => _tab = 1);
    _refreshMapsLocationOk();
  }

  Widget _presetsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Presets",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton(
                    onPressed: connected ? () => _setPreset(presetEco) : null,
                    child: Text("Eco (${presetEco.toStringAsFixed(2)})"),
                  ),
                  FilledButton(
                    onPressed:
                        connected ? () => _setPreset(presetNormal) : null,
                    child: Text("Normal (${presetNormal.toStringAsFixed(2)})"),
                  ),
                  FilledButton(
                    onPressed:
                        connected ? () => _setPreset(presetSport) : null,
                    child: Text("Sport (${presetSport.toStringAsFixed(2)})"),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text("Aktuel sensitivity: ${sensitivity.toStringAsFixed(2)}"),
              const SizedBox(height: 8),
              const Text(
                "Eco = kræver hårdere bremsning\nNormal = standard\nSport = reagerer hurtigt",
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              Text(connectStatus,
                  style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _sensitivityCard(),
      ],
    );
  }

  Widget _statusCard() => _card(
        child: Column(
          children: [
            Text(
              connected
                  ? "FORBINDET"
                  : (connecting ? "FORBINDER…" : "IKKE FORBINDET"),
              style: TextStyle(
                color: connected
                    ? Colors.green
                    : (connecting ? Colors.orange : Colors.redAccent),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              brakeActive ? "BREMSER" : "KØRER",
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: brakeActive ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            Text("PWM: $pwm  •  BS: ${bs.toStringAsFixed(2)}",
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 6),
            Text(connectStatus, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: connecting ? null : _connectSmart,
              child: const Text("Forbind nu"),
            ),
          ],
        ),
      );

  Widget _tripMiniCard() => _card(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tripActive ? "Tur kører" : "Ingen aktiv tur",
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(
                      "Distance: ${(tripDistanceM / 1000).toStringAsFixed(2)} km"),
                  Text("Bremsninger: $tripBrakes (hård: $tripHardBrakes)"),
                ],
              ),
            ),
            FilledButton(
              onPressed: tripActive ? _stopTrip : _startTrip,
              child: Text(tripActive ? "Stop" : "Start"),
            ),
          ],
        ),
      );

  Widget _sensitivityCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Bremselys-følsomhed",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Slider(
              min: 0.5,
              max: 5.0,
              divisions: 45,
              label: sensitivity.toStringAsFixed(2),
              value: sensitivity,
              onChanged: (v) => safeSetState(() => sensitivity = v),
              onChangeEnd: connected ? (v) => _writeSensitivity(v) : null,
            ),
            const Text(
              "Lav = reagerer hurtigt · Høj = kræver hårdere opbremsning",
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );

  Widget _counterCard(int today) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Bremsninger i dag"),
            const SizedBox(height: 8),
            Text(
              "$today",
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );

  Widget _chartCard() {
    final data = _brakesLast30Min();
    return _card(
      child: SizedBox(
        height: 180,
        child: BarChart(
          BarChartData(
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            barGroups: List.generate(30, (i) {
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].toDouble(),
                    color: const Color(0xFF00E0A4),
                  )
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );
}

/// ================= STATUS PARSER =================
class MunjaStatus {
  final bool brake;
  final int? pwm;
  final double? bs;

  MunjaStatus({required this.brake, this.pwm, this.bs});

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
