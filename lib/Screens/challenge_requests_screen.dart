import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/social_rider_profile.dart';
import '../services/challenge_service.dart';
import '../services/social_rider_service.dart';


String _t(String key) => AppText.t(key);

class ChallengeRequestsScreen extends StatefulWidget {
  const ChallengeRequestsScreen({super.key});

  @override
  State<ChallengeRequestsScreen> createState() =>
      _ChallengeRequestsScreenState();
}

class _ChallengeRequestsScreenState
    extends State<ChallengeRequestsScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;

  final Set<String> _processingChallengeIds = <String>{};

  List<_IncomingChallengeItem> _items =
      const <_IncomingChallengeItem>[];

  List<_OutgoingChallengeItem> _outgoingItems =
      const <_OutgoingChallengeItem>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadChallenges);
  }

  Future<void> _loadChallenges({
    bool showRefreshState = false,
  }) async {
    if (showRefreshState && mounted) {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final incomingChallenges =
          await ChallengeService.instance.getIncomingChallenges();

      final outgoingChallenges =
          await ChallengeService.instance.getOutgoingChallenges();

      final loadedItems = <_IncomingChallengeItem>[];
      final loadedOutgoingItems = <_OutgoingChallengeItem>[];

      for (final challenge in incomingChallenges) {
        try {
          final rider =
              await SocialRiderService.instance.getProfileByUid(
            challenge.creatorUid,
          );

          if (rider == null) {
            continue;
          }

          loadedItems.add(
            _IncomingChallengeItem(
              challenge: challenge,
              rider: rider,
            ),
          );
        } catch (error, stackTrace) {
          debugPrint(
            'CHALLENGE CREATOR PROFILE LOAD ERROR: $error',
          );
          debugPrint('$stackTrace');
        }
      }

      for (final challenge in outgoingChallenges) {
        try {
          final rider =
              await SocialRiderService.instance.getProfileByUid(
            challenge.opponentUid,
          );

          if (rider == null) {
            continue;
          }

          loadedOutgoingItems.add(
            _OutgoingChallengeItem(
              challenge: challenge,
              rider: rider,
            ),
          );
        } catch (error, stackTrace) {
          debugPrint(
            'CHALLENGE OPPONENT PROFILE LOAD ERROR: $error',
          );
          debugPrint('$stackTrace');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _items = loadedItems;
        _outgoingItems = loadedOutgoingItems;
        _errorMessage = null;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('CHALLENGE REQUESTS LOAD ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            _t('requestsLoadFailed');
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

  Future<void> _acceptChallenge(
    _IncomingChallengeItem item,
  ) async {
    final challengeId = item.challenge.id;

    if (_processingChallengeIds.contains(challengeId)) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _processingChallengeIds.add(challengeId);
    });

    try {
      await ChallengeService.instance.acceptChallenge(
        challengeId: challengeId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = _items
            .where(
              (current) =>
                  current.challenge.id != challengeId,
            )
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            '${_t('challengesTitle')}: ${item.rider.usernameWithAt} · ${_t('activeCaps')}',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(error.message),
        ),
      );

      await _loadChallenges();
    } catch (error, stackTrace) {
      debugPrint('ACCEPT CHALLENGE ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            _t('acceptFailed'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingChallengeIds.remove(challengeId);
        });
      }
    }
  }

  Future<void> _declineChallenge(
    _IncomingChallengeItem item,
  ) async {
    final challengeId = item.challenge.id;

    if (_processingChallengeIds.contains(challengeId)) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _processingChallengeIds.add(challengeId);
    });

    try {
      await ChallengeService.instance.declineChallenge(
        challengeId: challengeId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = _items
            .where(
              (current) =>
                  current.challenge.id != challengeId,
            )
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            '${item.rider.usernameWithAt} · ${_t('decline')}',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(error.message),
        ),
      );

      await _loadChallenges();
    } catch (error, stackTrace) {
      debugPrint('DECLINE CHALLENGE ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            _t('declineFailed'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingChallengeIds.remove(challengeId);
        });
      }
    }
  }

  Future<void> _confirmDecline(
    _IncomingChallengeItem item,
  ) async {
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
            _t('declineChallengeQ'),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Decline the ${item.challenge.targetDistanceKm.toStringAsFixed(0)} km '
            'challenge from ${item.rider.usernameWithAt}?',
            style: const TextStyle(
              color: MunjaColors.textSoft,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_t('cancel')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: MunjaColors.danger,
                foregroundColor: Colors.white,
              ),
              child: Text(
                _t('decline'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _declineChallenge(item);
    }
  }

  Future<void> _cancelChallenge(
    _OutgoingChallengeItem item,
  ) async {
    final challengeId = item.challenge.id;

    if (_processingChallengeIds.contains(challengeId)) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _processingChallengeIds.add(challengeId);
    });

    try {
      await ChallengeService.instance.cancelChallenge(
        challengeId: challengeId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _outgoingItems = _outgoingItems
            .where(
              (current) =>
                  current.challenge.id != challengeId,
            )
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            '${item.rider.usernameWithAt} · ${_t('cancelChallenge')}',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(error.message),
        ),
      );

      await _loadChallenges();
    } catch (error, stackTrace) {
      debugPrint('CANCEL CHALLENGE ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            _t('cancelFailed'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingChallengeIds.remove(challengeId);
        });
      }
    }
  }

  Future<void> _confirmCancel(
    _OutgoingChallengeItem item,
  ) async {
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
            _t('cancelChallengeQ'),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Cancel the ${item.challenge.targetDistanceKm.toStringAsFixed(0)} km '
            'challenge sent to ${item.rider.usernameWithAt}? '
            'This removes the pending invitation.',
            style: const TextStyle(
              color: MunjaColors.textSoft,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_t('keepChallenge')),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: MunjaColors.danger,
                foregroundColor: Colors.white,
              ),
              child: Text(
                _t('cancelChallenge'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _cancelChallenge(item);
    }
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
        title: Text(
          _t('challengeRequests'),
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
          onRefresh: () => _loadChallenges(
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
      return _ChallengeRequestsLoading();
    }

    if (_errorMessage != null) {
      return _ChallengeRequestsError(
        message: _errorMessage!,
        onRetry: _loadChallenges,
      );
    }

    if (_items.isEmpty && _outgoingItems.isEmpty) {
      return _EmptyChallengeRequests();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        12,
        20,
        360,
      ),
      children: [
        _ChallengeRequestsHeader(
          count: _items.length,
          outgoingCount: _outgoingItems.length,
          refreshing: _refreshing,
        ),
        const SizedBox(height: 18),

        if (_items.isNotEmpty) ...[
          _ChallengeSectionTitle(
            eyebrow: _t('incoming'),
            title: _t('requestsForYou'),
          ),
          const SizedBox(height: 12),
          ..._items.map(
            (item) {
              final processing =
                  _processingChallengeIds.contains(
                item.challenge.id,
              );

              return Padding(
                padding: const EdgeInsets.only(
                  bottom: 14,
                ),
                child: _ChallengeRequestCard(
                  item: item,
                  processing: processing,
                  onAccept: () => _acceptChallenge(item),
                  onDecline: () => _confirmDecline(item),
                ),
              );
            },
          ),
        ],

        if (_outgoingItems.isNotEmpty) ...[
          const SizedBox(height: 6),
          _ChallengeSectionTitle(
            eyebrow: _t('outgoing'),
            title: 'Sent challenges',
          ),
          const SizedBox(height: 12),
          ..._outgoingItems.map(
            (item) {
              final processing =
                  _processingChallengeIds.contains(
                item.challenge.id,
              );

              return Padding(
                padding: const EdgeInsets.only(
                  bottom: 14,
                ),
                child: _OutgoingChallengeCard(
                  item: item,
                  processing: processing,
                  onCancel: () => _confirmCancel(item),
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _IncomingChallengeItem {
  _IncomingChallengeItem({
    required this.challenge,
    required this.rider,
  });

  final MunjaChallenge challenge;
  final SocialRiderProfile rider;
}

class _OutgoingChallengeItem {
  _OutgoingChallengeItem({
    required this.challenge,
    required this.rider,
  });

  final MunjaChallenge challenge;
  final SocialRiderProfile rider;
}

class _ChallengeRequestsHeader extends StatelessWidget {
  _ChallengeRequestsHeader({
    required this.count,
    required this.outgoingCount,
    required this.refreshing,
  });

  final int count;
  final int outgoingCount;
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
              Icons.emoji_events_rounded,
              color: MunjaColors.mint,
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('challengesTitle'),
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${count + outgoingCount} pending '
                  '${count + outgoingCount == 1 ? 'challenge' : 'challenges'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  count > 0 && outgoingCount > 0
                      ? '$count incoming · $outgoingCount sent'
                      : count > 0
                          ? '$count incoming'
                          : '$outgoingCount sent',
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

class _ChallengeSectionTitle extends StatelessWidget {
  _ChallengeSectionTitle({
    required this.eyebrow,
    required this.title,
  });

  final String eyebrow;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
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
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _OutgoingChallengeCard extends StatelessWidget {
  _OutgoingChallengeCard({
    required this.item,
    required this.processing,
    required this.onCancel,
  });

  final _OutgoingChallengeItem item;
  final bool processing;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final rider = item.rider;
    final challenge = item.challenge;

    final hasPhoto =
        rider.photoUrl != null &&
        rider.photoUrl!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.72),
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
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MunjaColors.mint.withOpacity(0.10),
                  border: Border.all(
                    color: MunjaColors.mint.withOpacity(0.28),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? Image.network(
                        rider.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _FallbackAvatar(),
                      )
                    : _FallbackAvatar(),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rider.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rider.usernameWithAt,
                      style: const TextStyle(
                        color: MunjaColors.mint,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _t('waitingResponse'),
                      style: TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _t('pending'),
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ChallengeMetric(
                  icon: Icons.route_rounded,
                  label: _t('distance'),
                  value:
                      '${challenge.targetDistanceKm.toStringAsFixed(0)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChallengeMetric(
                  icon: Icons.calendar_month_rounded,
                  label: _t('duration'),
                  value: '${challenge.durationDays} days',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: processing ? null : onCancel,
              icon: processing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: MunjaColors.danger,
                      ),
                    )
                  : const Icon(
                      Icons.cancel_outlined,
                    ),
              label: Text(
                processing
                    ? _t('cancelling')
                    : _t('cancelChallenge'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MunjaColors.danger,
                side: BorderSide(
                  color: MunjaColors.danger.withOpacity(0.30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallengeRequestCard extends StatelessWidget {
  _ChallengeRequestCard({
    required this.item,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
  });

  final _IncomingChallengeItem item;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final rider = item.rider;
    final challenge = item.challenge;

    final hasPhoto =
        rider.photoUrl != null &&
        rider.photoUrl!.trim().isNotEmpty;

    return Container(
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
                    color: MunjaColors.mint.withOpacity(0.32),
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
                          return _FallbackAvatar();
                        },
                      )
                    : _FallbackAvatar(),
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
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
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
                                BorderRadius.circular(999),
                          ),
                          child: Text(
                            'LVL ${rider.level}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
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
                        fontWeight: FontWeight.w900,
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
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ChallengeMetric(
                  icon: Icons.route_rounded,
                  label: _t('distance'),
                  value:
                      '${challenge.targetDistanceKm.toStringAsFixed(0)} km',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ChallengeMetric(
                  icon: Icons.calendar_month_rounded,
                  label: _t('duration'),
                  value:
                      '${challenge.durationDays} days',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: MunjaColors.mint.withOpacity(0.11),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  color: MunjaColors.mint,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${rider.usernameWithAt} challenges you to '
                    '${challenge.targetDistanceKm.toStringAsFixed(0)} km '
                    'over ${challenge.durationDays} days.',
                    style: const TextStyle(
                      color: MunjaColors.textSoft,
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed:
                        processing ? null : onDecline,
                    icon: const Icon(
                      Icons.close_rounded,
                    ),
                    label: Text(
                      _t('decline'),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor:
                          MunjaColors.textSoft,
                      side: BorderSide(
                        color:
                            Colors.white.withOpacity(0.10),
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
                    onPressed:
                        processing ? null : onAccept,
                    icon: processing
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2.1,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(
                            Icons.check_rounded,
                          ),
                    label: Text(
                      processing
                          ? _t('working')
                          : _t('accept'),
                      style: const TextStyle(
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

class _ChallengeMetric extends StatelessWidget {
  _ChallengeMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

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
                  overflow: TextOverflow.ellipsis,
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

class _FallbackAvatar extends StatelessWidget {
  _FallbackAvatar();

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

class _ChallengeRequestsLoading extends StatelessWidget {
  _ChallengeRequestsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        80,
        20,
        360,
      ),
      children: [
        Center(
          child: Column(
            children: [
              const CircularProgressIndicator(
                color: MunjaColors.mint,
              ),
              const SizedBox(height: 16),
              Text(
                _t('loadingRequests'),
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

class _ChallengeRequestsError extends StatelessWidget {
  _ChallengeRequestsError({
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
        360,
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
              Text(
                _t('couldNotLoadRequests'),
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
                label: Text(
                  _t('tryAgain'),
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

class _EmptyChallengeRequests extends StatelessWidget {
  _EmptyChallengeRequests();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        20,
        60,
        20,
        360,
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
                Icons.emoji_events_outlined,
                color: MunjaColors.mint,
                size: 40,
              ),
              SizedBox(height: 16),
              Text(
                'No pending challenges',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'When a Munja friend challenges you, '
                'the invitation will appear here.',
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
