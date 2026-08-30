import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/theme/munja_colors.dart';
import '../models/crystal_package.dart';
import '../models/firestore_user.dart';
import '../services/firestore_skin_entitlement_service.dart';
import '../services/crystal_purchase_service.dart';

/// Munja Crystal Shop.
///
/// V1 responsibility:
/// - show live Firestore Crystal balance
/// - show the four Munja Crystal packages
/// - expose a clean purchase callback
/// - use Apple/Google localized prices when supplied
///
/// The actual store purchase is intentionally NOT implemented in this screen.
/// The next step is to connect [onPurchase] to CrystalPurchaseService using
/// Flutter's in_app_purchase package.
class CrystalShopScreen extends StatefulWidget {
  const CrystalShopScreen({
    super.key,
    this.packages = munjaCrystalPackages,
    this.purchaseService,
    this.verifyAndDeliver,
  });

  /// Crystal packages shown in the shop.
  final List<CrystalPackage> packages;

  /// Optional externally-owned purchase service.
  ///
  /// If supplied, CrystalShopScreen will use it but will NOT dispose it.
  final CrystalPurchaseService? purchaseService;

  /// Trusted backend bridge used when this screen creates its own
  /// CrystalPurchaseService.
  ///
  /// Until the backend/Cloud Function is connected, this can be omitted:
  /// product loading and localized store prices still work, but purchases are
  /// blocked safely before any Crystal delivery can happen.
  final CrystalPurchaseVerifier? verifyAndDeliver;

  @override
  State<CrystalShopScreen> createState() =>
      _CrystalShopScreenState();
}

class _CrystalShopScreenState extends State<CrystalShopScreen> {
  StreamSubscription<FirestoreUser?>? _userSubscription;

  late final CrystalPurchaseService _purchaseService;
  late final bool _ownsPurchaseService;

  FirestoreUser? _user;
  bool _loadingBalance = true;

  String get _uid =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

  int get _balance => _user?.crystalBalance ?? 0;

  @override
  void initState() {
    super.initState();

    final externalService = widget.purchaseService;

    if (externalService != null) {
      _purchaseService = externalService;
      _ownsPurchaseService = false;
    } else {
      _purchaseService = CrystalPurchaseService(
        verifyAndDeliver:
            widget.verifyAndDeliver ?? _backendNotConnectedVerifier,
      );
      _ownsPurchaseService = true;
    }

    _purchaseService.addListener(_handlePurchaseServiceChanged);

    _startUserWatch();

    Future.microtask(_initializeStore);
  }

  @override
  void dispose() {
    unawaited(_userSubscription?.cancel());

    _purchaseService.removeListener(
      _handlePurchaseServiceChanged,
    );

    if (_ownsPurchaseService) {
      _purchaseService.dispose();
    }

    super.dispose();
  }

  Future<void> _backendNotConnectedVerifier({
    required CrystalPackage package,
    required PurchaseDetails purchase,
    required String verificationData,
    required String verificationSource,
  }) async {
    throw StateError(
      'Crystal purchase verification backend is not connected yet.',
    );
  }

  Future<void> _initializeStore() async {
    try {
      await _purchaseService.initialize(
        packages: widget.packages,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'CRYSTAL SHOP STORE INITIALIZE ERROR: $error',
      );
      debugPrint('$stackTrace');
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _handlePurchaseServiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _startUserWatch() {
    final uid = _uid;

    if (uid.isEmpty) {
      _loadingBalance = false;
      return;
    }

    _userSubscription =
        FirestoreSkinEntitlementService.instance
            .watchUser(uid)
            .listen(
      (user) {
        if (!mounted) return;

        setState(() {
          _user = user;
          _loadingBalance = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'CRYSTAL SHOP USER WATCH ERROR: $error',
        );
        debugPrint('$stackTrace');

        if (!mounted) return;

        setState(() {
          _loadingBalance = false;
        });
      },
    );
  }

  Future<void> _buy(CrystalPackage package) async {
    if (_purchaseService.isPurchasing) {
      return;
    }

    if (!_purchaseService.isStoreAvailable) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'App Store / Google Play køb er ikke tilgængeligt endnu.',
            ),
          ),
        );
      return;
    }

    if (_purchaseService.productFor(package.productId) == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Produktet ${package.productId} findes endnu ikke i butikken.',
            ),
          ),
        );
      return;
    }

    try {
      final result =
          await _purchaseService.purchase(package);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              '${_formatNumber(result.package.totalCrystals)} Crystals er tilføjet.',
            ),
          ),
        );
    } catch (error, stackTrace) {
      debugPrint(
        'CRYSTAL SHOP PURCHASE ERROR: '
        '${package.productId} -> $error',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      final message = error.toString().contains(
        'verification backend is not connected',
      )
          ? 'Betalingen er klar, men sikker server-verificering mangler endnu.'
          : 'Købet kunne ikke gennemføres. Prøv igen.';

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(message),
          ),
        );
    }
  }

  String _priceFor(CrystalPackage package) {
    final realStorePrice =
        _purchaseService.productFor(package.productId)?.price.trim();

    if (realStorePrice != null &&
        realStorePrice.isNotEmpty) {
      return realStorePrice;
    }

    return package.previewPriceLabel ?? '—';
  }

  String _formatNumber(int value) {
    final safe = value < 0 ? 0 : value;
    final raw = safe.toString();

    if (raw.length <= 3) {
      return raw;
    }

    final buffer = StringBuffer();
    var first = raw.length % 3;
    var index = 0;

    if (first == 0) {
      first = 3;
    }

    buffer.write(raw.substring(0, first));
    index = first;

    while (index < raw.length) {
      buffer.write('.');
      buffer.write(raw.substring(index, index + 3));
      index += 3;
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final packages = widget.packages;
    final storeBusy =
        _purchaseService.isInitializing ||
        _purchaseService.isLoadingProducts;

    return Scaffold(
      backgroundColor: const Color(0xFF081A15),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ShopHeader(
              loading: _loadingBalance,
              balance: _balance,
              formatNumber: _formatNumber,
            ),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  18,
                  14,
                  18,
                  180,
                ),
                children: [
                  _HeroBalanceCard(
                    loading: _loadingBalance,
                    balance: _balance,
                    formatNumber: _formatNumber,
                  ),
                  const SizedBox(height: 20),
                  _SectionHeading(
                    storeAvailable:
                        _purchaseService.isStoreAvailable,
                    loading: storeBusy,
                  ),
                  if (_purchaseService.errorMessage != null) ...[
                    const SizedBox(height: 10),
                    _StoreErrorBanner(
                      message: _purchaseService.errorMessage!,
                      onRetry: _initializeStore,
                    ),
                  ],
                  const SizedBox(height: 12),
                  for (var i = 0; i < packages.length; i++) ...[
                    _CrystalPackageCard(
                      package: packages[i],
                      priceLabel: _priceFor(packages[i]),
                      loading:
                          _purchaseService.activeProductId ==
                              packages[i].productId,
                      disabled:
                          storeBusy ||
                          !_purchaseService.isStoreAvailable ||
                          _purchaseService.productFor(
                                packages[i].productId,
                              ) ==
                              null ||
                          (_purchaseService.isPurchasing &&
                              _purchaseService.activeProductId !=
                                  packages[i].productId),
                      formatNumber: _formatNumber,
                      onBuy: () => _buy(packages[i]),
                    ),
                    if (i != packages.length - 1)
                      const SizedBox(height: 11),
                  ],
                  const SizedBox(height: 18),
                  const _StoreNotice(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShopHeader extends StatelessWidget {
  const _ShopHeader({
    required this.loading,
    required this.balance,
    required this.formatNumber,
  });

  final bool loading;
  final int balance;
  final String Function(int value) formatNumber;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        18,
        10,
        18,
        8,
      ),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.05),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CRYSTAL SHOP',
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Munja Crystals',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF70D8FF)
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: const Color(0xFF70D8FF)
                    .withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.diamond_rounded,
                  size: 15,
                  color: Color(0xFF70D8FF),
                ),
                const SizedBox(width: 6),
                if (loading)
                  const SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.7,
                      color: MunjaColors.mint,
                    ),
                  )
                else
                  Text(
                    formatNumber(balance),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
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

class _HeroBalanceCard extends StatelessWidget {
  const _HeroBalanceCard({
    required this.loading,
    required this.balance,
    required this.formatNumber,
  });

  final bool loading;
  final int balance;
  final String Function(int value) formatNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        19,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MunjaColors.mint.withValues(alpha: 0.22),
            const Color(0xFF102820),
            const Color(0xFF0A1C17),
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withValues(alpha: 0.08),
            blurRadius: 34,
            spreadRadius: -8,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF70D8FF)
                  .withValues(alpha: 0.11),
              border: Border.all(
                color: const Color(0xFF70D8FF)
                    .withValues(alpha: 0.22),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF70D8FF)
                      .withValues(alpha: 0.13),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Icon(
              Icons.diamond_rounded,
              color: Color(0xFF70D8FF),
              size: 31,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR BALANCE',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                if (loading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MunjaColors.mint,
                    ),
                  )
                else
                  Text(
                    '${formatNumber(balance)} Crystals',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Unlock skins, frames and future Munja rewards.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.68),
                    fontSize: 10,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
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

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.storeAvailable,
    required this.loading,
  });

  final bool storeAvailable;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final statusText = loading
        ? 'CONNECTING TO STORE'
        : storeAvailable
            ? 'SECURE STORE PURCHASE'
            : 'STORE UNAVAILABLE';

    return Row(
      children: [
        const Expanded(
          child: Text(
            'CHOOSE YOUR PACK',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
        if (loading) ...[
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: MunjaColors.mint,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          statusText,
          style: TextStyle(
            color: storeAvailable || loading
                ? MunjaColors.mint.withValues(alpha: 0.88)
                : Colors.orangeAccent.withValues(alpha: 0.92),
            fontSize: 7.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _StoreErrorBanner extends StatelessWidget {
  const _StoreErrorBanner({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orangeAccent.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Colors.orangeAccent,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              unawaited(onRetry());
            },
            child: const Text(
              'RETRY',
              style: TextStyle(
                color: MunjaColors.mint,
                fontSize: 8,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrystalPackageCard extends StatelessWidget {
  const _CrystalPackageCard({
    required this.package,
    required this.priceLabel,
    required this.loading,
    required this.disabled,
    required this.formatNumber,
    required this.onBuy,
  });

  final CrystalPackage package;
  final String priceLabel;
  final bool loading;
  final bool disabled;
  final String Function(int value) formatNumber;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final featured = package.featured;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: 1.0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          15,
          14,
          14,
          14,
        ),
        decoration: BoxDecoration(
          gradient: featured
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    MunjaColors.mint.withValues(alpha: 0.23),
                    const Color(0xFF10271F),
                    const Color(0xFF0A1C17),
                  ],
                )
              : null,
          color: featured
              ? null
              : const Color(0xFF10241D).withValues(alpha: 0.98),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: featured
                ? MunjaColors.mint.withValues(alpha: 0.46)
                : Colors.white.withValues(alpha: 0.12),
            width: featured ? 1.15 : 1,
          ),
          boxShadow: featured
              ? [
                  BoxShadow(
                    color: MunjaColors.mint
                        .withValues(alpha: 0.08),
                    blurRadius: 28,
                    spreadRadius: -8,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF70D8FF)
                    .withValues(alpha: featured ? 0.13 : 0.08),
                border: Border.all(
                  color: const Color(0xFF70D8FF)
                      .withValues(alpha: featured ? 0.27 : 0.14),
                ),
              ),
              child: const Icon(
                Icons.diamond_rounded,
                color: Color(0xFF70D8FF),
                size: 30,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (package.badge != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: featured
                            ? MunjaColors.mint
                                .withValues(alpha: 0.13)
                            : const Color(0xFF70D8FF)
                                .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        package.badge!,
                        style: TextStyle(
                          color: featured
                              ? MunjaColors.mint
                              : const Color(0xFF70D8FF),
                          fontSize: 6.8,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.75,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    package.title.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.75,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${formatNumber(package.totalCrystals)} Crystals',
                            maxLines: 1,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.35,
                            ),
                          ),
                        ),
                      ),
                      if (package.hasBonus) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '+${formatNumber(package.bonusCrystals)} bonus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MunjaColors.mint,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    package.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 8.5,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 86,
              child: FilledButton(
                onPressed:
                    disabled || loading ? null : onBuy,
                style: FilledButton.styleFrom(
                  backgroundColor: featured
                      ? MunjaColors.mint
                      : Colors.white.withValues(alpha: 0.12),
                  foregroundColor:
                      featured ? MunjaColors.bg : Colors.white,
                  disabledBackgroundColor:
                      Colors.white.withValues(alpha: 0.11),
                  disabledForegroundColor:
                      Colors.white.withValues(alpha: 0.92),
                  minimumSize: const Size(
                    86,
                    47,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: loading
                    ? SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: featured
                              ? MunjaColors.bg
                              : MunjaColors.mint,
                        ),
                      )
                    : Text(
                        priceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreNotice extends StatelessWidget {
  const _StoreNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        14,
        13,
        14,
        13,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 17,
            color: MunjaColors.mint.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Crystal purchases will be processed securely by Apple App Store '
              'or Google Play. Purchased Crystals do not expire.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.68),
                fontSize: 8.5,
                height: 1.45,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
