import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/munja_colors.dart';
import '../models/social_rider_profile.dart';
import '../services/friend_service.dart';
import '../services/social_rider_service.dart';

class FriendRequestsScreen extends StatefulWidget {
  const FriendRequestsScreen({super.key});

  @override
  State<FriendRequestsScreen> createState() =>
      _FriendRequestsScreenState();
}

class _FriendRequestsScreenState extends State<FriendRequestsScreen> {
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;

  final Set<String> _processingRequestIds = <String>{};

  List<_IncomingFriendRequestItem> _items =
      const <_IncomingFriendRequestItem>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadRequests);
  }

  Future<void> _loadRequests({
    bool showRefreshState = false,
  }) async {
    if (showRefreshState && mounted) {
      setState(() {
        _refreshing = true;
      });
    }

    try {
      final requests =
          await FriendService.instance.getIncomingRequests();

      final loadedItems = <_IncomingFriendRequestItem>[];

      for (final request in requests) {
        try {
          final rider =
              await SocialRiderService.instance.getProfileByUid(
            request.fromUid,
          );

          if (rider == null) {
            continue;
          }

          loadedItems.add(
            _IncomingFriendRequestItem(
              request: request,
              rider: rider,
            ),
          );
        } catch (error, stackTrace) {
          debugPrint(
            'FRIEND REQUEST SENDER PROFILE LOAD ERROR: $error',
          );
          debugPrint('$stackTrace');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _items = loadedItems;
        _errorMessage = null;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('FRIEND REQUESTS LOAD ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'Friend requests could not be loaded. Please try again.';
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

  Future<void> _acceptRequest(
    _IncomingFriendRequestItem item,
  ) async {
    final requestId = item.request.id;

    if (_processingRequestIds.contains(requestId)) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _processingRequestIds.add(requestId);
    });

    try {
      await FriendService.instance.acceptFriendRequest(
        requestId: requestId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = _items
            .where(
              (current) =>
                  current.request.id != requestId,
            )
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            'You and ${item.rider.usernameWithAt} are now friends.',
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

      await _loadRequests();
    } catch (error, stackTrace) {
      debugPrint('ACCEPT FRIEND REQUEST ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: const Text(
            'Friend request could not be accepted. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingRequestIds.remove(requestId);
        });
      }
    }
  }

  Future<void> _declineRequest(
    _IncomingFriendRequestItem item,
  ) async {
    final requestId = item.request.id;

    if (_processingRequestIds.contains(requestId)) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _processingRequestIds.add(requestId);
    });

    try {
      await FriendService.instance.declineFriendRequest(
        requestId: requestId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _items = _items
            .where(
              (current) =>
                  current.request.id != requestId,
            )
            .toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            'Friend request from ${item.rider.usernameWithAt} declined.',
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

      await _loadRequests();
    } catch (error, stackTrace) {
      debugPrint('DECLINE FRIEND REQUEST ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: const Text(
            'Friend request could not be declined. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingRequestIds.remove(requestId);
        });
      }
    }
  }

  Future<void> _confirmDecline(
    _IncomingFriendRequestItem item,
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
          title: const Text(
            'Decline request?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Decline the friend request from '
            '${item.rider.usernameWithAt}?',
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: MunjaColors.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                'Decline',
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
      await _declineRequest(item);
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
        title: const Text(
          'Friend Requests',
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
          onRefresh: () => _loadRequests(
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
      return const _FriendRequestsLoading();
    }

    if (_errorMessage != null) {
      return _FriendRequestsError(
        message: _errorMessage!,
        onRetry: _loadRequests,
      );
    }

    if (_items.isEmpty) {
      return const _EmptyFriendRequests();
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
        _RequestsHeader(
          count: _items.length,
          refreshing: _refreshing,
        ),
        const SizedBox(height: 18),
        ..._items.map(
          (item) {
            final processing = _processingRequestIds.contains(
              item.request.id,
            );

            return Padding(
              padding: const EdgeInsets.only(
                bottom: 14,
              ),
              child: _FriendRequestCard(
                item: item,
                processing: processing,
                onAccept: () => _acceptRequest(item),
                onDecline: () => _confirmDecline(item),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _IncomingFriendRequestItem {
  const _IncomingFriendRequestItem({
    required this.request,
    required this.rider,
  });

  final FriendRequestRecord request;
  final SocialRiderProfile rider;
}

class _RequestsHeader extends StatelessWidget {
  const _RequestsHeader({
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
              Icons.mark_email_unread_rounded,
              color: MunjaColors.mint,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MUNJA SOCIAL',
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count pending ${count == 1 ? 'request' : 'requests'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Accept riders you know and build your Munja crew.',
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

class _FriendRequestCard extends StatelessWidget {
  const _FriendRequestCard({
    required this.item,
    required this.processing,
    required this.onAccept,
    required this.onDecline,
  });

  final _IncomingFriendRequestItem item;
  final bool processing;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final rider = item.rider;

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
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed:
                        processing ? null : onDecline,
                    icon: const Icon(
                      Icons.close_rounded,
                    ),
                    label: const Text(
                      'Decline',
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
                          ? 'Working...'
                          : 'Accept',
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

class _FriendRequestsLoading extends StatelessWidget {
  const _FriendRequestsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
                'Loading friend requests...',
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

class _FriendRequestsError extends StatelessWidget {
  const _FriendRequestsError({
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
      physics: const AlwaysScrollableScrollPhysics(),
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
            color: MunjaColors.panel.withOpacity(0.55),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: MunjaColors.danger.withOpacity(0.20),
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
                'Could not load requests',
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

class _EmptyFriendRequests extends StatelessWidget {
  const _EmptyFriendRequests();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
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
            color: MunjaColors.panel.withOpacity(0.50),
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
                'No pending requests',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 7),
              Text(
                'When another Munja rider sends you a friend request, '
                'it will appear here.',
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
