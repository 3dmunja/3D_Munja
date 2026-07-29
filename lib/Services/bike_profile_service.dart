import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bike_profile.dart';

class BikeProfileService {
  static const String _activeBikeKey = 'munja_active_bike_profile';

  const BikeProfileService();

  Future<BikeProfile?> loadActiveBike() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeBikeKey);

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return BikeProfile.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<BikeProfile> loadOrCreateKidsPrototype() async {
    final existing = await loadActiveBike();

    if (existing != null) {
      return existing;
    }

    final prototype = BikeProfile.kidsMtbPrototype();
    await saveActiveBike(prototype);

    return prototype;
  }

  Future<void> saveActiveBike(BikeProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(profile.toJson());

    await prefs.setString(_activeBikeKey, encoded);
  }

  Future<void> clearActiveBike() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeBikeKey);
  }

  Future<BikeProfile> saveKidsBikeFromPhotos({
    required List<String> photoPaths,
    String name = 'Kids MTB',
  }) async {
    final profile = BikeProfile.kidsMtbPrototype(
      photoPaths: photoPaths,
    ).copyWith(name: name, updatedAt: DateTime.now());

    await saveActiveBike(profile);

    return profile;
  }
}
