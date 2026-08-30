import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/social_rider_profile.dart';
import '../services/challenge_service.dart';
import '../services/friend_service.dart';
import '../Services/munja_pro_service.dart';
import '../services/monthly_special_service.dart';
import 'munja_pro_screen.dart';
import '../services/social_rider_service.dart';


String _t(String key) => AppText.t(key);

enum _ChallengeKind {
  distance,
  rides,
  rideTime,
  streak,
}

class _ChallengeTypeData {
  _ChallengeTypeData({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.enabled = false,
  });

  final _ChallengeKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final bool enabled;
}

class CreateChallengeScreen extends StatefulWidget {
  const CreateChallengeScreen({
    super.key,
    this.preselectedFriendUid,
  });

  final String? preselectedFriendUid;

  @override
  State<CreateChallengeScreen> createState() =>
      _CreateChallengeScreenState();
}

class _CreateChallengeScreenState
    extends State<CreateChallengeScreen> {
  bool _loading = true;
  bool _submitting = false;
  String? _errorMessage;

  List<SocialRiderProfile> _friends =
      const <SocialRiderProfile>[];

  SocialRiderProfile? _selectedFriend;

  _ChallengeKind _selectedKind =
      _ChallengeKind.distance;

  double _selectedDistanceKm = 25;
  int _selectedDurationDays = 7;
  int _selectedRideCount = 5;
  int _selectedRideTimeMinutes = 180;
  int _selectedStreakDays = 5;

  static const List<double> _distanceOptions =
      <double>[
    10,
    25,
    50,
  ];

  static const List<int> _durationOptions =
      <int>[
    3,
    7,
    14,
  ];

  static const List<int> _rideCountOptions = <int>[
    3,
    5,
    10,
  ];

  static const List<int> _rideTimeOptions = <int>[
    60,
    180,
    300,
  ];

  static const List<int> _streakOptions = <int>[
    3,
    5,
    7,
  ];

  static final List<_ChallengeTypeData>
      _challengeTypes =
      <_ChallengeTypeData>[
    _ChallengeTypeData(
      kind: _ChallengeKind.distance,
      title: _t('distance'),
      subtitle: _t('distanceDesc'),
      icon: Icons.route_rounded,
      enabled: true,
    ),
    _ChallengeTypeData(
      kind: _ChallengeKind.rides,
      title: _t('rideCount'),
      subtitle: _t('rideCountDesc'),
      icon: Icons.flag_rounded,
      enabled: true,
    ),
    _ChallengeTypeData(
      kind: _ChallengeKind.rideTime,
      title: _t('rideTime'),
      subtitle: _t('rideTimeDesc'),
      icon: Icons.timer_rounded,
      enabled: true,
    ),
    _ChallengeTypeData(
      kind: _ChallengeKind.streak,
      title: _t('streak'),
      subtitle: _t('streakDesc'),
      icon: Icons.local_fire_department_rounded,
      enabled: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadFriends);
  }

  Future<void> _loadFriends() async {
    try {
      final friendUids =
          await FriendService.instance.getFriendUids();

      final loadedFriends =
          <SocialRiderProfile>[];

      for (final uid in friendUids) {
        try {
          final rider =
              await SocialRiderService.instance
                  .getProfileByUid(uid);

          if (rider != null) {
            loadedFriends.add(rider);
          }
        } catch (error, stackTrace) {
          debugPrint(
            'CREATE CHALLENGE FRIEND PROFILE LOAD ERROR: $error',
          );
          debugPrint('$stackTrace');
        }
      }

      loadedFriends.sort(
        (a, b) => a.displayName
            .toLowerCase()
            .compareTo(
              b.displayName.toLowerCase(),
            ),
      );

      SocialRiderProfile? selectedFriend;

      final preferredUid =
          widget.preselectedFriendUid?.trim();

      if (preferredUid != null &&
          preferredUid.isNotEmpty) {
        for (final rider in loadedFriends) {
          if (rider.uid == preferredUid) {
            selectedFriend = rider;
            break;
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _friends = loadedFriends;
        _selectedFriend = selectedFriend;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'CREATE CHALLENGE FRIENDS LOAD ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _errorMessage =
            _t('friendsLoadFailed');
        _loading = false;
      });
    }
  }

  void _selectChallengeType(
    _ChallengeTypeData data,
  ) {
    HapticFeedback.selectionClick();


    setState(() {
      _selectedKind = data.kind;
    });
  }

  int get _previewCrystalReward {
    switch (_selectedKind) {
      case _ChallengeKind.distance:
        if (_selectedDistanceKm >= 50) return 10;
        if (_selectedDistanceKm >= 25) return 6;
        return 3;
      case _ChallengeKind.rides:
        if (_selectedRideCount >= 10) return 10;
        if (_selectedRideCount >= 5) return 6;
        return 3;
      case _ChallengeKind.rideTime:
        if (_selectedRideTimeMinutes >= 300) return 10;
        if (_selectedRideTimeMinutes >= 180) return 6;
        return 3;
      case _ChallengeKind.streak:
        if (_selectedStreakDays >= 7) return 10;
        if (_selectedStreakDays >= 5) return 6;
        return 3;
    }
  }

  int get _previewXpReward {
    switch (_selectedKind) {
      case _ChallengeKind.distance:
        if (_selectedDistanceKm >= 50) return 100;
        if (_selectedDistanceKm >= 25) return 60;
        return 30;
      case _ChallengeKind.rides:
        if (_selectedRideCount >= 10) return 100;
        if (_selectedRideCount >= 5) return 60;
        return 30;
      case _ChallengeKind.rideTime:
        if (_selectedRideTimeMinutes >= 300) return 100;
        if (_selectedRideTimeMinutes >= 180) return 60;
        return 30;
      case _ChallengeKind.streak:
        if (_selectedStreakDays >= 7) return 100;
        if (_selectedStreakDays >= 5) return 60;
        return 30;
    }
  }

  String get _goalLabel {
    switch (_selectedKind) {
      case _ChallengeKind.distance:
        return '${_selectedDistanceKm.toStringAsFixed(0)} km';
      case _ChallengeKind.rides:
        return '$_selectedRideCount ${_t('profileRides').toLowerCase()}';
      case _ChallengeKind.rideTime:
        if (_selectedRideTimeMinutes % 60 == 0) {
          return '${_selectedRideTimeMinutes ~/ 60} h';
        }
        return '$_selectedRideTimeMinutes min';
      case _ChallengeKind.streak:
        return '$_selectedStreakDays ${_t('homeDaysLeftPlural').replaceAll(' tilbage','').replaceAll(' left','').replaceAll(' preostalo','')}';
    }
  }

  IconData get _goalIcon {
    switch (_selectedKind) {
      case _ChallengeKind.distance:
        return Icons.route_rounded;
      case _ChallengeKind.rides:
        return Icons.flag_rounded;
      case _ChallengeKind.rideTime:
        return Icons.timer_rounded;
      case _ChallengeKind.streak:
        return Icons.local_fire_department_rounded;
    }
  }

  String get _goalSectionTitle {
    switch (_selectedKind) {
      case _ChallengeKind.distance:
        return _t('distance');
      case _ChallengeKind.rides:
        return _t('rideCount');
      case _ChallengeKind.rideTime:
        return _t('rideTime');
      case _ChallengeKind.streak:
        return _t('streak');
    }
  }

  Future<void> _sendChallenge() async {
    final friend = _selectedFriend;

    if (friend == null || _submitting) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _submitting = true;
    });

    try {
      late final String challengeId;

      switch (_selectedKind) {
        case _ChallengeKind.distance:
          challengeId =
              await ChallengeService.instance
                  .createDistanceChallenge(
            opponentUid: friend.uid,
            targetDistanceKm: _selectedDistanceKm,
            durationDays: _selectedDurationDays,
          );
          break;
        case _ChallengeKind.rides:
          challengeId =
              await ChallengeService.instance
                  .createRideCountChallenge(
            opponentUid: friend.uid,
            targetRideCount: _selectedRideCount,
            durationDays: _selectedDurationDays,
          );
          break;
        case _ChallengeKind.rideTime:
          challengeId =
              await ChallengeService.instance
                  .createRideTimeChallenge(
            opponentUid: friend.uid,
            targetRideTimeMinutes:
                _selectedRideTimeMinutes,
            durationDays: _selectedDurationDays,
          );
          break;
        case _ChallengeKind.streak:
          challengeId =
              await ChallengeService.instance
                  .createStreakChallenge(
            opponentUid: friend.uid,
            targetStreakDays: _selectedStreakDays,
            durationDays: _selectedDurationDays,
          );
          break;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          backgroundColor:
              MunjaColors.panel,
          content: Text(
            '${_t('sendChallenge')} · ${friend.usernameWithAt}',
          ),
        ),
      );

      Navigator.of(context).pop(
        challengeId,
      );
    } on StateError catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          backgroundColor:
              MunjaColors.panel,
          content: Text(
            error.message,
          ),
        ),
      );
    } on ArgumentError catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          backgroundColor:
              MunjaColors.panel,
          content: Text(
            error.message?.toString() ??
                _t('couldNotCreate'),
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'CREATE CHALLENGE ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          backgroundColor:
              MunjaColors.panel,
          content: Text(_t('couldNotCreate')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      appBar: AppBar(
        backgroundColor:
            MunjaColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: _submitting
              ? null
              : () =>
                  Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
          ),
        ),
        title: Text(
          _t('newChallenge'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight:
                FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return _CreateChallengeLoading();
    }

    if (_errorMessage != null) {
      return _CreateChallengeError(
        message: _errorMessage!,
        onRetry: _loadFriends,
      );
    }

    if (_friends.isEmpty) {
      return _NoChallengeFriends();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        20,
        10,
        20,
        360,
      ),
      physics:
          const BouncingScrollPhysics(),
      children: [
        _ChallengeIntroCard(),
        const SizedBox(height: 18),

        _MonthlySpecialPreview(
          proService: MunjaProService.instance,
        ),
        const SizedBox(height: 24),

        _SectionTitle(
          title: _t('challengeType'),
        ),
        const SizedBox(height: 10),

        _ChallengeTypeSelector(
          items: _challengeTypes,
          selected: _selectedKind,
          enabled: !_submitting,
          onSelected:
              _selectChallengeType,
        ),

        const SizedBox(height: 24),

        _SectionTitle(
          title: _t('chooseRider'),
        ),
        const SizedBox(height: 10),

        _FriendPicker(
          friends: _friends,
          selectedFriend:
              _selectedFriend,
          enabled: !_submitting,
          onSelected: (rider) {
            HapticFeedback
                .selectionClick();

            setState(() {
              _selectedFriend = rider;
            });
          },
        ),

        const SizedBox(height: 24),

        _SectionTitle(
          title: _goalSectionTitle,
        ),
        const SizedBox(height: 10),

        if (_selectedKind == _ChallengeKind.distance)
          _DistanceSelector(
            options: _distanceOptions,
            selected: _selectedDistanceKm,
            enabled: !_submitting,
            onSelected: (value) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedDistanceKm = value;
              });
            },
          ),

        if (_selectedKind == _ChallengeKind.rides)
          _IntChoiceSelector(
            options: _rideCountOptions,
            selected: _selectedRideCount,
            enabled: !_submitting,
            icon: Icons.flag_rounded,
            labelBuilder: (value) => '$value RIDES',
            onSelected: (value) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedRideCount = value;
              });
            },
          ),

        if (_selectedKind == _ChallengeKind.rideTime)
          _IntChoiceSelector(
            options: _rideTimeOptions,
            selected: _selectedRideTimeMinutes,
            enabled: !_submitting,
            icon: Icons.timer_rounded,
            labelBuilder: (value) =>
                value % 60 == 0
                    ? '${value ~/ 60} H'
                    : '$value MIN',
            onSelected: (value) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedRideTimeMinutes = value;
              });
            },
          ),

        if (_selectedKind == _ChallengeKind.streak)
          _IntChoiceSelector(
            options: _streakOptions,
            selected: _selectedStreakDays,
            enabled: !_submitting,
            icon: Icons.local_fire_department_rounded,
            labelBuilder: (value) => '$value DAYS',
            onSelected: (value) {
              HapticFeedback.selectionClick();
              setState(() {
                _selectedStreakDays = value;
              });
            },
          ),

        const SizedBox(height: 24),
        _SectionTitle(
          title: _t('duration'),
        ),
        const SizedBox(height: 10),
        _DurationSelector(
          options: _durationOptions,
          selected: _selectedDurationDays,
          enabled: !_submitting,
          onSelected: (value) {
            HapticFeedback.selectionClick();
            setState(() {
              _selectedDurationDays = value;
            });
          },
        ),

        const SizedBox(height: 24),
        _ChallengeRewardPreview(
          crystals: _previewCrystalReward,
          xp: _previewXpReward,
        ),
        const SizedBox(height: 16),
        _ChallengeSummaryCard(
          friend: _selectedFriend,
          goal: _goalLabel,
          goalIcon: _goalIcon,
          durationDays: _selectedDurationDays,
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 58,
          child: FilledButton.icon(
            onPressed:
                _selectedFriend == null || _submitting
                    ? null
                    : _sendChallenge,
            icon: _submitting
                ? const SizedBox(
                    width: 19,
                    height: 19,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.1,
                      color: Colors.black,
                    ),
                  )
                : const Icon(
                    Icons.bolt_rounded,
                  ),
            label: Text(
              _submitting
                  ? _t('sending')
                  : _t('sendChallenge'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _t('challengeRewardsBalanced'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white30,
            fontSize: 10,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ChallengeIntroCard
    extends StatelessWidget {
  _ChallengeIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _premiumDecoration(),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color:
                  MunjaColors.mint.withOpacity(
                0.11,
              ),
              borderRadius:
                  BorderRadius.circular(
                20,
              ),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: MunjaColors.mint,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  _t('challengesTitle'),
                  style: TextStyle(
                    color:
                        MunjaColors.mint,
                    fontSize: 9,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  _t('challengeARider'),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  _t('challengeIntro'),
                  style: TextStyle(
                    color:
                        MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlySpecialPreview extends StatefulWidget {
  _MonthlySpecialPreview({
    required this.proService,
  });

  final MunjaProService proService;

  @override
  State<_MonthlySpecialPreview> createState() =>
      _MonthlySpecialPreviewState();
}

class _MonthlySpecialPreviewState
    extends State<_MonthlySpecialPreview> {
  final MonthlySpecialService _specialService =
      MonthlySpecialService.instance;

  MonthlySpecialActivation? _activation;
  bool _loadingActivation = true;
  bool _startingSpecial = false;
  bool _claimingReward = false;
  String? _activationError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadActivation);
  }

  MonthlySpecial get _offeredSpecial =>
      _specialService.current();

  MonthlySpecial get _displaySpecial {
    final activation = _activation;

    if (activation != null &&
        activation.status !=
            MonthlySpecialActivationStatus.expired) {
      return _specialService.specialForActivation(
        activation,
      );
    }

    return _offeredSpecial;
  }

  bool get _hasActiveSpecial {
    final activation = _activation;

    if (activation == null) {
      return false;
    }

    return activation.status ==
            MonthlySpecialActivationStatus.active &&
        activation.endsAt.isAfter(DateTime.now());
  }

  bool get _hasCompletedSpecial {
    return _activation?.status ==
        MonthlySpecialActivationStatus.completed;
  }

  bool get _rewardClaimed {
    return _activation?.rewardClaimed == true;
  }

  Future<void> _loadActivation() async {
    if (mounted) {
      setState(() {
        _loadingActivation = true;
        _activationError = null;
      });
    }

    try {
      final activation =
          await _specialService.getActiveActivation();

      if (!mounted) return;

      setState(() {
        _activation = activation;
        _loadingActivation = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'MONTHLY SPECIAL LOAD ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _loadingActivation = false;
        _activationError =
            _t('monthlyLoadFailed');
      });
    }
  }

  Future<void> _startSpecial(
    BuildContext context,
  ) async {
    if (_startingSpecial) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _startingSpecial = true;
      _activationError = null;
    });

    try {
      final result =
          await _specialService.activateCurrentSpecial();

      if (!mounted) return;

      setState(() {
        _activation = result.activation;
        _startingSpecial = false;
      });

      final special =
          _specialService.specialForActivation(
        result.activation,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            result.created
                ? '${special.title} started. You now have 30 full days.'
                : '${special.title} is already active.',
          ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MONTHLY SPECIAL START ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _startingSpecial = false;
        _activationError =
            'Monthly Special could not be started. Please try again.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            'Monthly Special could not be started. Please try again.',
          ),
        ),
      );
    }
  }

  Future<void> _claimReward(
    BuildContext context,
  ) async {
    final activation = _activation;

    if (activation == null ||
        !_hasCompletedSpecial ||
        _rewardClaimed ||
        _claimingReward) {
      return;
    }

    HapticFeedback.heavyImpact();

    setState(() {
      _claimingReward = true;
      _activationError = null;
    });

    try {
      final result =
          await _specialService.claimCompletedReward(
        activationId: activation.id,
      );

      if (!mounted) return;

      await _loadActivation();

      if (!mounted) return;

      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: MunjaColors.panel,
            duration: const Duration(seconds: 4),
            content: Text(
              '+${result.xpGranted} XP · '
              '+${result.crystalsGranted} Crystals · '
              '${result.rewardName} unlocked!',
            ),
          ),
        );
        return;
      }

      if (result.alreadyClaimed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: MunjaColors.panel,
            content: Text(
              _t('rewardAlreadyClaimed'),
            ),
          ),
        );
        return;
      }

      final message = switch (result.status) {
        MonthlySpecialClaimStatus.notCompleted =>
          _t('completeBeforeClaim'),
        MonthlySpecialClaimStatus.activationNotFound =>
          _t('monthlyNotFound'),
        MonthlySpecialClaimStatus.userNotFound =>
          _t('profileNotFound'),
        MonthlySpecialClaimStatus.success =>
          _t('rewardClaimed'),
        MonthlySpecialClaimStatus.alreadyClaimed =>
          _t('rewardAlreadyClaimed'),
      };

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(message),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MONTHLY SPECIAL CLAIM ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _activationError =
            _t('rewardClaimFailed');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            _t('rewardClaimFailed'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _claimingReward = false;
        });
      }
    }
  }

  String _timeLeftLabel() {
    if (_loadingActivation) {
      return _t('loading');
    }

    if (_hasCompletedSpecial) {
      return _t('completed');
    }

    if (!_hasActiveSpecial) {
      return _t('thirtyDays');
    }

    final activation = _activation!;

    final remaining =
        _specialService.timeRemainingForActivation(
      activation: activation,
    );

    if (remaining <= Duration.zero) {
      return _t('expired');
    }

    // Ceil the day count so a freshly activated 30-day Special displays
    // "30 days left" instead of immediately dropping to 29.
    final totalMinutes = remaining.inMinutes;
    final days =
        (totalMinutes / Duration.minutesPerDay).ceil();

    if (days > 1) {
      return '$days days left';
    }

    if (days == 1) {
      return '1 day left';
    }

    final hours = remaining.inHours;

    if (hours > 1) {
      return '$hours hours left';
    }

    if (hours == 1) {
      return '1 hour left';
    }

    final minutes = remaining.inMinutes;

    if (minutes > 1) {
      return '$minutes min left';
    }

    return 'Ends soon';
  }

  String _statusLabel({
    required bool isPro,
  }) {
    if (!isPro) {
      return _t('proCaps');
    }

    if (_loadingActivation) {
      return _t('proCaps');
    }

    if (_hasCompletedSpecial) {
      return _rewardClaimed ? _t('claimed') : _t('claim');
    }

    if (_hasActiveSpecial) {
      return 'ACTIVE';
    }

    return _t('proCaps');
  }

  Future<void> _openPro(
    BuildContext context,
  ) async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const MunjaProScreen(),
      ),
    );

    if (mounted) {
      setState(() {});
      await _loadActivation();
    }
  }

  IconData _rewardIcon(
    MonthlySpecialRewardType type,
  ) {
    switch (type) {
      case MonthlySpecialRewardType.badge:
        return Icons.workspace_premium_rounded;
      case MonthlySpecialRewardType.skin:
        return Icons.palette_rounded;
      case MonthlySpecialRewardType.frame:
        return Icons.crop_free_rounded;
    }
  }

  void _showSpecialInfo(
    BuildContext context, {
    required bool isPro,
  }) {
    HapticFeedback.selectionClick();

    final special = _displaySpecial;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            sheetContext,
            setSheetState,
          ) {
            final active = _hasActiveSpecial;
            final completed =
                _hasCompletedSpecial;
            final claimed =
                _rewardClaimed;
            final timeLeft =
                _timeLeftLabel();

            Future<void> startFromSheet() async {
              Navigator.of(sheetContext).pop();
              await _startSpecial(context);
            }

            Future<void> claimFromSheet() async {
              Navigator.of(sheetContext).pop();
              await _claimReward(context);
            }

            return Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.fromLTRB(
                20,
                20,
                20,
                18,
              ),
              decoration: BoxDecoration(
                color: MunjaColors.panel,
                borderRadius:
                    BorderRadius.circular(30),
                border: Border.all(
                  color: MunjaColors.mint
                      .withOpacity(0.24),
                ),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: MunjaColors.mint
                                .withOpacity(0.12),
                          ),
                          child: Icon(
                            active
                                ? Icons
                                    .electric_bolt_rounded
                                : Icons
                                    .auto_awesome_rounded,
                            color: MunjaColors.mint,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                '${special.monthName.toUpperCase()} SPECIAL',
                                style:
                                    const TextStyle(
                                  color:
                                      MunjaColors.mint,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight.w900,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                special.title,
                                style:
                                    const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SpecialStatusBadge(
                          label: _statusLabel(
                            isPro: isPro,
                          ),
                          active:
                              isPro && active,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      special.subtitle,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 12,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      active
                          ? _t('monthlyTimerInfo')
                          : _t('monthlyActivateInfo'),
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        height: 1.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _MonthlySpecialGoalCard(
                      goal: special.goalLabel,
                      timeLeft: timeLeft,
                    ),
                    if (active ||
                        completed) ...[
                      const SizedBox(height: 12),
                      _MonthlySpecialProgressCard(
                        currentValue:
                            _activation?.progressValue ??
                                0,
                        special: special,
                        completed: completed,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child:
                              _MonthlySpecialMiniReward(
                            icon:
                                Icons.bolt_rounded,
                            value:
                                '+${special.xpReward}',
                            label: 'XP',
                          ),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child:
                              _MonthlySpecialMiniReward(
                            icon:
                                Icons.diamond_rounded,
                            value:
                                '+${special.crystalReward}',
                            label: 'CRYSTALS',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    _SpecialRewardRow(
                      icon: _rewardIcon(
                        special.specialReward.type,
                      ),
                      title:
                          special.specialReward.name,
                      subtitle:
                          '${special.specialReward.typeLabel} unlocked when this Monthly Special is completed.',
                    ),
                    if (_activationError !=
                        null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _activationError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton.icon(
                        onPressed:
                            _startingSpecial ||
                                    _claimingReward
                                ? null
                                : !isPro
                                    ? () {
                                        Navigator.of(
                                          sheetContext,
                                        ).pop();
                                        _openPro(
                                          context,
                                        );
                                      }
                                    : active
                                        ? null
                                        : completed
                                            ? claimed
                                                ? null
                                                : claimFromSheet
                                            : startFromSheet,
                        icon:
                            _startingSpecial ||
                                    _claimingReward
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child:
                                        CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : Icon(
                                    !isPro
                                        ? Icons
                                            .lock_open_rounded
                                        : completed
                                            ? claimed
                                                ? Icons
                                                    .verified_rounded
                                                : Icons
                                                    .redeem_rounded
                                            : active
                                                ? Icons
                                                    .electric_bolt_rounded
                                                : Icons
                                                    .play_arrow_rounded,
                                  ),
                        label: Text(
                          _startingSpecial
                              ? 'STARTING...'
                              : _claimingReward
                                  ? 'CLAIMING...'
                                  : !isPro
                                      ? _t('unlockPro')
                                      : completed
                                          ? claimed
                                              ? _t('rewardClaimedCaps')
                                              : _t('claimReward')
                                          : active
                                              ? _t('specialActive')
                                              : 'START ${special.monthName.toUpperCase()} SPECIAL',
                          style: const TextStyle(
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MunjaProState>(
      valueListenable: widget.proService.state,
      builder: (context, proState, _) {
        final isPro = proState.hasActivePro;
        final special = _displaySpecial;
        final active = _hasActiveSpecial;
        final completed =
            _hasCompletedSpecial;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showSpecialInfo(
              context,
              isPro: isPro,
            ),
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              padding: const EdgeInsets.fromLTRB(
                18,
                16,
                18,
                16,
              ),
              decoration: BoxDecoration(
                color: MunjaColors.mint
                    .withOpacity(0.065),
                borderRadius:
                    BorderRadius.circular(26),
                border: Border.all(
                  color: MunjaColors.mint
                      .withOpacity(
                    active ? 0.38 : 0.22,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MunjaColors.mint
                          .withOpacity(0.12),
                    ),
                    child: Icon(
                      !isPro
                          ? Icons.lock_rounded
                          : completed
                              ? Icons
                                  .check_circle_rounded
                              : active
                                  ? Icons
                                      .electric_bolt_rounded
                                  : Icons
                                      .auto_awesome_rounded,
                      color: MunjaColors.mint,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${special.monthName.toUpperCase()} SPECIAL',
                                style:
                                    const TextStyle(
                                  color:
                                      MunjaColors.mint,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight.w900,
                                  letterSpacing: 1.15,
                                ),
                              ),
                            ),
                            Text(
                              _timeLeftLabel(),
                              style: TextStyle(
                                color: active
                                    ? MunjaColors.mint
                                    : Colors.white38,
                                fontSize: 8.5,
                                fontWeight:
                                    FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          special.title,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${special.goalLabel}  ·  +${special.xpReward} XP  ·  +${special.crystalReward} Crystals',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color:
                                MunjaColors.textSoft,
                            fontSize: 9.5,
                            height: 1.3,
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          active
                              ? 'Progress ${_formatSpecialProgress(_activation?.progressValue ?? 0, special)}'
                              : completed
                                  ? _rewardClaimed
                                      ? 'Claimed · ${special.specialReward.name} unlocked'
                                      : 'Completed · reward ready to claim'
                                  : '${special.specialReward.typeLabel}: ${special.specialReward.name}',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                            fontWeight:
                                FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SpecialStatusBadge(
                    label: _statusLabel(
                      isPro: isPro,
                    ),
                    active: isPro && active,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpecialStatusBadge extends StatelessWidget {
  _SpecialStatusBadge({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: active
            ? MunjaColors.mint.withOpacity(0.13)
            : Colors.white.withOpacity(0.055),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.30)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active
              ? MunjaColors.mint
              : Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _MonthlySpecialProgressCard
    extends StatelessWidget {
  _MonthlySpecialProgressCard({
    required this.currentValue,
    required this.special,
    required this.completed,
  });

  final double currentValue;
  final MonthlySpecial special;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final progress =
        MonthlySpecialService.instance.progress(
      special: special,
      currentValue: currentValue,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('progressCaps'),
                style: TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                completed
                    ? '100%'
                    : '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor:
                  Colors.white.withOpacity(0.06),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                MunjaColors.mint,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatSpecialProgress(
              currentValue,
              special,
            ),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSpecialProgress(
  double currentValue,
  MonthlySpecial special,
) {
  final safeCurrent = currentValue
      .clamp(0.0, special.goalValue)
      .toDouble();

  switch (special.goalType) {
    case MonthlySpecialGoalType.distanceKm:
      return '${safeCurrent.toStringAsFixed(1)} / ${special.goalValue.toStringAsFixed(0)} km';
    case MonthlySpecialGoalType.rideCount:
      return '${safeCurrent.toInt()} / ${special.goalValue.toInt()} rides';
    case MonthlySpecialGoalType.rideMinutes:
      return '${safeCurrent.toInt()} / ${special.goalValue.toInt()} min';
    case MonthlySpecialGoalType.streakDays:
      return '${safeCurrent.toInt()} / ${special.goalValue.toInt()} days';
  }
}

class _MonthlySpecialGoalCard
    extends StatelessWidget {
  _MonthlySpecialGoalCard({
    required this.goal,
    required this.timeLeft,
  });

  final String goal;
  final String timeLeft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.16),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.flag_rounded,
            color: MunjaColors.mint,
            size: 22,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  _t('monthlyGoal'),
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  goal,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          Text(
            timeLeft,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlySpecialMiniReward
    extends StatelessWidget {
  _MonthlySpecialMiniReward({
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
      height: 66,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 7.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProStatusBadge extends StatelessWidget {
  _ProStatusBadge({
    required this.active,
  });

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: active
            ? MunjaColors.mint.withOpacity(0.13)
            : Colors.white.withOpacity(0.055),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.25)
              : Colors.white.withOpacity(0.06),
        ),
      ),
      child: Text(
        active ? _t('proCaps') : _t('proCaps'),
        style: TextStyle(
          color: active ? MunjaColors.mint : Colors.white54,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SpecialRewardRow extends StatelessWidget {
  _SpecialRewardRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 20,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 9.5,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle
    extends StatelessWidget {
  _SectionTitle({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: MunjaColors.textSoft,
        fontSize: 10,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.25,
      ),
    );
  }
}

class _ChallengeTypeSelector
    extends StatelessWidget {
  _ChallengeTypeSelector({
    required this.items,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<_ChallengeTypeData> items;
  final _ChallengeKind selected;
  final bool enabled;
  final ValueChanged<_ChallengeTypeData>
      onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.38,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final active =
            selected == item.kind;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled
                ? () => onSelected(item)
                : null,
            borderRadius:
                BorderRadius.circular(24),
            child: AnimatedContainer(
              duration:
                  const Duration(
                milliseconds: 220,
              ),
              padding:
                  const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: active
                    ? MunjaColors.mint
                        .withOpacity(0.11)
                    : MunjaColors.panel
                        .withOpacity(0.62),
                borderRadius:
                    BorderRadius.circular(
                  24,
                ),
                border: Border.all(
                  color: active
                      ? MunjaColors.mint
                          .withOpacity(0.42)
                      : Colors.white
                          .withOpacity(0.055),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        item.icon,
                        color: item.enabled
                            ? MunjaColors.mint
                            : Colors.white30,
                        size: 21,
                      ),
                      const Spacer(),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    item.title,
                    style: TextStyle(
                      color: item.enabled
                          ? Colors.white
                          : Colors.white54,
                      fontSize: 14,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        const TextStyle(
                      color:
                          MunjaColors.textSoft,
                      fontSize: 9,
                      height: 1.25,
                      fontWeight:
                          FontWeight.w600,
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
}

class _FriendPicker
    extends StatelessWidget {
  _FriendPicker({
    required this.friends,
    required this.selectedFriend,
    required this.enabled,
    required this.onSelected,
  });

  final List<SocialRiderProfile>
      friends;
  final SocialRiderProfile?
      selectedFriend;
  final bool enabled;
  final ValueChanged<SocialRiderProfile>
      onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: friends.map(
        (rider) {
          final selected =
              selectedFriend?.uid ==
                  rider.uid;

          return Padding(
            padding:
                const EdgeInsets.only(
              bottom: 10,
            ),
            child: _FriendChoiceCard(
              rider: rider,
              selected: selected,
              enabled: enabled,
              onTap: () =>
                  onSelected(rider),
            ),
          );
        },
      ).toList(),
    );
  }
}

class _FriendChoiceCard
    extends StatelessWidget {
  _FriendChoiceCard({
    required this.rider,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final SocialRiderProfile rider;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        rider.photoUrl != null &&
            rider.photoUrl!
                .trim()
                .isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            enabled ? onTap : null,
        borderRadius:
            BorderRadius.circular(25),
        child: AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 220,
          ),
          padding:
              const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint
                    .withOpacity(0.10)
                : MunjaColors.panel
                    .withOpacity(0.66),
            borderRadius:
                BorderRadius.circular(25),
            border: Border.all(
              color: selected
                  ? MunjaColors.mint
                      .withOpacity(0.42)
                  : Colors.white
                      .withOpacity(0.06),
              width:
                  selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration:
                    BoxDecoration(
                  shape: BoxShape.circle,
                  color: MunjaColors.mint
                      .withOpacity(0.09),
                  border: Border.all(
                    color: selected
                        ? MunjaColors.mint
                            .withOpacity(
                              0.48,
                            )
                        : MunjaColors.mint
                            .withOpacity(
                              0.20,
                            ),
                  ),
                ),
                clipBehavior:
                    Clip.antiAlias,
                child: hasPhoto
                    ? Image.network(
                        rider.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (
                          context,
                          error,
                          stackTrace,
                        ) {
                          return _FallbackAvatar();
                        },
                      )
                    : _FallbackAvatar(),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      rider.displayName,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          const TextStyle(
                        color:
                            Colors.white,
                        fontSize: 16,
                        fontWeight:
                            FontWeight
                                .w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      rider.usernameWithAt,
                      style:
                          const TextStyle(
                        color:
                            MunjaColors.mint,
                        fontSize: 12,
                        fontWeight:
                            FontWeight
                                .w900,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      'LVL ${rider.level} · ${rider.totalXp} XP',
                      style:
                          const TextStyle(
                        color: MunjaColors
                            .textSoft,
                        fontSize: 10,
                        fontWeight:
                            FontWeight
                                .w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 220,
                ),
                width: 28,
                height: 28,
                decoration:
                    BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? MunjaColors.mint
                      : Colors.white
                          .withOpacity(
                            0.04,
                          ),
                  border: Border.all(
                    color: selected
                        ? MunjaColors.mint
                        : Colors.white
                            .withOpacity(
                              0.12,
                            ),
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons
                            .check_rounded,
                        color:
                            Colors.black,
                        size: 18,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DistanceSelector
    extends StatelessWidget {
  _DistanceSelector({
    required this.options,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<double> options;
  final double selected;
  final bool enabled;
  final ValueChanged<double>
      onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options
          .asMap()
          .entries
          .map(
            (entry) {
              final index =
                  entry.key;
              final value =
                  entry.value;

              return Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.only(
                    right:
                        index ==
                                options
                                        .length -
                                    1
                            ? 0
                            : 10,
                  ),
                  child: _ChoiceTile(
                    label:
                        '${value.toStringAsFixed(0)} KM',
                    icon:
                        Icons.route_rounded,
                    selected:
                        selected == value,
                    enabled: enabled,
                    onTap: () =>
                        onSelected(value),
                  ),
                ),
              );
            },
          )
          .toList(),
    );
  }
}

class _IntChoiceSelector extends StatelessWidget {
  _IntChoiceSelector({
    required this.options,
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.labelBuilder,
    required this.onSelected,
  });

  final List<int> options;
  final int selected;
  final bool enabled;
  final IconData icon;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.asMap().entries.map((entry) {
        final index = entry.key;
        final value = entry.value;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index == options.length - 1 ? 0 : 10,
            ),
            child: _ChoiceTile(
              label: labelBuilder(value),
              icon: icon,
              selected: selected == value,
              enabled: enabled,
              onTap: () => onSelected(value),
            ),
          ),
        );
      }).toList(),
    );
  }
}


class _DurationSelector
    extends StatelessWidget {
  _DurationSelector({
    required this.options,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final List<int> options;
  final int selected;
  final bool enabled;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options
          .asMap()
          .entries
          .map(
            (entry) {
              final index =
                  entry.key;
              final value =
                  entry.value;

              return Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.only(
                    right:
                        index ==
                                options
                                        .length -
                                    1
                            ? 0
                            : 10,
                  ),
                  child: _ChoiceTile(
                    label:
                        '$value DAYS',
                    icon: Icons
                        .calendar_month_rounded,
                    selected:
                        selected == value,
                    enabled: enabled,
                    onTap: () =>
                        onSelected(value),
                  ),
                ),
              );
            },
          )
          .toList(),
    );
  }
}

class _ChoiceTile
    extends StatelessWidget {
  _ChoiceTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:
            enabled ? onTap : null,
        borderRadius:
            BorderRadius.circular(22),
        child: AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 220,
          ),
          height: 94,
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint
                    .withOpacity(0.12)
                : MunjaColors.panel
                    .withOpacity(0.64),
            borderRadius:
                BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? MunjaColors.mint
                      .withOpacity(0.46)
                  : Colors.white
                      .withOpacity(0.06),
            ),
          ),
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected
                    ? MunjaColors.mint
                    : MunjaColors
                        .textSoft,
                size: 24,
              ),
              const SizedBox(height: 9),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : MunjaColors
                          .textSoft,
                  fontSize: 11,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChallengeRewardPreview
    extends StatelessWidget {
  _ChallengeRewardPreview({
    required this.crystals,
    required this.xp,
  });

  final int crystals;
  final int xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:
            MunjaColors.mint.withOpacity(
          0.065,
        ),
        borderRadius:
            BorderRadius.circular(27),
        border: Border.all(
          color:
              MunjaColors.mint.withOpacity(
            0.20,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            _t('challengeReward'),
            style: TextStyle(
              color: MunjaColors.mint,
              fontSize: 9,
              fontWeight:
                  FontWeight.w900,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RewardPill(
                  icon:
                      Icons.diamond_rounded,
                  value: '+$crystals',
                  label: 'CRYSTALS',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RewardPill(
                  icon:
                      Icons.bolt_rounded,
                  value: '+$xp',
                  label: 'XP',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RewardPill
    extends StatelessWidget {
  _RewardPill({
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
      height: 68,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 13,
      ),
      decoration: BoxDecoration(
        color:
            Colors.black.withOpacity(
          0.17,
        ),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color:
              Colors.white.withOpacity(
            0.055,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 20,
          ),
          const SizedBox(width: 9),
          Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color:
                      MunjaColors.textSoft,
                  fontSize: 8,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChallengeSummaryCard
    extends StatelessWidget {
  _ChallengeSummaryCard({
    required this.friend,
    required this.goal,
    required this.goalIcon,
    required this.durationDays,
  });

  final SocialRiderProfile? friend;
  final String goal;
  final IconData goalIcon;
  final int durationDays;

  @override
  Widget build(BuildContext context) {
    final riderText = friend == null
        ? _t('chooseRiderFirst')
        : friend!.usernameWithAt;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel
            .withOpacity(0.74),
        borderRadius:
            BorderRadius.circular(28),
        border: Border.all(
          color:
              MunjaColors.mint.withOpacity(
            0.13,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons
                    .sports_score_rounded,
                color:
                    MunjaColors.mint,
                size: 21,
              ),
              SizedBox(width: 8),
              Text(
                _t('challengeSummary'),
                style: TextStyle(
                  color:
                      MunjaColors.mint,
                  fontSize: 9,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            riderText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight:
                  FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child:
                    _SummaryMetric(
                  label: _t('goal'),
                  value: goal,
                  icon: goalIcon,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child:
                    _SummaryMetric(
                  label: _t('time'),
                  value:
                      '$durationDays days',
                  icon: Icons
                      .timer_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            _t('challengeStartsAccept'),
            style: TextStyle(
              color:
                  MunjaColors.textSoft,
              fontSize: 11,
              height: 1.4,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric
    extends StatelessWidget {
  _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color:
            Colors.black.withOpacity(
          0.16,
        ),
        borderRadius:
            BorderRadius.circular(19),
        border: Border.all(
          color:
              Colors.white.withOpacity(
            0.055,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment
                      .center,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  value,
                  style:
                      const TextStyle(
                    color:
                        Colors.white,
                    fontSize: 14,
                    fontWeight:
                        FontWeight
                            .w900,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  label,
                  style:
                      const TextStyle(
                    color: MunjaColors
                        .textSoft,
                    fontSize: 8,
                    fontWeight:
                        FontWeight
                            .w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackAvatar
    extends StatelessWidget {
  _FallbackAvatar();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.person_rounded,
        color: MunjaColors.mint,
        size: 30,
      ),
    );
  }
}

class _CreateChallengeLoading
    extends StatelessWidget {
  _CreateChallengeLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        20,
        90,
        20,
        360,
      ),
      children: [
        Center(
          child: Column(
            children: [
              const CircularProgressIndicator(
                color:
                    MunjaColors.mint,
              ),
              const SizedBox(height: 16),
              Text(
                _t('loadingFriends'),
                style: TextStyle(
                  color: MunjaColors
                      .textSoft,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateChallengeError
    extends StatelessWidget {
  _CreateChallengeError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function()
      onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        20,
        55,
        20,
        360,
      ),
      children: [
        Container(
          padding:
              const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: MunjaColors.panel
                .withOpacity(0.55),
            borderRadius:
                BorderRadius.circular(
              28,
            ),
            border: Border.all(
              color: MunjaColors.danger
                  .withOpacity(0.20),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons
                    .error_outline_rounded,
                color:
                    MunjaColors.danger,
                size: 34,
              ),
              const SizedBox(
                height: 14,
              ),
              Text(
                _t('couldNotCreate'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              const SizedBox(
                height: 7,
              ),
              Text(
                message,
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  color: MunjaColors
                      .textSoft,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              const SizedBox(
                height: 16,
              ),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: Text(
                  _t('tryAgain'),
                  style: TextStyle(
                    fontWeight:
                        FontWeight
                            .w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NoChallengeFriends
    extends StatelessWidget {
  _NoChallengeFriends();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        20,
        60,
        20,
        360,
      ),
      children: [
        Container(
          padding:
              const EdgeInsets.fromLTRB(
            24,
            30,
            24,
            30,
          ),
          decoration: BoxDecoration(
            color: MunjaColors.panel
                .withOpacity(0.50),
            borderRadius:
                BorderRadius.circular(
              30,
            ),
            border: Border.all(
              color: Colors.white
                  .withOpacity(0.055),
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons
                    .people_outline_rounded,
                color:
                    MunjaColors.mint,
                size: 40,
              ),
              SizedBox(height: 16),
              Text(
                _t('noFriendsChallenge'),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                _t('addFriendFirst'),
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  color: MunjaColors
                      .textSoft,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

BoxDecoration _premiumDecoration() {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.72),
    borderRadius: BorderRadius.circular(30),
    border: Border.all(
      color:
          MunjaColors.mint.withOpacity(
        0.14,
      ),
    ),
    boxShadow: [
      BoxShadow(
        color:
            MunjaColors.mint.withOpacity(
          0.06,
        ),
        blurRadius: 36,
        offset:
            const Offset(0, 18),
      ),
    ],
  );
}
