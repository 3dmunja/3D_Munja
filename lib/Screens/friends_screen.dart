import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/munja_colors.dart';
import '../models/social_rider_profile.dart';
import '../services/friend_service.dart';
import '../services/social_rider_service.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;

  List<SocialRiderProfile> _friends = const <SocialRiderProfile>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadFriends);
  }

  Future<void> _loadFriends({
    bool showRefreshState = false,
  }) async {
    if (showRefreshState && mounted) {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final friendUids = await FriendService.instance.getFriendUids();

      final loadedFriends = <SocialRiderProfile>[];

      for (final uid in friendUids) {
        try {
          final rider =
              await SocialRiderService.instance.getProfileByUid(uid);

          if (rider != null) {
            loadedFriends.add(rider);
          }
        } catch (error, stackTrace) {
          debugPrint('FRIEND PROFILE LOAD ERROR: $error');
          debugPrint('$stackTrace');
        }
      }

      loadedFriends.sort(
        (a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _friends = loadedFriends;
        _errorMessage = null;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('FRIENDS LOAD ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'Your Munja friends could not be loaded. Please try again.';
        _loading = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _openRider(
    SocialRiderProfile rider,
  ) async {
    HapticFeedback.selectionClick();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: MunjaColors.panel,
      barrierColor: Colors.black.withOpacity(0.72),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(32),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              18,
              20,
              28,
            ),
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
                _FriendSheetProfile(
                  rider: rider,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showChallengeComingSoon(
    SocialRiderProfile rider,
  ) {
    HapticFeedback.mediumImpact();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: MunjaColors.panel,
        content: Text(
          '1 vs 1 challenge with ${rider.usernameWithAt} '
          'is the next Munja social step.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MunjaColors.bg,
      appBar: AppBar(
        backgroundColor: MunjaColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
          ),
        ),
        title: const Text(
          'Friends',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: () => _loadFriends(
            showRefreshState: true,
          ),
          color: MunjaColors.mint,
          backgroundColor: MunjaColors.panel,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const _FriendsLoading();
    }

    if (_errorMessage != null) {
      return _FriendsError(
        message: _errorMessage!,
        onRetry: _loadFriends,
      );
    }

    if (_friends.isEmpty) {
      return const _EmptyFriends();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        12,
        20,
        44,
      ),
      children: [
        _FriendsHeader(
          count: _friends.length,
          refreshing: _refreshing,
        ),
        const SizedBox(height: 18),
        ..._friends.map(
          (rider) {
            return Padding(
              padding: const EdgeInsets.only(
                bottom: 14,
              ),
              child: _FriendCard(
                rider: rider,
                onTap: () => _openRider(rider),
                onChallenge: () =>
                    _showChallengeComingSoon(rider),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FriendsHeader extends StatelessWidget {
  const _FriendsHeader({
    required this.count,
    required this.refreshing,
  });

  final int count;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.72),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.14),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.06),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.11),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.people_alt_rounded,
              color: MunjaColors.mint,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MUNJA CREW',
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? 'friend' : 'friends'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Your Munja riders are ready for rides, '
                  'progress and future challenges.',
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (refreshing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MunjaColors.mint,
              ),
            ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.rider,
    required this.onTap,
    required this.onChallenge,
  });

  final SocialRiderProfile rider;
  final VoidCallback onTap;
  final VoidCallback onChallenge;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        rider.photoUrl != null &&
        rider.photoUrl!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: MunjaColors.panel.withOpacity(0.78),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MunjaColors.mint.withOpacity(0.10),
                      border: Border.all(
                        color:
                            MunjaColors.mint.withOpacity(0.32),
                        width: 2,
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
                              return const _FallbackAvatar();
                            },
                          )
                        : const _FallbackAvatar(),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                rider.displayName,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight:
                                      FontWeight.w900,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: MunjaColors.mint,
                                borderRadius:
                                    BorderRadius.circular(
                                  999,
                                ),
                              ),
                              child: Text(
                                'LVL ${rider.level}',
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 9,
                                  fontWeight:
                                      FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rider.usernameWithAt,
                          style: const TextStyle(
                            color: MunjaColors.mint,
                            fontSize: 13,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          rider.riderId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 9,
                            fontWeight:
                                FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (rider.city != null &&
                  rider.city!.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_rounded,
                      color: MunjaColors.textSoft,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      rider.city!,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _FriendMetric(
                      label: 'LEVEL',
                      value: '${rider.level}',
                      icon:
                          Icons.workspace_premium_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FriendMetric(
                      label: 'TOTAL XP',
                      value: '${rider.totalXp}',
                      icon: Icons.bolt_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: onChallenge,
                  icon: const Icon(
                    Icons.bolt_rounded,
                  ),
                  label: const Text(
                    'Challenge',
                    style: TextStyle(
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
  }
}

class _FriendMetric extends StatelessWidget {
  const _FriendMetric({
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
      height: 72,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: MunjaColors.mint,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
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
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendSheetProfile extends StatelessWidget {
  const _FriendSheetProfile({
    required this.rider,
  });

  final SocialRiderProfile rider;

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        rider.photoUrl != null &&
        rider.photoUrl!.trim().isNotEmpty;

    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MunjaColors.mint.withOpacity(0.10),
            border: Border.all(
              color: MunjaColors.mint.withOpacity(0.40),
              width: 2,
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
                    return const _FallbackAvatar();
                  },
                )
              : const _FallbackAvatar(),
        ),
        const SizedBox(height: 14),
        Text(
          rider.displayName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rider.usernameWithAt,
          style: const TextStyle(
            color: MunjaColors.mint,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rider.riderId,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        if (rider.city != null &&
            rider.city!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_on_rounded,
                color: MunjaColors.textSoft,
                size: 16,
              ),
              const SizedBox(width: 5),
              Text(
                rider.city!,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _FriendMetric(
                label: 'LEVEL',
                value: '${rider.level}',
                icon:
                    Icons.workspace_premium_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _FriendMetric(
                label: 'TOTAL XP',
                value: '${rider.totalXp}',
                icon: Icons.bolt_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  const _FallbackAvatar();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(
        Icons.person_rounded,
        color: MunjaColors.mint,
        size: 32,
      ),
    );
  }
}

class _FriendsLoading extends StatelessWidget {
  const _FriendsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        80,
        20,
        44,
      ),
      children: const [
        Center(
          child: Column(
            children: [
              CircularProgressIndicator(
                color: MunjaColors.mint,
              ),
              SizedBox(height: 16),
              Text(
                'Loading friends...',
                style: TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FriendsError extends StatelessWidget {
  const _FriendsError({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function({
    bool showRefreshState,
  }) onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        50,
        20,
        44,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color:
                MunjaColors.panel.withOpacity(0.55),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color:
                  MunjaColors.danger.withOpacity(0.20),
            ),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: MunjaColors.danger,
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                'Could not load friends',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  onRetry(
                    showRefreshState: false,
                  );
                },
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text(
                  'Try again',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
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

class _EmptyFriends extends StatelessWidget {
  const _EmptyFriends();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        60,
        20,
        44,
      ),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(
            24,
            30,
            24,
            30,
          ),
          decoration: BoxDecoration(
            color:
                MunjaColors.panel.withOpacity(0.50),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withOpacity(0.055),
            ),
          ),
          child: const Column(
            children: [
              Icon(
                Icons.people_outline_rounded,
                color: MunjaColors.mint,
                size: 40,
              ),
              SizedBox(height: 16),
              Text(
                'No friends yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'Find another Munja rider, send a request '
                'and build your crew.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
