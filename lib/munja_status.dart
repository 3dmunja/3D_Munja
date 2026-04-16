class MunjaStatus {
  final bool brake;
  final int? pwm;
  final double? bs;
  final int? battery; // 0-100

  MunjaStatus({
    required this.brake,
    this.pwm,
    this.bs,
    this.battery,
  });

  static MunjaStatus? tryParse(String raw) {
    // raw eksempel: "BRAKE=0;PWM=25;BS=1.80;BAT=87;"
    final parts = raw.split(';').where((e) => e.trim().isNotEmpty);
    final map = <String, String>{};

    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      final k = p.substring(0, idx).trim().toUpperCase();
      final v = p.substring(idx + 1).trim();
      map[k] = v;
    }

    if (!map.containsKey('BRAKE')) return null;

    final brake = map['BRAKE'] == '1';
    final pwm = int.tryParse(map['PWM'] ?? '');
    final bs = double.tryParse(map['BS'] ?? '');
    final bat = int.tryParse(map['BAT'] ?? '');

    return MunjaStatus(
      brake: brake,
      pwm: pwm,
      bs: bs,
      battery: bat,
    );
  }
}
class BrakeCounter {
  bool _lastBrake = false;

  /// Returnerer true hvis det var et "nyt brake event" (0 -> 1)
  bool onStatus(MunjaStatus s) {
    final rising = (!_lastBrake && s.brake);
    _lastBrake = s.brake;
    return rising;
  }
}
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class BrakeStore {
  static const _key = "brake_events"; // list af timestamps (ms)

  Future<List<int>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null) return [];
    final list = (jsonDecode(raw) as List).cast<int>();
    return list;
  }

  Future<void> addEvent(int epochMs) async {
    final sp = await SharedPreferences.getInstance();
    final events = await load();
    events.add(epochMs);

    // hold fx max 5000 events
    if (events.length > 5000) {
      events.removeRange(0, events.length - 5000);
    }

    await sp.setString(_key, jsonEncode(events));
  }
}
List<int> brakeCountsLast30Min(List<int> eventsMs) {
  final now = DateTime.now();
  final start = now.subtract(const Duration(minutes: 30));
  final bins = List<int>.filled(30, 0);

  for (final ms in eventsMs) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    if (t.isBefore(start) || t.isAfter(now)) continue;
    final diffMin = now.difference(t).inMinutes; // 0..29
    final idx = 29 - diffMin; // så grafen går venstre->højre i tid
    if (idx >= 0 && idx < 30) bins[idx]++;
  }
  return bins;
}


