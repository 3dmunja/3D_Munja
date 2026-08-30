import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../Models/navigation_instruction.dart';
import '../Models/voice_instruction.dart';

class VoiceNavigationService {
  VoiceNavigationService._();

  static final VoiceNavigationService instance =
      VoiceNavigationService._();

  static const double approachDistanceMeters = 220;
  static const double prepareDistanceMeters = 65;
  static const double nowDistanceMeters = 18;

  static const Duration minimumSpeechInterval =
      Duration(seconds: 2);

  final FlutterTts _tts = FlutterTts();

  final ValueNotifier<VoiceInstruction?> lastInstruction =
      ValueNotifier<VoiceInstruction?>(null);

  final Set<String> _spokenInstructionIds = <String>{};

  bool _initialized = false;
  bool _enabled = true;
  bool _speaking = false;

  String _routeId = '';
  VoiceNavigationLanguage _language =
      VoiceNavigationLanguage.danish;

  DateTime? _lastSpeechAt;
  int? _lastRoutePointIndex;

  bool get isEnabled => _enabled;
  bool get isSpeaking => _speaking;
  VoiceNavigationLanguage get language => _language;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      await _applyLanguage();

      _initialized = true;

      debugPrint(
        'VOICE NAVIGATION INITIALIZED: ${_language.name}',
      );
    } catch (error, stackTrace) {
      debugPrint('VOICE NAVIGATION INIT ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;

    if (!enabled) {
      await stop();
    }
  }

  Future<void> setLanguage(
    VoiceNavigationLanguage language,
  ) async {
    _language = language;

    if (_initialized) {
      await _applyLanguage();
    }
  }

  Future<void> setLanguageCode(String languageCode) async {
    final normalized = languageCode.trim().toLowerCase();

    if (normalized.startsWith('bs')) {
      await setLanguage(VoiceNavigationLanguage.bosnian);
      return;
    }

    if (normalized.startsWith('en')) {
      await setLanguage(VoiceNavigationLanguage.english);
      return;
    }

    await setLanguage(VoiceNavigationLanguage.danish);
  }

  Future<void> startRoute(String routeId) async {
    await initialize();

    final normalized = routeId.trim();

    if (_routeId == normalized && normalized.isNotEmpty) {
      return;
    }

    reset(routeId: normalized);
  }

  void reset({String routeId = ''}) {
    _routeId = routeId;
    _spokenInstructionIds.clear();
    _lastRoutePointIndex = null;
    _lastSpeechAt = null;
    lastInstruction.value = null;

    debugPrint('VOICE NAVIGATION RESET: route=$_routeId');
  }

  Future<VoiceInstruction?> handleInstruction({
    required NavigationInstruction instruction,
    required bool rideIsActive,
    String? routeId,
  }) async {
    if (!_enabled || !rideIsActive) {
      return null;
    }

    await initialize();

    final incomingRouteId = routeId?.trim();

    if (incomingRouteId != null &&
        incomingRouteId.isNotEmpty &&
        incomingRouteId != _routeId) {
      reset(routeId: incomingRouteId);
    }

    if (instruction.isArrival) {
      return _speakSpecial(
        stage: VoiceInstructionStage.arrival,
        maneuver: NavigationManeuver.arrive,
        text: _arrivalText(),
        routePointIndex: instruction.routePointIndex,
        distanceMeters: instruction.distanceToInstructionMeters,
      );
    }

    if (instruction.isOffRoute) {
      return _speakSpecial(
        stage: VoiceInstructionStage.offRoute,
        maneuver: NavigationManeuver.offRoute,
        text: _offRouteText(),
        routePointIndex: instruction.routePointIndex,
        distanceMeters: instruction.distanceToInstructionMeters,
      );
    }

    if (_lastRoutePointIndex != null &&
        instruction.routePointIndex != _lastRoutePointIndex) {
      _removeOldPointKeys(instruction.routePointIndex);
    }

    _lastRoutePointIndex = instruction.routePointIndex;

    final distance = instruction.distanceToInstructionMeters;
    VoiceInstructionStage? stage;

    if (distance <= nowDistanceMeters) {
      stage = VoiceInstructionStage.now;
    } else if (distance <= prepareDistanceMeters) {
      stage = VoiceInstructionStage.prepare;
    } else if (distance <= approachDistanceMeters) {
      stage = VoiceInstructionStage.approach;
    }

    if (stage == null) {
      return null;
    }

    final id = _instructionId(
      routePointIndex: instruction.routePointIndex,
      maneuver: instruction.maneuver,
      stage: stage,
    );

    if (_spokenInstructionIds.contains(id)) {
      return null;
    }

    final voiceInstruction = VoiceInstruction(
      id: id,
      routeId: _routeId,
      routePointIndex: instruction.routePointIndex,
      maneuver: instruction.maneuver,
      stage: stage,
      language: _language,
      text: _instructionText(
        maneuver: instruction.maneuver,
        stage: stage,
        distanceMeters: distance,
      ),
      distanceMeters: distance,
      createdAt: DateTime.now(),
    );

    await _speakInstruction(voiceInstruction);
    return voiceInstruction;
  }

  Future<VoiceInstruction?> announceRerouting({
    required bool rideIsActive,
  }) async {
    if (!_enabled || !rideIsActive) {
      return null;
    }

    await initialize();

    return _speakSpecial(
      stage: VoiceInstructionStage.rerouting,
      maneuver: NavigationManeuver.offRoute,
      text: _reroutingText(),
      routePointIndex: -1,
      distanceMeters: 0,
    );
  }

  Future<VoiceInstruction?> announceRouteReady({
    required bool rideIsActive,
  }) async {
    if (!_enabled || !rideIsActive) {
      return null;
    }

    await initialize();

    return _speakSpecial(
      stage: VoiceInstructionStage.routeReady,
      maneuver: NavigationManeuver.continueStraight,
      text: _routeReadyText(),
      routePointIndex: -1,
      distanceMeters: 0,
    );
  }

  Future<VoiceInstruction?> _speakSpecial({
    required VoiceInstructionStage stage,
    required NavigationManeuver maneuver,
    required String text,
    required int routePointIndex,
    required double distanceMeters,
  }) async {
    final id = _instructionId(
      routePointIndex: routePointIndex,
      maneuver: maneuver,
      stage: stage,
    );

    if (_spokenInstructionIds.contains(id)) {
      return null;
    }

    final instruction = VoiceInstruction(
      id: id,
      routeId: _routeId,
      routePointIndex: routePointIndex,
      maneuver: maneuver,
      stage: stage,
      language: _language,
      text: text,
      distanceMeters: distanceMeters,
      createdAt: DateTime.now(),
    );

    await _speakInstruction(instruction);
    return instruction;
  }

  Future<void> _speakInstruction(
    VoiceInstruction instruction,
  ) async {
    if (instruction.text.trim().isEmpty) {
      return;
    }

    final now = DateTime.now();

    if (_lastSpeechAt != null &&
        now.difference(_lastSpeechAt!) < minimumSpeechInterval) {
      return;
    }

    _spokenInstructionIds.add(instruction.id);
    lastInstruction.value = instruction;
    _lastSpeechAt = now;
    _speaking = true;

    try {
      await _tts.stop();
      await _applyLanguage();
      await _tts.speak(instruction.text);

      debugPrint('VOICE NAVIGATION SPOKE: $instruction');
    } catch (error, stackTrace) {
      _spokenInstructionIds.remove(instruction.id);
      debugPrint('VOICE NAVIGATION SPEAK ERROR: $error');
      debugPrint('$stackTrace');
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('VOICE NAVIGATION STOP ERROR: $error');
    } finally {
      _speaking = false;
    }
  }

  Future<void> _applyLanguage() async {
    final locale = switch (_language) {
      VoiceNavigationLanguage.danish => 'da-DK',
      VoiceNavigationLanguage.english => 'en-US',
      VoiceNavigationLanguage.bosnian => 'bs-BA',
    };

    try {
      final available = await _tts.isLanguageAvailable(locale);

      if (available == true || available == 1) {
        await _tts.setLanguage(locale);
        return;
      }

      if (_language == VoiceNavigationLanguage.bosnian) {
        await _tts.setLanguage('hr-HR');
        return;
      }

      await _tts.setLanguage('en-US');
    } catch (error) {
      debugPrint('VOICE NAVIGATION LANGUAGE ERROR: $error');
    }
  }

  void _removeOldPointKeys(int activePointIndex) {
    _spokenInstructionIds.removeWhere((key) {
      if (!key.startsWith('$_routeId|')) {
        return false;
      }

      final parts = key.split('|');

      if (parts.length < 4) {
        return false;
      }

      final pointIndex = int.tryParse(parts[1]);

      return pointIndex != null &&
          pointIndex < activePointIndex - 2;
    });
  }

  String _instructionId({
    required int routePointIndex,
    required NavigationManeuver maneuver,
    required VoiceInstructionStage stage,
  }) {
    return '$_routeId|$routePointIndex|${maneuver.name}|${stage.name}';
  }

  String _instructionText({
    required NavigationManeuver maneuver,
    required VoiceInstructionStage stage,
    required double distanceMeters,
  }) {
    final maneuverText = _maneuverText(maneuver);

    switch (_language) {
      case VoiceNavigationLanguage.danish:
        if (stage == VoiceInstructionStage.now) {
          return _danishNowText(maneuver);
        }
        return 'Om ${_roundedDistance(distanceMeters)} meter, '
            '$maneuverText.';

      case VoiceNavigationLanguage.english:
        if (stage == VoiceInstructionStage.now) {
          return _englishNowText(maneuver);
        }
        return 'In ${_roundedDistance(distanceMeters)} meters, '
            '$maneuverText.';

      case VoiceNavigationLanguage.bosnian:
        if (stage == VoiceInstructionStage.now) {
          return _bosnianNowText(maneuver);
        }
        return 'Za ${_roundedDistance(distanceMeters)} metara, '
            '$maneuverText.';
    }
  }

  String _maneuverText(NavigationManeuver maneuver) {
    switch (_language) {
      case VoiceNavigationLanguage.danish:
        return switch (maneuver) {
          NavigationManeuver.start => 'start turen',
          NavigationManeuver.continueStraight => 'fortsæt ligeud',
          NavigationManeuver.slightLeft => 'hold let til venstre',
          NavigationManeuver.left => 'drej til venstre',
          NavigationManeuver.sharpLeft => 'drej skarpt til venstre',
          NavigationManeuver.slightRight => 'hold let til højre',
          NavigationManeuver.right => 'drej til højre',
          NavigationManeuver.sharpRight => 'drej skarpt til højre',
          NavigationManeuver.uTurn => 'vend om',
          NavigationManeuver.arrive => 'du er fremme',
          NavigationManeuver.offRoute => 'du er kørt fra ruten',
        };

      case VoiceNavigationLanguage.english:
        return switch (maneuver) {
          NavigationManeuver.start => 'start the ride',
          NavigationManeuver.continueStraight => 'continue straight',
          NavigationManeuver.slightLeft => 'keep slightly left',
          NavigationManeuver.left => 'turn left',
          NavigationManeuver.sharpLeft => 'make a sharp left',
          NavigationManeuver.slightRight => 'keep slightly right',
          NavigationManeuver.right => 'turn right',
          NavigationManeuver.sharpRight => 'make a sharp right',
          NavigationManeuver.uTurn => 'make a U-turn',
          NavigationManeuver.arrive => 'you have arrived',
          NavigationManeuver.offRoute => 'you are off route',
        };

      case VoiceNavigationLanguage.bosnian:
        return switch (maneuver) {
          NavigationManeuver.start => 'započnite vožnju',
          NavigationManeuver.continueStraight => 'nastavite pravo',
          NavigationManeuver.slightLeft => 'držite se blago lijevo',
          NavigationManeuver.left => 'skrenite lijevo',
          NavigationManeuver.sharpLeft => 'skrenite oštro lijevo',
          NavigationManeuver.slightRight => 'držite se blago desno',
          NavigationManeuver.right => 'skrenite desno',
          NavigationManeuver.sharpRight => 'skrenite oštro desno',
          NavigationManeuver.uTurn => 'okrenite se',
          NavigationManeuver.arrive => 'stigli ste',
          NavigationManeuver.offRoute => 'skrenuli ste sa rute',
        };
    }
  }

  String _danishNowText(NavigationManeuver maneuver) {
    return switch (maneuver) {
      NavigationManeuver.continueStraight => 'Fortsæt ligeud nu.',
      NavigationManeuver.slightLeft => 'Hold let til venstre nu.',
      NavigationManeuver.left => 'Drej til venstre nu.',
      NavigationManeuver.sharpLeft => 'Drej skarpt til venstre nu.',
      NavigationManeuver.slightRight => 'Hold let til højre nu.',
      NavigationManeuver.right => 'Drej til højre nu.',
      NavigationManeuver.sharpRight => 'Drej skarpt til højre nu.',
      NavigationManeuver.uTurn => 'Vend om nu.',
      _ => '${_maneuverText(maneuver)} nu.',
    };
  }

  String _englishNowText(NavigationManeuver maneuver) {
    return switch (maneuver) {
      NavigationManeuver.continueStraight => 'Continue straight now.',
      NavigationManeuver.slightLeft => 'Keep slightly left now.',
      NavigationManeuver.left => 'Turn left now.',
      NavigationManeuver.sharpLeft => 'Make a sharp left now.',
      NavigationManeuver.slightRight => 'Keep slightly right now.',
      NavigationManeuver.right => 'Turn right now.',
      NavigationManeuver.sharpRight => 'Make a sharp right now.',
      NavigationManeuver.uTurn => 'Make a U-turn now.',
      _ => '${_maneuverText(maneuver)} now.',
    };
  }

  String _bosnianNowText(NavigationManeuver maneuver) {
    return switch (maneuver) {
      NavigationManeuver.continueStraight => 'Nastavite pravo sada.',
      NavigationManeuver.slightLeft => 'Držite se blago lijevo sada.',
      NavigationManeuver.left => 'Skrenite lijevo sada.',
      NavigationManeuver.sharpLeft => 'Skrenite oštro lijevo sada.',
      NavigationManeuver.slightRight => 'Držite se blago desno sada.',
      NavigationManeuver.right => 'Skrenite desno sada.',
      NavigationManeuver.sharpRight => 'Skrenite oštro desno sada.',
      NavigationManeuver.uTurn => 'Okrenite se sada.',
      _ => '${_maneuverText(maneuver)} sada.',
    };
  }

  int _roundedDistance(double meters) {
    if (meters <= 25) {
      return 20;
    }

    if (meters <= 75) {
      return (meters / 10).round() * 10;
    }

    return (meters / 50).round() * 50;
  }

  String _arrivalText() {
    return switch (_language) {
      VoiceNavigationLanguage.danish =>
        'Du er ankommet til din destination.',
      VoiceNavigationLanguage.english =>
        'You have arrived at your destination.',
      VoiceNavigationLanguage.bosnian =>
        'Stigli ste na odredište.',
    };
  }

  String _offRouteText() {
    return switch (_language) {
      VoiceNavigationLanguage.danish => 'Du er kørt fra ruten.',
      VoiceNavigationLanguage.english => 'You are off route.',
      VoiceNavigationLanguage.bosnian => 'Skrenuli ste sa rute.',
    };
  }

  String _reroutingText() {
    return switch (_language) {
      VoiceNavigationLanguage.danish => 'Genberegner ruten.',
      VoiceNavigationLanguage.english => 'Recalculating the route.',
      VoiceNavigationLanguage.bosnian => 'Ponovo izračunavam rutu.',
    };
  }

  String _routeReadyText() {
    return switch (_language) {
      VoiceNavigationLanguage.danish => 'Den nye rute er klar.',
      VoiceNavigationLanguage.english => 'The new route is ready.',
      VoiceNavigationLanguage.bosnian => 'Nova ruta je spremna.',
    };
  }

  void dispose() {
    _tts.stop();
    lastInstruction.dispose();
  }
}
