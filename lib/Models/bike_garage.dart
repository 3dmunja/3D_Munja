import 'bike_profile.dart';

class BikeGarage {
  final List<BikeProfile> bikes;
  final String? activeBikeId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BikeGarage({
    required this.bikes,
    required this.activeBikeId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BikeGarage.empty() {
    final now = DateTime.now();

    return BikeGarage(
      bikes: const [],
      activeBikeId: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  factory BikeGarage.withKidsPrototype() {
    final now = DateTime.now();
    final bike = BikeProfile.kidsMtbPrototype();

    return BikeGarage(
      bikes: [bike],
      activeBikeId: bike.id,
      createdAt: now,
      updatedAt: now,
    );
  }

  BikeProfile? get activeBike {
    if (activeBikeId == null) return bikes.isEmpty ? null : bikes.first;

    for (final bike in bikes) {
      if (bike.id == activeBikeId) return bike;
    }

    return bikes.isEmpty ? null : bikes.first;
  }

  bool get hasBikes => bikes.isNotEmpty;

  BikeGarage copyWith({
    List<BikeProfile>? bikes,
    String? activeBikeId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BikeGarage(
      bikes: bikes ?? this.bikes,
      activeBikeId: activeBikeId ?? this.activeBikeId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  BikeGarage addBike(BikeProfile bike, {bool makeActive = true}) {
    final filtered = bikes.where((item) => item.id != bike.id).toList();

    return copyWith(
      bikes: [...filtered, bike],
      activeBikeId: makeActive ? bike.id : activeBikeId,
    );
  }

  BikeGarage updateBike(BikeProfile bike) {
    final updatedBikes = bikes.map((item) {
      if (item.id == bike.id) return bike;
      return item;
    }).toList();

    final exists = bikes.any((item) => item.id == bike.id);

    return copyWith(
      bikes: exists ? updatedBikes : [...bikes, bike],
      activeBikeId: activeBikeId ?? bike.id,
    );
  }

  BikeGarage removeBike(String bikeId) {
    final updatedBikes = bikes.where((bike) => bike.id != bikeId).toList();

    String? nextActiveId = activeBikeId;

    if (activeBikeId == bikeId) {
      nextActiveId = updatedBikes.isEmpty ? null : updatedBikes.first.id;
    }

    return copyWith(bikes: updatedBikes, activeBikeId: nextActiveId);
  }

  BikeGarage setActiveBike(String bikeId) {
    final exists = bikes.any((bike) => bike.id == bikeId);

    if (!exists) return this;

    return copyWith(activeBikeId: bikeId);
  }

  Map<String, dynamic> toJson() {
    return {
      'bikes': bikes.map((bike) => bike.toJson()).toList(),
      'activeBikeId': activeBikeId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory BikeGarage.fromJson(Map<String, dynamic> json) {
    final rawBikes = json['bikes'];

    final bikes = rawBikes is List
        ? rawBikes
              .whereType<Map<String, dynamic>>()
              .map(BikeProfile.fromJson)
              .toList()
        : <BikeProfile>[];

    return BikeGarage(
      bikes: bikes,
      activeBikeId: json['activeBikeId'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
