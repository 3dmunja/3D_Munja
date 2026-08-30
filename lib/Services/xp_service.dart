import '../models/trip.dart';

class XpService {
  XpService._();

  static const int xpPerLevel = 350;
  static const int minLevel = 1;
  static const int maxLevel = 99;

  static double distanceKmForTrip(Trip trip) {
    return trip.distanceM / 1000;
  }

  static double averageSpeedKmhForTrip(Trip trip) {
    final hours = trip.duration.inSeconds / 3600;

    if (hours <= 0) {
      return 0;
    }

    return distanceKmForTrip(trip) / hours;
  }

  static int rideScoreForTrip(Trip trip) {
    final distanceKm = distanceKmForTrip(trip);
    final avgSpeedKmh = averageSpeedKmhForTrip(trip);
    final minutes = trip.duration.inMinutes.clamp(1, 999);

    final base = (distanceKm * 5).round();
    final timeBonus = (minutes / 4).round();
    final speedBonus = (avgSpeedKmh / 2).round();

    return (base + timeBonus + speedBonus).clamp(10, 100);
  }

  static int xpForTrip(Trip trip) {
    final distanceKm = distanceKmForTrip(trip);
    final rideScore = rideScoreForTrip(trip);

    return (distanceKm * 18 + rideScore * 1.7)
        .round()
        .clamp(20, 9999);
  }

  static int totalXp(Iterable<Trip> trips) {
    return trips.fold<int>(
      0,
      (sum, trip) => sum + xpForTrip(trip),
    );
  }

  /// Resolves which XP value account-facing UI should display.
  ///
  /// Once account XP has been loaded from Firestore it is the canonical value.
  /// Local trip XP is only a fallback for offline/legacy sessions.
  static int resolveTotalXp({
    required int localXp,
    int? accountXp,
  }) {
    final safeLocalXp = localXp < 0 ? 0 : localXp;
    final safeAccountXp =
        accountXp == null ? null : (accountXp < 0 ? 0 : accountXp);

    return safeAccountXp ?? safeLocalXp;
  }

  static int levelForTotalXp(int totalXp) {
    final safeXp = totalXp < 0 ? 0 : totalXp;
    final calculatedLevel = (safeXp ~/ xpPerLevel) + 1;

    return calculatedLevel.clamp(minLevel, maxLevel);
  }

  static int xpIntoCurrentLevel(int totalXp) {
    final safeXp = totalXp < 0 ? 0 : totalXp;

    if (levelForTotalXp(safeXp) >= maxLevel) {
      return xpPerLevel;
    }

    return safeXp % xpPerLevel;
  }

  static int xpNeededForNextLevel(int totalXp) {
    if (levelForTotalXp(totalXp) >= maxLevel) {
      return xpPerLevel;
    }

    return xpPerLevel;
  }

  static double levelProgress(int totalXp) {
    if (levelForTotalXp(totalXp) >= maxLevel) {
      return 1.0;
    }

    return (xpIntoCurrentLevel(totalXp) / xpPerLevel)
        .clamp(0.0, 1.0);
  }

  static int totalDistanceMeters(Iterable<Trip> trips) {
    return trips.fold<int>(
      0,
      (sum, trip) => sum + trip.distanceM.round(),
    );
  }

  static double totalDistanceKm(Iterable<Trip> trips) {
    return totalDistanceMeters(trips) / 1000;
  }
}
