import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/firestore_bike.dart';
import '../models/bike_product.dart';
import '../providers/digital_twin_provider.dart';
import '../widgets/munja_subpage_header.dart';
import '../widgets/digital_twin_ble_connection_sheet.dart';

class BikeDevicesScreen extends StatelessWidget {
  const BikeDevicesScreen({super.key, required this.bike});

  final FirestoreBike bike;

  String get _bikeDescription {
    final values = <String>[
      _bikeTypeLabel(bike.type),
      if (bike.brand.trim().isNotEmpty) bike.brand.trim(),
      if (bike.model.trim().isNotEmpty) bike.model.trim(),
    ];

    return values.join(' · ');
  }

  String get _bikeFirmware {
    final value = bike.firmwareVersion.trim();
    return value.isEmpty ? '—' : value;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DigitalTwinProvider>(
      builder: (context, digitalTwinProvider, _) {
        final productCount = digitalTwinProvider.productCount;

        final connectedCount = digitalTwinProvider.connectedProductCount;

        final firmwareUpdateCount = digitalTwinProvider.firmwareUpdateCount;

        final products = digitalTwinProvider.products;

        final connectedProductIds = digitalTwinProvider.connectedProducts
            .map((product) => product.id)
            .toSet();

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: Column(
            children: [
              MunjaSubpageHeader(title: AppText.t('devices')),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 180),
                  children: [
                    _BikeDeviceHero(
                      bike: bike,
                      description: _bikeDescription,
                      connectedCount: connectedCount,
                      productCount: productCount,
                      firmwareUpdateCount: firmwareUpdateCount,
                    ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: AppText.t('connectedDevices'),
                      subtitle: AppText.t('connectedDevicesSubtitle'),
                    ),
                    const SizedBox(height: 12),
                    if (digitalTwinProvider.isLoading)
                      const _LoadingDevicesCard()
                    else if (products.isEmpty)
                      const _NoMountedProductsCard()
                    else
                      _MountedDeviceProductsCard(
                        products: products,
                        connectedProductIds: connectedProductIds,
                        onOpenProduct: (product) =>
                            _openProductConnection(context, product),
                      ),
                    const SizedBox(height: 24),
                    _SectionHeader(
                      title: AppText.t('connectionStatus'),
                      subtitle: AppText.t('connectionStatusSubtitle'),
                    ),
                    const SizedBox(height: 12),
                    _DeviceStatusGrid(
                      connectedCount: connectedCount,
                      productCount: productCount,
                      firmwareUpdateCount: firmwareUpdateCount,
                      digitalTwinEnabled: bike.digitalTwinEnabled,
                      bikeFirmware: _bikeFirmware,
                    ),
                    const SizedBox(height: 24),
                    _ConnectionInfoCard(
                      connectedCount: connectedCount,
                      productCount: productCount,
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

  Future<void> _openProductConnection(
    BuildContext context,
    BikeProduct product,
  ) async {
    await DigitalTwinBleConnectionSheet.show(context, product: product);
  }
}

class _BikeDeviceHero extends StatelessWidget {
  const _BikeDeviceHero({
    required this.bike,
    required this.description,
    required this.connectedCount,
    required this.productCount,
    required this.firmwareUpdateCount,
  });

  final FirestoreBike bike;
  final String description;
  final int connectedCount;
  final int productCount;
  final int firmwareUpdateCount;

  @override
  Widget build(BuildContext context) {
    final connected = connectedCount > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.17)),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withValues(alpha: 0.07),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  connected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_rounded,
                  color: MunjaColors.mint,
                  size: 27,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bike.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.44),
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(
                label: connected
                    ? '$connectedCount ${AppText.t('connected').toLowerCase()}'
                    : AppText.t('notConnected'),
                active: connected,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
            ),
            child: Row(
              children: [
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
                    label: AppText.t('products'),
                    value: '$productCount',
                    active: productCount > 0,
                  ),
                ),
                const _MetricDivider(),
                Expanded(
                  child: _HeroMetric(
                    label: 'Firmware',
                    value: firmwareUpdateCount > 0
                        ? '$firmwareUpdateCount ${AppText.t('newLabel').toLowerCase()}'
                        : 'OK',
                    active: firmwareUpdateCount == 0,
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
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
            color: Colors.white.withValues(alpha: 0.43),
            fontSize: 11,
            height: 1.35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NoMountedProductsCard extends StatelessWidget {
  const _NoMountedProductsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.extension_off_rounded,
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
            AppText.t('physicalDeviceConnectsProduct') +
                ' ' +
                AppText.t('mountProductFirst'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.43),
              fontSize: 11,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MountedDeviceProductsCard extends StatelessWidget {
  const _MountedDeviceProductsCard({
    required this.products,
    required this.connectedProductIds,
    required this.onOpenProduct,
  });

  final List<BikeProduct> products;
  final Set<String> connectedProductIds;
  final ValueChanged<BikeProduct> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.13)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < products.length; index++) ...[
            _DeviceProductTile(
              product: products[index],
              connected: connectedProductIds.contains(products[index].id),
              onTap: () => onOpenProduct(products[index]),
            ),
            if (index < products.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DeviceProductTile extends StatelessWidget {
  const _DeviceProductTile({
    required this.product,
    required this.connected,
    required this.onTap,
  });

  final BikeProduct product;
  final bool connected;
  final VoidCallback onTap;

  String? _metadataString(String key) {
    final value = product.metadata[key];

    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  bool get _hasBleConfiguration {
    final serviceUuid =
        _metadataString('bleServiceUuid') ?? _metadataString('serviceUuid');

    final notifyUuid =
        _metadataString('bleNotifyCharacteristicUuid') ??
        _metadataString('notifyCharacteristicUuid');

    return serviceUuid != null && notifyUuid != null;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = connected
        ? MunjaColors.mint
        : _hasBleConfiguration
        ? Colors.white54
        : Colors.amberAccent;

    final statusText = connected
        ? 'FORBUNDET'
        : _hasBleConfiguration
        ? 'FORBIND'
        : AppText.t('missingUuidCaps');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: connected
                ? MunjaColors.mint.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: connected
                  ? MunjaColors.mint.withValues(alpha: 0.24)
                  : Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  connected
                      ? Icons.bluetooth_connected_rounded
                      : Icons.bluetooth_rounded,
                  color: statusColor,
                  size: 23,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      connected
                          ? AppText.t('physicalDeviceLinked')
                          : _hasBleConfiguration
                          ? AppText.t('tapScanConnect')
                          : AppText.t('bleUuidMissing'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 10,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.20),
                  ),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.3,
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

class _DeviceStatusGrid extends StatelessWidget {
  const _DeviceStatusGrid({
    required this.connectedCount,
    required this.productCount,
    required this.firmwareUpdateCount,
    required this.digitalTwinEnabled,
    required this.bikeFirmware,
  });

  final int connectedCount;
  final int productCount;
  final int firmwareUpdateCount;
  final bool digitalTwinEnabled;
  final String bikeFirmware;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.42,
      children: [
        _StatusCard(
          icon: Icons.bluetooth_connected_rounded,
          label: 'Bluetooth',
          value: connectedCount > 0
              ? '$connectedCount ${AppText.t('connected').toLowerCase()}'
              : AppText.t('notConnected'),
          active: connectedCount > 0,
        ),
        _StatusCard(
          icon: Icons.view_in_ar_rounded,
          label: 'Digital Twin',
          value: digitalTwinEnabled ? 'Ready' : AppText.t('notEnabled'),
          active: digitalTwinEnabled,
        ),
        _StatusCard(
          icon: Icons.extension_rounded,
          label: 'Products',
          value: '$productCount ${AppText.t('mounted').toLowerCase()}',
          active: productCount > 0,
        ),
        _StatusCard(
          icon: Icons.system_update_rounded,
          label: 'Firmware',
          value: firmwareUpdateCount > 0
              ? '$firmwareUpdateCount ${AppText.t('update').toLowerCase()}'
              : bikeFirmware == '—'
              ? AppText.t('upToDate')
              : bikeFirmware,
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
            ? MunjaColors.mint.withValues(alpha: 0.09)
            : MunjaColors.panel.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.065),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: active ? MunjaColors.mint : Colors.white54,
            size: 22,
          ),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
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
              color: active ? MunjaColors.mint : MunjaColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionInfoCard extends StatelessWidget {
  const _ConnectionInfoCard({
    required this.connectedCount,
    required this.productCount,
  });

  final int connectedCount;
  final int productCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: MunjaColors.mint,
            size: 21,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              connectedCount > 0
                  ? '$connectedCount ${connectedCount == 1 ? AppText.t('deviceSingular').toLowerCase() : AppText.t('devices').toLowerCase()} ${AppText.t('isConnected').toLowerCase()}. ${AppText.t('munjaKeepsStatusTogether')}'
                  : productCount > 0
                  ? AppText.t('mountedNoActiveConnections')
                  : AppText.t('connectedDeviceAppearsHere'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 10,
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

class _LoadingDevicesCard extends StatelessWidget {
  const _LoadingDevicesCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
            AppText.t('loadingDevices'),
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
  const _StatusPill({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(alpha: 0.11)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? MunjaColors.mint : Colors.white54,
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
            color: Colors.white.withValues(alpha: 0.33),
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
            color: active ? MunjaColors.mint : MunjaColors.text,
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
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}

String _bikeTypeLabel(FirestoreBikeType type) {
  final value = type.name.trim();

  if (value.isEmpty) {
    return 'Bike';
  }

  if (value.toLowerCase() == 'mtb') {
    return 'MTB';
  }

  if (value.toLowerCase() == 'ebike') {
    return 'E-bike';
  }

  return value[0].toUpperCase() + value.substring(1).toLowerCase();
}
