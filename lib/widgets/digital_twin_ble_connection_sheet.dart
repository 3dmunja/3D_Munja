import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../core/theme/munja_colors.dart';
import '../models/bike_product.dart';
import '../services/ble_service.dart';
import '../services/bluetooth/digital_twin_ble_service.dart';

/// Bottom sheet for scanning, connecting and disconnecting a physical Munja
/// product from its Digital Twin product.
///
/// BLE UUID values can be supplied directly through the constructor or stored
/// in [BikeProduct.metadata] with one of these keys:
///
/// Service:
/// - bleServiceUuid
/// - serviceUuid
///
/// Notify characteristic:
/// - bleNotifyCharacteristicUuid
/// - notifyCharacteristicUuid
///
/// Write characteristic:
/// - bleWriteCharacteristicUuid
/// - writeCharacteristicUuid
class DigitalTwinBleConnectionSheet extends StatefulWidget {
  const DigitalTwinBleConnectionSheet({
    super.key,
    required this.product,
    this.serviceUuid,
    this.notifyCharacteristicUuid,
    this.writeCharacteristicUuid,
    this.scanTimeout = const Duration(seconds: 6),
  });

  final BikeProduct product;
  final String? serviceUuid;
  final String? notifyCharacteristicUuid;
  final String? writeCharacteristicUuid;
  final Duration scanTimeout;

  /// Opens the BLE connection panel as a modal bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required BikeProduct product,
    String? serviceUuid,
    String? notifyCharacteristicUuid,
    String? writeCharacteristicUuid,
    Duration scanTimeout = const Duration(seconds: 6),
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DigitalTwinBleConnectionSheet(
        product: product,
        serviceUuid: serviceUuid,
        notifyCharacteristicUuid: notifyCharacteristicUuid,
        writeCharacteristicUuid: writeCharacteristicUuid,
        scanTimeout: scanTimeout,
      ),
    );
  }

  @override
  State<DigitalTwinBleConnectionSheet> createState() =>
      _DigitalTwinBleConnectionSheetState();
}

class _DigitalTwinBleConnectionSheetState
    extends State<DigitalTwinBleConnectionSheet> {
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  final Map<String, _DiscoveredBleDevice> _devices = {};

  bool _isScanning = false;
  String? _localError;

  String? get _serviceUuid => _firstNonEmpty([
    widget.serviceUuid,
    _metadataString('bleServiceUuid'),
    _metadataString('serviceUuid'),
  ]);

  String? get _notifyCharacteristicUuid => _firstNonEmpty([
    widget.notifyCharacteristicUuid,
    _metadataString('bleNotifyCharacteristicUuid'),
    _metadataString('notifyCharacteristicUuid'),
  ]);

  String? get _writeCharacteristicUuid => _firstNonEmpty([
    widget.writeCharacteristicUuid,
    _metadataString('bleWriteCharacteristicUuid'),
    _metadataString('writeCharacteristicUuid'),
  ]);

  bool get _hasRequiredUuids =>
      _serviceUuid != null && _notifyCharacteristicUuid != null;

  @override
  void initState() {
    super.initState();
    _listenToScanResults();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_startScan());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_scanSubscription?.cancel());
    unawaited(FlutterBluePlus.stopScan());
    super.dispose();
  }

  void _listenToScanResults() {
    _scanSubscription = FlutterBluePlus.scanResults.listen(
      (results) {
        if (!mounted) {
          return;
        }

        var changed = false;

        for (final result in results) {
          final name = result.device.advName.trim();

          if (name.isEmpty || !BleService.isMunjaDeviceName(name)) {
            continue;
          }

          final id = result.device.remoteId.str;
          final current = _devices[id];

          if (current == null || current.rssi != result.rssi) {
            _devices[id] = _DiscoveredBleDevice(
              device: result.device,
              name: name,
              rssi: result.rssi,
            );
            changed = true;
          }
        }

        if (changed) {
          setState(() {});
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'DigitalTwinBleConnectionSheet scan stream error: '
          '$error\n$stackTrace',
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _localError = 'Bluetooth-scanningen fejlede: $error';
          _isScanning = false;
        });
      },
    );
  }

  Future<void> _startScan() async {
    if (_isScanning) {
      return;
    }

    setState(() {
      _isScanning = true;
      _localError = null;
      _devices.clear();
    });

    final permissionsGranted = await BleService.ensureBlePermissions();

    if (!mounted) {
      return;
    }

    if (!permissionsGranted) {
      setState(() {
        _isScanning = false;
        _localError =
            'Bluetooth- og placeringstilladelser er nødvendige for at finde '
            'Munja-produkter.';
      });
      return;
    }

    try {
      await FlutterBluePlus.stopScan();

      await FlutterBluePlus.startScan(timeout: widget.scanTimeout);

      await Future<void>.delayed(
        widget.scanTimeout + const Duration(milliseconds: 350),
      );

      await FlutterBluePlus.stopScan();
    } catch (error, stackTrace) {
      debugPrint(
        'DigitalTwinBleConnectionSheet._startScan error: '
        '$error\n$stackTrace',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _localError = 'Kunne ikke starte Bluetooth-scanningen: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _connect(
    DigitalTwinBleService bleService,
    _DiscoveredBleDevice found,
  ) async {
    final serviceUuid = _serviceUuid;
    final notifyUuid = _notifyCharacteristicUuid;

    if (serviceUuid == null || notifyUuid == null) {
      setState(() {
        _localError =
            'Produktets BLE UUID-konfiguration mangler. Tilføj service- og '
            'notification-UUID til produktets metadata.';
      });
      return;
    }

    setState(() => _localError = null);

    await FlutterBluePlus.stopScan();

    if (mounted) {
      setState(() => _isScanning = false);
    }

    await bleService.connect(
      productId: widget.product.id,
      device: found.device,
      serviceUuid: serviceUuid,
      notifyCharacteristicUuid: notifyUuid,
      writeCharacteristicUuid: _writeCharacteristicUuid,
    );
  }

  Future<void> _disconnect(DigitalTwinBleService bleService) async {
    setState(() => _localError = null);
    await bleService.disconnect();
  }

  String? _metadataString(String key) {
    final value = widget.product.metadata[key];

    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = value?.trim();

      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Consumer<DigitalTwinBleService>(
      builder: (context, bleService, _) {
        final belongsToCurrentProduct =
            bleService.productId == widget.product.id;
        final connected = belongsToCurrentProduct && bleService.isConnected;
        final connecting = belongsToCurrentProduct && bleService.isConnecting;
        final disconnecting =
            belongsToCurrentProduct && bleService.isDisconnecting;
        final busy = connecting || disconnecting;

        final error = _localError ?? bleService.errorMessage;
        final sortedDevices = _devices.values.toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.86,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF07100E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetHeader(
                  product: widget.product,
                  connected: connected,
                  connecting: connecting,
                  onClose: busy ? null : () => Navigator.of(context).pop(),
                ),
                Flexible(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                    children: [
                      _CurrentConnectionCard(
                        product: widget.product,
                        bleService: bleService,
                        connected: connected,
                        connecting: connecting,
                        disconnecting: disconnecting,
                        onDisconnect: connected || connecting
                            ? () => _disconnect(bleService)
                            : null,
                      ),
                      const SizedBox(height: 14),
                      if (!_hasRequiredUuids) ...[
                        const _MissingUuidCard(),
                        const SizedBox(height: 14),
                      ],
                      if (error != null && error.trim().isNotEmpty) ...[
                        _ErrorCard(
                          message: error,
                          onDismiss: () {
                            setState(() => _localError = null);
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _ScanHeader(
                        isScanning: _isScanning,
                        count: sortedDevices.length,
                        onScan: busy || _isScanning ? null : _startScan,
                      ),
                      const SizedBox(height: 10),
                      if (_isScanning && sortedDevices.isEmpty)
                        const _ScanningPlaceholder()
                      else if (!_isScanning && sortedDevices.isEmpty)
                        _EmptyScanResult(onScan: busy ? null : _startScan)
                      else
                        ...sortedDevices.map(
                          (found) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _BleDeviceTile(
                              found: found,
                              connected:
                                  connected &&
                                  bleService.device?.remoteId.str ==
                                      found.device.remoteId.str,
                              connecting:
                                  connecting &&
                                  bleService.device?.remoteId.str ==
                                      found.device.remoteId.str,
                              enabled: !busy && _hasRequiredUuids,
                              onConnect: () => _connect(bleService, found),
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _ConfigurationSummary(
                        serviceUuid: _serviceUuid,
                        notifyUuid: _notifyCharacteristicUuid,
                        writeUuid: _writeCharacteristicUuid,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.product,
    required this.connected,
    required this.connecting,
    required this.onClose,
  });

  final BikeProduct product;
  final bool connected;
  final bool connecting;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final statusLabel = connected
        ? 'FORBUNDET'
        : connecting
        ? 'FORBINDER'
        : 'BLUETOOTH';

    final statusColor = connected
        ? MunjaColors.mint
        : connecting
        ? Colors.amberAccent
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 15),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.20),
                  ),
                ),
                child: const Icon(
                  Icons.bluetooth_rounded,
                  color: MunjaColors.mint,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Forbind fysisk produkt med Digital Twin',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.46),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.24),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Luk',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded),
                color: Colors.white60,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CurrentConnectionCard extends StatelessWidget {
  const _CurrentConnectionCard({
    required this.product,
    required this.bleService,
    required this.connected,
    required this.connecting,
    required this.disconnecting,
    required this.onDisconnect,
  });

  final BikeProduct product;
  final DigitalTwinBleService bleService;
  final bool connected;
  final bool connecting;
  final bool disconnecting;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final status = disconnecting
        ? 'Afbryder forbindelsen...'
        : connecting
        ? 'Forbinder til ${bleService.device?.platformName ?? 'produkt'}...'
        : connected
        ? 'Forbundet til ${bleService.device?.platformName ?? 'Munja-produkt'}'
        : 'Produktet er ikke forbundet';

    final statusColor = connected
        ? MunjaColors.mint
        : connecting || disconnecting
        ? Colors.amberAccent
        : Colors.white54;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: connected ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: statusColor.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: connecting || disconnecting
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: statusColor,
                    ),
                  )
                : Icon(
                    connected
                        ? Icons.bluetooth_connected_rounded
                        : Icons.bluetooth_disabled_rounded,
                    color: statusColor,
                    size: 21,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected
                      ? 'Batteri, firmware og signal opdateres automatisk.'
                      : 'Vælg en enhed fra listen nedenfor.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.42),
                    fontSize: 10,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (onDisconnect != null)
            TextButton(
              onPressed: disconnecting ? null : onDisconnect,
              child: const Text(
                'AFBRYD',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanHeader extends StatelessWidget {
  const _ScanHeader({
    required this.isScanning,
    required this.count,
    required this.onScan,
  });

  final bool isScanning;
  final int count;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'TILGÆNGELIGE MUNJA-ENHEDER',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
        if (count > 0)
          Text(
            '$count fundet',
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: isScanning ? 'Scanner...' : 'Scan igen',
          onPressed: onScan,
          icon: isScanning
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MunjaColors.mint,
                  ),
                )
              : const Icon(Icons.refresh_rounded),
          color: MunjaColors.mint,
        ),
      ],
    );
  }
}

class _BleDeviceTile extends StatelessWidget {
  const _BleDeviceTile({
    required this.found,
    required this.connected,
    required this.connecting,
    required this.enabled,
    required this.onConnect,
  });

  final _DiscoveredBleDevice found;
  final bool connected;
  final bool connecting;
  final bool enabled;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final signalLabel = BleService.proximityLabel(found.rssi);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: connected
            ? MunjaColors.mint.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: connected
              ? MunjaColors.mint.withValues(alpha: 0.26)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: connected
                  ? MunjaColors.mint.withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              connected
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_searching_rounded,
              color: connected ? MunjaColors.mint : Colors.white70,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  found.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(
                      Icons.network_cell_rounded,
                      color: _signalColor(found.rssi),
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        '$signalLabel · ${found.rssi} dBm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.43),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 38,
            child: FilledButton(
              onPressed: enabled && !connected && !connecting
                  ? onConnect
                  : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                backgroundColor: connected
                    ? MunjaColors.mint.withValues(alpha: 0.16)
                    : MunjaColors.mint,
                foregroundColor: connected
                    ? MunjaColors.mint
                    : const Color(0xFF03110D),
              ),
              child: connecting
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF03110D),
                      ),
                    )
                  : Text(
                      connected ? 'FORBUNDET' : 'FORBIND',
                      style: const TextStyle(
                        fontSize: 10,
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

class _ScanningPlaceholder extends StatelessWidget {
  const _ScanningPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: const Column(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2.3,
              color: MunjaColors.mint,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Scanner efter Munja-produkter...',
            textAlign: TextAlign.center,
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

class _EmptyScanResult extends StatelessWidget {
  const _EmptyScanResult({required this.onScan});

  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.bluetooth_searching_rounded,
            color: Colors.white.withValues(alpha: 0.36),
            size: 38,
          ),
          const SizedBox(height: 12),
          const Text(
            'Ingen Munja-enheder fundet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Sørg for, at produktet er tændt og tæt på telefonen.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.42),
              fontSize: 11,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text(
              'SCAN IGEN',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _MissingUuidCard extends StatelessWidget {
  const _MissingUuidCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.22)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 21),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'BLE UUID-konfiguration mangler. Scanning virker, men produktet '
              'kan først forbindes, når serviceUuid og '
              'notifyCharacteristicUuid er angivet.',
              style: TextStyle(
                color: Colors.amberAccent,
                fontSize: 11,
                height: 1.45,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.redAccent,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 11,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Luk fejl',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
            color: Colors.redAccent,
            iconSize: 19,
          ),
        ],
      ),
    );
  }
}

class _ConfigurationSummary extends StatelessWidget {
  const _ConfigurationSummary({
    required this.serviceUuid,
    required this.notifyUuid,
    required this.writeUuid,
  });

  final String? serviceUuid;
  final String? notifyUuid;
  final String? writeUuid;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      collapsedIconColor: Colors.white38,
      iconColor: MunjaColors.mint,
      title: Text(
        'BLE-konfiguration',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.46),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
      children: [
        _UuidRow(label: 'Service', value: serviceUuid),
        const SizedBox(height: 7),
        _UuidRow(label: 'Notify', value: notifyUuid),
        const SizedBox(height: 7),
        _UuidRow(label: 'Write', value: writeUuid),
      ],
    );
  }
}

class _UuidRow extends StatelessWidget {
  const _UuidRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: SelectableText(
            hasValue ? value! : 'Ikke angivet',
            style: TextStyle(
              color: hasValue ? Colors.white60 : Colors.amberAccent,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoveredBleDevice {
  const _DiscoveredBleDevice({
    required this.device,
    required this.name,
    required this.rssi,
  });

  final BluetoothDevice device;
  final String name;
  final int rssi;
}

Color _signalColor(int rssi) {
  if (rssi >= -55) {
    return MunjaColors.mint;
  }

  if (rssi >= -70) {
    return Colors.amberAccent;
  }

  return Colors.redAccent;
}
