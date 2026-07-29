import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/firestore_bike.dart';
import '../providers/bike_provider.dart';
import '../providers/digital_twin_provider.dart';
import '../widgets/digital_twin_viewer.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  String? _lastSyncedBikeSignature;
  bool _digitalTwinSyncScheduled = false;

  String _bikeSignature(FirestoreBike bike) {
    return <Object?>[
      bike.id,
      bike.name,
      bike.brand,
      bike.model,
      bike.type,
      bike.color,
      bike.imageUrl,
      bike.glbModelUrl,
      bike.digitalTwinEnabled,
      bike.firmwareVersion,
      bike.updatedAt,
    ].join('|');
  }

  void _scheduleDigitalTwinSync({
    required FirestoreBike? activeBike,
    required DigitalTwinProvider digitalTwinProvider,
  }) {
    final signature = activeBike == null ? null : _bikeSignature(activeBike);

    if (_digitalTwinSyncScheduled || signature == _lastSyncedBikeSignature) {
      return;
    }

    _digitalTwinSyncScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _digitalTwinSyncScheduled = false;

      if (!mounted) {
        return;
      }

      final currentActiveBike = context.read<BikeProvider>().activeBike;
      final currentSignature = currentActiveBike == null
          ? null
          : _bikeSignature(currentActiveBike);

      if (currentSignature == _lastSyncedBikeSignature) {
        return;
      }

      if (currentActiveBike == null) {
        digitalTwinProvider.reset();
        _lastSyncedBikeSignature = null;
        return;
      }

      final currentTwin = digitalTwinProvider.digitalTwin;

      if (currentTwin == null || currentTwin.bike.id != currentActiveBike.id) {
        await digitalTwinProvider.initializeEmpty(bike: currentActiveBike);
      } else {
        digitalTwinProvider.updateBike(currentActiveBike);
      }

      _lastSyncedBikeSignature = currentSignature;
    });
  }

  Future<void> _openBikeEditor(
    BuildContext context, {
    FirestoreBike? bike,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BikeEditorSheet(bike: bike),
    );

    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bike == null ? 'Cyklen blev oprettet.' : 'Cyklen blev opdateret.',
          ),
        ),
      );
    }
  }

  Future<void> _setActiveBike(BuildContext context, FirestoreBike bike) async {
    final provider = context.read<BikeProvider>();
    final success = await provider.setActiveBike(bike.id);

    if (!context.mounted) {
      return;
    }

    if (!success) {
      _showError(
        context,
        provider.errorMessage ?? 'Cyklen kunne ikke aktiveres.',
      );
    }
  }

  Future<void> _deleteBike(BuildContext context, FirestoreBike bike) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MunjaColors.panel,
          title: const Text(
            'Slet cykel',
            style: TextStyle(
              color: MunjaColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Er du sikker på, at du vil slette "${bike.displayName}"?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuller'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Slet',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !context.mounted) {
      return;
    }

    final provider = context.read<BikeProvider>();
    final success = await provider.deleteBike(bike.id);

    if (!context.mounted) {
      return;
    }

    if (!success) {
      _showError(
        context,
        provider.errorMessage ?? 'Cyklen kunne ikke slettes.',
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Cyklen blev slettet.')));
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<BikeProvider, DigitalTwinProvider>(
      builder: (context, provider, digitalTwinProvider, _) {
        final bikes = provider.bikes;
        final activeBike = provider.activeBike;

        _scheduleDigitalTwinSync(
          activeBike: activeBike,
          digitalTwinProvider: digitalTwinProvider,
        );

        final showInitialLoading =
            !provider.isInitialized || (provider.isLoading && bikes.isEmpty);

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: provider.refresh,
              color: MunjaColors.mint,
              backgroundColor: MunjaColors.panel,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 360),
                children: [
                  _GarageHeader(
                    bikesCount: bikes.length,
                    busy: provider.isCreating,
                    onAddBike: () => _openBikeEditor(context),
                  ),
                  const SizedBox(height: 18),
                  if (provider.hasError && !showInitialLoading) ...[
                    _ErrorCard(
                      message:
                          provider.errorMessage ??
                          'Cyklerne kunne ikke indlæses.',
                      onRetry: provider.refresh,
                      onDismiss: provider.clearError,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (showInitialLoading)
                    const _LoadingCard()
                  else if (bikes.isEmpty)
                    _EmptyGarageCard(
                      onCreateBike: () => _openBikeEditor(context),
                    )
                  else ...[
                    if (activeBike != null) ...[
                      _ActiveBikeHero(
                        bike: activeBike,
                        busy: provider.isBusy,
                        digitalTwinProvider: digitalTwinProvider,
                        onEdit: () =>
                            _openBikeEditor(context, bike: activeBike),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Text(
                      AppText.t('myBikes').toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.44),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final bike in bikes) ...[
                      _BikeCard(
                        bike: bike,
                        busy: provider.isBusy,
                        onEdit: () => _openBikeEditor(context, bike: bike),
                        onSetActive: () => _setActiveBike(context, bike),
                        onDelete: () => _deleteBike(context, bike),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 6),
                    _AddBikeCard(
                      busy: provider.isCreating,
                      onTap: () => _openBikeEditor(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GarageHeader extends StatelessWidget {
  const _GarageHeader({
    required this.bikesCount,
    required this.busy,
    required this.onAddBike,
  });

  final int bikesCount;
  final bool busy;
  final VoidCallback onAddBike;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppText.t('garage'),
                style: const TextStyle(
                  color: MunjaColors.text,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$bikesCount ${bikesCount == 1 ? 'cykel' : 'cykler'}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.46),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        Material(
          color: MunjaColors.mint.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: busy ? null : onAddBike,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: MunjaColors.mint.withValues(alpha: 0.28),
                ),
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: MunjaColors.mint,
                      ),
                    )
                  : const Icon(
                      Icons.add_rounded,
                      color: MunjaColors.mint,
                      size: 28,
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveBikeHero extends StatelessWidget {
  const _ActiveBikeHero({
    required this.bike,
    required this.busy,
    required this.digitalTwinProvider,
    required this.onEdit,
  });

  final FirestoreBike bike;
  final bool busy;
  final DigitalTwinProvider digitalTwinProvider;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withValues(alpha: 0.08),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _StatusBadge(
                icon: Icons.check_circle_rounded,
                label: 'AKTIV CYKEL',
              ),
              const Spacer(),
              IconButton(
                onPressed: busy ? null : onEdit,
                icon: const Icon(Icons.edit_rounded),
                color: Colors.white70,
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (bike.hasDigitalTwinModel)
            DigitalTwinViewer(
              modelUrl: bike.glbModelUrl,
              title: bike.displayName,
              subtitle: 'Din aktive Munja Digital Twin',
              height: 260,
              borderRadius: 28,
              autoRotate: false,
              cameraControls: true,
              showHeader: false,
              showStatusBadge: false,
              showFullscreenButton: true,
            )
          else
            Container(
              height: 210,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (bike.hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(27),
                      child: Image.network(
                        bike.imageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _BikeHeroPlaceholder(type: bike.type),
                      ),
                    )
                  else
                    _BikeHeroPlaceholder(type: bike.type),
                  if (bike.digitalTwinEnabled)
                    const Positioned(
                      top: 14,
                      right: 14,
                      child: _StatusBadge(
                        icon: Icons.view_in_ar_rounded,
                        label: 'DIGITAL TWIN',
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text(
            bike.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MunjaColors.text,
              fontSize: 25,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _bikeDescription(bike),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.52),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          _DigitalTwinStatusRow(
            enabled: bike.digitalTwinEnabled,
            hasModel: bike.hasDigitalTwinModel,
            isLoading: digitalTwinProvider.isLoading,
            productCount: digitalTwinProvider.productCount,
            connectedProductCount: digitalTwinProvider.connectedProductCount,
            firmwareUpdateCount: digitalTwinProvider.firmwareUpdateCount,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  icon: Icons.straighten_rounded,
                  label: 'Hjul',
                  value: bike.wheelSize.isEmpty ? '—' : bike.wheelSize,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoTile(
                  icon: Icons.palette_outlined,
                  label: 'Farve',
                  value: bike.color.isEmpty ? '—' : bike.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InfoTile(
                  icon: Icons.memory_rounded,
                  label: 'Firmware',
                  value: bike.firmwareVersion.isEmpty
                      ? '—'
                      : bike.firmwareVersion,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DigitalTwinStatusRow extends StatelessWidget {
  const _DigitalTwinStatusRow({
    required this.enabled,
    required this.hasModel,
    required this.isLoading,
    required this.productCount,
    required this.connectedProductCount,
    required this.firmwareUpdateCount,
  });

  final bool enabled;
  final bool hasModel;
  final bool isLoading;
  final int productCount;
  final int connectedProductCount;
  final int firmwareUpdateCount;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: MunjaColors.mint,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Initialiserer Digital Twin...',
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

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _TwinMetricBadge(
          icon: hasModel ? Icons.view_in_ar_rounded : Icons.view_in_ar_outlined,
          label: enabled && hasModel ? 'Digital Twin klar' : 'Ingen 3D-model',
          active: enabled && hasModel,
        ),
        _TwinMetricBadge(
          icon: Icons.extension_rounded,
          label: '$productCount produkter',
          active: productCount > 0,
        ),
        _TwinMetricBadge(
          icon: Icons.bluetooth_connected_rounded,
          label: '$connectedProductCount forbundet',
          active: connectedProductCount > 0,
        ),
        if (firmwareUpdateCount > 0)
          _TwinMetricBadge(
            icon: Icons.system_update_rounded,
            label: '$firmwareUpdateCount opdatering',
            active: true,
          ),
      ],
    );
  }
}

class _TwinMetricBadge extends StatelessWidget {
  const _TwinMetricBadge({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? MunjaColors.mint : Colors.white54;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withValues(alpha: 0.11)
            : Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: foreground, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BikeHeroPlaceholder extends StatelessWidget {
  const _BikeHeroPlaceholder({required this.type});

  final FirestoreBikeType type;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(_bikeIcon(type), color: MunjaColors.mint, size: 86),
        const SizedBox(height: 12),
        Text(
          _bikeTypeLabel(type).toUpperCase(),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.48),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }
}

class _BikeCard extends StatelessWidget {
  const _BikeCard({
    required this.bike,
    required this.busy,
    required this.onEdit,
    required this.onSetActive,
    required this.onDelete,
  });

  final FirestoreBike bike;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onSetActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
      decoration: BoxDecoration(
        color: bike.active
            ? MunjaColors.mint.withValues(alpha: 0.11)
            : MunjaColors.panel.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: bike.active
              ? MunjaColors.mint.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: bike.hasImage
                ? Image.network(
                    bike.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      _bikeIcon(bike.type),
                      color: bike.active
                          ? MunjaColors.mint
                          : MunjaColors.textSoft,
                      size: 27,
                    ),
                  )
                : Icon(
                    _bikeIcon(bike.type),
                    color: bike.active
                        ? MunjaColors.mint
                        : MunjaColors.textSoft,
                    size: 27,
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: busy ? null : onEdit,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bike.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MunjaColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _bikeDescription(bike),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.44),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (bike.active)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.check_circle_rounded,
                color: MunjaColors.mint,
                size: 24,
              ),
            )
          else
            TextButton(
              onPressed: busy ? null : onSetActive,
              child: const Text(
                'Aktivér',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          PopupMenuButton<String>(
            enabled: !busy,
            color: MunjaColors.panel,
            icon: Icon(
              Icons.more_vert_rounded,
              color: Colors.white.withValues(alpha: 0.55),
            ),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  onEdit();
                  break;
                case 'activate':
                  onSetActive();
                  break;
                case 'delete':
                  onDelete();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem<String>(
                value: 'edit',
                child: Text('Rediger'),
              ),
              if (!bike.active)
                const PopupMenuItem<String>(
                  value: 'activate',
                  child: Text('Gør aktiv'),
                ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: Text('Slet', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BikeEditorSheet extends StatefulWidget {
  const _BikeEditorSheet({this.bike});

  final FirestoreBike? bike;

  @override
  State<_BikeEditorSheet> createState() => _BikeEditorSheetState();
}

class _BikeEditorSheetState extends State<_BikeEditorSheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _colorController;
  late final TextEditingController _frameSizeController;
  late final TextEditingController _wheelSizeController;
  late final TextEditingController _serialNumberController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _glbModelUrlController;
  late final TextEditingController _firmwareController;
  late final TextEditingController _notesController;

  late FirestoreBikeType _type;
  late bool _digitalTwinEnabled;
  late bool _makeActive;

  final ImagePicker _imagePicker = ImagePicker();

  String? _pendingImagePath;
  String? _pendingModelPath;
  String? _pendingModelName;
  bool _removeExistingImage = false;
  bool _removeExistingModel = false;

  bool get _editing => widget.bike != null;

  @override
  void initState() {
    super.initState();

    final bike = widget.bike;

    _nameController = TextEditingController(text: bike?.name ?? '');
    _brandController = TextEditingController(text: bike?.brand ?? '');
    _modelController = TextEditingController(text: bike?.model ?? '');
    _colorController = TextEditingController(text: bike?.color ?? '');
    _frameSizeController = TextEditingController(text: bike?.frameSize ?? '');
    _wheelSizeController = TextEditingController(text: bike?.wheelSize ?? '');
    _serialNumberController = TextEditingController(
      text: bike?.serialNumber ?? '',
    );
    _imageUrlController = TextEditingController(text: bike?.imageUrl ?? '');
    _glbModelUrlController = TextEditingController(
      text: bike?.glbModelUrl ?? '',
    );
    _firmwareController = TextEditingController(
      text: bike?.firmwareVersion ?? '',
    );
    _notesController = TextEditingController(text: bike?.notes ?? '');

    _type = bike?.type ?? FirestoreBikeType.mtb;
    _digitalTwinEnabled = bike?.digitalTwinEnabled ?? false;
    _makeActive = bike?.active ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    _frameSizeController.dispose();
    _wheelSizeController.dispose();
    _serialNumberController.dispose();
    _imageUrlController.dispose();
    _glbModelUrlController.dispose();
    _firmwareController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _chooseBikeImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: MunjaColors.panel,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: MunjaColors.mint,
                ),
                title: const Text(
                  'Vælg fra galleri',
                  style: TextStyle(
                    color: MunjaColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: MunjaColors.mint,
                ),
                title: const Text(
                  'Tag et billede',
                  style: TextStyle(
                    color: MunjaColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 2400,
      );

      if (image == null || !mounted) return;

      setState(() {
        _pendingImagePath = image.path;
        _removeExistingImage = false;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Billedet kunne ikke vælges.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _chooseBikeModel() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['glb', 'gltf'],
        allowMultiple: false,
        withData: false,
      );

      if (result == null || result.files.isEmpty || !mounted) return;

      final file = result.files.single;
      final filePath = file.path;

      if (filePath == null || filePath.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('3D-filen kunne ikke åbnes på denne enhed.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() {
        _pendingModelPath = filePath;
        _pendingModelName = file.name;
        _removeExistingModel = false;
        _digitalTwinEnabled = true;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('3D-modellen kunne ikke vælges.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _removeImageSelection() {
    setState(() {
      _pendingImagePath = null;
      _removeExistingImage = true;
    });
  }

  void _removeModelSelection() {
    setState(() {
      _pendingModelPath = null;
      _pendingModelName = null;
      _removeExistingModel = true;
      _digitalTwinEnabled = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<BikeProvider>();
    provider.clearError(notify: false);

    bool success;
    String? targetBikeId;

    if (_editing) {
      targetBikeId = widget.bike!.id;

      success = await provider.updateBikeFields(
        bikeId: targetBikeId,
        name: _nameController.text,
        brand: _brandController.text,
        model: _modelController.text,
        type: _type,
        color: _colorController.text,
        frameSize: _frameSizeController.text,
        wheelSize: _wheelSizeController.text,
        serialNumber: _serialNumberController.text,
        firmwareVersion: _firmwareController.text,
        digitalTwinEnabled: _removeExistingModel ? false : _digitalTwinEnabled,
        notes: _notesController.text,
      );

      if (success && _makeActive && !widget.bike!.active) {
        success = await provider.setActiveBike(targetBikeId);
      }
    } else {
      final ownerId = provider.currentUserId ?? '';

      final bike = FirestoreBike.empty(ownerId: ownerId).copyWith(
        name: _nameController.text,
        brand: _brandController.text,
        model: _modelController.text,
        type: _type,
        color: _colorController.text,
        frameSize: _frameSizeController.text,
        wheelSize: _wheelSizeController.text,
        serialNumber: _serialNumberController.text,
        firmwareVersion: _firmwareController.text,
        digitalTwinEnabled: _pendingModelPath != null && !_removeExistingModel,
        notes: _notesController.text,
      );

      final createdBike = await provider.createBike(
        bike,
        makeActive: _makeActive || provider.bikes.isEmpty,
      );

      success = createdBike != null;
      targetBikeId = createdBike?.id;
    }

    if (!success || targetBikeId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Cyklen kunne ikke gemmes.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_removeExistingImage && _editing && widget.bike!.hasImage) {
      success = await provider.deleteBikeImage(bikeId: targetBikeId);
    }

    if (success && _pendingImagePath != null) {
      success =
          await provider.uploadBikeImage(
            bikeId: targetBikeId,
            filePath: _pendingImagePath!,
          ) !=
          null;
    }

    if (success &&
        _removeExistingModel &&
        _editing &&
        widget.bike!.hasDigitalTwinModel) {
      success = await provider.deleteBikeModel(
        bikeId: targetBikeId,
        disableDigitalTwin: true,
      );
    }

    if (success && _pendingModelPath != null) {
      success =
          await provider.uploadBikeModel(
            bikeId: targetBikeId,
            filePath: _pendingModelPath!,
            enableDigitalTwin: true,
          ) !=
          null;
    }

    if (!mounted) return;

    if (!success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            provider.errorMessage ??
                'Cyklen blev gemt, men filen kunne ikke behandles.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Consumer<BikeProvider>(
      builder: (context, provider, _) {
        final saving =
            provider.isCreating ||
            provider.isUpdating ||
            provider.isChangingActiveBike ||
            provider.isUploadingBikeImage ||
            provider.isUploadingBikeModel ||
            provider.isDeletingBikeImage ||
            provider.isDeletingBikeModel;

        return Container(
          margin: const EdgeInsets.only(top: 22),
          padding: EdgeInsets.fromLTRB(20, 12, 20, bottomInset + 24),
          decoration: const BoxDecoration(
            color: MunjaColors.bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _editing ? 'Rediger cykel' : 'Tilføj cykel',
                        style: const TextStyle(
                          color: MunjaColors.text,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Cyklen gemmes i Firebase og synkroniseres med din Munja-konto.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                _TextField(
                  controller: _nameController,
                  label: 'Cyklens navn',
                  icon: Icons.directions_bike_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Indtast et navn til cyklen.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TextField(
                        controller: _brandController,
                        label: 'Mærke',
                        icon: Icons.sell_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TextField(
                        controller: _modelController,
                        label: 'Model',
                        icon: Icons.badge_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FirestoreBikeType>(
                  initialValue: _type,
                  dropdownColor: MunjaColors.panel,
                  decoration: const InputDecoration(
                    labelText: 'Cykeltype',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: FirestoreBikeType.values
                      .map(
                        (type) => DropdownMenuItem<FirestoreBikeType>(
                          value: type,
                          child: Text(_bikeTypeLabel(type)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _type = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TextField(
                        controller: _colorController,
                        label: 'Farve',
                        icon: Icons.palette_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TextField(
                        controller: _wheelSizeController,
                        label: 'Hjulstørrelse',
                        icon: Icons.straighten_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TextField(
                        controller: _frameSizeController,
                        label: 'Stelstørrelse',
                        icon: Icons.height_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TextField(
                        controller: _firmwareController,
                        label: 'Firmware',
                        icon: Icons.memory_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _TextField(
                  controller: _serialNumberController,
                  label: 'Serienummer',
                  icon: Icons.qr_code_rounded,
                ),
                const SizedBox(height: 18),
                _BikeImagePickerCard(
                  pendingImagePath: _pendingImagePath,
                  existingImageUrl: _removeExistingImage
                      ? ''
                      : _imageUrlController.text,
                  uploading: provider.isUploadingBikeImage,
                  deleting: provider.isDeletingBikeImage,
                  uploadProgress: provider.bikeImageUploadProgress,
                  onChoose: saving ? null : _chooseBikeImage,
                  onRemove: saving ? null : _removeImageSelection,
                ),
                const SizedBox(height: 12),
                _BikeModelPickerCard(
                  pendingModelName: _pendingModelName,
                  existingModelUrl: _removeExistingModel
                      ? ''
                      : _glbModelUrlController.text,
                  uploading: provider.isUploadingBikeModel,
                  deleting: provider.isDeletingBikeModel,
                  uploadProgress: provider.bikeModelUploadProgress,
                  onChoose: saving ? null : _chooseBikeModel,
                  onRemove: saving ? null : _removeModelSelection,
                ),
                const SizedBox(height: 12),
                _TextField(
                  controller: _notesController,
                  label: 'Noter',
                  icon: Icons.notes_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _SwitchTile(
                  title: 'Digital Twin',
                  subtitle: 'Aktivér den digitale 3D-version af cyklen.',
                  value: _digitalTwinEnabled,
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() => _digitalTwinEnabled = value);
                        },
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  title: 'Aktiv cykel',
                  subtitle: 'Brug denne cykel som din primære cykel.',
                  value: _makeActive,
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() => _makeActive = value);
                        },
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      saving
                          ? 'Gemmer...'
                          : _editing
                          ? 'Gem ændringer'
                          : 'Opret cykel',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
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

class _BikeImagePickerCard extends StatelessWidget {
  const _BikeImagePickerCard({
    required this.pendingImagePath,
    required this.existingImageUrl,
    required this.uploading,
    required this.deleting,
    required this.uploadProgress,
    required this.onChoose,
    required this.onRemove,
  });

  final String? pendingImagePath;
  final String existingImageUrl;
  final bool uploading;
  final bool deleting;
  final double uploadProgress;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;

  bool get _hasPendingImage =>
      pendingImagePath != null && pendingImagePath!.trim().isNotEmpty;

  bool get _hasExistingImage => existingImageUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final busy = uploading || deleting;

    return _MediaCard(
      icon: Icons.image_rounded,
      title: 'Cykelbillede',
      subtitle: _hasPendingImage
          ? 'Nyt billede klar til upload'
          : _hasExistingImage
          ? 'Billedet er gemt i Firebase Storage'
          : 'Tilføj et billede fra kamera eller galleri',
      actionLabel: _hasPendingImage || _hasExistingImage
          ? 'Skift billede'
          : 'Vælg billede',
      onAction: onChoose,
      onRemove: _hasPendingImage || _hasExistingImage ? onRemove : null,
      busy: busy,
      progress: uploading ? uploadProgress : null,
      preview: SizedBox(
        height: 170,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: _hasPendingImage
              ? Image.file(
                  File(pendingImagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const _MediaPlaceholder(icon: Icons.broken_image_rounded),
                )
              : _hasExistingImage
              ? Image.network(
                  existingImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) =>
                      const _MediaPlaceholder(icon: Icons.broken_image_rounded),
                )
              : const _MediaPlaceholder(icon: Icons.add_a_photo_rounded),
        ),
      ),
    );
  }
}

class _BikeModelPickerCard extends StatelessWidget {
  const _BikeModelPickerCard({
    required this.pendingModelName,
    required this.existingModelUrl,
    required this.uploading,
    required this.deleting,
    required this.uploadProgress,
    required this.onChoose,
    required this.onRemove,
  });

  final String? pendingModelName;
  final String existingModelUrl;
  final bool uploading;
  final bool deleting;
  final double uploadProgress;
  final VoidCallback? onChoose;
  final VoidCallback? onRemove;

  bool get _hasPendingModel =>
      pendingModelName != null && pendingModelName!.trim().isNotEmpty;

  bool get _hasExistingModel => existingModelUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final busy = uploading || deleting;
    final hasModel = _hasPendingModel || _hasExistingModel;

    return _MediaCard(
      icon: Icons.view_in_ar_rounded,
      title: '3D Digital Twin',
      subtitle: _hasPendingModel
          ? pendingModelName!
          : _hasExistingModel
          ? 'GLB-modellen er forbundet'
          : 'Vælg en GLB- eller GLTF-model',
      actionLabel: hasModel ? 'Skift model' : 'Vælg 3D-model',
      onAction: onChoose,
      onRemove: hasModel ? onRemove : null,
      busy: busy,
      progress: uploading ? uploadProgress : null,
      preview: Container(
        height: 112,
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: hasModel
                ? MunjaColors.mint.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                hasModel ? Icons.view_in_ar_rounded : Icons.widgets_rounded,
                color: MunjaColors.mint,
                size: 32,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasModel ? 'DIGITAL TWIN READY' : 'INGEN MODEL',
                    style: TextStyle(
                      color: hasModel
                          ? MunjaColors.mint
                          : Colors.white.withValues(alpha: 0.42),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    _hasPendingModel
                        ? pendingModelName!
                        : _hasExistingModel
                        ? 'Firebase Storage'
                        : 'Understøtter .glb og .gltf',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: MunjaColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.preview,
    required this.busy,
    required this.onAction,
    required this.onRemove,
    this.progress,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final Widget preview;
  final bool busy;
  final double? progress;
  final VoidCallback? onAction;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final normalizedProgress = progress?.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MunjaColors.mint, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Fjern',
                  onPressed: busy ? null : onRemove,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                ),
            ],
          ),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 13),
          preview,
          if (normalizedProgress != null) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: normalizedProgress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(999),
              color: MunjaColors.mint,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 8),
            Text(
              'Uploader ${(normalizedProgress * 100).round()}%',
              style: const TextStyle(
                color: MunjaColors.mint,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onAction,
              icon: busy
                  ? const SizedBox(
                      width: 17,
                      height: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(
                busy ? 'Arbejder...' : actionLabel,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.22),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: MunjaColors.mint.withValues(alpha: 0.72),
        size: 46,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      validator: validator,
      textInputAction: maxLines > 1
          ? TextInputAction.newline
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: onChanged,
        activeTrackColor: MunjaColors.mint,
        title: Text(
          title,
          style: const TextStyle(
            color: MunjaColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.46),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 18),
          const Spacer(),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.40),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MunjaColors.text,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddBikeCard extends StatelessWidget {
  const _AddBikeCard({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: MunjaColors.panel.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MunjaColors.mint,
                  ),
                )
              else
                const Icon(
                  Icons.add_circle_rounded,
                  color: MunjaColors.mint,
                  size: 22,
                ),
              const SizedBox(width: 10),
              Text(
                busy ? 'Opretter...' : AppText.t('addBike'),
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyGarageCard extends StatelessWidget {
  const _EmptyGarageCard({required this.onCreateBike});

  final VoidCallback onCreateBike;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          const Icon(Icons.garage_rounded, color: MunjaColors.mint, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Din garage er tom',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tilføj din første cykel, så den kan synkroniseres mellem appen og hjemmesiden.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.48),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          _AddBikeCard(busy: false, onTap: onCreateBike),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String message;
  final Future<void> Function() onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Prøv igen',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Luk',
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: MunjaColors.mint),
          SizedBox(height: 16),
          Text(
            'Henter dine cykler...',
            style: TextStyle(
              color: MunjaColors.textSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _bikeIcon(FirestoreBikeType type) {
  switch (type) {
    case FirestoreBikeType.road:
    case FirestoreBikeType.gravel:
      return Icons.directions_bike_rounded;
    case FirestoreBikeType.mtb:
    case FirestoreBikeType.kids:
      return Icons.pedal_bike_rounded;
    case FirestoreBikeType.city:
      return Icons.commute_rounded;
    case FirestoreBikeType.ebike:
      return Icons.electric_bike_rounded;
    case FirestoreBikeType.other:
      return Icons.two_wheeler_rounded;
  }
}

String _bikeTypeLabel(FirestoreBikeType type) {
  switch (type) {
    case FirestoreBikeType.road:
      return 'Landevej';
    case FirestoreBikeType.gravel:
      return 'Gravel';
    case FirestoreBikeType.mtb:
      return 'MTB';
    case FirestoreBikeType.city:
      return 'Citybike';
    case FirestoreBikeType.ebike:
      return 'Elcykel';
    case FirestoreBikeType.kids:
      return 'Børnecykel';
    case FirestoreBikeType.other:
      return 'Anden';
  }
}

String _bikeDescription(FirestoreBike bike) {
  final values = <String>[
    _bikeTypeLabel(bike.type),
    if (bike.brand.trim().isNotEmpty) bike.brand.trim(),
    if (bike.model.trim().isNotEmpty) bike.model.trim(),
    if (bike.wheelSize.trim().isNotEmpty) bike.wheelSize.trim(),
  ];

  return values.join(' · ');
}
