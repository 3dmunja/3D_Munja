import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../core/localization/app_text.dart';

enum VoiceCoachEvent {
  rideStarted,
  rideStopped,
  routeSelected,
  coachActivated,
  lowBattery,
  highSpeed,
  takingBreak,
  rideSaved,
}

class VoiceCoachService {
  VoiceCoachService._();

  static final VoiceCoachService instance = VoiceCoachService._();

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool enabled = true;

  Future<void> initialize() async {
    if (_initialized) return;

    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    await _setLanguageFromApp();

    _initialized = true;
  }

  Future<void> _setLanguageFromApp() async {
    final code = AppText.currentLocale.languageCode;

    switch (code) {
      case 'da':
        await _tts.setLanguage('da-DK');
        break;
      case 'bs':
        await _tts.setLanguage('bs-BA');
        break;
      case 'en':
        await _tts.setLanguage('en-US');
        break;
      default:
        await _tts.setLanguage('en-US');
    }
  }

  Future<void> speak(String text) async {
    if (!enabled || text.trim().isEmpty) return;

    try {
      await initialize();
      await _setLanguageFromApp();
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('VOICE COACH ERROR: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> speakEvent(VoiceCoachEvent event) async {
    final code = AppText.currentLocale.languageCode;

    final text = switch (event) {
      VoiceCoachEvent.rideStarted => _rideStarted(code),
      VoiceCoachEvent.rideStopped => _rideStopped(code),
      VoiceCoachEvent.routeSelected => _routeSelected(code),
      VoiceCoachEvent.coachActivated => _coachActivated(code),
      VoiceCoachEvent.lowBattery => _lowBattery(code),
      VoiceCoachEvent.highSpeed => _highSpeed(code),
      VoiceCoachEvent.takingBreak => _takingBreak(code),
      VoiceCoachEvent.rideSaved => _rideSaved(code),
    };

    await speak(text);
  }

  String _rideStarted(String code) {
    switch (code) {
      case 'da':
        return 'God tur. Munja tracking er startet.';
      case 'bs':
        return 'Sretna vožnja. Munja praćenje je pokrenuto.';
      default:
        return 'Have a good ride. Munja tracking has started.';
    }
  }

  String _rideStopped(String code) {
    switch (code) {
      case 'da':
        return 'Turen er stoppet.';
      case 'bs':
        return 'Vožnja je zaustavljena.';
      default:
        return 'Ride stopped.';
    }
  }

  String _routeSelected(String code) {
    switch (code) {
      case 'da':
        return 'Ruten er valgt og gemt.';
      case 'bs':
        return 'Ruta je odabrana i sačuvana.';
      default:
        return 'Route selected and saved.';
    }
  }

  String _coachActivated(String code) {
    switch (code) {
      case 'da':
        return 'AI coach er aktiveret.';
      case 'bs':
        return 'AI trener je aktiviran.';
      default:
        return 'AI coach activated.';
    }
  }

  String _lowBattery(String code) {
    switch (code) {
      case 'da':
        return 'Lavt batteri registreret.';
      case 'bs':
        return 'Detektovana je niska baterija.';
      default:
        return 'Low battery detected.';
    }
  }

  String _highSpeed(String code) {
    switch (code) {
      case 'da':
        return 'Høj hastighed. Husk at holde fokus.';
      case 'bs':
        return 'Velika brzina. Ostani fokusiran.';
      default:
        return 'High speed. Stay focused.';
    }
  }

  String _takingBreak(String code) {
    switch (code) {
      case 'da':
        return 'Du holder stille. Tag en kort pause hvis du har brug for det.';
      case 'bs':
        return 'Stojiš. Napravi kratku pauzu ako ti treba.';
      default:
        return 'You are standing still. Take a short break if needed.';
    }
  }

  String _rideSaved(String code) {
    switch (code) {
      case 'da':
        return 'Turen er gemt.';
      case 'bs':
        return 'Vožnja je sačuvana.';
      default:
        return 'Ride saved.';
    }
  }
}
