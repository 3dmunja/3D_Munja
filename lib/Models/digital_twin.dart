import 'bike_hotspot.dart';
import 'bike_product.dart';
import 'firestore_bike.dart';

class DigitalTwin {
  const DigitalTwin({
    required this.bike,
    required this.products,
    required this.hotspots,
    this.selectedHotspotId,
    this.selectedProductId,
    this.isInitialized = false,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
    this.lastSyncedAt,
  });

  final FirestoreBike bike;
  final List<BikeProduct> products;
  final List<BikeHotspot> hotspots;

  final String? selectedHotspotId;
  final String? selectedProductId;

  final bool isInitialized;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;

  final DateTime? lastSyncedAt;

  bool get isReady =>
      isInitialized && !isLoading && !hasError && bike.id.trim().isNotEmpty;

  bool get hasProducts => products.isNotEmpty;

  bool get hasHotspots => hotspots.isNotEmpty;

  bool get hasDigitalTwinModel => bike.hasDigitalTwinModel;

  bool get isDigitalTwinEnabled => bike.digitalTwinEnabled;

  bool get canShowDigitalTwin =>
      bike.digitalTwinEnabled && bike.hasDigitalTwinModel;

  int get productCount => products.length;

  int get connectedProductCount =>
      products.where((product) => product.isConnected).length;

  int get installedProductCount =>
      products.where((product) => product.isInstalled).length;

  int get firmwareUpdateCount =>
      products.where((product) => product.hasFirmwareUpdate).length;

  bool get hasConnectedProducts => connectedProductCount > 0;

  bool get hasFirmwareUpdates => firmwareUpdateCount > 0;

  BikeHotspot? get selectedHotspot {
    final hotspotId = selectedHotspotId;

    if (hotspotId == null || hotspotId.trim().isEmpty) {
      return null;
    }

    return hotspotById(hotspotId);
  }

  BikeProduct? get selectedProduct {
    final productId = selectedProductId;

    if (productId != null && productId.trim().isNotEmpty) {
      final product = productById(productId);

      if (product != null) {
        return product;
      }
    }

    final hotspot = selectedHotspot;

    if (hotspot == null || hotspot.productId.trim().isEmpty) {
      return null;
    }

    return productById(hotspot.productId);
  }

  List<BikeProduct> get enabledProducts =>
      products.where((product) => product.isEnabled).toList(growable: false);

  List<BikeProduct> get connectedProducts =>
      products.where((product) => product.isConnected).toList(growable: false);

  List<BikeProduct> get productsWithFirmwareUpdate => products
      .where((product) => product.hasFirmwareUpdate)
      .toList(growable: false);

  List<BikeHotspot> get enabledHotspots =>
      hotspots.where((hotspot) => hotspot.enabled).toList(growable: false);

  List<BikeHotspot> get productHotspots => hotspots
      .where((hotspot) => hotspot.productId.trim().isNotEmpty)
      .toList(growable: false);

  factory DigitalTwin.empty({required FirestoreBike bike}) {
    return DigitalTwin(
      bike: bike,
      products: const <BikeProduct>[],
      hotspots: defaultBikeHotspots,
      isInitialized: false,
    );
  }

  factory DigitalTwin.ready({
    required FirestoreBike bike,
    List<BikeProduct> products = const <BikeProduct>[],
    List<BikeHotspot> hotspots = defaultBikeHotspots,
    DateTime? lastSyncedAt,
  }) {
    return DigitalTwin(
      bike: bike,
      products: List<BikeProduct>.unmodifiable(products),
      hotspots: List<BikeHotspot>.unmodifiable(hotspots),
      isInitialized: true,
      isLoading: false,
      hasError: false,
      lastSyncedAt: lastSyncedAt ?? DateTime.now(),
    );
  }

  BikeHotspot? hotspotById(String hotspotId) {
    final normalizedId = hotspotId.trim();

    if (normalizedId.isEmpty) {
      return null;
    }

    for (final hotspot in hotspots) {
      if (hotspot.id == normalizedId) {
        return hotspot;
      }
    }

    return null;
  }

  BikeProduct? productById(String productId) {
    final normalizedId = productId.trim();

    if (normalizedId.isEmpty) {
      return null;
    }

    for (final product in products) {
      if (product.id == normalizedId) {
        return product;
      }
    }

    return null;
  }

  List<BikeProduct> productsByType(BikeProductType type) {
    return products
        .where((product) => product.type == type)
        .toList(growable: false);
  }

  List<BikeProduct> productsForHotspot(String hotspotId) {
    final normalizedHotspotId = hotspotId.trim();

    if (normalizedHotspotId.isEmpty) {
      return const <BikeProduct>[];
    }

    final hotspot = hotspotById(normalizedHotspotId);

    if (hotspot != null && hotspot.productId.trim().isNotEmpty) {
      final linkedProduct = productById(hotspot.productId);

      if (linkedProduct != null) {
        return <BikeProduct>[linkedProduct];
      }
    }

    return products
        .where((product) => product.hotspotId == normalizedHotspotId)
        .toList(growable: false);
  }

  BikeHotspot? hotspotForProduct(String productId) {
    final product = productById(productId);

    if (product == null) {
      return null;
    }

    if (product.hotspotId.trim().isNotEmpty) {
      final directHotspot = hotspotById(product.hotspotId);

      if (directHotspot != null) {
        return directHotspot;
      }
    }

    for (final hotspot in hotspots) {
      if (hotspot.productId == product.id) {
        return hotspot;
      }
    }

    return null;
  }

  DigitalTwin selectHotspot(String? hotspotId) {
    if (hotspotId == null || hotspotId.trim().isEmpty) {
      return clearSelection();
    }

    final hotspot = hotspotById(hotspotId);

    if (hotspot == null) {
      return this;
    }

    String? linkedProductId;

    if (hotspot.productId.trim().isNotEmpty &&
        productById(hotspot.productId) != null) {
      linkedProductId = hotspot.productId;
    } else {
      final matchingProducts = productsForHotspot(hotspot.id);

      if (matchingProducts.isNotEmpty) {
        linkedProductId = matchingProducts.first.id;
      }
    }

    return copyWith(
      selectedHotspotId: hotspot.id,
      selectedProductId: linkedProductId,
      clearSelectedProductId: linkedProductId == null,
    );
  }

  DigitalTwin selectProduct(String? productId) {
    if (productId == null || productId.trim().isEmpty) {
      return copyWith(clearSelectedProductId: true);
    }

    final product = productById(productId);

    if (product == null) {
      return this;
    }

    final hotspot = hotspotForProduct(product.id);

    return copyWith(
      selectedProductId: product.id,
      selectedHotspotId: hotspot?.id,
      clearSelectedHotspotId: hotspot == null,
    );
  }

  DigitalTwin clearSelection() {
    return copyWith(clearSelectedHotspotId: true, clearSelectedProductId: true);
  }

  DigitalTwin replaceBike(FirestoreBike updatedBike) {
    return copyWith(bike: updatedBike, lastSyncedAt: DateTime.now());
  }

  DigitalTwin replaceProducts(List<BikeProduct> updatedProducts) {
    final productIds = updatedProducts.map((product) => product.id).toSet();

    return copyWith(
      products: List<BikeProduct>.unmodifiable(updatedProducts),
      clearSelectedProductId:
          selectedProductId != null && !productIds.contains(selectedProductId),
      lastSyncedAt: DateTime.now(),
    );
  }

  DigitalTwin replaceHotspots(List<BikeHotspot> updatedHotspots) {
    final hotspotIds = updatedHotspots.map((hotspot) => hotspot.id).toSet();

    return copyWith(
      hotspots: List<BikeHotspot>.unmodifiable(updatedHotspots),
      clearSelectedHotspotId:
          selectedHotspotId != null && !hotspotIds.contains(selectedHotspotId),
      lastSyncedAt: DateTime.now(),
    );
  }

  DigitalTwin addProduct(BikeProduct product) {
    final updatedProducts = <BikeProduct>[
      ...products.where((item) => item.id != product.id),
      product,
    ];

    return replaceProducts(updatedProducts);
  }

  DigitalTwin updateProduct(BikeProduct updatedProduct) {
    final updatedProducts = products
        .map(
          (product) =>
              product.id == updatedProduct.id ? updatedProduct : product,
        )
        .toList(growable: false);

    final exists = products.any((product) => product.id == updatedProduct.id);

    return replaceProducts(
      exists ? updatedProducts : <BikeProduct>[...products, updatedProduct],
    );
  }

  DigitalTwin removeProduct(String productId) {
    final normalizedId = productId.trim();

    if (normalizedId.isEmpty) {
      return this;
    }

    final updatedProducts = products
        .where((product) => product.id != normalizedId)
        .toList(growable: false);

    return copyWith(
      products: List<BikeProduct>.unmodifiable(updatedProducts),
      clearSelectedProductId: selectedProductId == normalizedId,
      lastSyncedAt: DateTime.now(),
    );
  }

  DigitalTwin addHotspot(BikeHotspot hotspot) {
    final updatedHotspots = <BikeHotspot>[
      ...hotspots.where((item) => item.id != hotspot.id),
      hotspot,
    ];

    return replaceHotspots(updatedHotspots);
  }

  DigitalTwin updateHotspot(BikeHotspot updatedHotspot) {
    final updatedHotspots = hotspots
        .map(
          (hotspot) =>
              hotspot.id == updatedHotspot.id ? updatedHotspot : hotspot,
        )
        .toList(growable: false);

    final exists = hotspots.any((hotspot) => hotspot.id == updatedHotspot.id);

    return replaceHotspots(
      exists ? updatedHotspots : <BikeHotspot>[...hotspots, updatedHotspot],
    );
  }

  DigitalTwin removeHotspot(String hotspotId) {
    final normalizedId = hotspotId.trim();

    if (normalizedId.isEmpty) {
      return this;
    }

    final updatedHotspots = hotspots
        .where((hotspot) => hotspot.id != normalizedId)
        .toList(growable: false);

    return copyWith(
      hotspots: List<BikeHotspot>.unmodifiable(updatedHotspots),
      clearSelectedHotspotId: selectedHotspotId == normalizedId,
      lastSyncedAt: DateTime.now(),
    );
  }

  DigitalTwin setLoading(bool value) {
    return copyWith(
      isLoading: value,
      hasError: value ? false : hasError,
      clearErrorMessage: value,
    );
  }

  DigitalTwin setError(String message) {
    return copyWith(isLoading: false, hasError: true, errorMessage: message);
  }

  DigitalTwin clearError() {
    return copyWith(hasError: false, clearErrorMessage: true);
  }

  DigitalTwin markInitialized({DateTime? syncedAt}) {
    return copyWith(
      isInitialized: true,
      isLoading: false,
      hasError: false,
      clearErrorMessage: true,
      lastSyncedAt: syncedAt ?? DateTime.now(),
    );
  }

  DigitalTwin copyWith({
    FirestoreBike? bike,
    List<BikeProduct>? products,
    List<BikeHotspot>? hotspots,
    String? selectedHotspotId,
    bool clearSelectedHotspotId = false,
    String? selectedProductId,
    bool clearSelectedProductId = false,
    bool? isInitialized,
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
    bool clearErrorMessage = false,
    DateTime? lastSyncedAt,
    bool clearLastSyncedAt = false,
  }) {
    return DigitalTwin(
      bike: bike ?? this.bike,
      products: products == null
          ? List<BikeProduct>.unmodifiable(this.products)
          : List<BikeProduct>.unmodifiable(products),
      hotspots: hotspots == null
          ? List<BikeHotspot>.unmodifiable(this.hotspots)
          : List<BikeHotspot>.unmodifiable(hotspots),
      selectedHotspotId: clearSelectedHotspotId
          ? null
          : selectedHotspotId ?? this.selectedHotspotId,
      selectedProductId: clearSelectedProductId
          ? null
          : selectedProductId ?? this.selectedProductId,
      isInitialized: isInitialized ?? this.isInitialized,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      lastSyncedAt: clearLastSyncedAt
          ? null
          : lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'bikeId': bike.id,
      'products': products
          .map((product) => product.toMap())
          .toList(growable: false),
      'hotspots': hotspots
          .map((hotspot) => hotspot.toMap())
          .toList(growable: false),
      'selectedHotspotId': selectedHotspotId,
      'selectedProductId': selectedProductId,
      'isInitialized': isInitialized,
      'isLoading': isLoading,
      'hasError': hasError,
      'errorMessage': errorMessage,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
    };
  }

  @override
  String toString() {
    return 'DigitalTwin('
        'bikeId: ${bike.id}, '
        'products: ${products.length}, '
        'hotspots: ${hotspots.length}, '
        'selectedHotspotId: $selectedHotspotId, '
        'selectedProductId: $selectedProductId, '
        'isInitialized: $isInitialized, '
        'isLoading: $isLoading, '
        'hasError: $hasError'
        ')';
  }
}
