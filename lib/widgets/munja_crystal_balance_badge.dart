import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../models/firestore_user.dart';
import '../services/firestore_skin_entitlement_service.dart';

/// Compact, reusable Munja Crystal balance badge.
///
/// The badge listens directly to the user's Firestore entitlement document and
/// updates automatically whenever the Crystal balance changes.
///
/// Typical usage:
///
/// ```dart
/// MunjaCrystalBalanceBadge(
///   uid: currentUserId,
///   onTap: () {
///     // Later: open Crystal Shop.
///   },
/// )
/// ```
///
/// If [uid] is empty, the badge shows 0 instead of attempting a Firestore read.
class MunjaCrystalBalanceBadge extends StatefulWidget {
  const MunjaCrystalBalanceBadge({
    super.key,
    required this.uid,
    this.onTap,
    this.compact = false,
    this.showLabel = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: 11,
      vertical: 8,
    ),
  });

  /// Firestore user id used by [FirestoreSkinEntitlementService].
  final String uid;

  /// Optional action when the user taps the Crystal badge.
  ///
  /// This can later open the Crystal Shop / wallet.
  final VoidCallback? onTap;

  /// Slightly smaller badge for tight headers.
  final bool compact;

  /// When true, displays the word "CRYSTALS" below the balance.
  final bool showLabel;

  final EdgeInsetsGeometry padding;

  @override
  State<MunjaCrystalBalanceBadge> createState() =>
      _MunjaCrystalBalanceBadgeState();
}

class _MunjaCrystalBalanceBadgeState
    extends State<MunjaCrystalBalanceBadge> {
  StreamSubscription<FirestoreUser?>? _subscription;

  int _balance = 0;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void didUpdateWidget(
    covariant MunjaCrystalBalanceBadge oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.uid.trim() != widget.uid.trim()) {
      _startListening();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _startListening() {
    unawaited(_subscription?.cancel());

    final uid = widget.uid.trim();

    if (uid.isEmpty) {
      if (mounted) {
        setState(() {
          _balance = 0;
          _loading = false;
          _hasError = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _hasError = false;
      });
    }

    _subscription =
        FirestoreSkinEntitlementService.instance
            .watchUser(uid)
            .listen(
      (user) {
        if (!mounted) return;

        setState(() {
          _balance = user?.crystalBalance ?? 0;
          _loading = false;
          _hasError = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'MUNJA CRYSTAL BADGE WATCH ERROR: $error',
        );
        debugPrint('$stackTrace');

        if (!mounted) return;

        setState(() {
          _loading = false;
          _hasError = true;
        });
      },
    );
  }

  String _formatBalance(int value) {
    final safeValue = value < 0 ? 0 : value;
    final raw = safeValue.toString();

    if (raw.length <= 3) {
      return raw;
    }

    final buffer = StringBuffer();
    final firstGroupLength = raw.length % 3;
    var index = 0;

    if (firstGroupLength > 0) {
      buffer.write(
        raw.substring(
          0,
          firstGroupLength,
        ),
      );

      index = firstGroupLength;

      if (index < raw.length) {
        buffer.write('.');
      }
    }

    while (index < raw.length) {
      buffer.write(
        raw.substring(
          index,
          index + 3,
        ),
      );

      index += 3;

      if (index < raw.length) {
        buffer.write('.');
      }
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;

    final iconSize = compact ? 15.0 : 17.0;
    final balanceFontSize = compact ? 11.0 : 12.5;

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: widget.padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B1A16).withValues(
              alpha: 0.98,
            ),
            const Color(0xFF06110E).withValues(
              alpha: 0.98,
            ),
          ],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _hasError
              ? Colors.redAccent.withValues(alpha: 0.24)
              : const Color(0xFF70D8FF).withValues(
                  alpha: 0.24,
                ),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF70D8FF).withValues(
              alpha: 0.07,
            ),
            blurRadius: 18,
            spreadRadius: -2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 25 : 29,
            height: compact ? 25 : 29,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF70D8FF).withValues(
                alpha: 0.10,
              ),
              border: Border.all(
                color: const Color(0xFF70D8FF).withValues(
                  alpha: 0.18,
                ),
              ),
            ),
            child: Icon(
              Icons.diamond_rounded,
              color: const Color(0xFF70D8FF),
              size: iconSize,
            ),
          ),
          SizedBox(
            width: compact ? 7 : 9,
          ),
          if (_loading)
            SizedBox(
              width: compact ? 34 : 44,
              height: 14,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: MunjaColors.mint.withValues(
                      alpha: 0.88,
                    ),
                  ),
                ),
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration:
                      const Duration(milliseconds: 220),
                  transitionBuilder: (
                    child,
                    animation,
                  ) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(
                          begin: 0.94,
                          end: 1.0,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Text(
                    _hasError
                        ? '--'
                        : _formatBalance(_balance),
                    key: ValueKey<String>(
                      _hasError
                          ? 'error'
                          : _balance.toString(),
                    ),
                    maxLines: 1,
                    style: TextStyle(
                      color: _hasError
                          ? Colors.white54
                          : Colors.white,
                      fontSize: balanceFontSize,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.15,
                    ),
                  ),
                ),
                if (widget.showLabel) ...[
                  const SizedBox(height: 3),
                  Text(
                    'CRYSTALS',
                    style: TextStyle(
                      color: MunjaColors.mint.withValues(
                        alpha: 0.72,
                      ),
                      fontSize: compact ? 6.5 : 7.0,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.85,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    if (widget.onTap == null) {
      return badge;
    }

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: badge,
      ),
    );
  }
}
