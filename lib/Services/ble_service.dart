import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_constants.dart';
import '../models/munja_device.dart';

class BleService {
  static Future<bool> ensureBlePermissions() async {
    final scan = await Permission.bluetoothScan.request();
    final connect = await Permission.bluetoothConnect.request();
    final loc = await Permission.locationWhenInUse.request();

    return scan.isGranted && connect.isGranted && loc.isGranted;
  }

  static bool isMunjaDeviceName(String name) {
    final lower = name.toLowerCase();

    return lower.startsWith('munja') ||
        lower.contains('brakelight') ||
        lower == deviceName.toLowerCase();
  }

  static MunjaProductType detectProductType(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('brake')) {
      return MunjaProductType.brakeLight;
    }

    return MunjaProductType.unknown;
  }

  static String proximityLabel(int rssi) {
    if (rssi >= -55) return 'Very close';
    if (rssi >= -70) return 'Nearby';

    return 'Farther away';
  }

  static Future<List<MunjaDevice>> scanNearbyMunjaDevices({
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

        if (name.isEmpty || !isMunjaDeviceName(name)) {
          continue;
        }

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
}
