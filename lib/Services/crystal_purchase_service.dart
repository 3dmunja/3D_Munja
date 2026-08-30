import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/crystal_package.dart';

@immutable
class CrystalPurchaseResult {
  const CrystalPurchaseResult({
    required this.package,
    required this.purchase,
  });

  final CrystalPackage package;
  final PurchaseDetails purchase;
}

/// Trusted server-side verification/delivery bridge.
///
/// Your backend / Cloud Function must verify the Apple/Google purchase,
/// use the store transaction as an idempotency key, and credit Firestore
/// exactly once. The mobile app must never directly add paid Crystals.
typedef CrystalPurchaseVerifier = Future<void> Function({
  required CrystalPackage package,
  required PurchaseDetails purchase,
  required String verificationData,
  required String verificationSource,
});

class CrystalPurchaseService extends ChangeNotifier {
  CrystalPurchaseService({
    InAppPurchase? inAppPurchase,
    required CrystalPurchaseVerifier verifyAndDeliver,
  })  : _iap = inAppPurchase ?? InAppPurchase.instance,
        _verifyAndDeliver = verifyAndDeliver;

  final InAppPurchase _iap;
  final CrystalPurchaseVerifier _verifyAndDeliver;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  final Map<String, ProductDetails> _products =
      <String, ProductDetails>{};

  final Map<String, Completer<CrystalPurchaseResult>> _pending =
      <String, Completer<CrystalPurchaseResult>>{};

  bool _initialized = false;
  bool _initializing = false;
  bool _storeAvailable = false;
  bool _loadingProducts = false;
  bool _disposed = false;
  String? _activeProductId;
  String? _errorMessage;

  bool get isInitialized => _initialized;
  bool get isInitializing => _initializing;
  bool get isStoreAvailable => _storeAvailable;
  bool get isLoadingProducts => _loadingProducts;
  bool get isPurchasing => _activeProductId != null;
  String? get activeProductId => _activeProductId;
  String? get errorMessage => _errorMessage;

  Map<String, ProductDetails> get products =>
      Map<String, ProductDetails>.unmodifiable(_products);

  Map<String, String> get localizedPriceLabels =>
      Map<String, String>.unmodifiable({
        for (final entry in _products.entries)
          entry.key: entry.value.price,
      });

  ProductDetails? productFor(String productId) =>
      _products[productId.trim()];

  Future<void> initialize({
    List<CrystalPackage> packages = munjaCrystalPackages,
  }) async {
    if (_disposed || _initialized || _initializing) return;

    _initializing = true;
    _errorMessage = null;
    _notify();

    try {
      _purchaseSubscription ??= _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('CRYSTAL PURCHASE STREAM ERROR: $error');
          debugPrint('$stackTrace');
          _errorMessage = 'Store purchase connection failed.';
          _failAllPending(StateError(_errorMessage!));
          _notify();
        },
      );

      _storeAvailable = await _iap.isAvailable();

      if (!_storeAvailable) {
        _errorMessage =
            'App Store / Google Play purchases are unavailable.';
        return;
      }

      await loadProducts(packages: packages);
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('CRYSTAL PURCHASE INIT ERROR: $error');
      debugPrint('$stackTrace');
      _errorMessage =
          'Crystal purchases could not be initialized.';
      rethrow;
    } finally {
      _initializing = false;
      _notify();
    }
  }

  Future<void> loadProducts({
    List<CrystalPackage> packages = munjaCrystalPackages,
  }) async {
    if (_disposed) return;

    _loadingProducts = true;
    _errorMessage = null;
    _notify();

    try {
      final ids = packages
          .map((p) => p.normalizedProductId)
          .where((id) => id.isNotEmpty)
          .toSet();

      final response = await _iap.queryProductDetails(ids);

      _products
        ..clear()
        ..addEntries(
          response.productDetails.map(
            (product) => MapEntry(product.id, product),
          ),
        );

      if (response.error != null) {
        _errorMessage = response.error!.message;
        debugPrint(
          'CRYSTAL PRODUCT QUERY ERROR: ${response.error}',
        );
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          'CRYSTAL PRODUCTS NOT FOUND: '
          '${response.notFoundIDs.join(', ')}',
        );
      }
    } finally {
      _loadingProducts = false;
      _notify();
    }
  }

  /// Starts a consumable purchase.
  ///
  /// This future completes only after [verifyAndDeliver] succeeds and the
  /// purchase has been completed with Apple/Google.
  Future<CrystalPurchaseResult> purchase(
    CrystalPackage package,
  ) async {
    if (_disposed) {
      throw StateError('CrystalPurchaseService is disposed.');
    }

    if (!_initialized) {
      await initialize();
    }

    if (!_storeAvailable) {
      throw StateError(
        'App Store / Google Play purchases are unavailable.',
      );
    }

    if (_activeProductId != null) {
      throw StateError(
        'Another Crystal purchase is already in progress.',
      );
    }

    final productId = package.normalizedProductId;
    final product = _products[productId];

    if (product == null) {
      throw StateError(
        'Store product "$productId" is unavailable.',
      );
    }

    final completer = Completer<CrystalPurchaseResult>();
    _pending[productId] = completer;
    _activeProductId = productId;
    _errorMessage = null;
    _notify();

    try {
      final started = await _iap.buyConsumable(
        purchaseParam: PurchaseParam(
          productDetails: product,
        ),
        // Paid Crystals are delivered only after trusted verification.
        autoConsume: false,
      );

      if (!started) {
        throw StateError('The store did not start the purchase.');
      }

      return await completer.future;
    } catch (error) {
      final pending = _pending.remove(productId);
      if (pending != null && !pending.isCompleted) {
        pending.completeError(error);
      }
      if (_activeProductId == productId) {
        _activeProductId = null;
      }
      _notify();
      rethrow;
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      try {
        await _handlePurchase(purchase);
      } catch (error, stackTrace) {
        debugPrint(
          'CRYSTAL PURCHASE UPDATE ERROR: '
          '${purchase.productID}: $error',
        );
        debugPrint('$stackTrace');

        _completeError(
          purchase.productID,
          error,
        );
        _errorMessage =
            'The Crystal purchase could not be verified.';
        _notify();
      }
    }
  }

  Future<void> _handlePurchase(
    PurchaseDetails purchase,
  ) async {
    final productId = purchase.productID.trim();

    debugPrint(
      'CRYSTAL PURCHASE: '
      '$productId | ${purchase.status} | '
      'pendingComplete=${purchase.pendingCompletePurchase}',
    );

    switch (purchase.status) {
      case PurchaseStatus.pending:
        _activeProductId = productId;
        _notify();
        return;

      case PurchaseStatus.error:
        _completeError(
          productId,
          StateError(
            purchase.error?.message ??
                'Store purchase failed.',
          ),
        );
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        return;

      case PurchaseStatus.canceled:
        _completeError(
          productId,
          StateError('Crystal purchase was canceled.'),
        );
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        final package =
            crystalPackageByProductId(productId);

        if (package == null) {
          throw StateError(
            'Unknown Crystal product: $productId',
          );
        }

        await _verifyDeliverAndComplete(
          package,
          purchase,
        );
        return;
    }
  }

  Future<void> _verifyDeliverAndComplete(
    CrystalPackage package,
    PurchaseDetails purchase,
  ) async {
    final verification =
        purchase.verificationData.serverVerificationData;
    final source = purchase.verificationData.source;

    if (verification.trim().isEmpty) {
      throw StateError(
        'Store verification data is empty.',
      );
    }

    // SECURITY BOUNDARY:
    // This callback must call a trusted server/Cloud Function. Only that
    // server may update the paid Crystal balance.
    await _verifyAndDeliver(
      package: package,
      purchase: purchase,
      verificationData: verification,
      verificationSource: source,
    );

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }

    final result = CrystalPurchaseResult(
      package: package,
      purchase: purchase,
    );

    final completer = _pending.remove(package.productId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }

    if (_activeProductId == package.productId) {
      _activeProductId = null;
    }

    _errorMessage = null;
    _notify();

    debugPrint(
      'CRYSTAL PURCHASE DELIVERED: '
      '${package.productId} -> ${package.totalCrystals}',
    );
  }

  void _completeError(
    String productId,
    Object error,
  ) {
    final completer = _pending.remove(productId);

    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }

    if (_activeProductId == productId) {
      _activeProductId = null;
    }

    _notify();
  }

  void _failAllPending(Object error) {
    final values = _pending.values.toList();
    _pending.clear();
    _activeProductId = null;

    for (final completer in values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  void clearError() {
    _errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _failAllPending(
      StateError('CrystalPurchaseService disposed.'),
    );

    unawaited(_purchaseSubscription?.cancel());
    _purchaseSubscription = null;

    super.dispose();
  }
}
