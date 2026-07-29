enum BikeHotspotType {
  frame,
  fork,
  handlebar,
  saddle,
  frontWheel,
  rearWheel,
  drivetrain,
  battery,
  gps,
  smartLight,
  motor,
  display,
  other,
}

class BikeHotspot {
  const BikeHotspot({
    required this.id,
    required this.name,
    required this.type,
    required this.position,
    this.description = '',
    this.icon = '',
    this.productId = '',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String description;
  final BikeHotspotType type;

  /// x,y,z coordinates on the 3D bike model.
  final List<double> position;

  /// Optional icon name.
  final String icon;

  /// Linked BikeProduct id.
  final String productId;

  final bool enabled;

  BikeHotspot copyWith({
    String? id,
    String? name,
    String? description,
    BikeHotspotType? type,
    List<double>? position,
    String? icon,
    String? productId,
    bool? enabled,
  }) {
    return BikeHotspot(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      position: position ?? List<double>.from(this.position),
      icon: icon ?? this.icon,
      productId: productId ?? this.productId,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'position': position,
    'icon': icon,
    'productId': productId,
    'enabled': enabled,
  };

  factory BikeHotspot.fromMap(Map<String, dynamic> map) {
    return BikeHotspot(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      type: _typeFromString(map['type']?.toString() ?? ''),
      position: (map['position'] as List? ?? const [0.0, 0.0, 0.0])
          .map((e) => (e as num).toDouble())
          .toList(),
      icon: map['icon']?.toString() ?? '',
      productId: map['productId']?.toString() ?? '',
      enabled: map['enabled'] is bool ? map['enabled'] : true,
    );
  }
}

BikeHotspotType _typeFromString(String value) {
  for (final t in BikeHotspotType.values) {
    if (t.name == value) return t;
  }
  return BikeHotspotType.other;
}

const List<BikeHotspot> defaultBikeHotspots = [
  BikeHotspot(
    id: 'frame',
    name: 'Frame',
    type: BikeHotspotType.frame,
    position: [0.0, 0.45, 0.0],
  ),
  BikeHotspot(
    id: 'handlebar',
    name: 'Handlebar',
    type: BikeHotspotType.handlebar,
    position: [0.75, 0.95, 0.0],
  ),
  BikeHotspot(
    id: 'saddle',
    name: 'Saddle',
    type: BikeHotspotType.saddle,
    position: [-0.25, 0.95, 0.0],
  ),
  BikeHotspot(
    id: 'frontWheel',
    name: 'Front Wheel',
    type: BikeHotspotType.frontWheel,
    position: [1.05, 0.35, 0.0],
  ),
  BikeHotspot(
    id: 'rearWheel',
    name: 'Rear Wheel',
    type: BikeHotspotType.rearWheel,
    position: [-1.05, 0.35, 0.0],
  ),
  BikeHotspot(
    id: 'smartLight',
    name: 'Smart Brake Light',
    type: BikeHotspotType.smartLight,
    position: [-0.95, 0.82, 0.0],
    productId: 'smart_brake_light',
  ),
  BikeHotspot(
    id: 'gps',
    name: 'GPS',
    type: BikeHotspotType.gps,
    position: [0.55, 0.88, 0.0],
  ),
  BikeHotspot(
    id: 'battery',
    name: 'Battery',
    type: BikeHotspotType.battery,
    position: [0.0, 0.55, 0.0],
  ),
];
