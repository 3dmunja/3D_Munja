import 'package:flutter/foundation.dart';

/// Immutable configuration for a Munja Crystal in-app purchase package.
///
/// IMPORTANT:
/// - [productId] must match the ID created in App Store Connect / Google Play.
/// - Store price text should come from Apple/Google at runtime. The optional
///   [previewPriceLabel] is only a UI fallback while real IAP is not connected.
/// - Purchased Crystals are digital currency and should be credited only after
///   the store purchase has been verified.
@immutable
class CrystalPackage {
  const CrystalPackage({
    required this.productId,
    required this.crystals,
    required this.title,
    required this.subtitle,
    this.bonusCrystals = 0,
    this.badge,
    this.featured = false,
    this.previewPriceLabel,
  });

  /// Stable store product identifier.
  final String productId;

  /// Base Crystal amount granted by this product.
  final int crystals;

  /// Additional promotional Crystals included in the package.
  final int bonusCrystals;

  /// User-facing package title.
  final String title;

  /// Short package description.
  final String subtitle;

  /// Optional marketing badge, e.g. "POPULAR" or "BEST VALUE".
  final String? badge;

  /// Highlights this package in the Crystal Shop UI.
  final bool featured;

  /// Temporary/fallback UI price before the real store price is loaded.
  ///
  /// Do not use this value as purchase truth. Apple/Google remain the source
  /// of truth for the actual localized price.
  final String? previewPriceLabel;

  int get totalCrystals => crystals + bonusCrystals;

  bool get hasBonus => bonusCrystals > 0;

  String get normalizedProductId => productId.trim();

  CrystalPackage copyWith({
    String? productId,
    int? crystals,
    int? bonusCrystals,
    String? title,
    String? subtitle,
    String? badge,
    bool? featured,
    String? previewPriceLabel,
  }) {
    return CrystalPackage(
      productId: productId ?? this.productId,
      crystals: crystals ?? this.crystals,
      bonusCrystals: bonusCrystals ?? this.bonusCrystals,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      badge: badge ?? this.badge,
      featured: featured ?? this.featured,
      previewPriceLabel:
          previewPriceLabel ?? this.previewPriceLabel,
    );
  }

  @override
  String toString() {
    return 'CrystalPackage('
        'productId: $productId, '
        'crystals: $crystals, '
        'bonusCrystals: $bonusCrystals, '
        'totalCrystals: $totalCrystals, '
        'featured: $featured'
        ')';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CrystalPackage &&
            runtimeType == other.runtimeType &&
            productId == other.productId &&
            crystals == other.crystals &&
            bonusCrystals == other.bonusCrystals &&
            title == other.title &&
            subtitle == other.subtitle &&
            badge == other.badge &&
            featured == other.featured &&
            previewPriceLabel == other.previewPriceLabel;
  }

  @override
  int get hashCode => Object.hash(
        productId,
        crystals,
        bonusCrystals,
        title,
        subtitle,
        badge,
        featured,
        previewPriceLabel,
      );
}

/// Munja V1 Crystal catalog.
///
/// Keep these product IDs stable after they have been created in App Store
/// Connect / Google Play Console.
const List<CrystalPackage> munjaCrystalPackages = <CrystalPackage>[
  CrystalPackage(
    productId: 'munja.crystals.500',
    crystals: 500,
    title: 'Starter',
    subtitle: 'A quick boost for your first unlocks',
    previewPriceLabel: '19 kr.',
  ),
  CrystalPackage(
    productId: 'munja.crystals.1200',
    crystals: 1200,
    bonusCrystals: 100,
    title: 'Rider',
    subtitle: 'More freedom for skins and frames',
    badge: 'POPULAR',
    previewPriceLabel: '39 kr.',
  ),
  CrystalPackage(
    productId: 'munja.crystals.2500',
    crystals: 2500,
    bonusCrystals: 300,
    title: 'Pro',
    subtitle: 'Build a premium Digital Twin collection',
    badge: 'GREAT VALUE',
    previewPriceLabel: '69 kr.',
  ),
  CrystalPackage(
    productId: 'munja.crystals.6000',
    crystals: 6000,
    bonusCrystals: 1000,
    title: 'Ultimate',
    subtitle: 'Maximum value for serious customization',
    badge: 'BEST VALUE',
    featured: true,
    previewPriceLabel: '129 kr.',
  ),
];

CrystalPackage? crystalPackageByProductId(String productId) {
  final normalized = productId.trim();

  for (final package in munjaCrystalPackages) {
    if (package.productId == normalized) {
      return package;
    }
  }

  return null;
}
