import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../Services/munja_pro_service.dart';

const String munjaProMonthlyProductId = 'munja.pro.monthly';

typedef MunjaProPurchaseVerifier = Future<void> Function({
  required String uid,
  required PurchaseDetails purchase,
  required String verificationData,
  required String verificationSource,
});

/// Store-facing purchase service for MUNJA PRO.
///
/// Responsibilities:
/// - query Google Play / App Store for the live subscription product
/// - expose the localized store price to the UI
/// - start and restore subscription purchases
/// - forward purchase tokens/receipts to a trusted backend verifier
/// - complete the store transaction only after trusted verification succeeds
///
/// SECURITY:
/// This service intentionally never writes `isPro` directly from the client.
/// The supplied [verifyPurchase] callback must verify the purchase on a trusted
/// backend and update the user's Firestore entitlement. MunjaProService then
/// receives that entitlement through its existing Firestore listener.
class MunjaProPurchaseService extends ChangeNotifier {
  MunjaProPurchaseService({
    InAppPurchase? inAppPurchase,
    FirebaseAuth? auth,
    MunjaProPurchaseVerifier? verifyPurchase,
    FirebaseFunctions? functions,
  })  : _iap = inAppPurchase ?? InAppPurchase.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ??
            FirebaseFunctions.instanceFor(region: 'europe-west1'),
        _verifyPurchase = verifyPurchase;

  final InAppPurchase _iap;
  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;
  final MunjaProPurchaseVerifier? _verifyPurchase;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  ProductDetails? _monthlyProduct;

  bool _initialized = false;
  bool _initializing = false;
  bool _storeAvailable = false;
  bool _loadingProduct = false;
  bool _purchasing = false;
  bool _restoring = false;
  bool _disposed = false;

  String? _errorMessage;

  bool get isInitialized => _initialized;
  bool get isInitializing => _initializing;
  bool get isStoreAvailable => _storeAvailable;
  bool get isLoadingProduct => _loadingProduct;
  bool get isPurchasing => _purchasing;
  bool get isRestoring => _restoring;
  bool get isBusy => _initializing || _loadingProduct || _purchasing || _restoring;

  /// Purchases are verified by the deployed Firebase callable.
  /// A custom verifier may still be injected for tests.
  bool get hasTrustedVerifier => true;

  ProductDetails? get monthlyProduct => _monthlyProduct;

  String? get localizedMonthlyPrice => _monthlyProduct?.price;

  String? get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_disposed || _initialized || _initializing) {
      return;
    }

    _initializing = true;
    _errorMessage = null;
    _notify();

    try {
      _purchaseSubscription ??= _iap.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('MUNJA PRO PURCHASE STREAM ERROR: $error');
          debugPrint('$stackTrace');

          _errorMessage = 'Store connection failed. Please try again.';
          _purchasing = false;
          _restoring = false;
          _notify();
        },
      );

      _storeAvailable = await _iap.isAvailable();

      if (!_storeAvailable) {
        _errorMessage = 'Google Play purchases are unavailable on this device.';
        return;
      }

      await loadProduct();
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('MUNJA PRO PURCHASE INIT ERROR: $error');
      debugPrint('$stackTrace');
      _errorMessage = 'MUNJA PRO could not connect to the store.';
      rethrow;
    } finally {
      _initializing = false;
      _notify();
    }
  }

  Future<void> loadProduct() async {
    if (_disposed) {
      return;
    }

    _loadingProduct = true;
    _errorMessage = null;
    _notify();

    try {
      final response = await _iap.queryProductDetails(
        const <String>{munjaProMonthlyProductId},
      );

      if (response.error != null) {
        debugPrint('MUNJA PRO PRODUCT QUERY ERROR: ${response.error}');
        _errorMessage = response.error!.message;
      }

      if (response.notFoundIDs.contains(munjaProMonthlyProductId)) {
        _monthlyProduct = null;
        _errorMessage = 'MUNJA PRO is not available from Google Play yet.';
        return;
      }

      ProductDetails? selected;

      for (final product in response.productDetails) {
        if (product.id != munjaProMonthlyProductId) {
          continue;
        }

        // With one active monthly base plan this normally returns one product.
        // If Google exposes more than one eligible offer later, prefer the
        // lowest current store price until we add explicit offer selection.
        if (selected == null || product.rawPrice < selected.rawPrice) {
          selected = product;
        }
      }

      _monthlyProduct = selected;

      if (_monthlyProduct == null && _errorMessage == null) {
        _errorMessage = 'MUNJA PRO is not available from Google Play yet.';
      }
    } finally {
      _loadingProduct = false;
      _notify();
    }
  }

  Future<void> purchaseMonthly() async {
    if (_disposed) {
      throw StateError('MunjaProPurchaseService is disposed.');
    }

    if (!_initialized) {
      await initialize();
    }

    if (!_storeAvailable) {
      throw StateError('Google Play purchases are unavailable.');
    }

    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Sign in before subscribing to MUNJA PRO.');
    }

    final product = _monthlyProduct;

    if (product == null) {
      await loadProduct();
    }

    final resolvedProduct = _monthlyProduct;

    if (resolvedProduct == null) {
      throw StateError('MUNJA PRO is unavailable from Google Play.');
    }

    if (_purchasing) {
      return;
    }

    _purchasing = true;
    _errorMessage = null;
    _notify();

    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(
          productDetails: resolvedProduct,
          applicationUserName: user.uid,
        ),
      );

      if (!started) {
        throw StateError('Google Play did not start the purchase.');
      }
    } catch (error) {
      _purchasing = false;
      _notify();
      rethrow;
    }
  }

  Future<void> restorePurchases() async {
    if (_disposed) {
      return;
    }

    if (!_initialized) {
      await initialize();
    }

    if (_auth.currentUser == null) {
      throw StateError('Sign in before restoring MUNJA PRO.');
    }

    if (_restoring) {
      return;
    }

    _restoring = true;
    _errorMessage = null;
    _notify();

    try {
      await _iap.restorePurchases(
        applicationUserName: _auth.currentUser!.uid,
      );
    } catch (error) {
      _restoring = false;
      _notify();
      rethrow;
    }
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.productID.trim() != munjaProMonthlyProductId) {
        continue;
      }

      try {
        await _handlePurchase(purchase);
      } catch (error, stackTrace) {
        debugPrint('MUNJA PRO PURCHASE UPDATE ERROR: $error');
        debugPrint('$stackTrace');

        _errorMessage = 'MUNJA PRO purchase could not be verified.';
        _purchasing = false;
        _restoring = false;
        _notify();
      }
    }
  }

  Future<void> _handlePurchase(PurchaseDetails purchase) async {
    debugPrint(
      'MUNJA PRO PURCHASE: '
      '${purchase.productID} | ${purchase.status} | '
      'pendingComplete=${purchase.pendingCompletePurchase}',
    );

    switch (purchase.status) {
      case PurchaseStatus.pending:
        _purchasing = true;
        _notify();
        return;

      case PurchaseStatus.error:
        _errorMessage = purchase.error?.message ?? 'Google Play purchase failed.';
        _purchasing = false;
        _restoring = false;

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }

        _notify();
        return;

      case PurchaseStatus.canceled:
        _errorMessage = null;
        _purchasing = false;
        _restoring = false;

        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }

        _notify();
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        await _verifyAndComplete(purchase);
        return;
    }
  }

  Future<void> _verifyAndComplete(PurchaseDetails purchase) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in Munja user for purchase verification.');
    }

    final verificationData = purchase.verificationData.serverVerificationData;
    final verificationSource = purchase.verificationData.source;

    if (verificationData.trim().isEmpty) {
      throw StateError('Google Play verification data is empty.');
    }

    final customVerifier = _verifyPurchase;

    if (customVerifier != null) {
      await customVerifier(
        uid: user.uid,
        purchase: purchase,
        verificationData: verificationData,
        verificationSource: verificationSource,
      );
    } else {
      if (verificationSource.toLowerCase() != 'google_play') {
        throw StateError(
          'MUNJA PRO Google verification received an unsupported store source.',
        );
      }

      final callable = _functions.httpsCallable(
        'verifyMunjaProGooglePurchase',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final result = await callable.call(<String, dynamic>{
        'purchaseToken': verificationData,
        'productId': purchase.productID,
      });

      final data = result.data;

      if (data is! Map || data['success'] != true || data['active'] != true) {
        throw StateError(
          'Google Play did not confirm an active MUNJA PRO subscription.',
        );
      }
    }

    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }

    // The backend verifier should have updated users/{uid}. Force one refresh
    // in addition to the live Firestore listener so the UI reacts immediately.
    await MunjaProService.instance.refresh();

    _purchasing = false;
    _restoring = false;
    _errorMessage = null;
    _notify();
  }

  void clearError() {
    _errorMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    unawaited(_purchaseSubscription?.cancel());
    _purchaseSubscription = null;
    super.dispose();
  }
}
