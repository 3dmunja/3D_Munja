import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/munja_colors.dart';
import '../models/social_rider_profile.dart';
import '../services/friend_service.dart';
import '../services/social_rider_service.dart';

class FindRiderScreen extends StatefulWidget {
  const FindRiderScreen({super.key});

  @override
  State<FindRiderScreen> createState() => _FindRiderScreenState();
}

class _FindRiderScreenState extends State<FindRiderScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  bool _searching = false;
  bool _hasSearched = false;
  bool _sendingFriendRequest = false;
  bool _hasPendingOutgoingRequest = false;
  bool _hasPendingIncomingRequest = false;
  bool _alreadyFriends = false;

  String? _errorMessage;
  SocialRiderProfile? _result;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  String get _query => _searchController.text.trim();

  bool get _isCurrentUser {
    final result = _result;
    final currentUid = SocialRiderService.instance.currentUid;

    return result != null &&
        currentUid != null &&
        result.uid == currentUid;
  }

  Future<void> _search() async {
    if (_searching) return;

    final query = _query;

    if (query.isEmpty) {
      setState(() {
        _hasSearched = false;
        _result = null;
        _errorMessage = 'Enter a @username, e-mail or Munja Friend Code.';
      });
      return;
    }

    HapticFeedback.selectionClick();
    _searchFocusNode.unfocus();

    setState(() {
      _searching = true;
      _hasSearched = true;
      _result = null;
      _errorMessage = null;
      _hasPendingOutgoingRequest = false;
      _hasPendingIncomingRequest = false;
      _alreadyFriends = false;
    });

    try {
      final result =
          await SocialRiderService.instance.findRider(query);

      if (!mounted) return;

      var hasPendingOutgoingRequest = false;
      var hasPendingIncomingRequest = false;
      var alreadyFriends = false;

      final currentUid = SocialRiderService.instance.currentUid;

      if (result != null &&
          currentUid != null &&
          result.uid != currentUid) {
        alreadyFriends = await FriendService.instance.areFriends(
          otherUid: result.uid,
        );

        if (!alreadyFriends) {
          hasPendingOutgoingRequest =
              await FriendService.instance.hasPendingOutgoingRequest(
            toUid: result.uid,
          );

          hasPendingIncomingRequest =
              await FriendService.instance.hasPendingIncomingRequest(
            fromUid: result.uid,
          );
        }
      }

      if (!mounted) return;

      setState(() {
        _result = result;
        _hasPendingOutgoingRequest = hasPendingOutgoingRequest;
        _hasPendingIncomingRequest = hasPendingIncomingRequest;
        _alreadyFriends = alreadyFriends;

        if (result == null) {
          _errorMessage =
              'No Munja rider was found with that username, e-mail or Friend Code.';
        }
      });
    } catch (error, stackTrace) {
      debugPrint('FIND RIDER SEARCH ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _errorMessage =
            'Rider search failed. Please check your connection and try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _searching = false;
        });
      }
    }
  }

  void _clearSearch() {
    HapticFeedback.selectionClick();
    _searchController.clear();

    setState(() {
      _result = null;
      _errorMessage = null;
      _hasSearched = false;
      _hasPendingOutgoingRequest = false;
      _hasPendingIncomingRequest = false;
      _alreadyFriends = false;
    });

    _searchFocusNode.requestFocus();
  }

  Future<void> _sendFriendRequest() async {
    final result = _result;

    if (result == null ||
        _isCurrentUser ||
        _sendingFriendRequest ||
        _hasPendingOutgoingRequest ||
        _hasPendingIncomingRequest ||
        _alreadyFriends) {
      return;
    }

    HapticFeedback.mediumImpact();

    setState(() {
      _sendingFriendRequest = true;
    });

    try {
      await FriendService.instance.sendFriendRequest(
        toUid: result.uid,
      );

      if (!mounted) return;

      setState(() {
        _hasPendingOutgoingRequest = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(
            'Friend request sent to ${result.usernameWithAt}.',
          ),
        ),
      );
    } on StateError catch (error) {
      if (!mounted) return;

      final message = error.message;

      if (message.contains('already sent you a friend request')) {
        setState(() {
          _hasPendingIncomingRequest = true;
        });
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: Text(message),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('SEND FRIEND REQUEST ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: MunjaColors.panel,
          content: const Text(
            'Friend request could not be sent. Please try again.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingFriendRequest = false;
        });
      }
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
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text(
          'Find Rider',
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
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 44),
          children: [
            const _FindRiderIntro(),
            const SizedBox(height: 20),
            _SearchCard(
              controller: _searchController,
              focusNode: _searchFocusNode,
              searching: _searching,
              onSearch: _search,
              onClear: _query.isEmpty ? null : _clearSearch,
            ),
            const SizedBox(height: 18),
            if (_searching)
              const _SearchingCard()
            else if (_result != null)
              _RiderResultCard(
                rider: _result!,
                isCurrentUser: _isCurrentUser,
                sendingFriendRequest: _sendingFriendRequest,
                hasPendingOutgoingRequest:
                    _hasPendingOutgoingRequest,
                hasPendingIncomingRequest:
                    _hasPendingIncomingRequest,
                alreadyFriends: _alreadyFriends,
                onAddFriend:
                    _isCurrentUser ? null : _sendFriendRequest,
              )
            else if (_errorMessage != null)
              _SearchMessageCard(
                icon: _hasSearched
                    ? Icons.person_search_rounded
                    : Icons.info_outline_rounded,
                title: _hasSearched ? 'Rider not found' : 'Ready to search',
                message: _errorMessage!,
              )
            else
              const _SearchTipsCard(),
          ],
        ),
      ),
    );
  }
}

class _FindRiderIntro extends StatelessWidget {
  const _FindRiderIntro();

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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MUNJA SOCIAL',
            style: TextStyle(
              color: MunjaColors.mint,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Find another rider',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.7,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Search by @username, e-mail or a simple Munja Friend Code. '
            'Use whichever method is easiest for you.',
            style: TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  const _SearchCard({
    required this.controller,
    required this.focusNode,
    required this.searching,
    required this.onSearch,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool searching;
  final Future<void> Function() onSearch;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.58),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withOpacity(0.065),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: !searching,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(
                hintText: '@username, e-mail or Friend Code',
                hintStyle: const TextStyle(
                  color: Colors.white30,
                  fontWeight: FontWeight.w700,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: MunjaColors.mint,
                ),
                suffixIcon: onClear == null
                    ? null
                    : IconButton(
                        onPressed: onClear,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white38,
                        ),
                      ),
                filled: true,
                fillColor: Colors.black.withOpacity(0.18),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide(
                    color: MunjaColors.mint.withOpacity(0.55),
                  ),
                ),
              ),
              onSubmitted: (_) {
                onSearch();
              },
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 56,
            height: 56,
            child: FilledButton(
              onPressed: searching ? null : onSearch,
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: MunjaColors.mint,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: searching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchingCard extends StatelessWidget {
  const _SearchingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.45),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: MunjaColors.mint,
            strokeWidth: 2.5,
          ),
          SizedBox(height: 14),
          Text(
            'Searching Munja riders...',
            style: TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderResultCard extends StatelessWidget {
  const _RiderResultCard({
    required this.rider,
    required this.isCurrentUser,
    required this.sendingFriendRequest,
    required this.hasPendingOutgoingRequest,
    required this.hasPendingIncomingRequest,
    required this.alreadyFriends,
    required this.onAddFriend,
  });

  final SocialRiderProfile rider;
  final bool isCurrentUser;
  final bool sendingFriendRequest;
  final bool hasPendingOutgoingRequest;
  final bool hasPendingIncomingRequest;
  final bool alreadyFriends;
  final VoidCallback? onAddFriend;

  Widget _buildFriendActionButton() {
    if (isCurrentUser) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.person_rounded),
        label: const Text(
          'This is you',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    if (alreadyFriends) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.people_alt_rounded),
        label: const Text(
          'Friends',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    if (hasPendingIncomingRequest) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.mark_email_unread_rounded),
        label: const Text(
          'Request received',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    if (hasPendingOutgoingRequest) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.schedule_send_rounded),
        label: const Text(
          'Request sent',
          style: TextStyle(
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    return FilledButton.icon(
      onPressed: sendingFriendRequest ? null : onAddFriend,
      icon: sendingFriendRequest
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.black,
              ),
            )
          : const Icon(Icons.person_add_alt_1_rounded),
      label: Text(
        sendingFriendRequest ? 'Sending...' : 'Add Friend',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto =
        rider.photoUrl != null && rider.photoUrl!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.82),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(0.08),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MunjaColors.mint.withOpacity(0.10),
                  border: Border.all(
                    color: MunjaColors.mint.withOpacity(0.35),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? Image.network(
                        rider.photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) {
                          return const _FallbackAvatar();
                        },
                      )
                    : const _FallbackAvatar(),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: MunjaColors.mint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'LVL ${rider.level}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
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
                    const SizedBox(height: 4),
                    Text(
                      'Friend Code: ${rider.riderId.replaceFirst('MUNJA-', '')}',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (rider.city != null && rider.city!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  color: MunjaColors.textSoft,
                  size: 17,
                ),
                const SizedBox(width: 6),
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
                child: _ResultMetric(
                  label: 'LEVEL',
                  value: '${rider.level}',
                  icon: Icons.workspace_premium_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ResultMetric(
                  label: 'TOTAL XP',
                  value: '${rider.totalXp}',
                  icon: Icons.bolt_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: _buildFriendActionButton(),
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
        size: 34,
      ),
    );
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
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

class _SearchMessageCard extends StatelessWidget {
  const _SearchMessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.48),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.055),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: MunjaColors.mint,
              size: 27,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
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
        ],
      ),
    );
  }
}

class _SearchTipsCard extends StatelessWidget {
  const _SearchTipsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withOpacity(0.42),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SEARCH WITH',
            style: TextStyle(
              color: MunjaColors.mint,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          SizedBox(height: 12),
          _SearchTip(
            icon: Icons.alternate_email_rounded,
            title: '@username',
            example: '@rider',
          ),
          SizedBox(height: 12),
          _SearchTip(
            icon: Icons.email_outlined,
            title: 'E-mail',
            example: 'rider@example.com',
          ),
          SizedBox(height: 12),
          _SearchTip(
            icon: Icons.badge_rounded,
            title: 'Friend Code',
            example: '7KQ2-X9PD',
          ),
        ],
      ),
    );
  }
}

class _SearchTip extends StatelessWidget {
  const _SearchTip({
    required this.icon,
    required this.title,
    required this.example,
  });

  final IconData icon;
  final String title;
  final String example;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: MunjaColors.mint.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: MunjaColors.mint,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                example,
                style: const TextStyle(
                  color: MunjaColors.textSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
