enum BikeType { road, gravel, mtb, city, ebike, kidsMtb }

enum BikeFrameColor { black, blue, green, red, white, grey, silver, custom }

enum BikeHandlebarType { drop, flat, rise, unknown }

enum BikeBrakeType { disc, rim, coaster, unknown }

enum BikeGearType { singleSpeed, internalHub, externalDerailleur, unknown }

enum BikeWheelSize { inch20, inch24, inch26, inch275, inch29, c700, unknown }

class BikeProfile {
  final String id;
  final String name;
  final BikeType type;
  final BikeFrameColor frameColor;
  final String? customFrameColorHex;
  final BikeHandlebarType handlebarType;
  final BikeBrakeType brakeType;
  final BikeGearType gearType;
  final BikeWheelSize wheelSize;
  final bool hasMudguards;
  final bool hasKickstand;
  final bool hasBottleCage;
  final bool hasRearLight;
  final bool hasFrontLight;
  final bool hasRearRack;
  final bool hasBell;
  final List<String> photoPaths;
  final String modelPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BikeProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.frameColor,
    this.customFrameColorHex,
    required this.handlebarType,
    required this.brakeType,
    required this.gearType,
    required this.wheelSize,
    required this.hasMudguards,
    required this.hasKickstand,
    required this.hasBottleCage,
    required this.hasRearLight,
    required this.hasFrontLight,
    required this.hasRearRack,
    required this.hasBell,
    required this.photoPaths,
    required this.modelPath,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BikeProfile.kidsMtbPrototype({List<String> photoPaths = const []}) {
    final now = DateTime.now();

    return BikeProfile(
      id: 'kids_mtb_prototype',
      name: 'Kids MTB',
      type: BikeType.kidsMtb,
      frameColor: BikeFrameColor.blue,
      handlebarType: BikeHandlebarType.flat,
      brakeType: BikeBrakeType.rim,
      gearType: BikeGearType.externalDerailleur,
      wheelSize: BikeWheelSize.inch24,
      hasMudguards: true,
      hasKickstand: true,
      hasBottleCage: true,
      hasRearLight: true,
      hasFrontLight: false,
      hasRearRack: false,
      hasBell: false,
      photoPaths: photoPaths,
      modelPath: 'assets/models/munja_bike.glb',
      createdAt: now,
      updatedAt: now,
    );
  }

  BikeProfile copyWith({
    String? id,
    String? name,
    BikeType? type,
    BikeFrameColor? frameColor,
    String? customFrameColorHex,
    BikeHandlebarType? handlebarType,
    BikeBrakeType? brakeType,
    BikeGearType? gearType,
    BikeWheelSize? wheelSize,
    bool? hasMudguards,
    bool? hasKickstand,
    bool? hasBottleCage,
    bool? hasRearLight,
    bool? hasFrontLight,
    bool? hasRearRack,
    bool? hasBell,
    List<String>? photoPaths,
    String? modelPath,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return BikeProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      frameColor: frameColor ?? this.frameColor,
      customFrameColorHex: customFrameColorHex ?? this.customFrameColorHex,
      handlebarType: handlebarType ?? this.handlebarType,
      brakeType: brakeType ?? this.brakeType,
      gearType: gearType ?? this.gearType,
      wheelSize: wheelSize ?? this.wheelSize,
      hasMudguards: hasMudguards ?? this.hasMudguards,
      hasKickstand: hasKickstand ?? this.hasKickstand,
      hasBottleCage: hasBottleCage ?? this.hasBottleCage,
      hasRearLight: hasRearLight ?? this.hasRearLight,
      hasFrontLight: hasFrontLight ?? this.hasFrontLight,
      hasRearRack: hasRearRack ?? this.hasRearRack,
      hasBell: hasBell ?? this.hasBell,
      photoPaths: photoPaths ?? this.photoPaths,
      modelPath: modelPath ?? this.modelPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'frameColor': frameColor.name,
      'customFrameColorHex': customFrameColorHex,
      'handlebarType': handlebarType.name,
      'brakeType': brakeType.name,
      'gearType': gearType.name,
      'wheelSize': wheelSize.name,
      'hasMudguards': hasMudguards,
      'hasKickstand': hasKickstand,
      'hasBottleCage': hasBottleCage,
      'hasRearLight': hasRearLight,
      'hasFrontLight': hasFrontLight,
      'hasRearRack': hasRearRack,
      'hasBell': hasBell,
      'photoPaths': photoPaths,
      'modelPath': modelPath,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory BikeProfile.fromJson(Map<String, dynamic> json) {
    return BikeProfile(
      id: json['id'] as String? ?? 'unknown_bike',
      name: json['name'] as String? ?? 'Bike',
      type: _enumFromName(
        BikeType.values,
        json['type'] as String?,
        BikeType.kidsMtb,
      ),
      frameColor: _enumFromName(
        BikeFrameColor.values,
        json['frameColor'] as String?,
        BikeFrameColor.blue,
      ),
      customFrameColorHex: json['customFrameColorHex'] as String?,
      handlebarType: _enumFromName(
        BikeHandlebarType.values,
        json['handlebarType'] as String?,
        BikeHandlebarType.flat,
      ),
      brakeType: _enumFromName(
        BikeBrakeType.values,
        json['brakeType'] as String?,
        BikeBrakeType.unknown,
      ),
      gearType: _enumFromName(
        BikeGearType.values,
        json['gearType'] as String?,
        BikeGearType.unknown,
      ),
      wheelSize: _enumFromName(
        BikeWheelSize.values,
        json['wheelSize'] as String?,
        BikeWheelSize.unknown,
      ),
      hasMudguards: json['hasMudguards'] as bool? ?? false,
      hasKickstand: json['hasKickstand'] as bool? ?? false,
      hasBottleCage: json['hasBottleCage'] as bool? ?? false,
      hasRearLight: json['hasRearLight'] as bool? ?? false,
      hasFrontLight: json['hasFrontLight'] as bool? ?? false,
      hasRearRack: json['hasRearRack'] as bool? ?? false,
      hasBell: json['hasBell'] as bool? ?? false,
      photoPaths: (json['photoPaths'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      modelPath: json['modelPath'] as String? ?? 'assets/models/munja_bike.glb',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static T _enumFromName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    if (name == null) return fallback;

    for (final value in values) {
      if (value.name == name) return value;
    }

    return fallback;
  }
}
