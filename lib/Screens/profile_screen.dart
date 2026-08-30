import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/munja_device.dart';
import '../models/trip.dart';
import '../models/user_profile.dart';
import '../models/social_rider_profile.dart';
import '../models/firestore_user.dart';
import '../services/auth_service.dart';
import '../services/firestore_user_service.dart';
import '../services/friend_service.dart';
import '../services/storage_service.dart';
import '../services/social_rider_service.dart';
import '../services/xp_service.dart';
import '../Services/munja_pro_service.dart';
import '../widgets/digital_twin/digital_twin.dart';
import '../widgets/munja_crystal_balance_badge.dart';

import 'find_rider_screen.dart';
import 'friend_requests_screen.dart';
import 'friends_screen.dart';
import 'create_challenge_screen.dart';
import 'challenge_requests_screen.dart';
import 'active_challenges_screen.dart';
import 'ride_analytics_screen.dart';
import 'ride_history_screen.dart';
import 'crystal_shop_screen.dart';
import 'munja_pro_screen.dart';

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
  String? remotePhotoUrl;
  FirestoreUser? firestoreUser;
  SocialRiderProfile? socialProfile;

  int _accountTotalXp = 0;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _accountSubscription;

  List<Trip> trips = [];
  List<MunjaDevice> savedDevices = [];
  List<SocialRiderProfile> friendsPreview = [];

  static const double bottomWheelSafePadding = 360;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await MunjaProService.instance.initialize();

      if (!mounted) {
        return;
      }

      _startLiveAccountData();
      await _load();
    });
  }

  @override
  void dispose() {
    unawaited(_accountSubscription?.cancel());

    nameCtrl.dispose();
    ageCtrl.dispose();
    cityCtrl.dispose();
    super.dispose();
  }

  String t(String key) => AppText.t(key);

  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  void _startLiveAccountData() {
    final uid = _currentUserId;

    unawaited(
      _accountSubscription?.cancel(),
    );

    _accountSubscription = null;

    if (uid.isEmpty) {
      return;
    }

    _accountSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        if (!snapshot.exists) {
          return;
        }

        final data =
            snapshot.data() ??
                const <String, dynamic>{};

        final totalXp =
            _readLiveInt(
          data['totalXp'],
        );

        if (!mounted ||
            totalXp == _accountTotalXp) {
          return;
        }

        setState(() {
          _accountTotalXp = totalXp;
        });

        debugPrint(
          'PROFILE LIVE ACCOUNT XP: $_accountTotalXp',
        );
      },
      onError: (
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          'PROFILE LIVE ACCOUNT ERROR: $error',
        );
        debugPrint('$stackTrace');
      },
    );
  }

  static int _readLiveInt(
    Object? value,
  ) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }

    if (value is num) {
      final parsed = value.toInt();
      return parsed < 0 ? 0 : parsed;
    }

    if (value is String) {
      final parsed =
          int.tryParse(
            value.trim(),
          ) ??
          0;

      return parsed < 0 ? 0 : parsed;
    }

    return 0;
  }

  String get _profilePhotoSubtitle =>
      AppText.t('profilePhotoSubtitle');

  String get _accountTitle => AppText.t('account');

  String get _accountSubtitle => AppText.t('accountSubtitle');

  String get _signOutText => AppText.t('signOut');

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

  String get _cancelText => AppText.t('cancel');

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

    // Legacy/local XP is used only as a migration candidate.
    // Firestore can only be increased by this migration, never reduced.
    final localCalculatedXp = XpService.totalXp(loadedTrips);

    FirestoreUser? loadedFirestoreUser;
    var resolvedTotalXp = localCalculatedXp;
    String? resolvedRemotePhotoUrl;

    try {
      loadedFirestoreUser =
          await FirestoreUserService.instance.ensureCurrentUserExists(
        updateLastLogin: false,
      );

      resolvedTotalXp =
          await FirestoreUserService.instance.syncTotalXpAtLeast(
        localCalculatedXp,
      );

      // Re-read after migration so Profile holds the canonical account object.
      loadedFirestoreUser =
          await FirestoreUserService.instance.getCurrentUser();

      if (loadedFirestoreUser != null) {
        resolvedTotalXp = loadedFirestoreUser.safeTotalXp;
        final candidateUrl = loadedFirestoreUser.photoUrl.trim();

        if (candidateUrl.isNotEmpty) {
          resolvedRemotePhotoUrl = candidateUrl;
        }
      }

      debugPrint(
        'PROFILE XP SYNC: '
        'local=$localCalculatedXp '
        'account=$resolvedTotalXp',
      );
    } catch (error, stackTrace) {
      // Offline/failure fallback: never make Profile unusable.
      debugPrint('PROFILE FIRESTORE LOAD ERROR: $error');
      debugPrint('$stackTrace');

      resolvedTotalXp = localCalculatedXp;
    }

    final resolvedLevel =
        XpService.levelForTotalXp(resolvedTotalXp);

    SocialRiderProfile? loadedSocialProfile;
    final loadedFriendsPreview = <SocialRiderProfile>[];

    try {
      loadedSocialProfile =
          await SocialRiderService.instance.ensureCurrentProfile(
        displayName: profile.name,
        level: resolvedLevel,
        totalXp: resolvedTotalXp,
        city: profile.city,
      );
    } catch (error, stackTrace) {
      debugPrint('PROFILE SOCIAL LOAD ERROR: $error');
      debugPrint('$stackTrace');
    }

    try {
      final friendUids =
          await FriendService.instance.getFriendUids();

      for (final uid in friendUids.take(3)) {
        final rider =
            await SocialRiderService.instance.getProfileByUid(uid);

        if (rider != null) {
          loadedFriendsPreview.add(rider);
        }
      }
    } catch (error, stackTrace) {
      debugPrint('PROFILE FRIENDS PREVIEW LOAD ERROR: $error');
      debugPrint('$stackTrace');
    }

    if (!mounted) return;

    setState(() {
      nameCtrl.text = profile.name;
      ageCtrl.text = profile.age > 0 ? '${profile.age}' : '';
      cityCtrl.text = profile.city;
      photoPath = profile.photoPath;
      remotePhotoUrl = resolvedRemotePhotoUrl;
      firestoreUser = loadedFirestoreUser;
      _accountTotalXp = resolvedTotalXp;
      trips = loadedTrips;
      savedDevices = devices;
      socialProfile = loadedSocialProfile;
      friendsPreview = loadedFriendsPreview;
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

    try {
      await FirestoreUserService.instance.updateCurrentUserProfile(
        displayName: profile.name,
      );
    } catch (error, stackTrace) {
      debugPrint('PROFILE FIRESTORE SAVE ERROR: $error');
      debugPrint('$stackTrace');
    }

    try {
      socialProfile =
          await SocialRiderService.instance.ensureCurrentProfile(
        displayName: profile.name,
        level: level,
        totalXp: totalXp,
        city: profile.city,
      );
    } catch (error, stackTrace) {
      debugPrint('PROFILE SOCIAL SAVE ERROR: $error');
      debugPrint('$stackTrace');
    }

    if (!mounted) return;

    setState(() {});

    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppText.t('profileSaved')),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    await _load();
  }

  Future<void> _openFindRider() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FindRiderScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openFriendRequests() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FriendRequestsScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openFriends() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FriendsScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openCreateChallenge() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const CreateChallengeScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openChallengeRequests() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ChallengeRequestsScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openActiveChallenges() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const ActiveChallengesScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openCrystalShop() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CrystalShopScreen(),
      ),
    );

    if (!mounted) return;

    await _load();
  }

  Future<void> _openMunjaPro() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MunjaProScreen(),
      ),
    );

    if (!mounted) return;

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
          content: Text(AppText.t('profilePhotoSaved')),
          backgroundColor: MunjaColors.panel,
        ),
      );
    } catch (e) {
      debugPrint('PROFILE PHOTO PICK ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppText.t('photoUploadFailed')),
          backgroundColor: MunjaColors.panel,
        ),
      );
    }
  }

  Future<void> _removePhoto() async {
    await StorageService.clearUserPhotoPath();

    try {
      await FirestoreUserService.instance.updatePhotoUrl(null);
    } catch (error, stackTrace) {
      debugPrint('PROFILE FIRESTORE PHOTO REMOVE ERROR: $error');
      debugPrint('$stackTrace');
    }

    if (!mounted) return;

    setState(() {
      photoPath = null;
      remotePhotoUrl = null;
    });

    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppText.t('profilePhotoRemoved')),
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
                  AppText.t('profilePhoto'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _profilePhotoSubtitle,
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
                  title: AppText.t('chooseFromGallery'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 10),
                _PhotoSheetButton(
                  icon: Icons.photo_camera_rounded,
                  title: AppText.t('takePhoto'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.camera);
                  },
                ),
                if ((photoPath != null && photoPath!.isNotEmpty) ||
                    (remotePhotoUrl != null &&
                        remotePhotoUrl!.isNotEmpty)) ...[
                  const SizedBox(height: 10),
                  _PhotoSheetButton(
                    icon: Icons.delete_outline_rounded,
                    title: AppText.t('removePhoto'),
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
    return XpService.totalDistanceKm(trips);
  }

  int get totalXp {
    return _accountTotalXp < 0 ? 0 : _accountTotalXp;
  }

  int get level {
    return XpService.levelForTotalXp(totalXp);
  }

  int get xp {
    return XpService.xpIntoCurrentLevel(totalXp);
  }

  int get xpForNextLevel {
    return XpService.xpNeededForNextLevel(totalXp);
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
    if (city.isEmpty) return AppText.t('digitalRider');
    return '$city ${AppText.t('rider')}';
  }

  String get riderUsername {
    final current = socialProfile;

    if (current != null) {
      return current.usernameWithAt;
    }

    final normalized = SocialRiderProfile.createUsernameCandidate(
      riderName,
    );

    return '@$normalized';
  }

  String get riderId {
    return socialProfile?.riderId ?? AppText.t('profileCreatingRiderId');
  }

  List<_AchievementData> get achievements {
    final items = <_AchievementData>[
      _AchievementData(
        icon: Icons.flag_rounded,
        title: AppText.t('profileFirstRide'),
        unlocked: trips.isNotEmpty,
      ),
      _AchievementData(
        icon: Icons.route_rounded,
        title: '10 KM',
        unlocked: totalKm >= 10,
      ),
      _AchievementData(
        icon: Icons.bolt_rounded,
        title: '50 KM',
        unlocked: totalKm >= 50,
      ),
      _AchievementData(
        icon: Icons.local_fire_department_rounded,
        title: AppText.t('profileThreeDayStreak'),
        unlocked: streakDays >= 3,
      ),
      _AchievementData(
        icon: Icons.workspace_premium_rounded,
        title: 'LVL 5',
        unlocked: level >= 5,
      ),
    ];

    return items;
  }

  void _showComingSoon(String title) {
    HapticFeedback.selectionClick();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title ${AppText.t('profileComingSoon')}'),
        backgroundColor: MunjaColors.panel,
      ),
    );
  }

  bool get hasBrakeLight {
    return savedDevices.any(
      (device) => device.type == MunjaProductType.brakeLight,
    );
  }

  Future<void> _showEditProfileSheet() async {
    HapticFeedback.selectionClick();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: MunjaColors.panel,
      barrierColor: Colors.black.withOpacity(0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(30),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppText.t('profileEditProfile'),
                    style: TextStyle(
                      color: MunjaColors.mint,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppText.t('profileRiderDetails'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _PremiumTextField(
                    controller: nameCtrl,
                    label: AppText.t('name'),
                    icon: Icons.person_rounded,
                    onChanged: (_) {
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _PremiumTextField(
                    controller: ageCtrl,
                    label: AppText.t('age'),
                    icon: Icons.cake_rounded,
                    keyboardType: TextInputType.number,
                    digitsOnly: true,
                  ),
                  const SizedBox(height: 12),
                  _PremiumTextField(
                    controller: cityCtrl,
                    label: AppText.t('city'),
                    icon: Icons.location_city_rounded,
                    onChanged: (_) {
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: () async {
                        await _save();

                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: Text(
                        AppText.t('saveProfile'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showLanguageSheet() async {
    HapticFeedback.selectionClick();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MunjaColors.panel,
      barrierColor: Colors.black.withOpacity(0.72),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(30),
        ),
      ),
      builder: (sheetContext) {
        Widget languageRow({
          required String label,
          required String code,
          required String languageCode,
        }) {
          final active =
              AppText.currentLocale.languageCode == languageCode;

          return _CompactLanguageRow(
            label: label,
            code: code,
            active: active,
            onTap: () async {
              await AppText.setLocale(
                Locale(languageCode),
              );

              if (mounted) {
                setState(() {});
              }

              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
            },
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              14,
              20,
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                    AppText.t('profileLanguage'),
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppText.t('language'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                languageRow(
                  label: 'Dansk',
                  code: 'DA',
                  languageCode: 'da',
                ),
                const SizedBox(height: 8),
                languageRow(
                  label: 'English',
                  code: 'EN',
                  languageCode: 'en',
                ),
                const SizedBox(height: 8),
                languageRow(
                  label: 'Bosanski',
                  code: 'BS',
                  languageCode: 'bs',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: MunjaColors.bg,
        body: Center(
          child: CircularProgressIndicator(
            color: MunjaColors.mint,
          ),
        ),
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
              18,
              16,
              18,
              bottomWheelSafePadding,
            ),
            children: [
              _ProfileV2Header(
                uid: _currentUserId,
                onCrystals: _openCrystalShop,
                onEditProfile: _showEditProfileSheet,
              ),
              const SizedBox(height: 14),

              _CompactProfileHero(
                name: riderName,
                username: riderUsername,
                city: cityCtrl.text.trim(),
                level: level,
                xp: xp,
                xpForNextLevel: xpForNextLevel,
                totalKm: totalKm,
                streakDays: streakDays,
                rides: trips.length,
                photoPath: photoPath,
                photoUrl: remotePhotoUrl,
                onPhoto: _showPhotoPicker,
              ),

              const SizedBox(height: 12),

              _SocialQuickActions(
                onAddFriend: _openFindRider,
                onChallenge: _openCreateChallenge,
              ),

              const SizedBox(height: 12),

              ValueListenableBuilder<MunjaProState>(
                valueListenable: MunjaProService.instance.state,
                builder: (
                  context,
                  proState,
                  _,
                ) {
                  return _CompactProRow(
                    isPro: proState.hasActivePro,
                    onTap: _openMunjaPro,
                  );
                },
              ),

              const SizedBox(height: 12),

              _CompactProfileMenu(
                title: 'MUNJA',
                items: [
                  _CompactProfileMenuItem(
                    icon: Icons.people_alt_rounded,
                    title: AppText.t('profileFriends'),
                    subtitle: friendsPreview.isEmpty
                        ? 'Find and manage riders'
                        : '${friendsPreview.length} recent riders',
                    onTap: _openFriends,
                  ),
                  _CompactProfileMenuItem(
                    icon: Icons.mark_email_unread_rounded,
                    title: AppText.t('profileRequests'),
                    subtitle: AppText.t('profileFriendChallengeRequests'),
                    onTap: _openFriendRequests,
                  ),
                  _CompactProfileMenuItem(
                    icon: Icons.emoji_events_rounded,
                    title: AppText.t('profileActiveChallenges'),
                    subtitle: AppText.t('profileSeeCurrentBattles'),
                    onTap: _openActiveChallenges,
                  ),
                  _CompactProfileMenuItem(
                    icon: Icons.history_rounded,
                    title: AppText.t('rideHistory'),
                    subtitle:
                        '${trips.length} ${AppText.t('savedRides')} · ${totalKm.toStringAsFixed(1)} km',
                    onTap: () => _openScreen(
                      const RideHistoryScreen(),
                    ),
                  ),
                  _CompactProfileMenuItem(
                    icon: Icons.insights_rounded,
                    title: AppText.t('analytics'),
                    subtitle: AppText.t('analyticsSubtitle'),
                    onTap: () => _openScreen(
                      const RideAnalyticsScreen(),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              _CompactAchievements(
                items: achievements,
              ),

              const SizedBox(height: 12),

              _CompactProfileMenu(
                title: AppText.t('profileSettingsSection'),
                items: [
                  _CompactProfileMenuItem(
                    icon: Icons.person_outline_rounded,
                    title: AppText.t('profileDetails'),
                    subtitle: riderSubtitle,
                    onTap: _showEditProfileSheet,
                  ),
                  _CompactProfileMenuItem(
                    icon: Icons.language_rounded,
                    title: AppText.t('language'),
                    subtitle: _currentLanguageLabel,
                    onTap: _showLanguageSheet,
                  ),
                  _CompactProfileMenuItem(
                    icon: Icons.logout_rounded,
                    title: _signOutText,
                    subtitle: _signOutDescription,
                    danger: true,
                    loading: signingOut,
                    onTap: _confirmSignOut,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _currentLanguageLabel {
    switch (AppText.currentLocale.languageCode) {
      case 'en':
        return 'English';
      case 'bs':
        return 'Bosanski';
      default:
        return 'Dansk';
    }
  }

}

class _CompactProfileHero extends StatelessWidget {
  const _CompactProfileHero({
    required this.name,
    required this.username,
    required this.city,
    required this.level,
    required this.xp,
    required this.xpForNextLevel,
    required this.totalKm,
    required this.streakDays,
    required this.rides,
    required this.photoPath,
    required this.photoUrl,
    required this.onPhoto,
  });

  final String name;
  final String username;
  final String city;
  final int level;
  final int xp;
  final int xpForNextLevel;
  final double totalKm;
  final int streakDays;
  final int rides;
  final String? photoPath;
  final String? photoUrl;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final progress = xpForNextLevel <= 0
        ? 0.0
        : (xp / xpForNextLevel).clamp(0.0, 1.0);

    final localPath = photoPath?.trim() ?? '';
    final localFile =
        localPath.isEmpty ? null : File(localPath);
    final hasLocal =
        localFile != null && localFile.existsSync();

    final remote = photoUrl?.trim() ?? '';
    final hasRemote = remote.isNotEmpty;

    Widget avatar = const Icon(
      Icons.person_rounded,
      color: MunjaColors.mint,
      size: 32,
    );

    if (hasLocal) {
      avatar = Image.file(
        localFile,
        fit: BoxFit.cover,
      );
    } else if (hasRemote) {
      avatar = Image.network(
        remote,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.person_rounded,
          color: MunjaColors.mint,
          size: 32,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.72),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.13),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.055),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: onPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.22),
                        border: Border.all(
                          color:
                              MunjaColors.mint.withOpacity(0.42),
                          width: 1.5,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: avatar,
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: MunjaColors.mint,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MunjaColors.bg,
                            width: 2.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.black,
                          size: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (city.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: MunjaColors.textSoft,
                            size: 12,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              city,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: const TextStyle(
                                color:
                                    MunjaColors.textSoft,
                                fontSize: 10.5,
                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
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
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Text(
                '$xp / $xpForNextLevel XP',
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              backgroundColor: Colors.white.withOpacity(0.07),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                MunjaColors.mint,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _CompactStat(
                  value: totalKm.toStringAsFixed(1),
                  label: AppText.t('profileKm'),
                ),
              ),
              _CompactVerticalDivider(),
              Expanded(
                child: _CompactStat(
                  value: '$streakDays',
                  label: AppText.t('profileStreak'),
                ),
              ),
              _CompactVerticalDivider(),
              Expanded(
                child: _CompactStat(
                  value: '$rides',
                  label: AppText.t('profileRides'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: MunjaColors.textSoft,
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _CompactVerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 27,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white.withOpacity(0.07),
    );
  }
}

class _CompactProRow extends StatelessWidget {
  const _CompactProRow({
    required this.isPro,
    required this.onTap,
  });

  final bool isPro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: MunjaColors.panel.withOpacity(0.58),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(
                isPro ? 0.34 : 0.13,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: MunjaColors.mint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'MUNJA PRO',
                      style: TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isPro
                          ? 'ACTIVE · Pro features unlocked'
                          : 'Unlock Pro experience',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPro
                            ? MunjaColors.mint
                            : Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: isPro ? 0.35 : 0,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isPro
                    ? Icons.verified_rounded
                    : Icons.chevron_right_rounded,
                color: MunjaColors.mint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactProfileMenu extends StatelessWidget {
  const _CompactProfileMenu({
    required this.title,
    required this.items,
  });

  final String title;
  final List<_CompactProfileMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.48),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              14,
              12,
              14,
              8,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
            ),
          ),
          for (var i = 0; i < items.length; i++) ...[
            items[i],
            if (i < items.length - 1)
              Padding(
                padding:
                    const EdgeInsets.only(left: 58),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CompactProfileMenuItem extends StatelessWidget {
  const _CompactProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
    this.loading = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final accent =
        danger ? MunjaColors.danger : MunjaColors.mint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: loading
                    ? Padding(
                        padding: const EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(
                        icon,
                        color: accent,
                        size: 18,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            danger ? accent : Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: danger
                    ? accent.withOpacity(0.8)
                    : Colors.white24,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactAchievements extends StatelessWidget {
  const _CompactAchievements({
    required this.items,
  });

  final List<_AchievementData> items;

  @override
  Widget build(BuildContext context) {
    final unlocked =
        items.where((item) => item.unlocked).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        14,
      ),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.48),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                    AppText.t('profileAchievementsCaps'),
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                '$unlocked / ${items.length}',
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                Expanded(
                  child: Tooltip(
                    message: items[i].title,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: items[i].unlocked
                            ? MunjaColors.mint
                                .withOpacity(0.10)
                            : Colors.white
                                .withOpacity(0.025),
                        borderRadius:
                            BorderRadius.circular(13),
                        border: Border.all(
                          color: items[i].unlocked
                              ? MunjaColors.mint
                                  .withOpacity(0.19)
                              : Colors.white
                                  .withOpacity(0.04),
                        ),
                      ),
                      child: Icon(
                        items[i].icon,
                        size: 18,
                        color: items[i].unlocked
                            ? MunjaColors.mint
                            : Colors.white24,
                      ),
                    ),
                  ),
                ),
                if (i < items.length - 1)
                  const SizedBox(width: 7),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactLanguageRow extends StatelessWidget {
  const _CompactLanguageRow({
    required this.label,
    required this.code,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String code;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          decoration: BoxDecoration(
            color: active
                ? MunjaColors.mint.withOpacity(0.10)
                : Colors.black.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: active
                  ? MunjaColors.mint.withOpacity(0.22)
                  : Colors.white.withOpacity(0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? MunjaColors.mint
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: active
                        ? Colors.black
                        : Colors.white54,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (active)
                const Icon(
                  Icons.check_circle_rounded,
                  color: MunjaColors.mint,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileV2Header extends StatelessWidget {
  const _ProfileV2Header({
    required this.uid,
    required this.onCrystals,
    required this.onEditProfile,
  });

  final String uid;
  final VoidCallback onCrystals;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppText.t('profileRiderProfile'),
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.8,
                ),
              ),
              SizedBox(height: 6),
              Text(
                AppText.t('profileTitle'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.1,
                ),
              ),
            ],
          ),
        ),
        MunjaCrystalBalanceBadge(
          uid: uid,
          compact: true,
          showLabel: false,
          onTap: onCrystals,
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.white.withOpacity(0.055),
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: onEditProfile,
            tooltip: AppText.t('profileSettings'),
            icon: const Icon(
              Icons.tune_rounded,
              color: MunjaColors.mint,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileIdentityHero extends StatelessWidget {
  const _ProfileIdentityHero({
    required this.name,
    required this.username,
    required this.riderId,
    required this.city,
    required this.level,
    required this.xp,
    required this.xpForNextLevel,
    required this.totalXp,
    required this.totalKm,
    required this.streakDays,
    required this.rides,
    required this.photoPath,
    required this.photoUrl,
    required this.onUploadPhoto,
  });

  final String name;
  final String username;
  final String riderId;
  final String city;
  final int level;
  final int xp;
  final int xpForNextLevel;
  final int totalXp;
  final double totalKm;
  final int streakDays;
  final int rides;
  final String? photoPath;
  final String? photoUrl;
  final VoidCallback onUploadPhoto;

  @override
  Widget build(BuildContext context) {
    final progress = xpForNextLevel <= 0
        ? 0.0
        : (xp / xpForNextLevel).clamp(0.0, 1.0);

    final photoFile = photoPath == null || photoPath!.trim().isEmpty
        ? null
        : File(photoPath!);

    final hasLocalPhoto =
        photoFile != null && photoFile.existsSync();

    final normalizedPhotoUrl = photoUrl?.trim() ?? '';
    final hasRemotePhoto = normalizedPhotoUrl.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.88),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.10),
            blurRadius: 42,
            spreadRadius: 1,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onUploadPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.24),
                        border: Border.all(
                          color:
                              MunjaColors.mint.withOpacity(0.52),
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: hasLocalPhoto
                          ? Image.file(
                              photoFile!,
                              fit: BoxFit.cover,
                            )
                          : hasRemotePhoto
                              ? Image.network(
                                  normalizedPhotoUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(
                                    Icons.person_rounded,
                                    color: MunjaColors.mint,
                                    size: 42,
                                  ),
                                )
                              : const Icon(
                                  Icons.person_rounded,
                                  color: MunjaColors.mint,
                                  size: 42,
                                ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: MunjaColors.mint,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: MunjaColors.bg,
                            width: 3,
                          ),
                        ),
                        child: const Icon(
                          Icons.add_a_photo_rounded,
                          color: Colors.black,
                          size: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      username,
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      riderId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (city.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            size: 14,
                            color: MunjaColors.textSoft,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: MunjaColors.textSoft,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
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
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text(
                    AppText.t('profileLevelProgress'),
                style: TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
              const Spacer(),
              Text(
                '$xp / $xpForNextLevel XP',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withOpacity(0.07),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                    MunjaColors.mint,
                  ),
            ),
          ),
          const SizedBox(height: 7),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$totalXp total XP',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _ProfileStat(
                  icon: Icons.route_rounded,
                  value: totalKm.toStringAsFixed(1),
                  label: AppText.t('profileKm'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileStat(
                  icon:
                      Icons.local_fire_department_rounded,
                  value: '$streakDays',
                  label: AppText.t('profileStreak'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ProfileStat(
                  icon: Icons.flag_rounded,
                  value: '$rides',
                  label: AppText.t('profileRides'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  _ProfileStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 19,
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MunjaProProfileCard extends StatelessWidget {
  const _MunjaProProfileCard({
    required this.isPro,
    required this.onTap,
  });

  final bool isPro;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: MunjaColors.panel.withOpacity(0.92),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.24),
            ),
            boxShadow: [
              BoxShadow(
                color: MunjaColors.mint.withOpacity(0.07),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: MunjaColors.mint.withOpacity(0.22),
                  ),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: MunjaColors.mint,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'MUNJA PRO',
                          style: TextStyle(
                            color: MunjaColors.mint,
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isPro
                              ? Icons.verified_rounded
                              : Icons
                                  .workspace_premium_rounded,
                          color: MunjaColors.mint,
                          size: 15,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isPro
                          ? 'Munja Pro is active'
                          : 'Unlock more of Munja',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPro
                          ? 'Your Pro features, Monthly Specials and selected premium cosmetics are unlocked.'
                          : 'AI Coach, advanced analytics, Pro challenges and exclusive cosmetics.',
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 11.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isPro
                      ? Icons.check_rounded
                      : Icons.arrow_forward_rounded,
                  color: MunjaColors.mint,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SocialQuickActions extends StatelessWidget {
  const _SocialQuickActions({
    required this.onAddFriend,
    required this.onChallenge,
  });

  final VoidCallback onAddFriend;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SocialActionButton(
            icon: Icons.person_add_alt_1_rounded,
            label: AppText.t('profileAddFriend'),
            filled: false,
            onTap: onAddFriend,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SocialActionButton(
            icon: Icons.bolt_rounded,
            label: AppText.t('profileChallenge'),
            filled: true,
            onTap: onChallenge,
          ),
        ),
      ],
    );
  }
}

class _SocialActionButton extends StatelessWidget {
  const _SocialActionButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: filled
          ? FilledButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon),
              label: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
    );
  }
}

class _FriendsPreviewCard extends StatelessWidget {
  const _FriendsPreviewCard({
    required this.friends,
    required this.onOpenFriends,
    required this.onFindRiders,
    required this.onInvite,
  });

  final List<SocialRiderProfile> friends;
  final VoidCallback onOpenFriends;
  final VoidCallback onFindRiders;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    return _ProfileSocialCard(
      eyebrow: 'SOCIAL',
      title: AppText.t('profileFriends'),
      subtitle:
          AppText.t('profileFindRidersBody'),
      child: Column(
        children: [
          if (friends.isEmpty)
            _NoFriendsPreview(
              onFindRiders: onFindRiders,
            )
          else
            Row(
              children: [
                ...friends.asMap().entries.expand(
                  (entry) {
                    final rider = entry.value;

                    return <Widget>[
                      _FriendAvatar(
                        rider: rider,
                        onTap: onOpenFriends,
                      ),
                      if (entry.key < friends.length - 1)
                        const SizedBox(width: 10),
                    ];
                  },
                ),
                const Spacer(),
                IconButton(
                  onPressed: onOpenFriends,
                  tooltip: AppText.t('profileViewAllFriends'),
                  icon: const Icon(
                    Icons.groups_rounded,
                    color: MunjaColors.mint,
                  ),
                ),
                IconButton(
                  onPressed: onFindRiders,
                  tooltip: AppText.t('profileFindRiders'),
                  icon: const Icon(
                    Icons.search_rounded,
                    color: MunjaColors.mint,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(
                      Icons.mark_email_unread_rounded,
                    ),
                    label: Text(
                    AppText.t('profileRequests'),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: onOpenFriends,
                    icon: const Icon(
                      Icons.people_alt_rounded,
                    ),
                    label: Text(
                    AppText.t('profileViewAll'),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoFriendsPreview extends StatelessWidget {
  const _NoFriendsPreview({
    required this.onFindRiders,
  });

  final VoidCallback onFindRiders;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.11),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.people_outline_rounded,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppText.t('profileNoFriendsYet'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  AppText.t('profileFindAnotherRider'),
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onFindRiders,
            icon: const Icon(
              Icons.person_search_rounded,
              color: MunjaColors.mint,
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({
    required this.rider,
    required this.onTap,
  });

  final SocialRiderProfile rider;
  final VoidCallback onTap;

  String get initials {
    final words = rider.displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return 'M';
    }

    if (words.length == 1) {
      return words.first.substring(0, 1).toUpperCase();
    }

    return '${words.first.substring(0, 1)}'
            '${words.last.substring(0, 1)}'
        .toUpperCase();
  }

  String get label {
    final name = rider.displayName.trim();

    if (name.isEmpty) {
      return rider.usernameWithAt;
    }

    final firstName = name.split(RegExp(r'\s+')).first;

    return firstName.length > 9
        ? '${firstName.substring(0, 8)}…'
        : firstName;
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        rider.photoUrl != null &&
        rider.photoUrl!.trim().isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 54,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MunjaColors.mint.withOpacity(0.11),
                border: Border.all(
                  color: MunjaColors.mint.withOpacity(0.28),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasPhoto
                  ? Image.network(
                      rider.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (
                        context,
                        error,
                        stackTrace,
                      ) {
                        return Text(
                          initials,
                          style: const TextStyle(
                            color: MunjaColors.mint,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        );
                      },
                    )
                  : Text(
                      initials,
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChallengePreviewCard extends StatelessWidget {
  const _ChallengePreviewCard({
    required this.onStartChallenge,
    required this.onOpenRequests,
    required this.onOpenActive,
  });

  final VoidCallback onStartChallenge;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenActive;

  @override
  Widget build(BuildContext context) {
    return _ProfileSocialCard(
      eyebrow: 'COMPETE',
      title: AppText.t('profileChallenges'),
      subtitle:
          AppText.t('profileChallengeHubBody'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.16),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: MunjaColors.mint.withOpacity(0.14),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: MunjaColors.mint.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.emoji_events_rounded,
                    color: MunjaColors.mint,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppText.t('profileChallengeHub'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        AppText.t('profileChallengeInfo'),
                        style: TextStyle(
                          color: MunjaColors.textSoft,
                          fontSize: 12,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: onOpenActive,
                icon: const Icon(
                  Icons.sports_score_rounded,
                ),
                label: Text(
                    AppText.t('profileActiveChallenges'),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: onOpenRequests,
                      icon: const Icon(
                        Icons.mark_email_unread_rounded,
                      ),
                      label: Text(
                    AppText.t('profileRequests'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: onStartChallenge,
                      icon: const Icon(
                        Icons.bolt_rounded,
                      ),
                      label: Text(
                    AppText.t('profileNewChallenge'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AchievementsCard extends StatelessWidget {
  const _AchievementsCard({
    required this.items,
  });

  final List<_AchievementData> items;

  @override
  Widget build(BuildContext context) {
    return _ProfileSocialCard(
      eyebrow: 'PROGRESS',
      title: AppText.t('profileAchievements'),
      subtitle:
          AppText.t('profileMilestonesBody'),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: items
            .map(
              (item) => _AchievementBadge(
                data: item,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _AchievementData {
  _AchievementData({
    required this.icon,
    required this.title,
    required this.unlocked,
  });

  final IconData icon;
  final String title;
  final bool unlocked;
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.data,
  });

  final _AchievementData data;

  @override
  Widget build(BuildContext context) {
    final color = data.unlocked
        ? MunjaColors.mint
        : Colors.white30;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: data.unlocked
            ? MunjaColors.mint.withOpacity(0.11)
            : Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: data.unlocked
              ? MunjaColors.mint.withOpacity(0.28)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            data.icon,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            data.title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (!data.unlocked) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.lock_rounded,
              size: 13,
              color: Colors.white24,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileSocialCard extends StatelessWidget {
  const _ProfileSocialCard({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _premiumDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 13,
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
