import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../Models/route_result.dart';
import '../config/api_keys.dart';

class RouteServiceException implements Exception {
  const RouteServiceException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'RouteServiceException$status: $message';
  }
}

class RouteService {
  RouteService._();

  static final RouteService instance = RouteService._();

  static const String _apiKey = ApiKeys.googleMaps;

  static const String _computeRoutesEndpoint =
      'https://routes.googleapis.com/directions/v2:computeRoutes';

  List<RouteNavigationStep> _lastNavigationSteps =
      const <RouteNavigationStep>[];

  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  /// Turn-by-turn steps returned directly by Google Routes for the
  /// most recently calculated route.
  List<RouteNavigationStep> get lastNavigationSteps =>
      _lastNavigationSteps;

  Future<RouteResult> calculateBicycleRoute({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    String languageCode = 'da-DK',
  }) {
    return _calculateRoute(
      originLatitude: originLatitude,
      originLongitude: originLongitude,
      destinationLatitude: destinationLatitude,
      destinationLongitude: destinationLongitude,
      languageCode: languageCode,
    );
  }

  /// Creates a bicycle loop that starts and ends at the rider's position.
  ///
  /// Google Routes does not expose a dedicated "round trip" endpoint, so
  /// Munja builds a loop from three shaping waypoints around the rider and
  /// lets Google snap the result to real bicycle roads.
  ///
  /// Several loop sizes are tried and the route whose real Google distance
  /// is closest to [targetDistanceKm] is returned.
  Future<RouteResult> calculateRoundTrip({
    required double originLatitude,
    required double originLongitude,
    required double targetDistanceKm,
    String languageCode = 'da-DK',
  }) async {
    if (targetDistanceKm <= 0) {
      throw const RouteServiceException(
        'Rundturens distance skal være større end 0 km.',
      );
    }

    if (!hasApiKey) {
      throw const RouteServiceException(
        'GOOGLE_MAPS_API_KEY mangler.',
      );
    }

    final targetMeters = targetDistanceKm * 1000.0;

    // A triangle has three outer legs plus the return to start.
    // Road snapping normally makes the real route longer than the raw
    // geometric loop, so start slightly conservative and try nearby scales.
    const scaleFactors = <double>[0.78, 0.92, 1.06, 1.20];

    RouteResult? bestRoute;
    var bestDifference = double.infinity;
    Object? lastError;

    for (var attempt = 0; attempt < scaleFactors.length; attempt++) {
      final scale = scaleFactors[attempt];

      // Rotate each attempt so Google gets materially different candidate
      // roads instead of repeatedly producing the exact same loop.
      final baseBearing = 25.0 + (attempt * 47.0);

      final radiusMeters =
          (targetMeters / 4.6) * scale;

      final waypoints = <RoutePoint>[
        _offsetPoint(
          latitude: originLatitude,
          longitude: originLongitude,
          distanceMeters: radiusMeters,
          bearingDegrees: baseBearing,
        ),
        _offsetPoint(
          latitude: originLatitude,
          longitude: originLongitude,
          distanceMeters: radiusMeters * 1.18,
          bearingDegrees: baseBearing + 120.0,
        ),
        _offsetPoint(
          latitude: originLatitude,
          longitude: originLongitude,
          distanceMeters: radiusMeters,
          bearingDegrees: baseBearing + 240.0,
        ),
      ];

      try {
        final route = await _calculateRoute(
          originLatitude: originLatitude,
          originLongitude: originLongitude,
          destinationLatitude: originLatitude,
          destinationLongitude: originLongitude,
          intermediates: waypoints,
          languageCode: languageCode,
        );

        if (!_isUsableLoopCandidate(
          route: route,
          originLatitude: originLatitude,
          originLongitude: originLongitude,
          targetMeters: targetMeters,
        )) {
          debugPrint(
            'MUNJA ROUND TRIP REJECTED: '
            'candidate collapsed or did not leave start area.',
          );
          continue;
        }

        final difference =
            (route.distanceMeters - targetMeters).abs();

        debugPrint(
          'MUNJA ROUND TRIP CANDIDATE: '
          'attempt=${attempt + 1}, '
          'target=${targetMeters.toStringAsFixed(0)}m, '
          'actual=${route.distanceMeters.toStringAsFixed(0)}m, '
          'difference=${difference.toStringAsFixed(0)}m',
        );

        if (difference < bestDifference) {
          bestDifference = difference;
          bestRoute = route;
        }

        // Within 12% is already a very good cycling loop.
        if (difference <= targetMeters * 0.12) {
          break;
        }
      } catch (error) {
        lastError = error;

        debugPrint(
          'MUNJA ROUND TRIP CANDIDATE ERROR '
          '${attempt + 1}: $error',
        );
      }
    }

    if (bestRoute != null) {
      // Restore navigation steps for the route we actually return. Because
      // _calculateRoute updates this cache on every candidate, recompute only
      // when the best candidate was not the final successful request.
      //
      // The returned RouteResult itself always contains the correct steps,
      // and NavigationService should prefer result.navigationSteps.
      _lastNavigationSteps =
          List<RouteNavigationStep>.unmodifiable(
        bestRoute.navigationSteps,
      );

      debugPrint(
        'MUNJA ROUND TRIP READY: '
        'target=${targetDistanceKm.toStringAsFixed(1)}km, '
        'actual=${(bestRoute.distanceMeters / 1000).toStringAsFixed(1)}km',
      );

      return bestRoute;
    }

    if (lastError is RouteServiceException) {
      throw lastError;
    }

    throw RouteServiceException(
      'Munja kunne ikke finde en rundtur i området.',
      responseBody: lastError?.toString(),
    );
  }

  bool _isUsableLoopCandidate({
    required RouteResult route,
    required double originLatitude,
    required double originLongitude,
    required double targetMeters,
  }) {
    if (route.points.length < 8 ||
        route.encodedPolyline.trim().isEmpty ||
        route.distanceMeters <= 0) {
      return false;
    }

    // Reject routes Google collapsed into a tiny local loop.
    final minimumUsefulDistance =
        math.max(700.0, targetMeters * 0.55);

    if (route.distanceMeters < minimumUsefulDistance) {
      return false;
    }

    var maxDistanceFromStart = 0.0;

    for (final point in route.points) {
      final distance = _distanceBetweenPointsMeters(
        RoutePoint(
          latitude: originLatitude,
          longitude: originLongitude,
        ),
        point,
      );

      if (distance > maxDistanceFromStart) {
        maxDistanceFromStart = distance;
      }
    }

    // A real 5/10/20/30 km loop must actually leave the start area.
    final minimumExcursion =
        math.max(250.0, targetMeters * 0.08);

    if (maxDistanceFromStart < minimumExcursion) {
      return false;
    }

    return true;
  }

  /// Generates several suggested bicycle loops around the rider.
  ///
  /// This is used by RideSetupMode.suggestedRoute. The suggestions are
  /// intentionally different from each other by rotating the waypoint
  /// geometry around the start position.
  ///
  /// Google Routes still performs the actual road snapping and bicycle
  /// routing. Munja only creates the shaping points and ranks the returned
  /// routes by how closely they match the requested distance.
  Future<List<RouteResult>> calculateSuggestedRoutes({
    required double originLatitude,
    required double originLongitude,
    required double targetDistanceKm,
    int suggestionCount = 3,
    String languageCode = 'da-DK',
  }) async {
    if (targetDistanceKm <= 0) {
      throw const RouteServiceException(
        'Ruteforslagets distance skal være større end 0 km.',
      );
    }

    if (!hasApiKey) {
      throw const RouteServiceException(
        'GOOGLE_MAPS_API_KEY mangler.',
      );
    }

    final safeSuggestionCount = suggestionCount.clamp(1, 5);
    final targetMeters = targetDistanceKm * 1000.0;

    // Use several base directions so the proposals actually leave the rider
    // in different directions instead of producing near-identical loops.
    const baseBearings = <double>[
      10,
      72,
      138,
      205,
      278,
    ];

    // A few size multipliers help compensate for road snapping and local
    // street geometry. The closest candidate from each direction is kept.
    const scaleFactors = <double>[
      0.82,
      0.96,
      1.10,
    ];

    final candidates = <_SuggestedRouteCandidate>[];
    Object? lastError;

    for (var bearingIndex = 0;
        bearingIndex < baseBearings.length;
        bearingIndex++) {
      final baseBearing = baseBearings[bearingIndex];

      RouteResult? bestForDirection;
      var bestDifferenceForDirection = double.infinity;

      for (final scale in scaleFactors) {
        final radiusMeters =
            (targetMeters / 4.7) * scale;

        final waypoints = <RoutePoint>[
          _offsetPoint(
            latitude: originLatitude,
            longitude: originLongitude,
            distanceMeters: radiusMeters,
            bearingDegrees: baseBearing,
          ),
          _offsetPoint(
            latitude: originLatitude,
            longitude: originLongitude,
            distanceMeters: radiusMeters * 1.16,
            bearingDegrees: baseBearing + 118.0,
          ),
          _offsetPoint(
            latitude: originLatitude,
            longitude: originLongitude,
            distanceMeters: radiusMeters * 0.96,
            bearingDegrees: baseBearing + 242.0,
          ),
        ];

        try {
          final route = await _calculateRoute(
            originLatitude: originLatitude,
            originLongitude: originLongitude,
            destinationLatitude: originLatitude,
            destinationLongitude: originLongitude,
            intermediates: waypoints,
            languageCode: languageCode,
          );

          if (!_isUsableLoopCandidate(
            route: route,
            originLatitude: originLatitude,
            originLongitude: originLongitude,
            targetMeters: targetMeters,
          )) {
            debugPrint(
              'MUNJA SUGGESTED ROUTE REJECTED: '
              'candidate collapsed or did not leave start area.',
            );
            continue;
          }

          final difference =
              (route.distanceMeters - targetMeters).abs();

          debugPrint(
            'MUNJA SUGGESTED ROUTE CANDIDATE: '
            'direction=$bearingIndex, '
            'bearing=${baseBearing.toStringAsFixed(0)}, '
            'scale=${scale.toStringAsFixed(2)}, '
            'target=${targetMeters.toStringAsFixed(0)}m, '
            'actual=${route.distanceMeters.toStringAsFixed(0)}m, '
            'difference=${difference.toStringAsFixed(0)}m',
          );

          if (difference < bestDifferenceForDirection) {
            bestDifferenceForDirection = difference;
            bestForDirection = route;
          }

          // Good enough for this direction, no need to spend another API call.
          if (difference <= targetMeters * 0.10) {
            break;
          }
        } catch (error) {
          lastError = error;

          debugPrint(
            'MUNJA SUGGESTED ROUTE CANDIDATE ERROR: '
            'direction=$bearingIndex, '
            'scale=$scale, '
            'error=$error',
          );
        }
      }

      if (bestForDirection != null) {
        candidates.add(
          _SuggestedRouteCandidate(
            route: bestForDirection,
            differenceMeters:
                bestDifferenceForDirection,
            baseBearing: baseBearing,
          ),
        );
      }
    }

    if (candidates.isEmpty) {
      if (lastError is RouteServiceException) {
        throw lastError;
      }

      throw RouteServiceException(
        'Munja kunne ikke finde ruteforslag i området.',
        responseBody: lastError?.toString(),
      );
    }

    candidates.sort(
      (a, b) => a.differenceMeters.compareTo(
        b.differenceMeters,
      ),
    );

    final selected = <RouteResult>[];

    for (final candidate in candidates) {
      final route = candidate.route;

      final duplicate = selected.any(
        (existing) =>
            _routesAreTooSimilar(existing, route),
      );

      if (duplicate) {
        continue;
      }

      selected.add(route);

      if (selected.length >= safeSuggestionCount) {
        break;
      }
    }

    // If local road geometry caused several suggestions to collapse into
    // essentially the same loop, still return the best available candidates.
    if (selected.length < safeSuggestionCount) {
      for (final candidate in candidates) {
        if (selected.contains(candidate.route)) {
          continue;
        }

        selected.add(candidate.route);

        if (selected.length >= safeSuggestionCount) {
          break;
        }
      }
    }

    if (selected.isNotEmpty) {
      _lastNavigationSteps =
          List<RouteNavigationStep>.unmodifiable(
        selected.first.navigationSteps,
      );
    }

    debugPrint(
      'MUNJA SUGGESTED ROUTES READY: '
      'requested=${targetDistanceKm.toStringAsFixed(1)}km, '
      'count=${selected.length}, '
      'distances=${selected.map((route) => (route.distanceMeters / 1000).toStringAsFixed(1)).join(', ')}',
    );

    return List<RouteResult>.unmodifiable(selected);
  }

  bool _routesAreTooSimilar(
    RouteResult a,
    RouteResult b,
  ) {
    final distanceDifference =
        (a.distanceMeters - b.distanceMeters).abs();

    if (distanceDifference >
        math.max(a.distanceMeters, b.distanceMeters) * 0.08) {
      return false;
    }

    if (a.points.isEmpty || b.points.isEmpty) {
      return false;
    }

    final sampleA = a.points[
        (a.points.length * 0.35)
            .floor()
            .clamp(0, a.points.length - 1)];

    final sampleB = b.points[
        (b.points.length * 0.35)
            .floor()
            .clamp(0, b.points.length - 1)];

    final separation = _distanceBetweenPointsMeters(
      sampleA,
      sampleB,
    );

    return separation < 350;
  }

  double _distanceBetweenPointsMeters(
    RoutePoint a,
    RoutePoint b,
  ) {
    const earthRadiusMeters = 6371000.0;

    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final deltaLat =
        (b.latitude - a.latitude) *
        math.pi /
        180.0;
    final deltaLon =
        (b.longitude - a.longitude) *
        math.pi /
        180.0;

    final sinLat = math.sin(deltaLat / 2);
    final sinLon = math.sin(deltaLon / 2);

    final haversine =
        sinLat * sinLat +
        math.cos(lat1) *
            math.cos(lat2) *
            sinLon *
            sinLon;

    final centralAngle = 2 *
        math.atan2(
          math.sqrt(haversine),
          math.sqrt(1 - haversine),
        );

    return earthRadiusMeters * centralAngle;
  }

  Future<RouteResult> _calculateRoute({
    required double originLatitude,
    required double originLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
    List<RoutePoint> intermediates = const <RoutePoint>[],
    String languageCode = 'da-DK',
  }) async {
    if (!hasApiKey) {
      throw const RouteServiceException(
        'GOOGLE_MAPS_API_KEY mangler.',
      );
    }

    final client = HttpClient();

    // Never expose steps from an older route while a new request is running.
    _lastNavigationSteps = const <RouteNavigationStep>[];

    try {
      final request = await client.postUrl(
        Uri.parse(_computeRoutesEndpoint),
      );

      request.headers.contentType = ContentType.json;
      request.headers.set('X-Goog-Api-Key', _apiKey);
      request.headers.set(
        'X-Goog-FieldMask',
        'routes.duration,'
        'routes.distanceMeters,'
        'routes.polyline.encodedPolyline,'
        'routes.legs.steps.distanceMeters,'
        'routes.legs.steps.staticDuration,'
        'routes.legs.steps.polyline.encodedPolyline,'
        'routes.legs.steps.startLocation.latLng,'
        'routes.legs.steps.endLocation.latLng,'
        'routes.legs.steps.navigationInstruction.maneuver,'
        'routes.legs.steps.navigationInstruction.instructions',
      );

      request.write(
        jsonEncode(
          <String, dynamic>{
            'origin': {
              'location': {
                'latLng': {
                  'latitude': originLatitude,
                  'longitude': originLongitude,
                },
              },
            },
            'destination': {
              'location': {
                'latLng': {
                  'latitude': destinationLatitude,
                  'longitude': destinationLongitude,
                },
              },
            },
            if (intermediates.isNotEmpty)
              'intermediates': intermediates
                  .map(
                    (point) => <String, dynamic>{
                      'location': {
                        'latLng': {
                          'latitude': point.latitude,
                          'longitude': point.longitude,
                        },
                      },
                      // These are shaping points for a deliberate loop.
                      // They must remain in the order Munja generated them.
                      'via': false,
                    },
                  )
                  .toList(growable: false),
            'travelMode': 'BICYCLE',
            'computeAlternativeRoutes': false,
            'polylineQuality': 'HIGH_QUALITY',
            'polylineEncoding': 'ENCODED_POLYLINE',
            'languageCode': languageCode,
            'units': 'METRIC',
          },
        ),
      );

      final response = await request.close();
      final responseBody =
          await utf8.decoder.bind(response).join();

      debugPrint(
        'MUNJA ROUTES STATUS: ${response.statusCode}',
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        debugPrint(
          'MUNJA ROUTES ERROR '
          '${response.statusCode}: $responseBody',
        );

        throw RouteServiceException(
          'Google Routes returnerede en fejl.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final decoded = jsonDecode(responseBody);

      if (decoded is! Map) {
        throw RouteServiceException(
          'Google Routes returnerede ugyldige data.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final responseMap =
          Map<String, dynamic>.from(decoded);

      final rawRoutes =
          responseMap['routes'] as List<dynamic>? ??
          const <dynamic>[];

      if (rawRoutes.isEmpty || rawRoutes.first is! Map) {
        throw RouteServiceException(
          'Google fandt ingen cykelrute.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final route = Map<String, dynamic>.from(
        rawRoutes.first as Map,
      );

      final distanceMeters =
          (route['distanceMeters'] as num?)?.toDouble();

      final durationSeconds = _parseDurationSeconds(
        route['duration'] as String?,
      );

      final rawPolyline = route['polyline'];

      final polyline = rawPolyline is Map
          ? Map<String, dynamic>.from(rawPolyline)
          : const <String, dynamic>{};

      final encodedPolyline =
          polyline['encodedPolyline'] as String? ?? '';

      if (distanceMeters == null ||
          durationSeconds == null ||
          encodedPolyline.isEmpty) {
        throw RouteServiceException(
          'Google-ruten mangler distance, tid eller polyline.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final points = decodePolyline(encodedPolyline);

      final navigationSteps =
          _parseNavigationSteps(route);

      _lastNavigationSteps = List<RouteNavigationStep>.unmodifiable(
        navigationSteps,
      );

      debugPrint(
        'MUNJA ROUTE STEPS READY: '
        '${_lastNavigationSteps.length}',
      );

      if (points.length < 2) {
        throw RouteServiceException(
          'Ruten kunne ikke afkodes.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final result = RouteResult(
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        encodedPolyline: encodedPolyline,
        points: points,
        navigationSteps: _lastNavigationSteps,
      );

      debugPrint(
        'MUNJA ROUTE READY: '
        'distance=${distanceMeters.toStringAsFixed(0)}m, '
        'duration=${durationSeconds}s, '
        'points=${points.length}, '
        'steps=${result.navigationSteps.length}',
      );

      return result;
    } on RouteServiceException {
      rethrow;
    } on SocketException catch (error) {
      throw RouteServiceException(
        'Kunne ikke forbinde til Google Routes.',
        responseBody: error.message,
      );
    } on FormatException catch (error) {
      throw RouteServiceException(
        'Google Routes returnerede ugyldig JSON.',
        responseBody: error.message,
      );
    } catch (error, stackTrace) {
      debugPrint('MUNJA ROUTES EXCEPTION: $error');
      debugPrint('$stackTrace');

      throw RouteServiceException(
        'Der opstod en ukendt fejl ved ruteberegningen.',
        responseBody: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  List<RouteNavigationStep> _parseNavigationSteps(
    Map<String, dynamic> route,
  ) {
    final rawLegs =
        route['legs'] as List<dynamic>? ??
        const <dynamic>[];

    final steps = <RouteNavigationStep>[];
    var globalIndex = 0;

    for (final rawLeg in rawLegs) {
      if (rawLeg is! Map) {
        continue;
      }

      final leg = Map<String, dynamic>.from(rawLeg);

      final rawSteps =
          leg['steps'] as List<dynamic>? ??
          const <dynamic>[];

      for (final rawStep in rawSteps) {
        if (rawStep is! Map) {
          continue;
        }

        final step = Map<String, dynamic>.from(rawStep);

        final navigationRaw =
            step['navigationInstruction'];

        final navigation = navigationRaw is Map
            ? Map<String, dynamic>.from(
                navigationRaw,
              )
            : const <String, dynamic>{};

        final maneuverRaw =
            navigation['maneuver'] as String? ?? '';

        final instruction =
            navigation['instructions'] as String? ?? '';

        final start = _parseStepLocation(
          step['startLocation'],
        );

        final end = _parseStepLocation(
          step['endLocation'],
        );

        final stepPolylineRaw = step['polyline'];

        final stepPolyline =
            stepPolylineRaw is Map
                ? Map<String, dynamic>.from(
                    stepPolylineRaw,
                  )
                : const <String, dynamic>{};

        final encodedStepPolyline =
            stepPolyline['encodedPolyline']
                    as String? ??
                '';

        final stepDurationSeconds =
            _parseDurationSeconds(
                  step['staticDuration'] as String?,
                ) ??
                0;

        final stepDistanceMeters =
            (step['distanceMeters'] as num?)
                    ?.toDouble() ??
                0.0;

        final maneuver =
            RouteNavigationManeuver.fromGoogleValue(
          maneuverRaw,
        );

        // Keep useful steps even when Google omits a human-readable
        // instruction. NavigationService can generate a localized fallback
        // from the maneuver enum.
        if (maneuver ==
                RouteNavigationManeuver.unknown &&
            instruction.trim().isEmpty &&
            start == null &&
            end == null) {
          continue;
        }

        steps.add(
          RouteNavigationStep(
            index: globalIndex,
            maneuver: maneuver,
            rawManeuver: maneuverRaw,
            instruction: instruction.trim(),
            distanceMeters: stepDistanceMeters,
            durationSeconds: stepDurationSeconds,
            startLatitude: start?.latitude,
            startLongitude: start?.longitude,
            endLatitude: end?.latitude,
            endLongitude: end?.longitude,
            encodedPolyline: encodedStepPolyline,
          ),
        );

        globalIndex++;
      }
    }

    return steps;
  }

  RoutePoint? _parseStepLocation(dynamic rawLocation) {
    if (rawLocation is! Map) {
      return null;
    }

    final location =
        Map<String, dynamic>.from(rawLocation);

    final rawLatLng = location['latLng'];

    if (rawLatLng is! Map) {
      return null;
    }

    final latLng =
        Map<String, dynamic>.from(rawLatLng);

    final latitude =
        (latLng['latitude'] as num?)?.toDouble();

    final longitude =
        (latLng['longitude'] as num?)?.toDouble();

    if (latitude == null || longitude == null) {
      return null;
    }

    return RoutePoint(
      latitude: latitude,
      longitude: longitude,
    );
  }

  RoutePoint _offsetPoint({
    required double latitude,
    required double longitude,
    required double distanceMeters,
    required double bearingDegrees,
  }) {
    const earthRadiusMeters = 6371000.0;

    final angularDistance =
        distanceMeters / earthRadiusMeters;

    final bearing =
        bearingDegrees * math.pi / 180.0;

    final lat1 = latitude * math.pi / 180.0;
    final lon1 = longitude * math.pi / 180.0;

    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) *
              math.sin(angularDistance) *
              math.cos(bearing),
    );

    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) *
              math.sin(angularDistance) *
              math.cos(lat1),
          math.cos(angularDistance) -
              math.sin(lat1) * math.sin(lat2),
        );

    return RoutePoint(
      latitude: lat2 * 180.0 / math.pi,
      longitude: lon2 * 180.0 / math.pi,
    );
  }

  List<RoutePoint> decodePolyline(String encoded) {
    final points = <RoutePoint>[];

    var index = 0;
    var latitude = 0;
    var longitude = 0;

    while (index < encoded.length) {
      final latitudeResult = _decodeValue(encoded, index);
      index = latitudeResult.nextIndex;
      latitude += latitudeResult.value;

      final longitudeResult = _decodeValue(encoded, index);
      index = longitudeResult.nextIndex;
      longitude += longitudeResult.value;

      points.add(
        RoutePoint(
          latitude: latitude / 1E5,
          longitude: longitude / 1E5,
        ),
      );
    }

    return points;
  }

  _DecodedPolylineValue _decodeValue(
    String encoded,
    int startIndex,
  ) {
    var index = startIndex;
    var result = 0;
    var shift = 0;
    var byte = 0;

    do {
      if (index >= encoded.length) {
        throw const FormatException(
          'Ugyldig encoded polyline.',
        );
      }

      byte = encoded.codeUnitAt(index) - 63;
      index++;
      result |= (byte & 0x1F) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final value = (result & 1) != 0
        ? ~(result >> 1)
        : result >> 1;

    return _DecodedPolylineValue(
      value: value,
      nextIndex: index,
    );
  }

  int? _parseDurationSeconds(String? value) {
    if (value == null || !value.endsWith('s')) {
      return null;
    }

    final numericValue =
        value.substring(0, value.length - 1);

    return double.tryParse(numericValue)?.round();
  }
}


class _SuggestedRouteCandidate {
  const _SuggestedRouteCandidate({
    required this.route,
    required this.differenceMeters,
    required this.baseBearing,
  });

  final RouteResult route;
  final double differenceMeters;
  final double baseBearing;
}


class _DecodedPolylineValue {
  const _DecodedPolylineValue({
    required this.value,
    required this.nextIndex,
  });

  final int value;
  final int nextIndex;
}
