import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/munja_device.dart';
import '../models/trip.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../widgets/digital_twin/digital_twin.dart';

import 'ride_analytics_screen.dart';
import 'ride_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController ageCtrl = TextEditingController();
  final TextEditingController cityCtrl = TextEditingController();

  final ImagePicker _imagePicker = ImagePicker();

  bool loading = true;
  bool signingOut = false;

  String? photoPath;

  List<Trip> trips = [];
  List<MunjaDevice> savedDevices = [];

  static const double bottomWheelSafePadding = 360;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    cityCtrl.dispose();
    super.dispose();
  }

  String t(String key) => AppText.t(key);

  String get _accountTitle {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Account';
      case 'bs':
        return 'Korisnički račun';
      default:
        return 'Konto';
    }
  }

  String get _accountSubtitle {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Manage your Munja login.';
      case 'bs':
        return 'Upravljaj svojom Munja prijavom.';
      default:
        return 'Administrer dit Munja-login.';
    }
  }

  String get _signOutText {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Sign out';
      case 'bs':
        return 'Odjavi se';
      default:
        return 'Log ud';
    }
  }

  String get _signOutDescription {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'You will return to the login screen.';
      case 'bs':
        return 'Vratit ćeš se na ekran za prijavu.';
      default:
        return 'Du vender tilbage til login-skærmen.';
    }
  }

  String get _signOutDialogTitle {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Sign out of Munja?';
      case 'bs':
        return 'Odjaviti se iz Munja aplikacije?';
      default:
        return 'Log ud af Munja?';
    }
  }

  String get _signOutDialogMessage {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Your local rides and settings stay on this device.';
      case 'bs':
        return 'Tvoje lokalne vožnje i postavke ostaju na ovom uređaju.';
      default:
        return 'Dine lokale ture og indstillinger bliver på denne enhed.';
    }
  }

  String get _cancelText {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Cancel';
      case 'bs':
        return 'Odustani';
      default:
        return 'Annuller';
    }
  }

  String get _signOutFailedText {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'Sign out failed. Please try again.';
      case 'bs':
        return 'Odjava nije uspjela. Pokušaj ponovo.';
      default:
        return 'Log ud mislykkedes. Prøv igen.';
    }
  }

  Future<void> _confirmSignOut() async {
    if (signingOut) return;

    HapticFeedback.selectionClick();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MunjaColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          title: Text(
            _signOutDialogTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            _signOutDialogMessage,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_cancelText),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: MunjaColors.danger,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.logout_rounded),
              label: Text(
                _signOutText,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await _signOut();
  }

  Future<void> _signOut() async {
    if (signingOut) return;

    setState(() {
      signingOut = true;
    });

    try {
      await AuthService.instance.signOut();
    } catch (error) {
      debugPrint('PROFILE SIGN OUT ERROR: $error');

      if (!mounted) return;

      setState(() {
        signingOut = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_signOutFailedText),
          backgroundColor: MunjaColors.danger,
        ),
      );
    }
  }

  Future<void> _load() async {
    final profile = await StorageService.loadUserProfile();
    final loadedTrips = await StorageService.loadTrips();
    final devices = await StorageService.loadSavedDevices();

    if (!mounted) return;

    setState(() {
      nameCtrl.text = profile.name;
      ageCtrl.text = profile.age > 0 ? '${profile.age}' : '';
      cityCtrl.text = profile.city;
      photoPath = profile.photoPath;
      trips = loadedTrips;
      savedDevices = devices;
      loading = false;
    });
  }

  Future<void> _save() async {
    final profile = UserProfile(
      name: nameCtrl.text.trim().isEmpty ? 'Munja' : nameCtrl.text.trim(),
      age: int.tryParse(ageCtrl.text.trim()) ?? 0,
      city: cityCtrl.text.trim().isEmpty ? 'Copenhagen' : cityCtrl.text.trim(),
      avatarIndex: 0,
      photoPath: photoPath,
    );

    await StorageService.saveUserProfile(profile);

    if (!mounted) return;

    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('profileSaved')),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    await _load();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (picked == null) return;

      await StorageService.saveUserPhotoPath(picked.path);

      if (!mounted) return;

      setState(() {
        photoPath = picked.path;
      });

      HapticFeedback.selectionClick();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('profilePhotoSaved')),
          backgroundColor: MunjaColors.panel,
        ),
      );
    } catch (e) {
      debugPrint('PROFILE PHOTO PICK ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t('photoUploadFailed')),
          backgroundColor: MunjaColors.panel,
        ),
      );
    }
  }

  Future<void> _removePhoto() async {
    await StorageService.clearUserPhotoPath();

    if (!mounted) return;

    setState(() {
      photoPath = null;
    });

    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t('profilePhotoRemoved')),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  void _showPhotoPicker() {
    HapticFeedback.selectionClick();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MunjaColors.panel,
      barrierColor: Colors.black.withOpacity(0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  t('profilePhoto'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t('profilePhotoSubtitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                _PhotoSheetButton(
                  icon: Icons.photo_library_rounded,
                  title: t('chooseFromGallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 10),
                _PhotoSheetButton(
                  icon: Icons.photo_camera_rounded,
                  title: t('takePhoto'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.camera);
                  },
                ),
                if (photoPath != null && photoPath!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _PhotoSheetButton(
                    icon: Icons.delete_outline_rounded,
                    title: t('removePhoto'),
                    danger: true,
                    onTap: () {
                      Navigator.pop(context);
                      _removePhoto();
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  double get totalKm {
    return trips.fold<double>(0, (sum, trip) => sum + (trip.distanceM / 1000));
  }

  int get level {
    return ((totalKm / 25).floor() + 1).clamp(1, 99);
  }

  int get xp {
    return ((totalKm * 10) + trips.length * 45).round();
  }

  int get xpForNextLevel {
    return level * 350;
  }

  int get streakDays {
    if (trips.isEmpty) return 0;

    final days = trips
        .map((trip) {
          final d = DateTime.fromMillisecondsSinceEpoch(trip.startedAtMs);
          return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch;
        })
        .toSet()
        .length;

    return days.clamp(0, 99);
  }

  String get riderName {
    final text = nameCtrl.text.trim();
    if (text.isEmpty) return 'Munja';
    return text;
  }

  String get riderSubtitle {
    final city = cityCtrl.text.trim();
    if (city.isEmpty) return t('digitalRider');
    return '$city ${t('rider')}';
  }

  bool get hasBrakeLight {
    return savedDevices.any(
      (device) => device.type == MunjaProductType.brakeLight,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(child: CircularProgressIndicator(color: MunjaColors.mint)),
      );
    }

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: MunjaColors.mint,
          backgroundColor: MunjaColors.panel,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              bottomWheelSafePadding,
            ),
            children: [
              _Header(title: t('digitalRider')),

              const SizedBox(height: 18),

              _RiderHeroCard(
                name: riderName,
                subtitle: riderSubtitle,
                level: level,
                xp: xp,
                xpForNextLevel: xpForNextLevel,
                totalKm: totalKm,
                streakDays: streakDays,
                rides: trips.length,
                photoPath: photoPath,
                onUploadPhoto: _showPhotoPicker,
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('myBike'),
                subtitle: t('digitalTwinProductStatus'),
                child: Column(
                  children: [
                    SizedBox(
                      height: 250,
                      child: DigitalTwin(
                        isLive: false,
                        brakeLightConnected: hasBrakeLight,
                        brakeLightBattery: hasBrakeLight ? 82 : 64,
                        onBikeTap: () {},
                        onBrakeLightTap: () {},
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStatusPill(
                            icon: Icons.bluetooth_rounded,
                            label: 'BLE',
                            value: hasBrakeLight ? t('active') : t('off'),
                            active: hasBrakeLight,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _MiniStatusPill(
                            icon: Icons.battery_charging_full_rounded,
                            label: t('battery'),
                            value: hasBrakeLight ? '82%' : '64%',
                            active: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('ridesHistory'),
                subtitle: t('ridesHistorySubtitle'),
                child: Column(
                  children: [
                    _ActionTile(
                      icon: Icons.history_rounded,
                      title: t('rideHistory'),
                      subtitle:
                          '${trips.length} ${t('savedRides')} · ${totalKm.toStringAsFixed(1)} km',
                      onTap: () => _openScreen(const RideHistoryScreen()),
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: Icons.insights_rounded,
                      title: t('analytics'),
                      subtitle: t('analyticsSubtitle'),
                      onTap: () => _openScreen(const RideAnalyticsScreen()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('myProducts'),
                subtitle: t('myProductsSubtitle'),
                child: Column(
                  children: [
                    _ProductRow(
                      title: 'Smart Lighting Brake',
                      subtitle: hasBrakeLight
                          ? '${t('connected')} · ${t('battery')} 82%'
                          : t('notInstalled'),
                      icon: Icons.light_mode_rounded,
                      active: hasBrakeLight,
                    ),
                    const SizedBox(height: 10),
                    _ProductRow(
                      title: 'Smart Helmet',
                      subtitle: t('notInstalled'),
                      icon: Icons.health_and_safety_rounded,
                      active: false,
                    ),
                    const SizedBox(height: 10),
                    _ProductRow(
                      title: 'Munja Band',
                      subtitle: t('notInstalled'),
                      icon: Icons.watch_rounded,
                      active: false,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('profile'),
                subtitle: t('profileSimpleSubtitle'),
                child: Column(
                  children: [
                    _PremiumTextField(
                      controller: nameCtrl,
                      label: t('name'),
                      icon: Icons.person_rounded,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    _PremiumTextField(
                      controller: ageCtrl,
                      label: t('age'),
                      icon: Icons.cake_rounded,
                      keyboardType: TextInputType.number,
                      digitsOnly: true,
                    ),
                    const SizedBox(height: 12),
                    _PremiumTextField(
                      controller: cityCtrl,
                      label: t('city'),
                      icon: Icons.location_city_rounded,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_rounded),
                        label: Text(
                          t('saveProfile'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: t('language'),
                subtitle: t('languageSubtitle'),
                child: Row(
                  children: [
                    Expanded(
                      child: _LanguageButton(
                        label: 'Dansk',
                        code: 'DA',
                        active: AppText.currentLocale.languageCode == 'da',
                        onTap: () async {
                          await AppText.setLocale(const Locale('da'));
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LanguageButton(
                        label: 'English',
                        code: 'EN',
                        active: AppText.currentLocale.languageCode == 'en',
                        onTap: () async {
                          await AppText.setLocale(const Locale('en'));
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LanguageButton(
                        label: 'Bosanski',
                        code: 'BS',
                        active: AppText.currentLocale.languageCode == 'bs',
                        onTap: () async {
                          await AppText.setLocale(const Locale('bs'));
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _SectionCard(
                title: _accountTitle,
                subtitle: _accountSubtitle,
                child: _SignOutButton(
                  title: _signOutText,
                  subtitle: _signOutDescription,
                  loading: signingOut,
                  onTap: _confirmSignOut,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool loading;
  final VoidCallback onTap;

  const _SignOutButton({
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MunjaColors.danger.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: MunjaColors.danger.withValues(alpha: 0.28),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MunjaColors.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: MunjaColors.danger,
                        ),
                      )
                    : const Icon(
                        Icons.logout_rounded,
                        color: MunjaColors.danger,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!loading)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: MunjaColors.danger,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhotoSheetButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;

  const _PhotoSheetButton({
    required this.icon,
    required this.title,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? MunjaColors.danger : MunjaColors.mint;

    return Material(
      color: danger
          ? MunjaColors.danger.withOpacity(0.10)
          : MunjaColors.mint.withOpacity(0.11),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: danger ? Colors.white70 : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color.withOpacity(0.75)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;

  const _Header({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.auto_awesome_rounded,
          color: MunjaColors.mint,
          size: 24,
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 34,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
      ],
    );
  }
}

class _RiderHeroCard extends StatelessWidget {
  final String name;
  final String subtitle;
  final int level;
  final int xp;
  final int xpForNextLevel;
  final double totalKm;
  final int streakDays;
  final int rides;
  final String? photoPath;
  final VoidCallback onUploadPhoto;

  const _RiderHeroCard({
    required this.name,
    required this.subtitle,
    required this.level,
    required this.xp,
    required this.xpForNextLevel,
    required this.totalKm,
    required this.streakDays,
    required this.rides,
    required this.photoPath,
    required this.onUploadPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final progress = xpForNextLevel <= 0
        ? 0.0
        : (xp / xpForNextLevel).clamp(0.0, 1.0);

    final photoFile = photoPath == null || photoPath!.trim().isEmpty
        ? null
        : File(photoPath!);

    final hasPhoto = photoFile != null && photoFile.existsSync();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _premiumDecoration(glow: true),
      child: Column(
        children: [
          GestureDetector(
            onTap: onUploadPhoto,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 142,
                  height: 142,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        MunjaColors.mint.withOpacity(0.30),
                        MunjaColors.mint.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: MunjaColors.mint.withOpacity(0.28),
                        blurRadius: 42,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 118,
                  height: 118,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.26),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: MunjaColors.mint.withOpacity(0.48),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: hasPhoto
                      ? Image.file(photoFile, fit: BoxFit.cover)
                      : const Center(
                          child: Icon(
                            Icons.person_rounded,
                            size: 58,
                            color: MunjaColors.mint,
                          ),
                        ),
                ),
                Positioned(
                  right: 5,
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: MunjaColors.mint,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'LVL $level',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  bottom: 18,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1713),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: MunjaColors.mint.withOpacity(0.55),
                      ),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      color: MunjaColors.mint,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(MunjaColors.mint),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$xp / $xpForNextLevel XP',
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  value: totalKm.toStringAsFixed(1),
                  label: 'km',
                  icon: Icons.route_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  value: '$streakDays',
                  label: AppText.t('streak'),
                  icon: Icons.local_fire_department_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  value: '$rides',
                  label: AppText.t('rides'),
                  icon: Icons.flag_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onUploadPhoto,
              icon: const Icon(Icons.add_a_photo_rounded),
              label: Text(
                hasPhoto
                    ? AppText.t('changePhoto')
                    : AppText.t('uploadOwnPhoto'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;

  const _HeroMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _premiumDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.16),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: MunjaColors.mint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool active;

  const _ProductRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.12)
            : Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.44)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: active ? MunjaColors.mint : Colors.white38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Text(
            active
                ? AppText.t('active').toUpperCase()
                : AppText.t('off').toUpperCase(),
            style: TextStyle(
              color: active ? MunjaColors.mint : Colors.white30,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool active;

  const _MiniStatusPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.12)
            : Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.34)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? MunjaColors.mint : Colors.white38,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: active ? MunjaColors.mint : Colors.white38,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool digitsOnly;
  final ValueChanged<String>? onChanged;

  const _PremiumTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.digitsOnly = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      onChanged: onChanged,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  final String label;
  final String code;
  final bool active;
  final VoidCallback onTap;

  const _LanguageButton({
    required this.label,
    required this.code,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 62,
        decoration: BoxDecoration(
          color: active
              ? MunjaColors.mint.withOpacity(0.18)
              : Colors.black.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? MunjaColors.mint.withOpacity(0.62)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              code,
              style: TextStyle(
                color: active ? MunjaColors.mint : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? Colors.white : MunjaColors.textSoft,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _premiumDecoration({bool glow = false}) {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.86),
    borderRadius: BorderRadius.circular(32),
    border: Border.all(color: Colors.white.withOpacity(0.075)),
    boxShadow: glow
        ? [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(0.16),
              blurRadius: 44,
              spreadRadius: 2,
              offset: const Offset(0, 18),
            ),
          ]
        : null,
  );
}
