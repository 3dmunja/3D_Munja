import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/bike_hotspot.dart';
import '../models/bike_product.dart';
import '../models/digital_twin.dart';
import '../models/firestore_bike.dart';

class DigitalTwinProvider extends ChangeNotifier {
  DigitalTwinProvider({List<BikeHotspot> defaultHotspots = defaultBikeHotspots})
    : _defaultHotspots = List<BikeHotspot>.unmodifiable(defaultHotspots);

  final List<BikeHotspot> _defaultHotspots;

  DigitalTwin? _digitalTwin;
  StreamSubscription<List<BikeProduct>>? _productsSubscription;

  bool _disposed = false;
  bool _isSaving = false;
  String? _errorMessage;

  DigitalTwin? get digitalTwin => _digitalTwin;

  FirestoreBike? get bike => _digitalTwin?.bike;

  List<BikeProduct> get products =>
      _digitalTwin?.products ?? const <BikeProduct>[];

  List<BikeHotspot> get hotspots => _digitalTwin?.hotspots ?? _defaultHotspots;

  BikeHotspot? get selectedHotspot => _digitalTwin?.selectedHotspot;

  BikeProduct? get selectedProduct => _digitalTwin?.selectedProduct;

  String? get selectedHotspotId => _digitalTwin?.selectedHotspotId;

  String? get selectedProductId => _digitalTwin?.selectedProductId;

  bool get isInitialized => _digitalTwin?.isInitialized ?? false;

  bool get isLoading => _digitalTwin?.isLoading ?? false;

  bool get isSaving => _isSaving;

  bool get isBusy => isLoading || _isSaving;

  bool get hasError =>
      _errorMessage != null || (_digitalTwin?.hasError ?? false);

  String? get errorMessage => _errorMessage ?? _digitalTwin?.errorMessage;

  bool get hasBike => bike != null;

  bool get hasProducts => products.isNotEmpty;

  bool get hasHotspots => hotspots.isNotEmpty;

  bool get canShowDigitalTwin => _digitalTwin?.canShowDigitalTwin ?? false;

  int get productCount => _digitalTwin?.productCount ?? 0;

  int get connectedProductCount => _digitalTwin?.connectedProductCount ?? 0;

  int get installedProductCount => _digitalTwin?.installedProductCount ?? 0;

  int get firmwareUpdateCount => _digitalTwin?.firmwareUpdateCount ?? 0;

  List<BikeProduct> get connectedProducts =>
      _digitalTwin?.connectedProducts ?? const <BikeProduct>[];

  List<BikeProduct> get productsWithFirmwareUpdate =>
      _digitalTwin?.productsWithFirmwareUpdate ?? const <BikeProduct>[];

  List<BikeHotspot> get enabledHotspots =>
      _digitalTwin?.enabledHotspots ?? _defaultHotspots;

  Future<void> initialize({
    required FirestoreBike bike,
    List<BikeProduct> products = const <BikeProduct>[],
    List<BikeHotspot>? hotspots,
  }) async {
    _setError(null);

    _digitalTwin = DigitalTwin(
      bike: bike,
      products: List<BikeProduct>.unmodifiable(products),
      hotspots: List<BikeHotspot>.unmodifiable(hotspots ?? _defaultHotspots),
      isInitialized: false,
      isLoading: true,
    );
    _safeNotifyListeners();

    try {
      _digitalTwin = DigitalTwin.ready(
        bike: bike,
        products: products,
        hotspots: hotspots ?? _defaultHotspots,
        lastSyncedAt: DateTime.now(),
      );
    } catch (error) {
      _setDigitalTwinError('Digital Twin kunne ikke initialiseres: $error');
    }

    _safeNotifyListeners();
  }

  Future<void> initializeEmpty({required FirestoreBike bike}) {
    return initialize(
      bike: bike,
      products: const <BikeProduct>[],
      hotspots: _defaultHotspots,
    );
  }

  void updateBike(FirestoreBike bike) {
    final current = _digitalTwin;

    if (current == null) {
      _digitalTwin = DigitalTwin.ready(
        bike: bike,
        products: const <BikeProduct>[],
        hotspots: _defaultHotspots,
      );
    } else {
      _digitalTwin = current.replaceBike(bike);
    }

    _setError(null);
    _safeNotifyListeners();
  }

  void replaceProducts(List<BikeProduct> products) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.replaceProducts(products);
    _setError(null);
    _safeNotifyListeners();
  }

  void replaceHotspots(List<BikeHotspot> hotspots) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.replaceHotspots(hotspots);
    _setError(null);
    _safeNotifyListeners();
  }

  void selectHotspot(String? hotspotId) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.selectHotspot(hotspotId);
    _safeNotifyListeners();
  }

  void selectProduct(String? productId) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.selectProduct(productId);
    _safeNotifyListeners();
  }

  void clearSelection() {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.clearSelection();
    _safeNotifyListeners();
  }

  BikeHotspot? hotspotById(String hotspotId) {
    return _digitalTwin?.hotspotById(hotspotId);
  }

  BikeProduct? productById(String productId) {
    return _digitalTwin?.productById(productId);
  }

  List<BikeProduct> productsByType(BikeProductType type) {
    return _digitalTwin?.productsByType(type) ?? const <BikeProduct>[];
  }

  List<BikeProduct> productsForHotspot(String hotspotId) {
    return _digitalTwin?.productsForHotspot(hotspotId) ?? const <BikeProduct>[];
  }

  BikeHotspot? hotspotForProduct(String productId) {
    return _digitalTwin?.hotspotForProduct(productId);
  }

  void addProduct(BikeProduct product) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.addProduct(product);
    _setError(null);
    _safeNotifyListeners();
  }

  void updateProduct(BikeProduct product) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.updateProduct(product);
    _setError(null);
    _safeNotifyListeners();
  }

  void removeProduct(String productId) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.removeProduct(productId);
    _setError(null);
    _safeNotifyListeners();
  }

  void addHotspot(BikeHotspot hotspot) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.addHotspot(hotspot);
    _setError(null);
    _safeNotifyListeners();
  }

  void updateHotspot(BikeHotspot hotspot) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.updateHotspot(hotspot);
    _setError(null);
    _safeNotifyListeners();
  }

  void removeHotspot(String hotspotId) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.removeHotspot(hotspotId);
    _setError(null);
    _safeNotifyListeners();
  }

  void setProductConnectionStatus({
    required String productId,
    required BikeProductConnectionStatus status,
    int? batteryLevel,
    int? rssi,
  }) {
    final product = productById(productId);

    if (product == null) {
      _setError('Produktet blev ikke fundet.');
      _safeNotifyListeners();
      return;
    }

    updateProduct(
      product.copyWith(
        connectionStatus: status,
        batteryLevel: batteryLevel,
        rssi: rssi,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void setProductBatteryLevel({
    required String productId,
    required int batteryLevel,
  }) {
    final product = productById(productId);

    if (product == null) {
      _setError('Produktet blev ikke fundet.');
      _safeNotifyListeners();
      return;
    }

    updateProduct(
      product.copyWith(
        batteryLevel: batteryLevel.clamp(0, 100),
        updatedAt: DateTime.now(),
      ),
    );
  }

  void setProductFirmware({
    required String productId,
    required String firmwareVersion,
    String? latestFirmwareVersion,
  }) {
    final product = productById(productId);

    if (product == null) {
      _setError('Produktet blev ikke fundet.');
      _safeNotifyListeners();
      return;
    }

    updateProduct(
      product.copyWith(
        firmwareVersion: firmwareVersion,
        latestFirmwareVersion: latestFirmwareVersion,
        installStatus:
            latestFirmwareVersion != null &&
                latestFirmwareVersion.trim().isNotEmpty &&
                latestFirmwareVersion.trim() != firmwareVersion.trim()
            ? BikeProductInstallStatus.updateAvailable
            : BikeProductInstallStatus.installed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void updateProductSetting({
    required String productId,
    required String key,
    required dynamic value,
  }) {
    final product = productById(productId);

    if (product == null) {
      _setError('Produktet blev ikke fundet.');
      _safeNotifyListeners();
      return;
    }

    updateProduct(product.withUpdatedSetting(key, value));
  }

  void removeProductSetting({required String productId, required String key}) {
    final product = productById(productId);

    if (product == null) {
      _setError('Produktet blev ikke fundet.');
      _safeNotifyListeners();
      return;
    }

    updateProduct(product.withoutSetting(key));
  }

  Future<T?> runSavingOperation<T>({
    required Future<T> Function() operation,
    String fallbackErrorMessage = 'Handlingen kunne ikke gennemføres.',
  }) async {
    if (_isSaving) {
      return null;
    }

    _isSaving = true;
    _setError(null);
    _safeNotifyListeners();

    try {
      final result = await operation();
      return result;
    } catch (error) {
      _setError('$fallbackErrorMessage $error');
      return null;
    } finally {
      _isSaving = false;
      _safeNotifyListeners();
    }
  }

  void bindProductsStream(Stream<List<BikeProduct>> stream) {
    unawaited(_productsSubscription?.cancel());

    _productsSubscription = stream.listen(
      replaceProducts,
      onError: (Object error, StackTrace stackTrace) {
        _setError('Produkterne kunne ikke synkroniseres: $error');
        _safeNotifyListeners();
      },
    );
  }

  Future<void> unbindProductsStream() async {
    await _productsSubscription?.cancel();
    _productsSubscription = null;
  }

  void setLoading(bool value) {
    final current = _digitalTwin;

    if (current == null) {
      return;
    }

    _digitalTwin = current.setLoading(value);
    _safeNotifyListeners();
  }

  void clearError() {
    _setError(null);

    final current = _digitalTwin;

    if (current != null && current.hasError) {
      _digitalTwin = current.clearError();
    }

    _safeNotifyListeners();
  }

  void reset({bool keepDefaultHotspots = true}) {
    _digitalTwin = null;
    _setError(null);
    _isSaving = false;

    if (!keepDefaultHotspots) {
      // Default hotspots are immutable and remain available through
      // the provider configuration.
    }

    _safeNotifyListeners();
  }

  void _setDigitalTwinError(String message) {
    final current = _digitalTwin;

    if (current == null) {
      _setError(message);
      return;
    }

    _digitalTwin = current.setError(message);
    _setError(message);
  }

  void _setError(String? message) {
    final normalizedMessage = message?.trim();
    _errorMessage = normalizedMessage == null || normalizedMessage.isEmpty
        ? null
        : normalizedMessage;
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_productsSubscription?.cancel());
    _productsSubscription = null;
    super.dispose();
  }
}
