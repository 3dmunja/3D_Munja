class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    this.latitude,
    this.longitude,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
  final double? latitude;
  final double? longitude;

  String get fullText {
    final primary = primaryText.trim();
    final secondary = secondaryText.trim();

    if (secondary.isEmpty) {
      return primary;
    }

    if (primary.isEmpty) {
      return secondary;
    }

    return '$primary, $secondary';
  }

  bool get hasCoordinates {
    return latitude != null && longitude != null;
  }

  PlaceSuggestion copyWith({
    String? placeId,
    String? primaryText,
    String? secondaryText,
    double? latitude,
    double? longitude,
  }) {
    return PlaceSuggestion(
      placeId: placeId ?? this.placeId,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'placeId': placeId,
      'primaryText': primaryText,
      'secondaryText': secondaryText,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      placeId: json['placeId'] as String? ?? '',
      primaryText: json['primaryText'] as String? ?? '',
      secondaryText: json['secondaryText'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'PlaceSuggestion('
        'placeId: $placeId, '
        'primaryText: $primaryText, '
        'secondaryText: $secondaryText, '
        'latitude: $latitude, '
        'longitude: $longitude'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlaceSuggestion &&
            runtimeType == other.runtimeType &&
            placeId == other.placeId &&
            primaryText == other.primaryText &&
            secondaryText == other.secondaryText &&
            latitude == other.latitude &&
            longitude == other.longitude;
  }

  @override
  int get hashCode {
    return Object.hash(
      placeId,
      primaryText,
      secondaryText,
      latitude,
      longitude,
    );
  }
}
