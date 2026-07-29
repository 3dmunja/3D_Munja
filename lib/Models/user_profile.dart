class UserProfile {
  final String name;
  final int age;
  final String city;
  final int avatarIndex;
  final String? photoPath;

  const UserProfile({
    required this.name,
    required this.age,
    required this.city,
    required this.avatarIndex,
    this.photoPath,
  });

  String get firstLine {
    final hasName = name.trim().isNotEmpty;
    final hasAge = age > 0;

    if (hasName && hasAge) return '$name · $age yrs';
    if (hasName) return name;
    if (hasAge) return '$age yrs';

    return 'Rider';
  }

  String get secondLine {
    if (city.trim().isNotEmpty) return city;
    return 'Ready for the next ride';
  }
}
