import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/firestore_bike.dart';
import '../models/bike_product.dart';
import '../providers/digital_twin_provider.dart';
import '../widgets/munja_subpage_header.dart';

class BikeProductsScreen extends StatelessWidget {
  const BikeProductsScreen({
    super.key,
    required this.bike,
  });

  final FirestoreBike bike;

  String get _bikeDescription {
    final values = <String>[
      _bikeTypeLabel(bike.type),
      if (bike.brand.trim().isNotEmpty) bike.brand.trim(),
      if (bike.model.trim().isNotEmpty) bike.model.trim(),
    ];

    return values.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DigitalTwinProvider>(
      builder: (
        context,
        digitalTwinProvider,
        _,
      ) {
        final productCount =
            digitalTwinProvider.productCount;
        final connectedCount =
            digitalTwinProvider.connectedProductCount;
        final firmwareUpdateCount =
            digitalTwinProvider.firmwareUpdateCount;

        final products = digitalTwinProvider.products;

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: Column(
            children: [
              MunjaSubpageHeader(
                title: AppText.t('products'),
              ),
              Expanded(
                child: ListView(
                  physics:
                      const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    0,
                    20,
                    180,
                  ),
                  children: [
                    _BikeProductHero(
                      bike: bike,
                      description: _bikeDescription,
                      productCount: productCount,
                      connectedCount: connectedCount,
                      firmwareUpdateCount:
                          firmwareUpdateCount,
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: AppText.t('mountedProducts'),
                      subtitle: AppText.t('mountedProductsSubtitle'),
                    ),
                    const SizedBox(height: 12),
                    if (digitalTwinProvider.isLoading)
                      const _LoadingProductsCard()
                    else if (products.isEmpty)
                      _EmptyProductsCard(
                        onScan: () =>
                            _openProductPicker(
                          context,
                          digitalTwinProvider,
                        ),
                      )
                    else
                      _MountedProductsCard(
                        products: products,
                        connectedCount:
                            connectedCount,
                        firmwareUpdateCount:
                            firmwareUpdateCount,
                        onAddProduct: () =>
                            _openProductPicker(
                          context,
                          digitalTwinProvider,
                        ),
                      ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: AppText.t('productStatus'),
                      subtitle: AppText.t('productStatusSubtitle'),
                    ),
                    const SizedBox(height: 12),
                    _ProductStatusGrid(
                      productCount: productCount,
                      connectedCount: connectedCount,
                      firmwareUpdateCount:
                          firmwareUpdateCount,
                      digitalTwinEnabled:
                          bike.digitalTwinEnabled,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openProductPicker(
    BuildContext context,
    DigitalTwinProvider digitalTwinProvider,
  ) async {
    final selection =
        await showModalBottomSheet<_MunjaProductCatalogItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return _MunjaProductPickerSheet(
          mountedProducts:
              digitalTwinProvider.products,
        );
      },
    );

    if (selection == null || !context.mounted) {
      return;
    }

    switch (selection.id) {
      case 'smart_brake_light':
        _mountSmartBrakeLight(
          context,
          digitalTwinProvider,
        );
        break;
    }
  }

  void _mountSmartBrakeLight(
    BuildContext context,
    DigitalTwinProvider digitalTwinProvider,
  ) {
    final alreadyMounted = digitalTwinProvider.products.any(
      (product) =>
          product.type == BikeProductType.smartLight &&
          product.hotspotId == 'smartLight',
    );

    if (alreadyMounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(AppText.t('brakeLightAlreadyMounted')),
          ),
        );
      return;
    }

    final now = DateTime.now();

    final product = BikeProduct.smartBrakeLight(
      id: 'smart_brake_light_${bike.id}_${now.microsecondsSinceEpoch}',
      ownerId: bike.ownerId,
      bikeId: bike.id,
    );

    digitalTwinProvider.addProduct(product);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(AppText.t('brakeLightMountedTwin')),
        ),
      );
  }

}

class _BikeProductHero extends StatelessWidget {
  const _BikeProductHero({
    required this.bike,
    required this.description,
    required this.productCount,
    required this.connectedCount,
    required this.firmwareUpdateCount,
  });

  final FirestoreBike bike;
  final String description;
  final int productCount;
  final int connectedCount;
  final int firmwareUpdateCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.76,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: MunjaColors.mint.withValues(
            alpha: 0.17,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withValues(
              alpha: 0.07,
            ),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: MunjaColors.mint
                      .withValues(alpha: 0.11),
                  borderRadius:
                      BorderRadius.circular(18),
                  border: Border.all(
                    color: MunjaColors.mint
                        .withValues(alpha: 0.18),
                  ),
                ),
                child: const Icon(
                  Icons.view_in_ar_rounded,
                  color: MunjaColors.mint,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      bike.displayName,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 20,
                        fontWeight:
                            FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: 0.44),
                        fontSize: 11,
                        height: 1.35,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: productCount > 0
                    ? '$productCount ${AppText.t('mounted').toLowerCase()}'
                    : AppText.t('noProducts'),
                active: productCount > 0,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 14,
            ),
            decoration: BoxDecoration(
              color: Colors.black
                  .withValues(alpha: 0.16),
              borderRadius:
                  BorderRadius.circular(21),
              border: Border.all(
                color: Colors.white
                    .withValues(alpha: 0.055),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    label: AppText.t('products'),
                    value: '$productCount',
                    active: productCount > 0,
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _HeroMetric(
                    label: AppText.t('connected'),
                    value: '$connectedCount',
                    active: connectedCount > 0,
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _HeroMetric(
                    label: 'Firmware',
                    value: firmwareUpdateCount > 0
                        ? '$firmwareUpdateCount ${AppText.t('newLabel').toLowerCase()}'
                        : 'OK',
                    active:
                        firmwareUpdateCount == 0,
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: MunjaColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(
              alpha: 0.43,
            ),
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyProductsCard extends StatelessWidget {
  const _EmptyProductsCard({
    required this.onScan,
  });

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.62,
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: MunjaColors.mint.withValues(
            alpha: 0.12,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: MunjaColors.mint
                  .withValues(alpha: 0.10),
              borderRadius:
                  BorderRadius.circular(21),
            ),
            child: const Icon(
              Icons.add_circle_outline_rounded,
              color: MunjaColors.mint,
              size: 31,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            AppText.t('noMountedProducts'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.text,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppText.t('scanMountProductsTwin'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(
                alpha: 0.43,
              ),
              fontSize: 11,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(
                Icons.bluetooth_searching_rounded,
              ),
              label: Text(
                AppText.t('scanMountProduct'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MountedProductsCard extends StatelessWidget {
  const _MountedProductsCard({
    required this.products,
    required this.connectedCount,
    required this.firmwareUpdateCount,
    required this.onAddProduct,
  });

  final List<BikeProduct> products;
  final int connectedCount;
  final int firmwareUpdateCount;
  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.62,
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: MunjaColors.mint.withValues(
            alpha: 0.13,
          ),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0;
              index < products.length;
              index++) ...[
            _MountedProductTile(
              product: products[index],
            ),
            if (index < products.length - 1)
              const SizedBox(height: 10),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: onAddProduct,
              icon: const Icon(
                Icons.add_rounded,
              ),
              label: Text(
                AppText.t('addAnotherProduct'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MountedProductTile extends StatelessWidget {
  const _MountedProductTile({
    required this.product,
  });

  final BikeProduct product;

  @override
  Widget build(BuildContext context) {
    final connected = product.isConnected;
    final hasUpdate = product.hasFirmwareUpdate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(
          alpha: 0.14,
        ),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: connected
              ? MunjaColors.mint.withValues(
                  alpha: 0.20,
                )
              : Colors.white.withValues(
                  alpha: 0.055,
                ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(
                alpha: 0.10,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              _productIcon(product.type),
              color: MunjaColors.mint,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  product.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _productSubtitle(product),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(
                      alpha: 0.42,
                    ),
                    fontSize: 10,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              _MiniStatusPill(
                label: connected
                    ? 'CONNECTED'
                    : 'MOUNTED',
                active: connected,
              ),
              if (hasUpdate) ...[
                const SizedBox(height: 6),
                const _MiniStatusPill(
                  label: 'UPDATE',
                  active: true,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStatusPill extends StatelessWidget {
  const _MiniStatusPill({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(
                alpha: 0.10,
              )
            : Colors.white.withValues(
                alpha: 0.035,
              ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(
                  alpha: 0.20,
                )
              : Colors.white.withValues(
                  alpha: 0.07,
                ),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active
              ? MunjaColors.mint
              : Colors.white54,
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _MunjaProductPickerSheet extends StatelessWidget {
  const _MunjaProductPickerSheet({
    required this.mountedProducts,
  });

  final List<BikeProduct> mountedProducts;

  bool get _smartBrakeLightMounted {
    return mountedProducts.any(
      (product) =>
          product.type == BikeProductType.smartLight &&
          product.hotspotId == 'smartLight',
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = <_MunjaProductCatalogItem>[
      _MunjaProductCatalogItem(
        id: 'smart_brake_light',
        name: 'Munja Smart Brake Light',
        subtitle:
            AppText.t('smartBrakeLightCatalogSubtitle'),
        icon: Icons.light_mode_rounded,
        available: true,
      ),
      _MunjaProductCatalogItem(
        id: 'gps',
        name: 'Munja GPS',
        subtitle:
            AppText.t('gpsCatalogSubtitle'),
        icon: Icons.location_on_rounded,
        available: false,
      ),
      _MunjaProductCatalogItem(
        id: 'battery',
        name: 'Munja Battery',
        subtitle:
            AppText.t('batteryCatalogSubtitle'),
        icon: Icons.battery_charging_full_rounded,
        available: false,
      ),
      _MunjaProductCatalogItem(
        id: 'sensor',
        name: 'Munja Ride Sensor',
        subtitle:
            AppText.t('rideSensorCatalogSubtitle'),
        icon: Icons.sensors_rounded,
        available: false,
      ),
    ];

    return Container(
      constraints: BoxConstraints(
        maxHeight:
            MediaQuery.sizeOf(context).height * 0.82,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF07100E),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(34),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              18,
              12,
              12,
              14,
            ),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: 0.18,
                    ),
                    borderRadius:
                        BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: MunjaColors.mint
                            .withValues(alpha: 0.11),
                        borderRadius:
                            BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.extension_rounded,
                        color: MunjaColors.mint,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppText.t('mountProduct'),
                            style: TextStyle(
                              color: MunjaColors.text,
                              fontSize: 20,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            AppText.t('chooseMunjaProductForBike'),
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                      ),
                      color: Colors.white60,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: Colors.white.withValues(
              alpha: 0.06,
            ),
          ),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                28,
              ),
              itemCount: catalog.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = catalog[index];

                final mounted =
                    item.id == 'smart_brake_light' &&
                    _smartBrakeLightMounted;

                return _ProductCatalogTile(
                  item: item,
                  mounted: mounted,
                  onTap: item.available && !mounted
                      ? () => Navigator.of(context)
                          .pop(item)
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCatalogTile extends StatelessWidget {
  const _ProductCatalogTile({
    required this.item,
    required this.mounted,
    required this.onTap,
  });

  final _MunjaProductCatalogItem item;
  final bool mounted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled =
        item.available && !mounted;

    final statusText = mounted
        ? 'MOUNTED'
        : item.available
            ? 'MOUNT'
            : AppText.t('comingSoonCaps');

    final statusColor = mounted
        ? MunjaColors.mint
        : item.available
            ? MunjaColors.mint
            : Colors.white38;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: mounted
                ? MunjaColors.mint.withValues(
                    alpha: 0.08,
                  )
                : Colors.white.withValues(
                    alpha: 0.035,
                  ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: mounted
                  ? MunjaColors.mint.withValues(
                      alpha: 0.22,
                    )
                  : Colors.white.withValues(
                      alpha: 0.065,
                    ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: MunjaColors.mint
                      .withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(16),
                ),
                child: Icon(
                  item.icon,
                  color: enabled || mounted
                      ? MunjaColors.mint
                      : Colors.white38,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled || mounted
                            ? MunjaColors.text
                            : Colors.white54,
                        fontSize: 13,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: 0.40),
                        fontSize: 10,
                        height: 1.35,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                    alpha: 0.09,
                  ),
                  borderRadius:
                      BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(
                      alpha: 0.18,
                    ),
                  ),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8,
                    fontWeight:
                        FontWeight.w900,
                    letterSpacing: 0.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MunjaProductCatalogItem {
  const _MunjaProductCatalogItem({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.available,
  });

  final String id;
  final String name;
  final String subtitle;
  final IconData icon;
  final bool available;
}


class _ProductStatusGrid extends StatelessWidget {
  const _ProductStatusGrid({
    required this.productCount,
    required this.connectedCount,
    required this.firmwareUpdateCount,
    required this.digitalTwinEnabled,
  });

  final int productCount;
  final int connectedCount;
  final int firmwareUpdateCount;
  final bool digitalTwinEnabled;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics:
          const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.42,
      children: [
        _StatusCard(
          icon: Icons.view_in_ar_rounded,
          label: 'Digital Twin',
          value: digitalTwinEnabled
              ? 'Ready'
              : AppText.t('notEnabled'),
          active: digitalTwinEnabled,
        ),
        _StatusCard(
          icon: Icons.extension_rounded,
          label: 'Products',
          value: '$productCount ${AppText.t('mounted').toLowerCase()}',
          active: productCount > 0,
        ),
        _StatusCard(
          icon:
              Icons.bluetooth_connected_rounded,
          label: 'Connections',
          value: '$connectedCount ${AppText.t('connected').toLowerCase()}',
          active: connectedCount > 0,
        ),
        _StatusCard(
          icon: Icons.system_update_rounded,
          label: 'Firmware',
          value: firmwareUpdateCount > 0
              ? '$firmwareUpdateCount ${AppText.t('update').toLowerCase()}'
              : AppText.t('upToDate'),
          active: firmwareUpdateCount == 0,
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.active,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(
                alpha: 0.09,
              )
            : MunjaColors.panel.withValues(
                alpha: 0.60,
              ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(
                  alpha: 0.20,
                )
              : Colors.white.withValues(
                  alpha: 0.065,
                ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: active
                ? MunjaColors.mint
                : Colors.white54,
            size: 22,
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(
                alpha: 0.45,
              ),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active
                  ? MunjaColors.mint
                  : MunjaColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingProductsCard extends StatelessWidget {
  const _LoadingProductsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(
          alpha: 0.62,
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: 0.06,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: MunjaColors.mint,
            ),
          ),
          SizedBox(width: 12),
          Text(
            AppText.t('loadingProducts'),
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

class _StatusPill extends StatelessWidget {
  _StatusPill({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints:
          const BoxConstraints(maxWidth: 108),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(
                alpha: 0.11,
              )
            : Colors.white.withValues(
                alpha: 0.04,
              ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(
                  alpha: 0.20,
                )
              : Colors.white.withValues(
                  alpha: 0.07,
                ),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active
              ? MunjaColors.mint
              : Colors.white54,
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(
              alpha: 0.33,
            ),
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active
                ? MunjaColors.mint
                : MunjaColors.text,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withValues(
        alpha: 0.07,
      ),
    );
  }
}

IconData _productIcon(BikeProductType type) {
  switch (type) {
    case BikeProductType.smartLight:
      return Icons.light_mode_rounded;
    case BikeProductType.gps:
      return Icons.location_on_rounded;
    case BikeProductType.battery:
      return Icons.battery_charging_full_rounded;
    case BikeProductType.sensor:
      return Icons.sensors_rounded;
    case BikeProductType.display:
      return Icons.monitor_rounded;
    case BikeProductType.lock:
      return Icons.lock_rounded;
    case BikeProductType.camera:
      return Icons.videocam_rounded;
    case BikeProductType.skin:
      return Icons.palette_rounded;
    case BikeProductType.accessory:
      return Icons.extension_rounded;
    case BikeProductType.other:
      return Icons.extension_rounded;
  }
}

String _productSubtitle(BikeProduct product) {
  final values = <String>[
    if (product.manufacturer.trim().isNotEmpty)
      product.manufacturer.trim(),
    if (product.model.trim().isNotEmpty)
      product.model.trim(),
    if (product.firmwareVersion.trim().isNotEmpty)
      'FW ${product.firmwareVersion.trim()}',
  ];

  if (values.isNotEmpty) {
    return values.join(' · ');
  }

  if (product.description.trim().isNotEmpty) {
    return product.description.trim();
  }

  return AppText.t('mountedOnDigitalTwin');
}

String _bikeTypeLabel(FirestoreBikeType type) {
  switch (type) {
    case FirestoreBikeType.mtb:
      return 'MTB';
    case FirestoreBikeType.road:
      return 'Road';
    case FirestoreBikeType.gravel:
      return 'Gravel';
    case FirestoreBikeType.city:
      return 'City';
    case FirestoreBikeType.ebike:
      return 'E-bike';
    case FirestoreBikeType.kids:
      return 'Kids';
    case FirestoreBikeType.other:
      return 'Bike';
  }
}
