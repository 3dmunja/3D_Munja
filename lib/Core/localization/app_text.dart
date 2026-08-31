import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bs.dart';
import 'da.dart';
import 'en.dart';

class AppText {
  static const String _languageKey = 'munja_language';

  static final ValueNotifier<Locale> localeNotifier = ValueNotifier<Locale>(
    const Locale('da'),
  );

  /// Understøttede sprog
  static const List<Locale> supportedLocales = [
    Locale('da'),
    Locale('en'),
    Locale('bs'),
  ];

  static Locale get currentLocale => localeNotifier.value;

  /// Indlæser gemt sprog ved app start
  static Future<void> loadSavedLocale() async {
    final sp = await SharedPreferences.getInstance();
    final code = sp.getString(_languageKey) ?? 'da';

    switch (code) {
      case 'da':
        localeNotifier.value = const Locale('da');
        break;
      case 'en':
        localeNotifier.value = const Locale('en');
        break;
      case 'bs':
        localeNotifier.value = const Locale('bs');
        break;
      default:
        localeNotifier.value = const Locale('da');
    }
  }

  /// Skift sprog og gem valget
  static Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode;

    if (!_isSupported(code)) return;

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_languageKey, code);

    localeNotifier.value = Locale(code);
  }

  /// Aktuelt sprogkode
  static String get currentLanguageCode => currentLocale.languageCode;

  /// Sprognavn til UI
  static String languageName(Locale locale) {
    switch (locale.languageCode) {
      case 'da':
        return 'Dansk';
      case 'en':
        return 'English';
      case 'bs':
        return 'Bosanski';
      default:
        return 'Dansk';
    }
  }

  /// Nuværende sprognavn
  static String get currentLanguageName => languageName(currentLocale);

  /// Kort flag til sprogvalg i login/onboarding.
  static String languageFlag(Locale locale) {
    switch (locale.languageCode) {
      case 'da':
        return '🇩🇰';
      case 'en':
        return '🇬🇧';
      case 'bs':
        return '🇧🇦';
      default:
        return '🌐';
    }
  }

  /// Tjek om sproget understøttes
  static bool _isSupported(String code) {
    return code == 'da' || code == 'en' || code == 'bs';
  }

  /// Oversættelse
  static String t(String key) {
    switch (currentLocale.languageCode) {
      case 'da':
        return da[key] ?? en[key] ?? _fallbackText(key);
      case 'bs':
        return bs[key] ?? en[key] ?? _fallbackText(key);
      case 'en':
        return en[key] ?? _fallbackText(key);
      default:
        return en[key] ?? _fallbackText(key);
    }
  }

  /// Midlertidig fallback, så appen ikke viser rå keys som "buildYourBike".
  /// De vigtigste keys skal stadig tilføjes i da.dart, en.dart og bs.dart senere.
  static String _fallbackText(String key) {
    final fallback = <String, String>{
      // General
      'home': 'Home',
      'ride': 'Ride',
      'garage': 'Garage',
      'gear': 'Gear',
      'profile': 'Profile',
      'goals': 'Goals',
      'active': 'Active',
      'inactive': 'Inactive',
      'ready': 'Ready',
      'live': 'Live',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'mounted': 'Mounted',
      'unknown': 'Unknown',
      'products': 'Products',
      'connection': 'Connection',
      'battery': 'Battery',
      'bluetooth': 'Bluetooth',
      'gps': 'GPS',
      'ble': 'BLE',
      'searching': 'Searching...',
      'connected': 'Connected',
      'distance': 'Distance',
      'speed': 'Speed',
      'time': 'Time',

      // Digital twin / garage
      'digitalTwin': 'Digital Twin',
      'digital_twin_ready': 'Digital Twin Ready',
      'buildYourBike': 'Build Your Bike',
      'buildYourBikeSubtitle':
          'Create your first digital bike and make it part of Munja.',
      'bikePhotos': 'Bike photos',
      'bikePhotosSubtitle':
          'Add up to 4 photos. Later AI will use these to improve your Digital Twin.',
      'bikePhotosHint':
          'Tip: take photos from left side, right side, front and rear.',
      'bikeIdentity': 'Bike identity',
      'bikeIdentitySubtitle': 'Name your bike and choose the basic type.',
      'bikeName': 'Bike name',
      'bikeType': 'Bike type',
      'frameColor': 'Frame color',
      'bikeComponents': 'Components',
      'bikeComponentsSubtitle': 'Choose the basic parts of the bike.',
      'bikeAccessories': 'Accessories',
      'bikeAccessoriesSubtitle': 'Select what is mounted on the bike.',
      'createBike': 'Create bike',
      'addBike': 'Add bike',
      'myBikes': 'My bikes',
      'bikes': 'Bikes',
      'activeBike': 'Active bike',
      'activate': 'Activate',
      'deleteBike': 'Delete bike',
      'deleteBikeConfirm': 'Are you sure you want to delete this bike?',
      'emptyGarage': 'Your garage is empty',
      'emptyGarageSubtitle': 'Add your first bike and create a Digital Twin.',
      'noBikePhotosYet': 'No bike photos yet.',
      'noProductsMounted': 'No products mounted yet.',
      'couldNotSaveBike': 'Could not save bike.',

      // Photos
      'photos': 'Photos',
      'camera': 'Camera',
      'gallery': 'Gallery',

      // Bike types
      'road': 'Road',
      'gravel': 'Gravel',
      'mtb': 'MTB',
      'city': 'City',
      'ebike': 'E-bike',
      'kidsMtb': 'Kids MTB',

      // Colors
      'black': 'Black',
      'blue': 'Blue',
      'green': 'Green',
      'red': 'Red',
      'white': 'White',
      'grey': 'Grey',
      'silver': 'Silver',
      'custom': 'Custom',

      // Components
      'wheelSize': 'Wheel size',
      'handlebar': 'Handlebar',
      'brakeType': 'Brake type',
      'gearType': 'Gear type',
      'dropHandlebar': 'Drop bar',
      'flatHandlebar': 'Flat bar',
      'riseHandlebar': 'Rise bar',
      'discBrake': 'Disc brake',
      'rimBrake': 'Rim brake',
      'coasterBrake': 'Coaster brake',
      'singleSpeed': 'Single speed',
      'internalHub': 'Internal hub',
      'externalDerailleur': 'External derailleur',

      // Accessories
      'mudguards': 'Mudguards',
      'kickstand': 'Kickstand',
      'bottleCage': 'Bottle cage',
      'rearLight': 'Rear light',
      'frontLight': 'Front light',
      'rearRack': 'Rear rack',
      'bell': 'Bell',

      // Product panel
      'smart_lighting_brake': 'Smart Lighting Brake',
      'night_mode': 'Night mode',
      'auto_brake': 'Auto brake',
      'visibilityBoost': 'Visibility boost',

      // Existing 3D widget keys that may appear
      'dragToRotate': 'Drag to rotate',
      'scanAndMountProducts': 'Scan and mount products',
      'digitalTwinProductStatus': 'Digital Twin product status',
    };

    return fallback[key] ?? _humanizeKey(key);
  }

  static String _humanizeKey(String key) {
    if (key.trim().isEmpty) return key;

    final spaced = key
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .trim();

    if (spaced.isEmpty) return key;

    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}
