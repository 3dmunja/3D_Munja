import 'navigation_instruction.dart';

enum VoiceNavigationLanguage {
  danish,
  english,
  bosnian,
}

enum VoiceInstructionStage {
  approach,
  prepare,
  now,
  arrival,
  offRoute,
  rerouting,
  routeReady,
}

class VoiceInstruction {
  const VoiceInstruction({
    required this.id,
    required this.routeId,
    required this.routePointIndex,
    required this.maneuver,
    required this.stage,
    required this.language,
    required this.text,
    required this.distanceMeters,
    required this.createdAt,
  });

  final String id;
  final String routeId;
  final int routePointIndex;
  final NavigationManeuver maneuver;
  final VoiceInstructionStage stage;
  final VoiceNavigationLanguage language;
  final String text;
  final double distanceMeters;
  final DateTime createdAt;

  bool get isArrival => stage == VoiceInstructionStage.arrival;
  bool get isImmediate => stage == VoiceInstructionStage.now;
  bool get isRouteWarning =>
      stage == VoiceInstructionStage.offRoute ||
      stage == VoiceInstructionStage.rerouting;

  VoiceInstruction copyWith({
    String? id,
    String? routeId,
    int? routePointIndex,
    NavigationManeuver? maneuver,
    VoiceInstructionStage? stage,
    VoiceNavigationLanguage? language,
    String? text,
    double? distanceMeters,
    DateTime? createdAt,
  }) {
    return VoiceInstruction(
      id: id ?? this.id,
      routeId: routeId ?? this.routeId,
      routePointIndex: routePointIndex ?? this.routePointIndex,
      maneuver: maneuver ?? this.maneuver,
      stage: stage ?? this.stage,
      language: language ?? this.language,
      text: text ?? this.text,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'routeId': routeId,
      'routePointIndex': routePointIndex,
      'maneuver': maneuver.name,
      'stage': stage.name,
      'language': language.name,
      'text': text,
      'distanceMeters': distanceMeters,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory VoiceInstruction.fromJson(Map<String, dynamic> json) {
    return VoiceInstruction(
      id: json['id'] as String? ?? '',
      routeId: json['routeId'] as String? ?? '',
      routePointIndex: (json['routePointIndex'] as num?)?.toInt() ?? 0,
      maneuver: NavigationManeuver.values.firstWhere(
        (value) => value.name == json['maneuver'],
        orElse: () => NavigationManeuver.continueStraight,
      ),
      stage: VoiceInstructionStage.values.firstWhere(
        (value) => value.name == json['stage'],
        orElse: () => VoiceInstructionStage.prepare,
      ),
      language: VoiceNavigationLanguage.values.firstWhere(
        (value) => value.name == json['language'],
        orElse: () => VoiceNavigationLanguage.danish,
      ),
      text: json['text'] as String? ?? '',
      distanceMeters: (json['distanceMeters'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(
            json['createdAt'] as String? ?? '',
          ) ??
          DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'VoiceInstruction('
        'id: $id, '
        'stage: ${stage.name}, '
        'maneuver: ${maneuver.name}, '
        'distance: ${distanceMeters.toStringAsFixed(0)} m, '
        'text: $text'
        ')';
  }
}
