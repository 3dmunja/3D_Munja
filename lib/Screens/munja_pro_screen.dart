import 'dart:async';

import 'package:flutter/material.dart';

import '../Services/munja_pro_service.dart';
import '../services/munja_pro_purchase_service.dart';
import '../services/monthly_special_service.dart';
import '../core/localization/app_text.dart';


String _t(String key) => AppText.t(key);

class MunjaProScreen extends StatefulWidget {
  const MunjaProScreen({
    super.key,
    this.purchaseService,
  });

  /// Optional externally configured purchase service.
  /// If omitted, the screen creates the live Google Play purchase service,
  /// which verifies purchases through the deployed Firebase callable.
  final MunjaProPurchaseService? purchaseService;

  @override
  State<MunjaProScreen> createState() => _MunjaProScreenState();
}

class _MunjaProScreenState extends State<MunjaProScreen> {
  final MunjaProService _proService = MunjaProService.instance;
  final MonthlySpecialService _monthlySpecialService =
      MonthlySpecialService.instance;

  late final MunjaProPurchaseService _purchaseService;
  late final bool _ownsPurchaseService;

  bool _loadingMonthlySpecial = true;
  bool _claimingMonthlyReward = false;

  MonthlySpecialActivation? _monthlyActivation;

  Timer? _monthlyCountdownTimer;

  @override
  void initState() {
    super.initState();

    final externalPurchaseService = widget.purchaseService;

    if (externalPurchaseService != null) {
      _purchaseService = externalPurchaseService;
      _ownsPurchaseService = false;
    } else {
      _purchaseService = MunjaProPurchaseService();
      _ownsPurchaseService = true;
    }

    _purchaseService.addListener(_handlePurchaseServiceChanged);

    _proService.state.addListener(_handleProStateChanged);
    _proService.initialize();
    _loadMonthlySpecial();
    Future.microtask(_initializeStoreProduct);

    _monthlyCountdownTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        if (mounted && _monthlyActivation != null) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    _monthlyCountdownTimer?.cancel();
    _purchaseService.removeListener(_handlePurchaseServiceChanged);

    if (_ownsPurchaseService) {
      _purchaseService.dispose();
    }

    _proService.state.removeListener(_handleProStateChanged);
    super.dispose();
  }

  void _handlePurchaseServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeStoreProduct() async {
    try {
      await _purchaseService.initialize();
    } catch (error, stackTrace) {
      debugPrint('MUNJA PRO STORE INIT ERROR: $error');
      debugPrint('$stackTrace');
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _purchaseMonthlyPro() async {
    try {
      await _purchaseService.purchaseMonthly();
    } catch (error, stackTrace) {
      debugPrint('MUNJA PRO BUY ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      final message = _t('proPurchaseFailed');

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0D120F),
            content: Text(message),
          ),
        );
    }
  }

  Future<void> _restorePro() async {
    try {
      await _purchaseService.restorePurchases();
    } catch (error, stackTrace) {
      debugPrint('MUNJA PRO RESTORE ERROR: $error');
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      final message = _t('proRestoreFailed');

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0D120F),
            content: Text(message),
          ),
        );
    }
  }

  void _handleProStateChanged() {
    if (!mounted) {
      return;
    }

    // MunjaProService owns auto-activation. The screen only refreshes after
    // entitlement changes so the newly-created 30-day Special appears.
    if (_proService.current.hasActivePro) {
      Future<void>.delayed(
        const Duration(milliseconds: 350),
        () {
          if (mounted) {
            _loadMonthlySpecial();
          }
        },
      );
    } else {
      setState(() {
        _monthlyActivation = null;
      });
    }
  }

  Future<void> _loadMonthlySpecial() async {
    if (mounted) {
      setState(() {
        _loadingMonthlySpecial = true;
      });
    }

    try {
      final activation =
          await _monthlySpecialService.getActiveActivation();

      if (!mounted) {
        return;
      }

      setState(() {
        _monthlyActivation = activation;
        _loadingMonthlySpecial = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA PRO MONTHLY SPECIAL LOAD ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      setState(() {
        _monthlyActivation = null;
        _loadingMonthlySpecial = false;
      });
    }
  }

  Future<void> _claimMonthlyReward() async {
    if (_claimingMonthlyReward) {
      return;
    }

    final activation = _monthlyActivation;

    if (activation == null) {
      return;
    }

    setState(() {
      _claimingMonthlyReward = true;
    });

    try {
      final result =
          await _monthlySpecialService.claimCompletedReward(
        activationId: activation.id,
      );

      if (!mounted) {
        return;
      }

      String message;

      switch (result.status) {
        case MonthlySpecialClaimStatus.success:
          message =
              'Reward claimed: +${result.xpGranted} XP, '
              '+${result.crystalsGranted} Crystals'
              '${result.rewardName.isEmpty ? '' : ' · ${result.rewardName} unlocked'}';
          break;
        case MonthlySpecialClaimStatus.alreadyClaimed:
          message = _t('rewardAlreadyClaimed');
          break;
        case MonthlySpecialClaimStatus.notCompleted:
          message = _t('completeBeforeClaim');
          break;
        case MonthlySpecialClaimStatus.activationNotFound:
          message = _t('monthlyNotFound');
          break;
        case MonthlySpecialClaimStatus.userNotFound:
          message = _t('profileNotFound');
          break;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0D120F),
            content: Text(message),
          ),
        );

      await _loadMonthlySpecial();
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA PRO MONTHLY SPECIAL CLAIM ERROR: $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0D120F),
            content: Text(_t('rewardClaimFailed')),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _claimingMonthlyReward = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050706),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050706),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'MUNJA PRO',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ValueListenableBuilder<MunjaProState>(
          valueListenable: _proService.state,
          builder: (context, proState, _) {
            final isPro = proState.hasActivePro;

            return ListView(
              padding: const EdgeInsets.fromLTRB(
                18,
                10,
                18,
                36,
              ),
              children: [
                _HeroCard(
                  isPro: isPro,
                ),
                const SizedBox(height: 18),
                _SectionTitle(
                  _t('proExperience'),
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.insights_rounded,
                  title: _t('proAdvancedAnalytics'),
                  description:
                      _t('proAdvancedAnalyticsDesc'),
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.auto_awesome_rounded,
                  title: _t('proAiRideAnalysis'),
                  description:
                      _t('proAiRideAnalysisDesc'),
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.record_voice_over_rounded,
                  title: _t('proAiCoach'),
                  description:
                      _t('proAiCoachDesc'),
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.route_rounded,
                  title: _t('proRoutePlanner'),
                  description:
                      _t('proRoutePlannerDesc'),
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.emoji_events_rounded,
                  title: _t('proChallenges'),
                  description:
                      _t('proChallengesDesc'),
                ),
                const SizedBox(height: 10),
                _FeatureCard(
                  icon: Icons.palette_rounded,
                  title: _t('proSkinsFrames'),
                  description:
                      _t('proSkinsFramesDesc'),
                ),
                const SizedBox(height: 22),
                _MonthlySpecialCard(
                  loading: _loadingMonthlySpecial,
                  claiming: _claimingMonthlyReward,
                  isPro: isPro,
                  activation: _monthlyActivation,
                  service: _monthlySpecialService,
                  onClaim: _claimMonthlyReward,
                  onRefresh: _loadMonthlySpecial,
                ),
                const SizedBox(height: 14),
                _PlanCard(
                  state: proState,
                  storePrice: _purchaseService.localizedMonthlyPrice,
                  storeLoading: _purchaseService.isInitializing ||
                      _purchaseService.isLoadingProduct,
                  storeAvailable: _purchaseService.isStoreAvailable,
                  purchasing: _purchaseService.isPurchasing,
                  restoring: _purchaseService.isRestoring,
                  onPurchase: _purchaseMonthlyPro,
                  onRestore: _restorePro,
                ),
                const SizedBox(height: 14),
                Text(
                  isPro
                      ? _t('proLinkedActive')
                      : _t('proLinkedSecure'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  _HeroCard({
    required this.isPro,
  });

  final bool isPro;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF0D120F),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF44FF8A).withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF44FF8A).withValues(alpha: 0.06),
            blurRadius: 28,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF44FF8A).withValues(alpha: 0.10),
              border: Border.all(
                color: const Color(0xFF44FF8A).withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Color(0xFF44FF8A),
              size: 38,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isPro
                ? _t('proYouArePro')
                : _t('proUnlockMore'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isPro
                ? _t('proFeaturesActive')
                : _t('proMoreInsight'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0D0B),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: const Color(0xFF44FF8A).withValues(alpha: 0.09),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF44FF8A),
              size: 22,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color:
                            const Color(0xFF44FF8A).withValues(alpha: 0.10),
                      ),
                      child: Text(
                        'PRO',
                        style: TextStyle(
                          color: Color(0xFF44FF8A),
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
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


class _MonthlySpecialCard extends StatelessWidget {
  _MonthlySpecialCard({
    required this.loading,
    required this.claiming,
    required this.isPro,
    required this.activation,
    required this.service,
    required this.onClaim,
    required this.onRefresh,
  });

  final bool loading;
  final bool claiming;
  final bool isPro;
  final MonthlySpecialActivation? activation;
  final MonthlySpecialService service;
  final VoidCallback onClaim;
  final VoidCallback onRefresh;

  String _countdownLabel(
    MonthlySpecialActivation activation,
  ) {
    if (activation.isCompleted) {
      return activation.rewardClaimed
          ? _t('monthlyCompletedClaimed')
          : _t('monthlyCompletedReady');
    }

    final remaining = activation.timeRemaining();

    if (remaining <= Duration.zero) {
      return _t('expired');
    }

    if (remaining.inHours < 24) {
      final hours = remaining.inHours;
      final minutes = remaining.inMinutes.remainder(60);
      return '${hours}H ${minutes}M LEFT';
    }

    // Use ceiling so a fresh 30-day activation displays 30 DAYS LEFT rather
    // than immediately dropping to 29 because a few seconds have elapsed.
    final days =
        (remaining.inSeconds / Duration.secondsPerDay).ceil();
    return '$days DAYS LEFT';
  }

  @override
  Widget build(BuildContext context) {
    final active = activation;

    if (loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0D120F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF44FF8A),
              ),
            ),
            SizedBox(width: 12),
            Text(
              _t('monthlyLoading'),
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    if (active == null) {
      final currentSpecial = service.current();

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF0D120F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF44FF8A)
                .withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFF44FF8A),
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  _t('monthlySpecial'),
                  style: TextStyle(
                    color: Color(0xFF44FF8A),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              currentSpecial.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              isPro
                  ? _t('monthlyStartsWithPro')
                  : _t('monthlyActivatePro'),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isPro) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF44FF8A),
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _t('monthlyActivating'),
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 17,
                  ),
                  label: Text(_t('refresh')),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final special = service.specialForActivation(active);
    final completed = active.isCompleted;
    final claimed = active.rewardClaimed;
    final countdown = _countdownLabel(active);
    final progress =
        active.progressRatio(special).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D120F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF44FF8A)
              .withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Color(0xFF44FF8A),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                _t('monthlySpecial'),
                style: TextStyle(
                  color: Color(0xFF44FF8A),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (claimed)
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF44FF8A),
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            special.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            special.subtitle,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11.5,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor:
                  Colors.white.withValues(alpha: 0.06),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(0xFF44FF8A),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${active.progressValue.toStringAsFixed(
                  active.progressValue == active.progressValue.roundToDouble()
                      ? 0
                      : 1,
                )} / ${special.goalLabel}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                countdown,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: completed || claimed
                      ? const Color(0xFF44FF8A)
                      : Colors.white54,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.7,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '+${special.xpReward} XP · '
              '+${special.crystalReward} Crystals · '
              '${special.specialReward.name}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (completed && !claimed) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: claiming ? null : onClaim,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      const Color(0xFF44FF8A),
                  foregroundColor:
                      const Color(0xFF031008),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: claiming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(
                        Icons.redeem_rounded,
                      ),
                label: Text(
                  claiming
                      ? _t('claiming')
                      : _t('claimReward'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  _PlanCard({
    required this.state,
    required this.storePrice,
    required this.storeLoading,
    required this.storeAvailable,
    required this.purchasing,
    required this.restoring,
    required this.onPurchase,
    required this.onRestore,
  });

  final MunjaProState state;
  final String? storePrice;
  final bool storeLoading;
  final bool storeAvailable;
  final bool purchasing;
  final bool restoring;
  final VoidCallback onPurchase;
  final VoidCallback onRestore;

  bool get _isPro => state.hasActivePro;

  String get _sourceLabel {
    final source = state.source?.trim().toLowerCase();

    switch (source) {
      case 'apple':
        return 'Apple App Store';
      case 'google':
        return 'Google Play';
      case 'promo':
        return 'Munja promotion';
      case 'admin':
        return 'Munja account';
      default:
        return 'Munja account';
    }
  }

  String get _expiryLabel {
    final expiry = state.expiresAt;

    if (expiry == null) {
      return _isPro ? _t('activeMembership') : _t('noActiveMembership');
    }

    final local = expiry.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    return _isPro
        ? 'Active until $day.$month.$year'
        : 'Expired $day.$month.$year';
  }

  String get _priceLabel {
    if (storeLoading) {
      return 'Loading Google Play price...';
    }

    final price = storePrice?.trim();

    if (price != null && price.isNotEmpty) {
      return '$price / month';
    }

    if (!storeAvailable) {
      return 'Google Play unavailable';
    }

    return _t('monthlySubscription');
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF44FF8A);
    final busy = purchasing || restoring;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF0D120F),
        border: Border.all(
          color: accent.withValues(
            alpha: _isPro ? 0.30 : 0.18,
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MUNJA PRO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isPro ? _expiryLabel : _t('premiumExperience'),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
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
                  color: _isPro
                      ? accent.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _isPro
                        ? accent.withValues(alpha: 0.26)
                        : Colors.white.withValues(alpha: 0.07),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPro
                          ? Icons.verified_rounded
                          : Icons.lock_outline_rounded,
                      color: _isPro ? accent : Colors.white38,
                      size: 15,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isPro ? 'ACTIVE' : _t('freeCaps'),
                      style: TextStyle(
                        color: _isPro ? accent : Colors.white54,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isPro
                      ? Icons.workspace_premium_rounded
                      : Icons.bolt_rounded,
                  color: accent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isPro ? _sourceLabel : _priceLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (storeLoading && !_isPro)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else if (_isPro)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: accent,
                    size: 19,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: accent.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isPro ? Icons.sync_rounded : Icons.info_outline_rounded,
                  color: accent,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _isPro
                        ? _t('membershipSync')
                        : _t('autoRenewing'),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_isPro) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: busy || storeLoading || storePrice == null
                    ? null
                    : onPurchase,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: const Color(0xFF031008),
                  disabledBackgroundColor: accent.withValues(alpha: 0.18),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: purchasing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.workspace_premium_rounded),
                label: Text(
                  purchasing ? _t('connectingStore') : _t('getPro'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            TextButton(
              onPressed: busy ? null : onRestore,
              child: Text(
                restoring ? _t('restoring') : _t('restorePurchase'),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
