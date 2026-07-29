enum MunjaProductType { brakeLight, unknown }

class MunjaDevice {
  final String id;
  final String name;
  final MunjaProductType type;
  final int rssi;
  final bool isNearby;
  final bool isSaved;

  const MunjaDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.rssi,
    required this.isNearby,
    required this.isSaved,
  });

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type.name};

  factory MunjaDevice.fromJson(Map<String, dynamic> json) {
    return MunjaDevice(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] == 'brakeLight'
          ? MunjaProductType.brakeLight
          : MunjaProductType.unknown,
      rssi: -100,
      isNearby: false,
      isSaved: true,
    );
  }
}
