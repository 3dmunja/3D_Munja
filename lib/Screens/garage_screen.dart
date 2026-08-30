import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'bike_customize_screen.dart';
import 'bike_products_screen.dart';
import 'bike_devices_screen.dart';
import 'bike_info_screen.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
import '../models/firestore_bike.dart';
import '../providers/bike_provider.dart';
import '../providers/digital_twin_provider.dart';
import '../widgets/munja_3d_bike_viewer.dart';

class _CosmeticUnlock {
  const _CosmeticUnlock({
    required this.rewardId,
    required this.name,
    required this.type,
    required this.source,
    required this.sourceId,
    required this.specialMonth,
    required this.specialYear,
  });

  final String rewardId;
  final String name;
  final String type;
  final String source;
  final String sourceId;
  final int specialMonth;
  final int specialYear;

  bool get isFrame => type == 'frame';
  bool get isSkin => type == 'skin';
  bool get isBadge => type == 'badge';

  factory _CosmeticUnlock.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? const <String, dynamic>{};

    int readInt(Object? value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value.trim()) ?? 0;
      return 0;
    }

    String readString(Object? value) {
      return value?.toString().trim() ?? '';
    }

    return _CosmeticUnlock(
      rewardId: readString(data['rewardId']).isEmpty
          ? snapshot.id
          : readString(data['rewardId']),
      name: readString(data['name']),
      type: readString(data['type']).toLowerCase(),
      source: readString(data['source']),
      sourceId: readString(data['sourceId']),
      specialMonth: readInt(data['specialMonth']),
      specialYear: readInt(data['specialYear']),
    );
  }
}

class GarageScreen extends StatefulWidget {
  const GarageScreen({super.key});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  String get _currentUserId =>
      FirebaseAuth.instance.currentUser?.uid.trim() ?? '';
  String? _lastSyncedBikeSignature;
  bool _digitalTwinSyncScheduled = false;

  // Garage removes only its Flutter-side 3D owner while a 3D subpage is open.
  // The native interactive_3d plugin now keeps one persistent renderer alive,
  // so this does NOT destroy/recreate Filament.
  bool _suspendGarage3d = false;

  Stream<List<_CosmeticUnlock>> _watchCosmeticUnlocks() {
    final uid = _currentUserId;

    if (uid.isEmpty) {
      return Stream<List<_CosmeticUnlock>>.value(
        const <_CosmeticUnlock>[],
      );
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('cosmeticUnlocks')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(_CosmeticUnlock.fromFirestore)
              .toList(growable: false),
        );
  }

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
      bike.effectiveActiveSkin,
      bike.effectiveActiveFrameId,
      bike.effectiveFrameColor,
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

  Future<void> _setGarage3dSuspended(bool value) async {
    if (!mounted || _suspendGarage3d == value) {
      return;
    }

    setState(() {
      _suspendGarage3d = value;
    });

    // Wait until Flutter has actually removed Munja3DBikeViewer from the tree.
    await WidgetsBinding.instance.endOfFrame;

    if (!mounted) {
      return;
    }

    // One extra event-loop turn is enough for the old Flutter owner to detach.
    // Native Filament remains persistent inside interactive_3d.
    if (value) {
      await Future<void>.delayed(
        const Duration(milliseconds: 40),
      );
    }
  }

  Future<T?> _pushWithGarage3dSuspended<T>(
    BuildContext context,
    Route<T> route,
  ) async {
    await _setGarage3dSuspended(true);

    if (!mounted || !context.mounted) {
      return null;
    }

    try {
      return await Navigator.of(context).push<T>(route);
    } finally {
      if (mounted) {
        // The pushed route has been popped. Reattach Garage to the persistent
        // native texture after Flutter completes the pop frame.
        await WidgetsBinding.instance.endOfFrame;

        if (mounted) {
          await _setGarage3dSuspended(false);
        }
      }
    }
  }

  Future<void> _openCustomize(
    BuildContext context,
    FirestoreBike bike,
  ) async {
    await _pushWithGarage3dSuspended<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BikeCustomizeScreen(
          bike: bike,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Firestore is the source of truth for frame, skin and frame color.
    // Refresh the bike snapshot when returning from Customize so Garage
    // immediately renders the same Digital Twin configuration.
    await context.read<BikeProvider>().refresh();
  }

  Future<void> _openProducts(
    BuildContext context,
    FirestoreBike bike,
  ) async {
    await _pushWithGarage3dSuspended<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BikeProductsScreen(
          bike: bike,
        ),
      ),
    );
  }

  Future<void> _openDevices(
    BuildContext context,
    FirestoreBike bike,
  ) async {
    await _pushWithGarage3dSuspended<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => BikeDevicesScreen(
          bike: bike,
        ),
      ),
    );
  }

  Future<void> _openBikeInfo(
    BuildContext context,
    FirestoreBike bike,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => BikeInfoScreen(
          bike: bike,
          onEdit: () {
            Navigator.of(context).pop();
            Future.microtask(
              () => _openBikeEditor(
                context,
                bike: bike,
              ),
            );
          },
        ),
      ),
    );
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
            bike == null ? AppText.t('bikeCreated') : AppText.t('bikeUpdated'),
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
        provider.errorMessage ?? AppText.t('bikeCouldNotActivate'),
      );
    }
  }

  Future<void> _deleteBike(BuildContext context, FirestoreBike bike) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: MunjaColors.panel,
          title: Text(
            AppText.t('deleteBike'),
            style: TextStyle(
              color: MunjaColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            '${AppText.t('confirmDeleteBike')} "${bike.displayName}"?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(AppText.t('cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                AppText.t('delete'),
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
        provider.errorMessage ?? AppText.t('bikeCouldNotDelete'),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(AppText.t('bikeDeleted'))));
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<_CosmeticUnlock>>(
      stream: _watchCosmeticUnlocks(),
      initialData: const <_CosmeticUnlock>[],
      builder: (
        context,
        unlockSnapshot,
      ) {
        final cosmeticUnlocks =
            unlockSnapshot.data ??
                const <_CosmeticUnlock>[];

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
                padding: const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  360,
                ),
                children: [
                  _GarageHeader(
                    bikesCount: bikes.length,
                    busy: provider.isCreating,
                    onAddBike: () => _openBikeEditor(context),
                  ),
                  if (cosmeticUnlocks.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _UnlockedRewardsCard(
                      unlocks: cosmeticUnlocks,
                      onCustomize: activeBike == null
                          ? null
                          : () => _openCustomize(
                                context,
                                activeBike,
                              ),
                    ),
                  ],
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
                        suspend3d: _suspendGarage3d,
                        onCustomize: () =>
                            _openCustomize(context, activeBike),
                        onProducts: () =>
                            _openProducts(context, activeBike),
                        onDevices: () =>
                            _openDevices(context, activeBike),
                        onBikeInfo: () =>
                            _openBikeInfo(context, activeBike),
                        onEdit: () =>
                            _openBikeEditor(context, bike: activeBike),
                      ),
                      const SizedBox(height: 18),
                    ],
                    Row(
                      children: [
                        Text(
                          AppText.t('myBikes').toUpperCase(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.44),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.7,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'SWIPE',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.22),
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 146,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        itemCount: bikes.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, itemIndex) {
                          if (itemIndex == bikes.length) {
                            return _GarageAddBikeTile(
                              busy: provider.isCreating,
                              onTap: () => _openBikeEditor(context),
                            );
                          }

                          final bike = bikes[itemIndex];

                          return _GarageBikeTile(
                            bike: bike,
                            busy: provider.isBusy,
                            onTap: () => bike.active
                                ? _openBikeEditor(context, bike: bike)
                                : _setActiveBike(context, bike),
                            onMore: () => _openBikeEditor(
                              context,
                              bike: bike,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
          },
        );
      },
    );
  }
}

class _UnlockedRewardsCard extends StatelessWidget {
  const _UnlockedRewardsCard({
    required this.unlocks,
    required this.onCustomize,
  });

  final List<_CosmeticUnlock> unlocks;
  final VoidCallback? onCustomize;

  @override
  Widget build(BuildContext context) {
    final recent = unlocks.take(3).toList(growable: false);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: MunjaColors.mint,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppText.t('unlockedRewardsCaps'),
                  style: TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              Text(
                '${unlocks.length}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recent.map(
            (unlock) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _UnlockedRewardRow(
                unlock: unlock,
              ),
            ),
          ),
          if (onCustomize != null) ...[
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onCustomize,
                icon: const Icon(
                  Icons.palette_rounded,
                ),
                label: Text(
                  AppText.t('openCustomizeCaps'),
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _UnlockedRewardRow extends StatelessWidget {
  const _UnlockedRewardRow({
    required this.unlock,
  });

  final _CosmeticUnlock unlock;

  @override
  Widget build(BuildContext context) {
    final icon = unlock.isFrame
        ? Icons.crop_free_rounded
        : unlock.isSkin
            ? Icons.palette_rounded
            : Icons.workspace_premium_rounded;

    final typeLabel = unlock.type.isEmpty
        ? 'REWARD'
        : unlock.type.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: MunjaColors.mint,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unlock.name.isEmpty
                      ? unlock.rewardId
                      : unlock.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  typeLabel,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.lock_open_rounded,
            color: MunjaColors.mint,
            size: 18,
          ),
        ],
      ),
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
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'GARAGE',
                style: TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                AppText.t('garage'),
                style: const TextStyle(
                  color: MunjaColors.text,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                bikesCount == 1
                    ? AppText.t('yourDigitalTwin')
                    : '$bikesCount ${AppText.t('bikes').toLowerCase()} · Digital Twin Garage',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.43),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : onAddBike,
            customBorder: const CircleBorder(),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(
                  color: MunjaColors.mint.withValues(alpha: 0.22),
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
                      size: 27,
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
    required this.suspend3d,
    required this.onCustomize,
    required this.onProducts,
    required this.onDevices,
    required this.onBikeInfo,
    required this.onEdit,
  });

  final FirestoreBike bike;
  final bool busy;
  final DigitalTwinProvider digitalTwinProvider;
  final bool suspend3d;
  final VoidCallback onCustomize;
  final VoidCallback onProducts;
  final VoidCallback onDevices;
  final VoidCallback onBikeInfo;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final connected = digitalTwinProvider.connectedProductCount;
    final products = digitalTwinProvider.productCount;
    final activeSkinPreviewAsset = _garageSkinPreviewAsset(
      bike.effectiveActiveSkin,
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: MunjaColors.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _StatusBadge(
                icon: Icons.view_in_ar_rounded,
                label: 'DIGITAL TWIN',
              ),
              const Spacer(),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 11),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: MunjaColors.mint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Text(
                      'ACTIVE',
                      style: TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Container(
              height: 310,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (suspend3d)
                    const _Garage3dSuspendedPlaceholder()
                  else
                    Munja3DBikeViewer(
                      key: ValueKey<String>(
                        'garage-digital-twin-${bike.id}-'
                        '${bike.effectiveActiveFrameId}-'
                        '${bike.effectiveActiveSkin}-'
                        '${bike.effectiveFrameColor}',
                      ),
                      height: 310,
                      isLive: false,
                      brakeLightMounted: false,
                      showControls: true,
                      showSkinTester: false,
                      enableTouch: true,
                      autoRotate: false,
                      showroomSwing: true,
                      showroomSwingDegrees: 10.0,
                      showroomSwingDuration:
                          const Duration(milliseconds: 2600),
                      showroomSwingResumeDelay:
                          const Duration(seconds: 2),
                      useDigitalTwinMaterials: true,
                      activeSkinId: bike.effectiveActiveSkin.isEmpty
                          ? 'standard'
                          : bike.effectiveActiveSkin,
                      activeFrameId: bike.effectiveActiveFrameId.isEmpty
                          ? 'frame_1'
                          : bike.effectiveActiveFrameId,
                      frameColor: bike.effectiveFrameColor.isEmpty
                          ? '#9AA2A0'
                          : bike.effectiveFrameColor,
                    ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.touch_app_rounded,
                              color: MunjaColors.mint,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppText.t('showroomDrag360Caps'),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.58),
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _bikeDescription(bike),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.46),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: busy ? null : onEdit,
                tooltip: AppText.t('editBike'),
                icon: const Icon(Icons.more_horiz_rounded),
                color: Colors.white54,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Primary action: premium entrance to the Digital Twin world.
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: busy ? null : onCustomize,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 17, 16, 17),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      MunjaColors.mint.withValues(alpha: 0.16),
                      const Color(0xFF07130F).withValues(alpha: 0.96),
                      const Color(0xFF03100D),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.24),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MunjaColors.mint.withValues(alpha: 0.10),
                      blurRadius: 24,
                      spreadRadius: -6,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.055),
                            Colors.black.withValues(alpha: 0.18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.055),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(13),
                        child: Image.asset(
                          activeSkinPreviewAsset,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.black.withValues(alpha: 0.16),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.pedal_bike_rounded,
                                color: MunjaColors.mint,
                                size: 28,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppText.t('customizeDigitalTwinCaps'),
                            style: TextStyle(
                              color: MunjaColors.mint,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.15,
                            ),
                          ),
                          SizedBox(height: 5),
                          Text(
                            AppText.t('makeBikeYours'),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.15,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            AppText.t('framesSkinsColors'),
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: MunjaColors.mint.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_rounded,
                        color: MunjaColors.mint,
                        size: 23,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 11),

          // Only the two secondary actions that matter on the Garage home.
          Row(
            children: [
              Expanded(
                child: _GarageQuickAction(
                  icon: Icons.bluetooth_connected_rounded,
                  title: 'Devices',
                  subtitle: connected > 0
                      ? '$connected ${AppText.t('connected').toLowerCase()}'
                      : AppText.t('connectGear'),
                  onTap: onDevices,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _GarageQuickAction(
                  icon: Icons.info_outline_rounded,
                  title: AppText.t('bikeInfo'),
                  subtitle: AppText.t('detailsAndSetup'),
                  onTap: onBikeInfo,
                ),
              ),
            ],
          ),
          if (products > 0) ...[
            const SizedBox(height: 10),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onProducts,
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.extension_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 17,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '$products ${AppText.t('mounted').toLowerCase()} ${products == 1 ? AppText.t('product').toLowerCase() : AppText.t('products').toLowerCase()}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.48),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.35),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


class _Garage3dSuspendedPlaceholder extends StatelessWidget {
  const _Garage3dSuspendedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black12,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MunjaColors.mint.withValues(alpha: 0.08),
                border: Border.all(
                  color: MunjaColors.mint.withValues(alpha: 0.16),
                ),
              ),
              child: const Icon(
                Icons.pedal_bike_rounded,
                color: MunjaColors.mint,
                size: 27,
              ),
            ),
            const SizedBox(height: 11),
            const Text(
              'LOADING DIGITAL TWIN',
              style: TextStyle(
                color: MunjaColors.textSoft,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _garageSkinPreviewAsset(String skinId) {
  switch (skinId.trim().toLowerCase()) {
    case 'brushed_metal':
      return 'assets/Images/Customize/Skins/brushed_metal.png';
    case 'carbon_fibre':
      return 'assets/Images/Customize/Skins/carbon_fibre.png';
    case 'gold':
      return 'assets/Images/Customize/Skins/gold.png';
    case 'ice_silver':
      return 'assets/Images/Customize/Skins/ice_silver.png';
    case 'lava_red':
      return 'assets/Images/Customize/Skins/lava_red.png';
    case 'matt_black':
      return 'assets/Images/Customize/Skins/matt_black.png';
    case 'neon_green':
      return 'assets/Images/Customize/Skins/neon_green.png';
    case 'titanium':
      return 'assets/Images/Customize/Skins/titanium.png';
    case 'standard':
    default:
      return 'assets/Images/Customize/Skins/standard.png';
  }
}

class _GarageQuickAction extends StatelessWidget {
  const _GarageQuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 78,
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: MunjaColors.mint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.37),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.28),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GarageOverviewStrip extends StatelessWidget {
  const _GarageOverviewStrip({
    required this.productCount,
    required this.connectedProductCount,
    required this.firmwareUpdateCount,
    required this.wheelSize,
  });

  final int productCount;
  final int connectedProductCount;
  final int firmwareUpdateCount;
  final String wheelSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(21),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.055),
        ),
      ),
      child: Row(
        children: [
          _GarageMetric(label: 'Produkter', value: '$productCount'),
          _GarageMetricDivider(),
          _GarageMetric(
            label: 'Forbundet',
            value: '$connectedProductCount',
          ),
          _GarageMetricDivider(),
          _GarageMetric(
            label: 'Firmware',
            value: firmwareUpdateCount > 0
                ? '$firmwareUpdateCount ny'
                : 'OK',
            active: firmwareUpdateCount == 0,
          ),
          _GarageMetricDivider(),
          _GarageMetric(
            label: 'Hjul',
            value: wheelSize.trim().isEmpty ? '—' : wheelSize,
          ),
        ],
      ),
    );
  }
}

class _GarageMetric extends StatelessWidget {
  const _GarageMetric({
    required this.label,
    required this.value,
    this.active = false,
  });

  final String label;
  final String value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.34),
              fontSize: 7.5,
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
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _GarageMetricDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 28,
      color: Colors.white.withValues(alpha: 0.07),
    );
  }
}

class _QuickSkinSelector extends StatelessWidget {
  const _QuickSkinSelector({
    required this.selectedSkinId,
    required this.loading,
    required this.disabled,
    required this.onSelected,
  });

  final String selectedSkinId;
  final bool loading;
  final bool disabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: MunjaColors.mint.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.palette_outlined,
                color: MunjaColors.mint,
                size: 19,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppText.t('skinsQuickTestCaps'),
                  style: TextStyle(
                    color: MunjaColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MunjaColors.mint,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _QuickSkinTile(
                  id: 'standard',
                  label: 'Standard',
                  subtitle: 'Original',
                  selected: selectedSkinId == 'standard',
                  disabled: disabled || loading,
                  previewColor: const Color(0xFF9AA2A0),
                  onTap: onSelected,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _QuickSkinTile(
                  id: 'forest',
                  label: 'Forest',
                  subtitle: AppText.t('newFrame'),
                  selected: selectedSkinId == 'forest',
                  disabled: disabled || loading,
                  previewColor: const Color(0xFF176B4A),
                  onTap: onSelected,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickSkinTile extends StatelessWidget {
  const _QuickSkinTile({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.disabled,
    required this.previewColor,
    required this.onTap,
  });

  final String id;
  final String label;
  final String subtitle;
  final bool selected;
  final bool disabled;
  final Color previewColor;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : () => onTap(id),
        borderRadius: BorderRadius.circular(19),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected
                ? MunjaColors.mint.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected
                  ? MunjaColors.mintStrong
                  : Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: previewColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: previewColor.withValues(alpha: 0.30),
                      blurRadius: 14,
                    ),
                  ],
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 19,
                      )
                    : null,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected
                            ? MunjaColors.mint
                            : Colors.white.withValues(alpha: 0.42),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        child: Row(
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
              AppText.t('initializingDigitalTwin'),
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
          label: enabled && hasModel ? AppText.t('digitalTwinReady') : AppText.t('no3dModel'),
          active: enabled && hasModel,
        ),
        _TwinMetricBadge(
          icon: Icons.extension_rounded,
          label: '$productCount ${AppText.t('products').toLowerCase()}',
          active: productCount > 0,
        ),
        _TwinMetricBadge(
          icon: Icons.bluetooth_connected_rounded,
          label: '$connectedProductCount ${AppText.t('connected').toLowerCase()}',
          active: connectedProductCount > 0,
        ),
        if (firmwareUpdateCount > 0)
          _TwinMetricBadge(
            icon: Icons.system_update_rounded,
            label: '$firmwareUpdateCount ${AppText.t('update').toLowerCase()}',
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

class _GarageBikeTile extends StatelessWidget {
  const _GarageBikeTile({
    required this.bike,
    required this.busy,
    required this.onTap,
    required this.onMore,
  });

  final FirestoreBike bike;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 158,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: bike.active
                  ? MunjaColors.mint.withValues(alpha: 0.11)
                  : MunjaColors.panel.withValues(alpha: 0.64),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: bike.active
                    ? MunjaColors.mint.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.07),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        _bikeIcon(bike.type),
                        color: bike.active
                            ? MunjaColors.mint
                            : Colors.white54,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    if (bike.active)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: MunjaColors.mint,
                        size: 21,
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: busy ? null : onMore,
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 19,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  bike.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _bikeDescription(bike),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.40),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
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

class _GarageAddBikeTile extends StatelessWidget {
  const _GarageAddBikeTile({
    required this.busy,
    required this.onTap,
  });

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 110,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            decoration: BoxDecoration(
              color: MunjaColors.panel.withValues(alpha: 0.48),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                busy
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MunjaColors.mint,
                        ),
                      )
                    : const Icon(
                        Icons.add_circle_rounded,
                        color: MunjaColors.mint,
                        size: 31,
                      ),
                const SizedBox(height: 10),
                Text(
                  AppText.t('addBike'),
                  style: TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
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
              child: Text(
                AppText.t('activate'),
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
              PopupMenuItem<String>(
                value: 'edit',
                child: Text(AppText.t('edit')),
              ),
              if (!bike.active)
                PopupMenuItem<String>(
                  value: 'activate',
                  child: Text(AppText.t('makeActive')),
                ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(AppText.t('delete'), style: const TextStyle(color: Colors.redAccent)),
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
                title: Text(
                  AppText.t('chooseFromGallery'),
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
                title: Text(
                  AppText.t('takePhoto'),
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
        SnackBar(
          content: Text(AppText.t('imageCouldNotBeSelected')),
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
          SnackBar(
            content: Text(AppText.t('3dFileCouldNotOpen')),
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
        SnackBar(
          content: Text(AppText.t('3dModelCouldNotBeSelected')),
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
          content: Text(provider.errorMessage ?? AppText.t('bikeCouldNotSave')),
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
                AppText.t('bikeSavedFileProcessFailed'),
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
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(
                bottom: 360,
              ),
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
                        _editing ? AppText.t('editBike') : AppText.t('addBike'),
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
                  AppText.t('bikeFirebaseSyncInfo'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.50),
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                _TextField(
                  controller: _nameController,
                  label: AppText.t('bikeName'),
                  icon: Icons.directions_bike_rounded,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return AppText.t('enterBikeName');
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
                        label: AppText.t('brand'),
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
                        label: AppText.t('color'),
                        icon: Icons.palette_outlined,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _TextField(
                        controller: _wheelSizeController,
                        label: AppText.t('wheelSize'),
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
                        label: AppText.t('frameSize'),
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
                  label: AppText.t('notes'),
                  icon: Icons.notes_rounded,
                  maxLines: 3,
                ),
                const SizedBox(height: 14),
                _SwitchTile(
                  title: AppText.t('digitalTwin'),
                  subtitle: AppText.t('enableDigitalBike3d'),
                  value: _digitalTwinEnabled,
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() => _digitalTwinEnabled = value);
                        },
                ),
                const SizedBox(height: 10),
                _SwitchTile(
                  title: AppText.t('activeBike'),
                  subtitle: AppText.t('useAsPrimaryBike'),
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
                          ? AppText.t('saveChanges')
                          : AppText.t('createBike'),
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
          ? AppText.t('newImageReadyUpload')
          : _hasExistingImage
          ? AppText.t('imageSavedFirebase')
          : AppText.t('addImageCameraGallery'),
      actionLabel: _hasPendingImage || _hasExistingImage
          ? AppText.t('changeImage')
          : AppText.t('chooseImage'),
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
      title: AppText.t('threeDDigitalTwin'),
      subtitle: _hasPendingModel
          ? pendingModelName!
          : _hasExistingModel
          ? AppText.t('glbModelConnected')
          : AppText.t('chooseGlbGltfModel'),
      actionLabel: hasModel ? AppText.t('changeModel') : AppText.t('choose3dModel'),
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
                    hasModel ? AppText.t('digitalTwinReadyCaps') : AppText.t('noModelCaps'),
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
                        : AppText.t('supportsGlbGltf'),
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
              '${AppText.t('uploading')} ${(normalizedProgress * 100).round()}%',
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
                busy ? AppText.t('creating') : AppText.t('addBike'),
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
          Text(
            AppText.t('garageEmpty'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppText.t('addFirstBikeSync'),
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
            tooltip: AppText.t('tryAgain'),
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: MunjaColors.mint),
          const SizedBox(height: 16),
          Text(
            AppText.t('loadingYourBikes'),
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
      return AppText.t('kidsBike');
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
