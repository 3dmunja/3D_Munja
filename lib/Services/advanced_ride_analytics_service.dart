import '../models/trip.dart';

class AnalyticsPeriodComparison {
  const AnalyticsPeriodComparison({
    required this.currentDistanceKm,
    required this.previousDistanceKm,
    required this.currentRideCount,
    required this.previousRideCount,
    required this.currentAverageSpeedKmh,
    required this.previousAverageSpeedKmh,
  });

  final double currentDistanceKm;
  final double previousDistanceKm;
  final int currentRideCount;
  final int previousRideCount;
  final double currentAverageSpeedKmh;
  final double previousAverageSpeedKmh;

  double? get distanceChangePercent {
    if (previousDistanceKm <= 0) {
      return null;
    }

    return ((currentDistanceKm / previousDistanceKm) - 1) * 100;
  }

  double? get speedChangePercent {
    if (previousAverageSpeedKmh <= 0) {
      return null;
    }

    return ((currentAverageSpeedKmh / previousAverageSpeedKmh) - 1) * 100;
  }
}

class AdvancedAnalyticsResult {
  const AdvancedAnalyticsResult({
    required this.weekComparison,
    required this.monthComparison,
    required this.bestMonthLabel,
    required this.bestMonthDistanceKm,
    required this.consistencyScore,
    required this.insightTitle,
    required this.insightBody,
  });

  final AnalyticsPeriodComparison weekComparison;
  final AnalyticsPeriodComparison monthComparison;
  final String bestMonthLabel;
  final double bestMonthDistanceKm;
  final int consistencyScore;
  final String insightTitle;
  final String insightBody;
}

class AdvancedRideAnalyticsService {
  const AdvancedRideAnalyticsService();

  AdvancedAnalyticsResult analyze(
    List<Trip> trips, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();

    final startOfToday = DateTime(
      reference.year,
      reference.month,
      reference.day,
    );

    final startOfCurrentWeek = startOfToday.subtract(
      Duration(days: startOfToday.weekday - DateTime.monday),
    );

    final startOfPreviousWeek =
        startOfCurrentWeek.subtract(const Duration(days: 7));

    final startOfCurrentMonth =
        DateTime(reference.year, reference.month, 1);

    final startOfPreviousMonth =
        DateTime(reference.year, reference.month - 1, 1);

    final startOfNextMonth =
        DateTime(reference.year, reference.month + 1, 1);

    final currentWeekTrips = _between(
      trips,
      startOfCurrentWeek,
      reference.add(const Duration(days: 1)),
    );

    final previousWeekTrips = _between(
      trips,
      startOfPreviousWeek,
      startOfCurrentWeek,
    );

    final currentMonthTrips = _between(
      trips,
      startOfCurrentMonth,
      startOfNextMonth,
    );

    final previousMonthTrips = _between(
      trips,
      startOfPreviousMonth,
      startOfCurrentMonth,
    );

    final weekComparison = _comparison(
      currentWeekTrips,
      previousWeekTrips,
    );

    final monthComparison = _comparison(
      currentMonthTrips,
      previousMonthTrips,
    );

    final monthBuckets = <String, List<Trip>>{};

    for (final trip in trips) {
      final date =
          DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);

      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}';

      monthBuckets.putIfAbsent(
        key,
        () => <Trip>[],
      );

      monthBuckets[key]!.add(trip);
    }

    String bestMonthLabel = '—';
    double bestMonthDistanceKm = 0;

    for (final entry in monthBuckets.entries) {
      final distance = _distanceKm(entry.value);

      if (distance > bestMonthDistanceKm) {
        bestMonthDistanceKm = distance;
        bestMonthLabel = _monthLabel(entry.key);
      }
    }

    final consistencyScore = _consistencyScore(trips);

    final insight = _insight(
      weekComparison: weekComparison,
      monthComparison: monthComparison,
      consistencyScore: consistencyScore,
    );

    return AdvancedAnalyticsResult(
      weekComparison: weekComparison,
      monthComparison: monthComparison,
      bestMonthLabel: bestMonthLabel,
      bestMonthDistanceKm: bestMonthDistanceKm,
      consistencyScore: consistencyScore,
      insightTitle: insight.$1,
      insightBody: insight.$2,
    );
  }

  AnalyticsPeriodComparison _comparison(
    List<Trip> current,
    List<Trip> previous,
  ) {
    return AnalyticsPeriodComparison(
      currentDistanceKm: _distanceKm(current),
      previousDistanceKm: _distanceKm(previous),
      currentRideCount: current.length,
      previousRideCount: previous.length,
      currentAverageSpeedKmh: _averageSpeed(current),
      previousAverageSpeedKmh: _averageSpeed(previous),
    );
  }

  List<Trip> _between(
    List<Trip> trips,
    DateTime start,
    DateTime end,
  ) {
    return trips.where((trip) {
      final date =
          DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);

      return !date.isBefore(start) && date.isBefore(end);
    }).toList(growable: false);
  }

  double _distanceKm(List<Trip> trips) {
    return trips.fold<double>(
      0,
      (sum, trip) => sum + (trip.distanceM / 1000),
    );
  }

  Duration _duration(List<Trip> trips) {
    return trips.fold<Duration>(
      Duration.zero,
      (sum, trip) => sum + trip.duration,
    );
  }

  double _averageSpeed(List<Trip> trips) {
    final hours = _duration(trips).inSeconds / 3600;

    if (hours <= 0) {
      return 0;
    }

    return _distanceKm(trips) / hours;
  }

  int _consistencyScore(List<Trip> trips) {
    if (trips.isEmpty) {
      return 0;
    }

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 28));

    final activeDays = trips
        .map(
          (trip) =>
              DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs),
        )
        .where((date) => !date.isBefore(cutoff))
        .map((date) => DateTime(date.year, date.month, date.day))
        .toSet()
        .length;

    final activeWeeks = trips
        .map(
          (trip) =>
              DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs),
        )
        .where((date) => !date.isBefore(cutoff))
        .map((date) {
          final normalized =
              DateTime(date.year, date.month, date.day);

          return normalized.subtract(
            Duration(
              days:
                  normalized.weekday - DateTime.monday,
            ),
          );
        })
        .toSet()
        .length;

    var score = 35;
    score += (activeDays * 3).clamp(0, 36);
    score += (activeWeeks * 7).clamp(0, 28);

    return score.clamp(0, 100);
  }

  (String, String) _insight({
    required AnalyticsPeriodComparison weekComparison,
    required AnalyticsPeriodComparison monthComparison,
    required int consistencyScore,
  }) {
    final monthDistanceChange =
        monthComparison.distanceChangePercent;

    final weekDistanceChange =
        weekComparison.distanceChangePercent;

    final monthSpeedChange =
        monthComparison.speedChangePercent;

    if (monthDistanceChange != null &&
        monthDistanceChange >= 15) {
      return (
        'Volume is rising',
        'You have ridden ${monthDistanceChange.toStringAsFixed(0)}% more distance this month than last month. Keep the increase controlled so consistency stays high.',
      );
    }

    if (monthSpeedChange != null &&
        monthSpeedChange >= 5) {
      return (
        'Pace is improving',
        'Your average speed is ${monthSpeedChange.toStringAsFixed(0)}% higher this month than last month while you continue building ride history.',
      );
    }

    if (weekDistanceChange != null &&
        weekDistanceChange <= -20) {
      return (
        'Lighter week',
        'Your distance is ${weekDistanceChange.abs().toStringAsFixed(0)}% lower than last week. That can be recovery or a signal to plan one more ride.',
      );
    }

    if (consistencyScore >= 80) {
      return (
        'Strong consistency',
        'Your recent ride frequency is very consistent. Keep the same rhythm and build distance gradually.',
      );
    }

    return (
      'Build your rhythm',
      'More regular rides will make Munja Pro analytics increasingly personal and useful.',
    );
  }

  String _monthLabel(String key) {
    final parts = key.split('-');

    if (parts.length != 2) {
      return key;
    }

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);

    if (year == null || month == null) {
      return key;
    }

    const labels = <String>[
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];

    if (month < 1 || month > 12) {
      return key;
    }

    return '${labels[month - 1]} ${year.toString().substring(2)}';
  }
}
