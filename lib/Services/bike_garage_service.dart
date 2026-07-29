import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bike_garage.dart';
import '../models/bike_profile.dart';

class BikeGarageService {
  static const String _garageKey = 'munja_bike_garage';

  const BikeGarageService();

  Future<BikeGarage> loadGarage() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_garageKey);

    if (raw == null || raw.trim().isEmpty) {
      return BikeGarage.empty();
    }

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! Map<String, dynamic>) {
        return BikeGarage.empty();
      }

      return BikeGarage.fromJson(decoded);
    } catch (_) {
      return BikeGarage.empty();
    }
  }

  Future<BikeGarage> loadOrCreateKidsPrototype() async {
    final garage = await loadGarage();

    if (garage.hasBikes) {
      return garage;
    }

    final prototypeGarage = BikeGarage.withKidsPrototype();
    await saveGarage(prototypeGarage);

    return prototypeGarage;
  }

  Future<void> saveGarage(BikeGarage garage) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(garage.toJson());

    await prefs.setString(_garageKey, encoded);
  }

  Future<void> clearGarage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_garageKey);
  }

  Future<BikeGarage> addBike(BikeProfile bike, {bool makeActive = true}) async {
    final garage = await loadGarage();
    final updatedGarage = garage.addBike(bike, makeActive: makeActive);

    await saveGarage(updatedGarage);

    return updatedGarage;
  }

  Future<BikeGarage> updateBike(BikeProfile bike) async {
    final garage = await loadGarage();
    final updatedGarage = garage.updateBike(bike);

    await saveGarage(updatedGarage);

    return updatedGarage;
  }

  Future<BikeGarage> removeBike(String bikeId) async {
    final garage = await loadGarage();
    final updatedGarage = garage.removeBike(bikeId);

    await saveGarage(updatedGarage);

    return updatedGarage;
  }

  Future<BikeGarage> setActiveBike(String bikeId) async {
    final garage = await loadGarage();
    final updatedGarage = garage.setActiveBike(bikeId);

    await saveGarage(updatedGarage);

    return updatedGarage;
  }

  Future<BikeProfile?> loadActiveBike() async {
    final garage = await loadGarage();
    return garage.activeBike;
  }

  Future<BikeGarage> saveKidsBikeFromPhotos({
    required List<String> photoPaths,
    String name = 'Kids MTB',
  }) async {
    final bike = BikeProfile.kidsMtbPrototype(photoPaths: photoPaths).copyWith(
      id: 'bike_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      updatedAt: DateTime.now(),
    );

    return addBike(bike, makeActive: true);
  }
}
