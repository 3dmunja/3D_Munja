import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:provider/provider.dart';

import '../core/theme/munja_colors.dart';
import '../models/bike_hotspot.dart';
import '../models/bike_product.dart';
import '../providers/digital_twin_provider.dart';
import '../screens/product_settings/smart_brake_light_settings.dart';
import 'digital_twin_ble_connection_sheet.dart';

/// Displays a Munja bicycle Digital Twin from a remote GLB/GLTF URL.
///
/// The viewer is connected directly to [DigitalTwinProvider] and supports:
/// - Remote Firebase Storage GLB/GLTF URLs
/// - Rotation, zoom and camera controls
/// - Interactive Digital Twin hotspots
/// - Selected hotspot and product inspector
/// - Product connection, battery, signal and firmware status
/// - Loading, empty and error states
/// - Fullscreen presentation
class DigitalTwinViewer extends StatefulWidget {
  const DigitalTwinViewer({
    super.key,
    required this.modelUrl,
    this.title = 'Digital Twin',
    this.subtitle,
    this.height = 360,
    this.borderRadius = 30,
    this.autoRotate = false,
    this.cameraControls = true,
    this.showHeader = true,
    this.showStatusBadge = true,
    this.showFullscreenButton = true,
    this.showHotspots = true,
    this.showInspector = true,
    this.backgroundColor = const Color(0xFF080B0A),
    this.placeholder,
    this.onFullscreen,
  });

  final String modelUrl;
  final String title;
  final String? subtitle;
  final double height;
  final double borderRadius;
  final bool autoRotate;
  final bool cameraControls;
  final bool showHeader;
  final bool showStatusBadge;
  final bool showFullscreenButton;
  final bool showHotspots;
  final bool showInspector;
  final Color backgroundColor;
  final Widget? placeholder;
  final VoidCallback? onFullscreen;

  @override
  State<DigitalTwinViewer> createState() => _DigitalTwinViewerState();
}

class _DigitalTwinViewerState extends State<DigitalTwinViewer> {
  Key _viewerKey = UniqueKey();
  bool _loading = true;
  bool _hasError = false;

  String get _normalizedModelUrl => widget.modelUrl.trim();

  bool get _hasModelUrl {
    final url = _normalizedModelUrl;

    if (url.isEmpty) {
      return false;
    }

    final uri = Uri.tryParse(url);

    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'https' || uri.scheme == 'http');
  }

  @override
  void didUpdateWidget(covariant DigitalTwinViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.modelUrl.trim() != widget.modelUrl.trim()) {
      _resetViewer();
    }
  }

  void _resetViewer() {
    if (!mounted) {
      return;
    }

    setState(() {
      _viewerKey = UniqueKey();
      _loading = true;
      _hasError = false;
    });
  }

  void _handleModelLoaded() {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = false;
      _hasError = false;
    });
  }

  Future<void> _openFullscreen() async {
    if (widget.onFullscreen != null) {
      widget.onFullscreen!();
      return;
    }

    final provider = context.read<DigitalTwinProvider>();

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider<DigitalTwinProvider>.value(
          value: provider,
          child: _DigitalTwinFullscreenPage(
            modelUrl: _normalizedModelUrl,
            title: widget.title,
            autoRotate: widget.autoRotate,
            cameraControls: widget.cameraControls,
            backgroundColor: widget.backgroundColor,
            showHotspots: widget.showHotspots,
            showInspector: widget.showInspector,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DigitalTwinProvider>(
      builder: (context, digitalTwinProvider, _) {
        final selectedHotspot = digitalTwinProvider.selectedHotspot;
        final selectedProduct = digitalTwinProvider.selectedProduct;

        return Container(
          decoration: BoxDecoration(
            color: MunjaColors.panel.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(
              color: _hasModelUrl
                  ? MunjaColors.mint.withValues(alpha: 0.20)
                  : Colors.white.withValues(alpha: 0.07),
            ),
            boxShadow: [
              if (_hasModelUrl)
                BoxShadow(
                  color: MunjaColors.mint.withValues(alpha: 0.07),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.showHeader)
                _ViewerHeader(
                  title: widget.title,
                  subtitle: widget.subtitle,
                  hasModel: _hasModelUrl && !_hasError,
                  showStatusBadge: widget.showStatusBadge,
                  showFullscreenButton:
                      widget.showFullscreenButton && _hasModelUrl && !_hasError,
                  onFullscreen: _openFullscreen,
                ),
              SizedBox(
                height: widget.height,
                width: double.infinity,
                child: _buildViewerContent(digitalTwinProvider),
              ),
              if (_hasModelUrl && !_hasError) const _ViewerControlsHint(),
              if (widget.showHotspots &&
                  digitalTwinProvider.enabledHotspots.isNotEmpty)
                _HotspotStrip(
                  hotspots: digitalTwinProvider.enabledHotspots,
                  selectedHotspotId: digitalTwinProvider.selectedHotspotId,
                  productForHotspot: digitalTwinProvider.productsForHotspot,
                  onSelected: (hotspot) {
                    final alreadySelected =
                        digitalTwinProvider.selectedHotspotId == hotspot.id;

                    if (alreadySelected) {
                      digitalTwinProvider.clearSelection();
                    } else {
                      digitalTwinProvider.selectHotspot(hotspot.id);
                    }
                  },
                ),
              if (widget.showInspector && selectedHotspot != null)
                _HotspotInspector(
                  hotspot: selectedHotspot,
                  product: selectedProduct,
                  products: digitalTwinProvider.productsForHotspot(
                    selectedHotspot.id,
                  ),
                  onClose: digitalTwinProvider.clearSelection,
                  onProductSelected: (product) {
                    digitalTwinProvider.selectProduct(product.id);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewerContent(DigitalTwinProvider provider) {
    if (!_hasModelUrl) {
      return widget.placeholder ?? const _EmptyDigitalTwin();
    }

    if (_hasError) {
      return _DigitalTwinError(onRetry: _resetViewer);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          color: widget.backgroundColor,
          child: ModelViewer(
            key: _viewerKey,
            src: _normalizedModelUrl,
            alt: '${widget.title} 3D model',
            ar: false,
            autoRotate: widget.autoRotate,
            cameraControls: widget.cameraControls,
            disableZoom: false,
            loading: Loading.eager,
            interactionPrompt: InteractionPrompt.none,
            backgroundColor: widget.backgroundColor,
            onWebViewCreated: (_) {},
          ),
        ),
        if (widget.showHotspots &&
            !_loading &&
            provider.enabledHotspots.isNotEmpty)
          _HotspotOverlay(
            hotspots: provider.enabledHotspots,
            selectedHotspotId: provider.selectedHotspotId,
            productForHotspot: provider.productsForHotspot,
            onSelected: (hotspot) {
              final alreadySelected = provider.selectedHotspotId == hotspot.id;

              if (alreadySelected) {
                provider.clearSelection();
              } else {
                provider.selectHotspot(hotspot.id);
              }
            },
          ),
        if (_loading)
          _LoadingOverlay(
            backgroundColor: widget.backgroundColor,
            onLoadedFallback: _handleModelLoaded,
          ),
      ],
    );
  }
}

class _HotspotOverlay extends StatelessWidget {
  const _HotspotOverlay({
    required this.hotspots,
    required this.selectedHotspotId,
    required this.productForHotspot,
    required this.onSelected,
  });

  final List<BikeHotspot> hotspots;
  final String? selectedHotspotId;
  final List<BikeProduct> Function(String hotspotId) productForHotspot;
  final ValueChanged<BikeHotspot> onSelected;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              for (final hotspot in hotspots)
                _buildMarker(
                  hotspot: hotspot,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMarker({
    required BikeHotspot hotspot,
    required double width,
    required double height,
  }) {
    final products = productForHotspot(hotspot.id);
    final connected = products.any((product) => product.isConnected);
    final selected = selectedHotspotId == hotspot.id;

    final alignment = _hotspotAlignment(hotspot);
    const markerSize = 42.0;

    final left = ((alignment.x + 1) / 2 * (width - markerSize)).clamp(
      4.0,
      width - markerSize - 4,
    );
    final top = ((alignment.y + 1) / 2 * (height - markerSize)).clamp(
      4.0,
      height - markerSize - 4,
    );

    return Positioned(
      left: left,
      top: top,
      child: _HotspotMarker(
        hotspot: hotspot,
        selected: selected,
        connected: connected,
        hasProduct: products.isNotEmpty,
        onTap: () => onSelected(hotspot),
      ),
    );
  }
}

class _HotspotMarker extends StatelessWidget {
  const _HotspotMarker({
    required this.hotspot,
    required this.selected,
    required this.connected,
    required this.hasProduct,
    required this.onTap,
  });

  final BikeHotspot hotspot;
  final bool selected;
  final bool connected;
  final bool hasProduct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = connected || selected;
    final color = active ? MunjaColors.mint : Colors.white70;

    return Semantics(
      button: true,
      label: hotspot.name,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: selected ? 46 : 40,
            height: selected ? 46 : 40,
            decoration: BoxDecoration(
              color: selected
                  ? MunjaColors.mint.withValues(alpha: 0.22)
                  : Colors.black.withValues(alpha: 0.72),
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? MunjaColors.mint
                    : active
                    ? MunjaColors.mint.withValues(alpha: 0.65)
                    : Colors.white.withValues(alpha: 0.30),
                width: selected ? 2 : 1,
              ),
              boxShadow: [
                if (active)
                  BoxShadow(
                    color: MunjaColors.mint.withValues(alpha: 0.28),
                    blurRadius: selected ? 22 : 14,
                  ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(_hotspotIcon(hotspot.type), color: color, size: 19),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: connected
                          ? MunjaColors.mint
                          : hasProduct
                          ? Colors.amberAccent
                          : Colors.white38,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.75),
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HotspotStrip extends StatelessWidget {
  const _HotspotStrip({
    required this.hotspots,
    required this.selectedHotspotId,
    required this.productForHotspot,
    required this.onSelected,
  });

  final List<BikeHotspot> hotspots;
  final String? selectedHotspotId;
  final List<BikeProduct> Function(String hotspotId) productForHotspot;
  final ValueChanged<BikeHotspot> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 15),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.14),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VÆLG EN DEL',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hotspots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final hotspot = hotspots[index];
                final products = productForHotspot(hotspot.id);
                final connected = products.any(
                  (product) => product.isConnected,
                );
                final selected = selectedHotspotId == hotspot.id;

                return _HotspotChip(
                  hotspot: hotspot,
                  selected: selected,
                  connected: connected,
                  hasProduct: products.isNotEmpty,
                  onTap: () => onSelected(hotspot),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HotspotChip extends StatelessWidget {
  const _HotspotChip({
    required this.hotspot,
    required this.selected,
    required this.connected,
    required this.hasProduct,
    required this.onTap,
  });

  final BikeHotspot hotspot;
  final bool selected;
  final bool connected;
  final bool hasProduct;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? MunjaColors.mint : Colors.white70;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? MunjaColors.mint.withValues(alpha: 0.42)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_hotspotIcon(hotspot.type), color: foreground, size: 16),
              const SizedBox(width: 7),
              Text(
                _hotspotLabel(hotspot),
                style: TextStyle(
                  color: foreground,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: connected
                      ? MunjaColors.mint
                      : hasProduct
                      ? Colors.amberAccent
                      : Colors.white24,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotspotInspector extends StatelessWidget {
  const _HotspotInspector({
    required this.hotspot,
    required this.product,
    required this.products,
    required this.onClose,
    required this.onProductSelected,
  });

  final BikeHotspot hotspot;
  final BikeProduct? product;
  final List<BikeProduct> products;
  final VoidCallback onClose;
  final ValueChanged<BikeProduct> onProductSelected;

  @override
  Widget build(BuildContext context) {
    final activeProduct =
        product ?? (products.isNotEmpty ? products.first : null);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.96),
        border: Border(
          top: BorderSide(color: MunjaColors.mint.withValues(alpha: 0.16)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(
                  _hotspotIcon(hotspot.type),
                  color: MunjaColors.mint,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hotspot.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hotspot.description.trim().isEmpty
                          ? _hotspotDescription(hotspot.type)
                          : hotspot.description.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.46),
                        fontSize: 11,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Luk',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                color: Colors.white60,
              ),
            ],
          ),
          if (products.length > 1) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = products[index];
                  final selected = activeProduct?.id == item.id;

                  return ChoiceChip(
                    selected: selected,
                    onSelected: (_) => onProductSelected(item),
                    label: Text(item.displayName),
                    selectedColor: MunjaColors.mint.withValues(alpha: 0.16),
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    side: BorderSide(
                      color: selected
                          ? MunjaColors.mint.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                    labelStyle: TextStyle(
                      color: selected ? MunjaColors.mint : Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                    showCheckmark: false,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (activeProduct == null)
            _NoProductPanel(hotspot: hotspot)
          else
            _ProductStatusPanel(product: activeProduct),
        ],
      ),
    );
  }
}

class _NoProductPanel extends StatelessWidget {
  const _NoProductPanel({required this.hotspot});

  final BikeHotspot hotspot;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.add_circle_outline_rounded,
            color: Colors.white.withValues(alpha: 0.42),
            size: 23,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Der er endnu ikke knyttet et smart produkt til ${hotspot.name}.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.52),
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductStatusPanel extends StatelessWidget {
  const _ProductStatusPanel({required this.product});

  final BikeProduct product;

  Future<void> _openBluetoothPanel(BuildContext context) async {
    await DigitalTwinBleConnectionSheet.show(context, product: product);
  }

  Future<void> _openSmartBrakeLightSettings(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SmartBrakeLightSettings(productId: product.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final battery = product.safeBatteryLevel;
    final firmware = product.firmwareVersion.trim().isEmpty
        ? '—'
        : product.firmwareVersion.trim();
    final signal = product.rssi == null ? '—' : '${product.rssi} dBm';

    final isConnected = product.isConnected;
    final isConnecting =
        product.connectionStatus == BikeProductConnectionStatus.connecting;
    final isSmartBrakeLight = _isSmartBrakeLightProduct(product);

    final metadata = product.metadata;
    final temperature = _readDouble(metadata, const <String>[
      'temperatureCelsius',
      'temperature',
      'temp',
      'tempC',
    ]);
    final brakePressed = _readBool(metadata, const <String>[
      'brakePressed',
      'brake',
      'braking',
    ]);
    final ledEnabled = _readBool(metadata, const <String>[
      'ledEnabled',
      'led',
      'lightOn',
    ]);
    final charging = _readBool(metadata, const <String>[
      'charging',
      'isCharging',
    ]);
    final brightness = _readInt(metadata, const <String>[
      'brightness',
      'ledBrightness',
      'pwm',
    ]);
    final sensitivity = _readInt(metadata, const <String>[
      'sensitivity',
      'brakeSensitivity',
    ]);
    final flashPattern = _readString(metadata, const <String>[
      'flashPattern',
      'pattern',
      'lightMode',
    ]);
    final lastBleMessage = _readString(metadata, const <String>[
      'lastBleMessage',
    ]);
    final lastBleMessageAt = _readDateTime(metadata, const <String>[
      'lastBleMessageAt',
    ]);
    final reportedStatus = _readString(metadata, const <String>[
      'bleReportedStatus',
      'status',
    ]);
    final errorCode = _readString(metadata, const <String>[
      'bleErrorCode',
      'errorCode',
      'bleConnectionError',
      'bleNotificationError',
      'lastBleParseError',
    ]);

    final hasLiveData =
        temperature != null ||
        brakePressed != null ||
        ledEnabled != null ||
        charging != null ||
        brightness != null ||
        sensitivity != null ||
        flashPattern != null ||
        lastBleMessage != null ||
        reportedStatus != null ||
        errorCode != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                product.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MunjaColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            _ConnectionBadge(product: product),
          ],
        ),
        if (product.description.trim().isNotEmpty) ...[
          const SizedBox(height: 7),
          Text(
            product.description.trim(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.46),
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _ProductMetric(
                icon: Icons.battery_5_bar_rounded,
                label: 'Batteri',
                value: battery == null ? '—' : '$battery%',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ProductMetric(
                icon: Icons.memory_rounded,
                label: 'Firmware',
                value: firmware,
                warning: product.hasFirmwareUpdate,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ProductMetric(
                icon: Icons.network_cell_rounded,
                label: 'Signal',
                value: signal,
              ),
            ),
          ],
        ),
        if (hasLiveData) ...[
          const SizedBox(height: 15),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'LIVE PRODUKTDATA',
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
              _LiveIndicator(
                connected: isConnected,
                lastMessageAt: lastBleMessageAt,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LiveDataGrid(
            temperature: temperature,
            brakePressed: brakePressed,
            ledEnabled: ledEnabled,
            charging: charging,
            brightness: brightness,
            sensitivity: sensitivity,
            flashPattern: flashPattern,
          ),
          if (reportedStatus != null || errorCode != null) ...[
            const SizedBox(height: 10),
            _ProductMessageBanner(
              isError: errorCode != null,
              title: errorCode != null ? 'Produktfejl' : 'Produktstatus',
              message: errorCode ?? reportedStatus!,
            ),
          ],
          if (lastBleMessage != null) ...[
            const SizedBox(height: 10),
            _LastBleMessage(
              message: lastBleMessage,
              receivedAt: lastBleMessageAt,
            ),
          ],
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: isConnecting ? null : () => _openBluetoothPanel(context),
            icon: Icon(
              isConnecting
                  ? Icons.bluetooth_searching_rounded
                  : isConnected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_rounded,
            ),
            label: Text(
              isConnecting
                  ? 'FORBINDER...'
                  : isConnected
                  ? 'ADMINISTRER FORBINDELSE'
                  : 'FORBIND PRODUKT',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.4,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: isConnected
                  ? MunjaColors.mint.withValues(alpha: 0.14)
                  : MunjaColors.mint,
              foregroundColor: isConnected
                  ? MunjaColors.mint
                  : const Color(0xFF03110D),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.06),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.38),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(17),
                side: BorderSide(
                  color: isConnected
                      ? MunjaColors.mint.withValues(alpha: 0.28)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ),
        if (isSmartBrakeLight) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () => _openSmartBrakeLightSettings(context),
              icon: const Icon(Icons.tune_rounded),
              label: const Text(
                'ÅBN INDSTILLINGER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: MunjaColors.mint,
                backgroundColor: MunjaColors.mint.withValues(alpha: 0.06),
                side: BorderSide(
                  color: MunjaColors.mint.withValues(alpha: 0.24),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
            ),
          ),
        ],
        if (product.hasFirmwareUpdate) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.amberAccent.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.system_update_rounded,
                  color: Colors.amberAccent,
                  size: 18,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Firmware ${product.latestFirmwareVersion} er klar.',
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveIndicator extends StatelessWidget {
  const _LiveIndicator({required this.connected, required this.lastMessageAt});

  final bool connected;
  final DateTime? lastMessageAt;

  @override
  Widget build(BuildContext context) {
    final fresh =
        lastMessageAt != null &&
        DateTime.now().difference(lastMessageAt!).inSeconds <= 30;
    final active = connected && fresh;
    final color = active ? MunjaColors.mint : Colors.white38;

    return Container(
      height: 25,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                if (active)
                  BoxShadow(
                    color: MunjaColors.mint.withValues(alpha: 0.55),
                    blurRadius: 8,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            active
                ? 'LIVE'
                : connected
                ? 'FORBUNDET'
                : 'OFFLINE',
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDataGrid extends StatelessWidget {
  const _LiveDataGrid({
    required this.temperature,
    required this.brakePressed,
    required this.ledEnabled,
    required this.charging,
    required this.brightness,
    required this.sensitivity,
    required this.flashPattern,
  });

  final double? temperature;
  final bool? brakePressed;
  final bool? ledEnabled;
  final bool? charging;
  final int? brightness;
  final int? sensitivity;
  final String? flashPattern;

  @override
  Widget build(BuildContext context) {
    final items = <_LiveMetricData>[
      if (temperature != null)
        _LiveMetricData(
          icon: Icons.thermostat_rounded,
          label: 'Temperatur',
          value: '${_formatNumber(temperature!)} °C',
        ),
      if (brakePressed != null)
        _LiveMetricData(
          icon: Icons.back_hand_rounded,
          label: 'Bremse',
          value: brakePressed! ? 'Aktiv' : 'Ikke aktiv',
          active: brakePressed!,
        ),
      if (ledEnabled != null)
        _LiveMetricData(
          icon: Icons.light_mode_rounded,
          label: 'LED',
          value: ledEnabled! ? 'Tændt' : 'Slukket',
          active: ledEnabled!,
        ),
      if (charging != null)
        _LiveMetricData(
          icon: Icons.battery_charging_full_rounded,
          label: 'Opladning',
          value: charging! ? 'Oplader' : 'Nej',
          active: charging!,
        ),
      if (brightness != null)
        _LiveMetricData(
          icon: Icons.brightness_6_rounded,
          label: 'Lysstyrke',
          value: '${brightness!.clamp(0, 100)}%',
        ),
      if (sensitivity != null)
        _LiveMetricData(
          icon: Icons.tune_rounded,
          label: 'Følsomhed',
          value: '${sensitivity!.clamp(0, 100)}%',
        ),
      if (flashPattern != null)
        _LiveMetricData(
          icon: Icons.flash_on_rounded,
          label: 'Lysmønster',
          value: flashPattern!,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 8) / 2;

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _LiveMetric(data: item),
              ),
          ],
        );
      },
    );
  }
}

class _LiveMetricData {
  const _LiveMetricData({
    required this.icon,
    required this.label,
    required this.value,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool active;
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({required this.data});

  final _LiveMetricData data;

  @override
  Widget build(BuildContext context) {
    final accent = data.active ? MunjaColors.mint : Colors.white60;

    return Container(
      constraints: const BoxConstraints(minHeight: 61),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: data.active
            ? MunjaColors.mint.withValues(alpha: 0.07)
            : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: data.active
              ? MunjaColors.mint.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(data.icon, color: accent, size: 17),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  data.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: data.active ? MunjaColors.mint : MunjaColors.text,
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

class _ProductMessageBanner extends StatelessWidget {
  const _ProductMessageBanner({
    required this.isError,
    required this.title,
    required this.message,
  });

  final bool isError;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final color = isError ? Colors.redAccent : Colors.amberAccent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 10,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
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

class _LastBleMessage extends StatelessWidget {
  const _LastBleMessage({required this.message, required this.receivedAt});

  final String message;
  final DateTime? receivedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.data_object_rounded,
                color: MunjaColors.mint.withValues(alpha: 0.78),
                size: 16,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'SENESTE BLE-BESKED',
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (receivedAt != null)
                Text(
                  _formatTime(receivedAt!),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.32),
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            message,
            maxLines: 3,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 10,
              height: 1.4,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

String _formatNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }

  return value.toStringAsFixed(1);
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');

  return '$hour:$minute:$second';
}

dynamic _readMetadataValue(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    if (metadata.containsKey(key)) {
      final value = metadata[key];

      if (value != null) {
        return value;
      }
    }
  }

  final nested = metadata['lastBleData'];

  if (nested is Map) {
    for (final key in keys) {
      if (nested.containsKey(key)) {
        final value = nested[key];

        if (value != null) {
          return value;
        }
      }
    }
  }

  return null;
}

String? _readString(Map<String, dynamic> metadata, List<String> keys) {
  final value = _readMetadataValue(metadata, keys);

  if (value == null) {
    return null;
  }

  final normalized = value.toString().trim();

  return normalized.isEmpty ? null : normalized;
}

int? _readInt(Map<String, dynamic> metadata, List<String> keys) {
  final value = _readMetadataValue(metadata, keys);

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.round();
  }

  return int.tryParse(value?.toString().trim() ?? '');
}

double? _readDouble(Map<String, dynamic> metadata, List<String> keys) {
  final value = _readMetadataValue(metadata, keys);

  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse((value?.toString() ?? '').trim().replaceAll(',', '.'));
}

bool? _readBool(Map<String, dynamic> metadata, List<String> keys) {
  final value = _readMetadataValue(metadata, keys);

  if (value is bool) {
    return value;
  }

  if (value is num) {
    return value != 0;
  }

  final normalized = value?.toString().trim().toLowerCase();

  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  if (<String>{
    '1',
    'true',
    'on',
    'yes',
    'active',
    'enabled',
  }.contains(normalized)) {
    return true;
  }

  if (<String>{
    '0',
    'false',
    'off',
    'no',
    'inactive',
    'disabled',
  }.contains(normalized)) {
    return false;
  }

  return null;
}

DateTime? _readDateTime(Map<String, dynamic> metadata, List<String> keys) {
  final value = _readMetadataValue(metadata, keys);

  if (value is DateTime) {
    return value;
  }

  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  if (value is String) {
    return DateTime.tryParse(value.trim());
  }

  return null;
}

bool _isSmartBrakeLightProduct(BikeProduct product) {
  final searchableValues = <String>[
    product.displayName,
    product.model,
    product.description,
    product.metadata['productType']?.toString() ?? '',
    product.metadata['type']?.toString() ?? '',
    product.metadata['category']?.toString() ?? '',
  ];

  final normalized = searchableValues
      .join(' ')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9æøå]+'), ' ');

  return normalized.contains('smart brake light') ||
      normalized.contains('brake light') ||
      normalized.contains('smart light') ||
      normalized.contains('smart baglygte') ||
      normalized.contains('baglygte');
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.product});

  final BikeProduct product;

  @override
  Widget build(BuildContext context) {
    final status = product.connectionStatus;

    final (label, color, icon) = switch (status) {
      BikeProductConnectionStatus.connected => (
        'FORBUNDET',
        MunjaColors.mint,
        Icons.bluetooth_connected_rounded,
      ),
      BikeProductConnectionStatus.connecting => (
        'FORBINDER',
        Colors.amberAccent,
        Icons.bluetooth_searching_rounded,
      ),
      BikeProductConnectionStatus.error => (
        'FEJL',
        Colors.redAccent,
        Icons.bluetooth_disabled_rounded,
      ),
      BikeProductConnectionStatus.disconnected => (
        'OFFLINE',
        Colors.white54,
        Icons.bluetooth_disabled_rounded,
      ),
    };

    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductMetric extends StatelessWidget {
  const _ProductMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.warning = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final accent = warning ? Colors.amberAccent : MunjaColors.mint;

    return Container(
      height: 72,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: warning
              ? Colors.amberAccent.withValues(alpha: 0.20)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 17),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 8,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: warning ? Colors.amberAccent : MunjaColors.text,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerHeader extends StatelessWidget {
  const _ViewerHeader({
    required this.title,
    required this.subtitle,
    required this.hasModel,
    required this.showStatusBadge,
    required this.showFullscreenButton,
    required this.onFullscreen,
  });

  final String title;
  final String? subtitle;
  final bool hasModel;
  final bool showStatusBadge;
  final bool showFullscreenButton;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 17, 12, 15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: MunjaColors.mint.withValues(alpha: 0.18),
              ),
            ),
            child: const Icon(
              Icons.view_in_ar_rounded,
              color: MunjaColors.mint,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showStatusBadge) _DigitalTwinStatusBadge(active: hasModel),
          if (showFullscreenButton) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Vis i fuld skærm',
              onPressed: onFullscreen,
              icon: const Icon(Icons.fullscreen_rounded),
              color: Colors.white70,
            ),
          ],
        ],
      ),
    );
  }
}

class _DigitalTwinStatusBadge extends StatelessWidget {
  const _DigitalTwinStatusBadge({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(alpha: 0.25)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: active
                  ? MunjaColors.mint
                  : Colors.white.withValues(alpha: 0.32),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'AKTIV' : 'INGEN MODEL',
            style: TextStyle(
              color: active
                  ? MunjaColors.mint
                  : Colors.white.withValues(alpha: 0.42),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.7,
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerControlsHint extends StatelessWidget {
  const _ViewerControlsHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.swipe_rounded,
            color: Colors.white.withValues(alpha: 0.38),
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            'Træk for at rotere · Knib for at zoome',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.38),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDigitalTwin extends StatelessWidget {
  const _EmptyDigitalTwin();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.16),
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.09),
              shape: BoxShape.circle,
              border: Border.all(
                color: MunjaColors.mint.withValues(alpha: 0.16),
              ),
            ),
            child: Icon(
              Icons.view_in_ar_rounded,
              color: MunjaColors.mint.withValues(alpha: 0.72),
              size: 43,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Ingen Digital Twin endnu',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Upload en GLB- eller GLTF-model i din garage for at se cyklen her.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.46),
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _DigitalTwinError extends StatelessWidget {
  const _DigitalTwinError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.18),
      padding: const EdgeInsets.all(26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 45,
          ),
          const SizedBox(height: 14),
          const Text(
            '3D-modellen kunne ikke indlæses',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Kontrollér internetforbindelsen og modellens Firebase URL.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.46),
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'Prøv igen',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/// model_viewer_plus does not expose a consistent Dart load callback on every
/// supported platform, so this overlay removes itself after initialization.
class _LoadingOverlay extends StatefulWidget {
  const _LoadingOverlay({
    required this.backgroundColor,
    required this.onLoadedFallback,
  });

  final Color backgroundColor;
  final VoidCallback onLoadedFallback;

  @override
  State<_LoadingOverlay> createState() => _LoadingOverlayState();
}

class _LoadingOverlayState extends State<_LoadingOverlay> {
  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  Future<void> _startTimer() async {
    await Future<void>.delayed(const Duration(milliseconds: 1800));

    if (!mounted) {
      return;
    }

    widget.onLoadedFallback();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: widget.backgroundColor.withValues(alpha: 0.94),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: MunjaColors.mint,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Indlæser Digital Twin...',
              style: TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DigitalTwinFullscreenPage extends StatelessWidget {
  const _DigitalTwinFullscreenPage({
    required this.modelUrl,
    required this.title,
    required this.autoRotate,
    required this.cameraControls,
    required this.backgroundColor,
    required this.showHotspots,
    required this.showInspector,
  });

  final String modelUrl;
  final String title;
  final bool autoRotate;
  final bool cameraControls;
  final Color backgroundColor;
  final bool showHotspots;
  final bool showInspector;

  @override
  Widget build(BuildContext context) {
    return Consumer<DigitalTwinProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ModelViewer(
                          src: modelUrl,
                          alt: '$title fullscreen 3D model',
                          ar: false,
                          autoRotate: autoRotate,
                          cameraControls: cameraControls,
                          disableZoom: false,
                          loading: Loading.eager,
                          interactionPrompt: InteractionPrompt.none,
                          backgroundColor: backgroundColor,
                        ),
                      ),
                      if (showHotspots && provider.enabledHotspots.isNotEmpty)
                        Positioned.fill(
                          child: _HotspotOverlay(
                            hotspots: provider.enabledHotspots,
                            selectedHotspotId: provider.selectedHotspotId,
                            productForHotspot: provider.productsForHotspot,
                            onSelected: (hotspot) {
                              if (provider.selectedHotspotId == hotspot.id) {
                                provider.clearSelection();
                              } else {
                                provider.selectHotspot(hotspot.id);
                              }
                            },
                          ),
                        ),
                      Positioned(
                        top: 14,
                        left: 14,
                        child: Material(
                          color: MunjaColors.panel.withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(18),
                          child: IconButton(
                            tooltip: 'Luk',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded),
                            color: MunjaColors.text,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 14,
                        right: 14,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 220),
                          height: 42,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: MunjaColors.panel.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: MunjaColors.mint.withValues(alpha: 0.16),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MunjaColors.text,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 20,
                        right: 20,
                        bottom: 22,
                        child: _FullscreenHint(),
                      ),
                    ],
                  ),
                ),
                if (showInspector && provider.selectedHotspot != null)
                  _HotspotInspector(
                    hotspot: provider.selectedHotspot!,
                    product: provider.selectedProduct,
                    products: provider.productsForHotspot(
                      provider.selectedHotspot!.id,
                    ),
                    onClose: provider.clearSelection,
                    onProductSelected: (product) {
                      provider.selectProduct(product.id);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FullscreenHint extends StatelessWidget {
  const _FullscreenHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: MunjaColors.panel.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swipe_rounded, color: MunjaColors.mint, size: 17),
            const SizedBox(width: 8),
            Text(
              'Rotér, zoom og vælg hotspots',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.72),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Alignment _hotspotAlignment(BikeHotspot hotspot) {
  switch (hotspot.type) {
    case BikeHotspotType.frame:
      return const Alignment(0.00, 0.05);
    case BikeHotspotType.fork:
      return const Alignment(0.48, 0.08);
    case BikeHotspotType.handlebar:
      return const Alignment(0.60, -0.48);
    case BikeHotspotType.saddle:
      return const Alignment(-0.30, -0.43);
    case BikeHotspotType.frontWheel:
      return const Alignment(0.66, 0.48);
    case BikeHotspotType.rearWheel:
      return const Alignment(-0.68, 0.48);
    case BikeHotspotType.drivetrain:
      return const Alignment(-0.08, 0.36);
    case BikeHotspotType.battery:
      return const Alignment(0.02, 0.18);
    case BikeHotspotType.gps:
      return const Alignment(0.48, -0.38);
    case BikeHotspotType.smartLight:
      return const Alignment(-0.70, -0.18);
    case BikeHotspotType.motor:
      return const Alignment(-0.02, 0.38);
    case BikeHotspotType.display:
      return const Alignment(0.48, -0.48);
    case BikeHotspotType.other:
      final x = hotspot.position.isNotEmpty
          ? hotspot.position.first.clamp(-1.0, 1.0)
          : 0.0;
      final y = hotspot.position.length > 1
          ? (-hotspot.position[1]).clamp(-1.0, 1.0)
          : 0.0;
      return Alignment(x, y);
  }
}

IconData _hotspotIcon(BikeHotspotType type) {
  switch (type) {
    case BikeHotspotType.frame:
      return Icons.directions_bike_rounded;
    case BikeHotspotType.fork:
      return Icons.call_split_rounded;
    case BikeHotspotType.handlebar:
      return Icons.sports_motorsports_rounded;
    case BikeHotspotType.saddle:
      return Icons.airline_seat_recline_normal_rounded;
    case BikeHotspotType.frontWheel:
    case BikeHotspotType.rearWheel:
      return Icons.circle_outlined;
    case BikeHotspotType.drivetrain:
      return Icons.settings_rounded;
    case BikeHotspotType.battery:
      return Icons.battery_charging_full_rounded;
    case BikeHotspotType.gps:
      return Icons.gps_fixed_rounded;
    case BikeHotspotType.smartLight:
      return Icons.light_mode_rounded;
    case BikeHotspotType.motor:
      return Icons.electric_bike_rounded;
    case BikeHotspotType.display:
      return Icons.monitor_rounded;
    case BikeHotspotType.other:
      return Icons.add_circle_outline_rounded;
  }
}

String _hotspotLabel(BikeHotspot hotspot) {
  final name = hotspot.name.trim();

  if (name.isNotEmpty) {
    return name;
  }

  switch (hotspot.type) {
    case BikeHotspotType.frame:
      return 'Stel';
    case BikeHotspotType.fork:
      return 'Forgaffel';
    case BikeHotspotType.handlebar:
      return 'Styr';
    case BikeHotspotType.saddle:
      return 'Sadel';
    case BikeHotspotType.frontWheel:
      return 'Forhjul';
    case BikeHotspotType.rearWheel:
      return 'Baghjul';
    case BikeHotspotType.drivetrain:
      return 'Drivlinje';
    case BikeHotspotType.battery:
      return 'Batteri';
    case BikeHotspotType.gps:
      return 'GPS';
    case BikeHotspotType.smartLight:
      return 'Smart baglygte';
    case BikeHotspotType.motor:
      return 'Motor';
    case BikeHotspotType.display:
      return 'Display';
    case BikeHotspotType.other:
      return 'Komponent';
  }
}

String _hotspotDescription(BikeHotspotType type) {
  switch (type) {
    case BikeHotspotType.frame:
      return 'Stel, model, materiale og kompatible skins.';
    case BikeHotspotType.fork:
      return 'Forgaffel, affjedring og serviceinformation.';
    case BikeHotspotType.handlebar:
      return 'Styr, betjening og monterede sensorer.';
    case BikeHotspotType.saddle:
      return 'Sadel, sadelpind, komfort og indstilling.';
    case BikeHotspotType.frontWheel:
      return 'Forhjul, dæk, tryk og slitage.';
    case BikeHotspotType.rearWheel:
      return 'Baghjul, dæk, kassette og slitage.';
    case BikeHotspotType.drivetrain:
      return 'Kæde, kranksæt, kassette og gearsystem.';
    case BikeHotspotType.battery:
      return 'Batteriniveau, sundhed og opladningsstatus.';
    case BikeHotspotType.gps:
      return 'Position, tracking og GPS-signal.';
    case BikeHotspotType.smartLight:
      return 'Smart baglygte, batteri, firmware og indstillinger.';
    case BikeHotspotType.motor:
      return 'Motorstatus, effekt og temperatur.';
    case BikeHotspotType.display:
      return 'Display, firmware og cykeldata.';
    case BikeHotspotType.other:
      return 'Komponentinformation for din Digital Twin.';
  }
}
