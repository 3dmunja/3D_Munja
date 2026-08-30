import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../Models/place_suggestion.dart';
import '../config/api_keys.dart';

class PlaceSearchException implements Exception {
  const PlaceSearchException(
    this.message, {
    this.statusCode,
    this.responseBody,
  });

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() {
    final codeText = statusCode == null ? '' : ' ($statusCode)';
    return 'PlaceSearchException$codeText: $message';
  }
}

class PlaceSearchService {
  PlaceSearchService._();

  static final PlaceSearchService instance = PlaceSearchService._();

  static const String _apiKey = ApiKeys.googleMaps;

  static const String _autocompleteEndpoint =
      'https://places.googleapis.com/v1/places:autocomplete';

  static const String _detailsEndpoint =
      'https://places.googleapis.com/v1/places';

  bool get hasApiKey => _apiKey.trim().isNotEmpty;

  Future<List<PlaceSuggestion>> search(
    String query, {
    String languageCode = 'da',
    String regionCode = 'DK',
  }) async {
    final normalizedQuery = query.trim();

    if (normalizedQuery.length < 2) {
      return const <PlaceSuggestion>[];
    }

    if (!hasApiKey) {
      debugPrint(
        'MUNJA PLACE SEARCH: GOOGLE_MAPS_API_KEY mangler. '
        'Bruger lokale testforslag.',
      );

      return _fallbackSuggestions(normalizedQuery);
    }

    final client = HttpClient();

    try {
      final request = await client.postUrl(
        Uri.parse(_autocompleteEndpoint),
      );

      request.headers.contentType = ContentType.json;
      request.headers.set('X-Goog-Api-Key', _apiKey);
      request.headers.set(
        'X-Goog-FieldMask',
        'suggestions.placePrediction.placeId,'
            'suggestions.placePrediction.text.text,'
            'suggestions.placePrediction.structuredFormat.mainText.text,'
            'suggestions.placePrediction.structuredFormat.secondaryText.text',
      );

      request.write(
        jsonEncode(
          <String, dynamic>{
            'input': normalizedQuery,
            'languageCode': languageCode,
            'regionCode': regionCode,
            'includedRegionCodes': <String>[regionCode],
          },
        ),
      );

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();

      debugPrint(
        'MUNJA GOOGLE PLACES AUTOCOMPLETE STATUS: '
        '${response.statusCode}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES AUTOCOMPLETE CONTENT-TYPE: '
        '${response.headers.contentType}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES AUTOCOMPLETE RAW LENGTH: '
        '${responseBody.length}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES AUTOCOMPLETE RAW RESPONSE: '
        '${_responsePreview(responseBody)}',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'MUNJA PLACE SEARCH ERROR '
          '${response.statusCode}: $responseBody',
        );

        throw PlaceSearchException(
          'Google Places Autocomplete returnerede en fejl.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final decoded = _decodeJsonObject(
        responseBody,
        operation: 'Google Places Autocomplete',
        statusCode: response.statusCode,
      );

      final rawSuggestions =
          decoded['suggestions'] as List<dynamic>? ?? const <dynamic>[];

      final suggestions = <PlaceSuggestion>[];

      for (final rawSuggestion in rawSuggestions) {
        if (rawSuggestion is! Map<String, dynamic>) {
          continue;
        }

        final prediction =
            rawSuggestion['placePrediction'] as Map<String, dynamic>?;

        if (prediction == null) {
          continue;
        }

        final placeId = prediction['placeId'] as String? ?? '';

        final structuredFormat =
            prediction['structuredFormat'] as Map<String, dynamic>?;

        final primaryText = _extractText(
          structuredFormat?['mainText'],
        );

        final secondaryText = _extractText(
          structuredFormat?['secondaryText'],
        );

        final fallbackText = _extractText(
          prediction['text'],
        );

        final resolvedPrimaryText = primaryText.isNotEmpty
            ? primaryText
            : fallbackText;

        if (placeId.isEmpty || resolvedPrimaryText.isEmpty) {
          continue;
        }

        suggestions.add(
          PlaceSuggestion(
            placeId: placeId,
            primaryText: resolvedPrimaryText,
            secondaryText: secondaryText,
          ),
        );
      }

      return suggestions.take(6).toList(growable: false);
    } on PlaceSearchException {
      rethrow;
    } on SocketException catch (error) {
      throw PlaceSearchException(
        'Kunne ikke forbinde til Google Places. '
        'Kontrollér internetforbindelsen.',
        responseBody: error.message,
      );
    } on FormatException catch (error) {
      throw PlaceSearchException(
        'Google Places returnerede ugyldige data.',
        responseBody: error.message,
      );
    } catch (error, stackTrace) {
      debugPrint('MUNJA PLACE SEARCH EXCEPTION: $error');
      debugPrint('$stackTrace');

      throw PlaceSearchException(
        'Der opstod en ukendt fejl under adressesøgningen.',
        responseBody: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<PlaceSuggestion> getDetails(
    PlaceSuggestion suggestion, {
    String languageCode = 'da',
  }) async {
    if (suggestion.hasCoordinates) {
      return suggestion;
    }

    if (!hasApiKey || suggestion.placeId.startsWith('fallback_')) {
      return suggestion;
    }

    final client = HttpClient();

    try {
      final encodedPlaceId = Uri.encodeComponent(suggestion.placeId);

      final uri = Uri.parse(
        '$_detailsEndpoint/$encodedPlaceId'
        '?languageCode=${Uri.encodeQueryComponent(languageCode)}',
      );

      final request = await client.getUrl(uri);

      request.headers.set('X-Goog-Api-Key', _apiKey);
      request.headers.set(
        'X-Goog-FieldMask',
        'id,displayName,formattedAddress,location',
      );

      final response = await request.close();
      final responseBody = await utf8.decoder.bind(response).join();

      debugPrint(
        'MUNJA GOOGLE PLACES DETAILS STATUS: '
        '${response.statusCode}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES DETAILS CONTENT-TYPE: '
        '${response.headers.contentType}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES DETAILS RAW LENGTH: '
        '${responseBody.length}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES DETAILS RAW RESPONSE: '
        '${_responsePreview(responseBody)}',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'MUNJA PLACE DETAILS ERROR '
          '${response.statusCode}: $responseBody',
        );

        throw PlaceSearchException(
          'Google Place Details returnerede en fejl.',
          statusCode: response.statusCode,
          responseBody: responseBody,
        );
      }

      final decoded = _decodeJsonObject(
        responseBody,
        operation: 'Google Place Details',
        statusCode: response.statusCode,
      );

      final location = decoded['location'] as Map<String, dynamic>?;

      final latitude = (location?['latitude'] as num?)?.toDouble();
      final longitude = (location?['longitude'] as num?)?.toDouble();

      final displayName = _extractText(decoded['displayName']);
      final formattedAddress =
          decoded['formattedAddress'] as String? ?? '';

      return suggestion.copyWith(
        primaryText: displayName.isNotEmpty
            ? displayName
            : suggestion.primaryText,
        secondaryText: formattedAddress.isNotEmpty
            ? formattedAddress
            : suggestion.secondaryText,
        latitude: latitude,
        longitude: longitude,
      );
    } on PlaceSearchException {
      rethrow;
    } on SocketException catch (error) {
      throw PlaceSearchException(
        'Kunne ikke hente adressens koordinater. '
        'Kontrollér internetforbindelsen.',
        responseBody: error.message,
      );
    } on FormatException catch (error) {
      throw PlaceSearchException(
        'Google Place Details returnerede ugyldige data.',
        responseBody: error.message,
      );
    } catch (error, stackTrace) {
      debugPrint('MUNJA PLACE DETAILS EXCEPTION: $error');
      debugPrint('$stackTrace');

      throw PlaceSearchException(
        'Der opstod en ukendt fejl ved hentning af adressen.',
        responseBody: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _decodeJsonObject(
    String responseBody, {
    required String operation,
    required int statusCode,
  }) {
    var safeBody = responseBody.trim();

    if (safeBody.startsWith('\uFEFF')) {
      safeBody = safeBody.substring(1).trimLeft();
    }

    if (safeBody.startsWith(")]}'")) {
      final newlineIndex = safeBody.indexOf('\n');

      safeBody = newlineIndex >= 0
          ? safeBody.substring(newlineIndex + 1).trim()
          : safeBody.substring(4).trim();
    }

    if (safeBody.isEmpty) {
      throw PlaceSearchException(
        '$operation returnerede et tomt svar.',
        statusCode: statusCode,
        responseBody: responseBody,
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(safeBody);
    } on FormatException catch (error) {
      debugPrint(
        'MUNJA GOOGLE PLACES JSON DECODE ERROR: '
        '${error.message}',
      );
      debugPrint(
        'MUNJA GOOGLE PLACES INVALID BODY: '
        '${_responsePreview(safeBody)}',
      );

      throw PlaceSearchException(
        '$operation returnerede ugyldig JSON.',
        statusCode: statusCode,
        responseBody: responseBody,
      );
    }

    debugPrint(
      'MUNJA GOOGLE PLACES DECODED TYPE: '
      '${decoded.runtimeType}',
    );
    debugPrint(
      'MUNJA GOOGLE PLACES DECODED VALUE: '
      '$decoded',
    );

    if (decoded is! Map) {
      throw PlaceSearchException(
        '$operation returnerede ikke et JSON-objekt.',
        statusCode: statusCode,
        responseBody: responseBody,
      );
    }

    return Map<String, dynamic>.from(decoded);
  }

  String _responsePreview(
    String value, {
    int maxLength = 4000,
  }) {
    final safeValue = value
        .replaceAll('\r', r'\r')
        .replaceAll('\n', r'\n');

    if (safeValue.length <= maxLength) {
      return safeValue;
    }

    return '${safeValue.substring(0, maxLength)}...';
  }

  String _extractText(dynamic value) {
    if (value is String) {
      return value.trim();
    }

    if (value is Map<String, dynamic>) {
      return (value['text'] as String? ?? '').trim();
    }

    return '';
  }

  List<PlaceSuggestion> _fallbackSuggestions(String query) {
    const places = <PlaceSuggestion>[
      PlaceSuggestion(
        placeId: 'fallback_odense_banegaard',
        primaryText: 'Odense Banegård Center',
        secondaryText: 'Østre Stationsvej 27, 5000 Odense C',
        latitude: 55.4019,
        longitude: 10.3877,
      ),
      PlaceSuggestion(
        placeId: 'fallback_odense_zoo',
        primaryText: 'Odense ZOO',
        secondaryText: 'Søndre Boulevard 306, 5000 Odense C',
        latitude: 55.3785,
        longitude: 10.3709,
      ),
      PlaceSuggestion(
        placeId: 'fallback_sdu',
        primaryText: 'Syddansk Universitet',
        secondaryText: 'Campusvej 55, 5230 Odense M',
        latitude: 55.3682,
        longitude: 10.4281,
      ),
      PlaceSuggestion(
        placeId: 'fallback_ouh',
        primaryText: 'Odense Universitetshospital',
        secondaryText: 'J.B. Winsløws Vej 4, 5000 Odense C',
        latitude: 55.3831,
        longitude: 10.3707,
      ),
      PlaceSuggestion(
        placeId: 'fallback_agedrup',
        primaryText: 'Agedrup',
        secondaryText: '5320 Agedrup',
        latitude: 55.4317,
        longitude: 10.4920,
      ),
      PlaceSuggestion(
        placeId: 'fallback_bullerup',
        primaryText: 'Bullerup',
        secondaryText: '5320 Agedrup',
        latitude: 55.4287,
        longitude: 10.4636,
      ),
      PlaceSuggestion(
        placeId: 'fallback_kerteminde',
        primaryText: 'Kerteminde',
        secondaryText: '5300 Kerteminde',
        latitude: 55.4497,
        longitude: 10.6570,
      ),
      PlaceSuggestion(
        placeId: 'fallback_nyborg',
        primaryText: 'Nyborg',
        secondaryText: '5800 Nyborg',
        latitude: 55.3127,
        longitude: 10.7896,
      ),
    ];

    final normalizedQuery = query.toLowerCase();

    return places
        .where(
          (place) =>
              place.primaryText.toLowerCase().contains(normalizedQuery) ||
              place.secondaryText.toLowerCase().contains(normalizedQuery),
        )
        .take(6)
        .toList(growable: false);
  }
}
