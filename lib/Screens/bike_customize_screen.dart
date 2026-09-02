    import 'dart:async';
    import 'dart:math' as math;

    import 'package:flutter/material.dart';
    import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
    import 'package:interactive_3d/interactive_3d.dart';

    import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';
    import '../models/firestore_bike.dart';
import '../models/firestore_user.dart';
    import '../services/firestore_bike_service.dart';
import '../services/firestore_skin_entitlement_service.dart';
    import '../services/storage_service.dart';
    import '../widgets/munja_3d_bike_viewer.dart';
import '../widgets/skin_unlock_celebration.dart';
    import '../widgets/munja_subpage_header.dart';

    class BikeCustomizeScreen extends StatefulWidget {
      const BikeCustomizeScreen({
        super.key,
        required this.bike,
      });

      final FirestoreBike bike;

      @override
      State<BikeCustomizeScreen> createState() =>
          _BikeCustomizeScreenState();
    }

    class _BikeCustomizeScreenState
        extends State<BikeCustomizeScreen> {
      static const double bottomWheelSafePadding = 205;

      // Premium skins can be previewed on the real 3D bike before unlock.
      // Persistence is controlled by Firestore ownership / Pro / reward entitlement.
      static const bool _premiumPreviewEnabled = true;

      static const String _masterModelPath =
          'assets/models/kids_mtb_master.glb';

      // Customize uses a calmer native showroom motion than Home/Garage so
      // skins and frames remain easy to inspect while the bike still feels alive.
      static const double _customizeShowroomAmplitudeDegrees = 9.0;
      static const Duration _customizeShowroomCycleDuration =
          Duration(milliseconds: 3000);
      static const Duration _customizeShowroomResumeDelay =
          Duration(seconds: 2);

      String _selectedSkinId = 'standard';
      _CustomizeCategory _selectedCategory =
          _CustomizeCategory.skins;

      bool _loadingSkin = true;
      bool _savingSkin = false;

      FirestoreUser? _entitlementUser;
      bool _loadingEntitlements = true;
      String? _unlockingSkinId;
      String? _unlockingFrameId;
      Set<String> _ownedFrameIds = <String>{'frame_1'};

      // Monthly Special / reward cosmetics are stored separately from normal
      // Crystal purchases. We merge them into the same ownership checks so
      // existing Customize UI automatically treats reward skins/frames as owned.
      Set<String> _rewardOwnedFrameIds = <String>{};
      Set<String> _rewardOwnedSkinIds = <String>{};
      Set<String> _rewardOwnedBadgeIds = <String>{};

      StreamSubscription<FirestoreUser?>? _entitlementSubscription;
      StreamSubscription<Set<String>>? _frameEntitlementSubscription;
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
          _cosmeticUnlockSubscription;

      // Full-screen reward animation shown only after a NEW Crystal skin
      // purchase succeeds. Already-owned skins do not trigger it.
      String? _celebrationSkinName;
      Color? _celebrationAccentColor;
      String _celebrationHeadline = 'NEW SKIN UNLOCKED';
      String _celebrationSubtitle = 'Equipped on your Digital Twin';
      int _celebrationSequence = 0;

      final Interactive3dController _frameController =
          Interactive3dController();

      String _selectedFrameId = 'frame_1';
      String _activeFrameId = 'frame_1';
      bool _switchingFrame = false;
      bool _masterFrameReady = false;
      bool _isPreviewInteracting = false;
      final ValueNotifier<double> _showroomStageAngle = ValueNotifier<double>(0.0);

      static const List<_FrameVariantOption> _frameVariants =
          <_FrameVariantOption>[
        _FrameVariantOption(
          id: 'frame_1',
          title: 'frameTrail',
          entityName: 'Frame 1',
          crystalPrice: 0,
          included: true,
        ),
        _FrameVariantOption(
          id: 'frame_2',
          title: 'frameEnduro',
          entityName: 'FRAME 2',
          crystalPrice: 450,
        ),
        _FrameVariantOption(
          id: 'frame_3',
          title: 'frameRace',
          entityName: 'FRAME 3',
          crystalPrice: 550,
        ),
        _FrameVariantOption(
          id: 'frame_4',
          title: 'frameUrban',
          entityName: 'frame 4',
          crystalPrice: 400,
        ),
      ];

      static const List<String> _nativeFrameEntityNames = <String>[
        'Frame 1',
        'FRAME 2',
        'FRAME 3',
        'frame 4',
      ];


      // ---------------------------------------------------------------------
      // MONTHLY SPECIAL REWARD -> CURRENT CUSTOMIZE ASSET MAPPING
      // ---------------------------------------------------------------------
      //
      // MonthlySpecialService stores stable reward IDs in:
      // users/{uid}/cosmeticUnlocks/{rewardId}
      //
      // The current Customize engine uses local frame_1..frame_4 geometry and
      // embedded skin material IDs. Until the remote content catalog is added,
      // these maps bridge the stable reward IDs to the assets already available
      // in the current master GLB.
      //
      // IMPORTANT: changing a value here changes WHICH existing cosmetic the
      // reward unlocks, but does not invalidate historical reward documents.
      static const Map<String, String> _monthlyRewardFrameMap =
          <String, String>{
        'monthly_february_frost_frame': 'frame_2',
        'monthly_may_endurance_frame': 'frame_3',
        'monthly_august_neon_frame': 'frame_3',
        'monthly_october_night_frame': 'frame_2',
      };

      static const Map<String, String> _monthlyRewardSkinMap =
          <String, String>{
        'monthly_march_spring_skin': 'neon_green',
        'monthly_june_summer_skin': 'gold',
        'monthly_september_streak_skin': 'titanium',
        'monthly_december_finale_skin': 'lava_red',
      };

      // ---------------------------------------------------------------------
      // MUNJA V1 SKIN ENGINE - ALL 4 FRAMES
      // ---------------------------------------------------------------------
      //
      // Frame and skin are now two separate concepts:
      // - Frame = geometry / bike shape.
      // - Frame color = free base-color customization.
      // - Skin = a REAL MaterialInstance already embedded in the Master GLB.
      //
      // The exact Frame 1 MaterialInstance names below come from the Blender/GLB
      // master exported by the 3D artist. We deliberately keep the strings exact,
      // including spaces and capitalization.
      //
      // All four native frame entities use their matching embedded MaterialInstances.
      //
      // Thumbnail masters live in assets/Images/Customize/Skins/.
      // Frame 1 is intentionally the common thumbnail geometry for all skins.
      // The live 3D preview remains the source of truth for skin + frame.
      static const List<_SkinOption> _skins = <_SkinOption>[
        _SkinOption(
          id: 'standard',
          title: 'skinStandard',
          subtitle: 'skinStandardSubtitle',
          previewColor: Color(0xFF9AA2A0),
          modelPath: _masterModelPath,
          access: _SkinAccess.owned,
          visibleInCarousel: true,
          previewAsset: 'assets/Images/Customize/Skins/standard.png',
          storeSku: 'munja.skin.standard',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Standard_Frame 1',
            'frame_2': 'Standard_Texture_Frame 2',
            'frame_3': 'Standard_Texture_Frame 3',
            'frame_4': 'Standard_Texture_Frame 4',
          },
        ),
        _SkinOption(
          id: 'brushed_metal',
          title: 'skinBrushedMetal',
          subtitle: 'skinPremiumMetal',
          previewColor: Color(0xFF8E9699),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 300,
          previewAsset: 'assets/Images/Customize/Skins/brushed_metal.png',
          storeSku: 'munja.skin.brushed_metal',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Brushed_Metal_Frame 1',
            'frame_2': 'Brushed_Metal_Frame 2',
            'frame_3': 'Brushed_Metal_Frame 3',
            'frame_4': 'Brushed_Metal_Frame 4',
          },
        ),
        _SkinOption(
          id: 'carbon_fibre',
          title: 'skinCarbonFibre',
          subtitle: 'skinPremiumCarbon',
          previewColor: Color(0xFF252A2C),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 350,
          previewAsset: 'assets/Images/Customize/Skins/carbon_fibre.png',
          storeSku: 'munja.skin.carbon_fibre',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Carbon_Fibre_Frame 1',
            'frame_2': 'Carbon_Fibre_Frame 2',
            'frame_3': 'Carbon_Fibre_Frame 3',
            'frame_4': 'Carbon_Fibre_Frame 4',
          },
        ),
        _SkinOption(
          id: 'gold',
          title: 'skinGold',
          subtitle: 'skinPremiumFinish',
          previewColor: Color(0xFFD6A93A),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 500,
          previewAsset: 'assets/Images/Customize/Skins/gold.png',
          storeSku: 'munja.skin.gold',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Gold_frame 1',
            'frame_2': 'Gold_Frame 2',
            'frame_3': 'Gold_Frame 3',
            'frame_4': 'Gold_Frame 4',
          },
        ),
        _SkinOption(
          id: 'ice_silver',
          title: 'skinIceSilver',
          subtitle: 'skinColdMetallic',
          previewColor: Color(0xFFCFD8DC),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 400,
          previewAsset: 'assets/Images/Customize/Skins/ice_silver.png',
          storeSku: 'munja.skin.ice_silver',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Ice_Silver_Frame 1',
            'frame_2': 'Ice_Silver_Frame 2',
            'frame_3': 'Ice_Silver_Frame 3',
            'frame_4': 'Ice_Silver_Frame 4',
          },
        ),
        _SkinOption(
          id: 'lava_red',
          title: 'skinLavaRed',
          subtitle: 'skinPerformanceFinish',
          previewColor: Color(0xFFD94848),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 450,
          previewAsset: 'assets/Images/Customize/Skins/lava_red.png',
          storeSku: 'munja.skin.lava_red',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Lava_Red_Frame 1',
            'frame_2': 'Lava_Red_Frame 2',
            'frame_3': 'Lava_Red_Frame 3',
            'frame_4': 'Lava_Red_Frame 4',
          },
        ),
        _SkinOption(
          id: 'matt_black',
          title: 'skinMattBlack',
          subtitle: 'skinStealthFinish',
          previewColor: Color(0xFF111111),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 250,
          previewAsset: 'assets/Images/Customize/Skins/matt_black.png',
          storeSku: 'munja.skin.matt_black',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Matt_Black_Frame 1',
            'frame_2': 'Matt_Black_Frame 2',
            'frame_3': 'Matt_Black_Frame 3',
            'frame_4': 'Matt_Black_Frame 4',
          },
        ),
        _SkinOption(
          id: 'neon_green',
          title: 'skinNeonGreen',
          subtitle: 'skinElectricFinish',
          previewColor: Color(0xFF39FF88),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 450,
          previewAsset: 'assets/Images/Customize/Skins/neon_green.png',
          storeSku: 'munja.skin.neon_green',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Neon_Green_Frame 1',
            'frame_2': 'Neon_Green_frame 2',
            'frame_3': 'Neon_Green_Frame 3',
            'frame_4': 'Neon_Green_Frame 4',
          },
        ),
        _SkinOption(
          id: 'titanium',
          title: 'skinTitanium',
          subtitle: 'skinEliteMetal',
          previewColor: Color(0xFF76838B),
          modelPath: _masterModelPath,
          access: _SkinAccess.crystals,
          crystalPrice: 550,
          previewAsset: 'assets/Images/Customize/Skins/titanium.png',
          storeSku: 'munja.skin.titanium',
          materialInstanceByFrameId: <String, String>{
            'frame_1': 'Titanium_Frame_1',
            'frame_2': 'Titanium_Frame_2',
            'frame_3': 'Titanium_Metal_Frame 3',
            'frame_4': 'Titanium_Frame 4',
          },
        ),
      ];

      @override
      void initState() {
        super.initState();
        AppText.localeNotifier.addListener(_handleLocaleChanged);

        // Firestore Digital Twin is the shared source of truth for the selected
        // frame. Resolve it before the 3D model is initialized so the first
        // master-model apply opens on the user's saved frame instead of always
        // falling back to Frame 1.
        final savedFrameId = widget.bike.effectiveActiveFrameId.trim();
        final initialFrameId = _frameVariants.any(
          (frame) => frame.id == savedFrameId,
        )
            ? savedFrameId
            : 'frame_1';

        _selectedFrameId = initialFrameId;
        _activeFrameId = initialFrameId;

        unawaited(_initializeEntitlementsAndSkin());
      }

      void _handleLocaleChanged() {
        if (mounted) {
          setState(() {});
        }
      }

      @override
      void dispose() {
        AppText.localeNotifier.removeListener(_handleLocaleChanged);
        unawaited(_entitlementSubscription?.cancel());
        unawaited(_frameEntitlementSubscription?.cancel());
        unawaited(_cosmeticUnlockSubscription?.cancel());

        // Do not send native Interactive3d commands from dispose().
        // The controller can already be detached while Navigator is removing
        // this route. The shared native renderer keeps its current state and
        // the next visible Digital Twin owner will apply the correct setup.
        _showroomStageAngle.dispose();
        super.dispose();
      }

      Future<void> _initializeEntitlementsAndSkin() async {
        await _refreshEntitlementUser();

        if (!mounted) {
          return;
        }

        _startEntitlementWatch();
        _startFrameEntitlementWatch();
        _startCosmeticUnlockWatch();
        await _loadSelectedSkin();
      }

      Future<void> _refreshEntitlementUser() async {
        final ownerId = widget.bike.ownerId.trim();

        if (ownerId.isEmpty) {
          if (!mounted) return;

          setState(() {
            _entitlementUser = null;
            _loadingEntitlements = false;
          });
          return;
        }

        try {
          final user =
              await FirestoreSkinEntitlementService.instance.getUser(ownerId);

          if (!mounted) return;

          setState(() {
            _entitlementUser = user;
            _loadingEntitlements = false;
          });
        } catch (error, stackTrace) {
          debugPrint('BIKE CUSTOMIZE ENTITLEMENT LOAD ERROR: $error');
          debugPrint('$stackTrace');

          if (!mounted) return;

          setState(() {
            _entitlementUser = null;
            _loadingEntitlements = false;
          });
        }
      }

      void _startEntitlementWatch() {
        final ownerId = widget.bike.ownerId.trim();

        if (ownerId.isEmpty) {
          return;
        }

        unawaited(_entitlementSubscription?.cancel());

        _entitlementSubscription =
            FirestoreSkinEntitlementService.instance.watchUser(ownerId).listen(
          (user) {
            if (!mounted) return;

            setState(() {
              _entitlementUser = user;
              _loadingEntitlements = false;
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('BIKE CUSTOMIZE ENTITLEMENT WATCH ERROR: $error');
            debugPrint('$stackTrace');
          },
        );
      }

      void _startFrameEntitlementWatch() {
        final ownerId = widget.bike.ownerId.trim();

        if (ownerId.isEmpty) {
          if (mounted) {
            setState(() {
              _ownedFrameIds = <String>{'frame_1'};
            });
          }
          return;
        }

        unawaited(_frameEntitlementSubscription?.cancel());

        _frameEntitlementSubscription =
            FirestoreSkinEntitlementService.instance
                .watchOwnedFrameIds(ownerId)
                .listen(
          (ownedFrameIds) {
            if (!mounted) return;

            setState(() {
              _ownedFrameIds = <String>{
                'frame_1',
                ...ownedFrameIds,
              };
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            debugPrint('BIKE CUSTOMIZE FRAME ENTITLEMENT WATCH ERROR: $error');
            debugPrint('$stackTrace');
          },
        );
      }

      void _startCosmeticUnlockWatch() {
        final ownerId = widget.bike.ownerId.trim();

        unawaited(
          _cosmeticUnlockSubscription?.cancel(),
        );
        _cosmeticUnlockSubscription = null;

        if (ownerId.isEmpty) {
          if (mounted) {
            setState(() {
              _rewardOwnedFrameIds = <String>{};
              _rewardOwnedSkinIds = <String>{};
              _rewardOwnedBadgeIds = <String>{};
            });
          }
          return;
        }

        _cosmeticUnlockSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('cosmeticUnlocks')
            .snapshots()
            .listen(
          (snapshot) {
            final rewardFrameIds = <String>{};
            final rewardSkinIds = <String>{};
            final rewardBadgeIds = <String>{};

            for (final document in snapshot.docs) {
              final data = document.data();

              final rewardId =
                  (data['rewardId']?.toString() ?? document.id)
                      .trim();

              final type =
                  (data['type']?.toString() ?? '')
                      .trim()
                      .toLowerCase();

              if (rewardId.isEmpty) {
                continue;
              }

              if (type == 'frame') {
                final mappedFrameId =
                    _monthlyRewardFrameMap[rewardId];

                if (mappedFrameId != null &&
                    mappedFrameId.isNotEmpty) {
                  rewardFrameIds.add(mappedFrameId);
                }
              } else if (type == 'skin') {
                final mappedSkinId =
                    _monthlyRewardSkinMap[rewardId];

                if (mappedSkinId != null &&
                    mappedSkinId.isNotEmpty) {
                  rewardSkinIds.add(mappedSkinId);
                }
              } else if (type == 'badge') {
                rewardBadgeIds.add(rewardId);
              }
            }

            if (!mounted) {
              return;
            }

            setState(() {
              _rewardOwnedFrameIds = rewardFrameIds;
              _rewardOwnedSkinIds = rewardSkinIds;
              _rewardOwnedBadgeIds = rewardBadgeIds;
            });

            debugPrint(
              'BIKE CUSTOMIZE MONTHLY REWARDS: '
              'frames=${rewardFrameIds.toList()} '
              'skins=${rewardSkinIds.toList()} '
              'badges=${rewardBadgeIds.toList()}',
            );
          },
          onError: (
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint(
              'BIKE CUSTOMIZE MONTHLY REWARD WATCH ERROR: $error',
            );
            debugPrint('$stackTrace');
          },
        );
      }

      bool _isFrameOwned(_FrameVariantOption frame) {
        return frame.included ||
            frame.id == 'frame_1' ||
            _ownedFrameIds.contains(frame.id) ||
            _rewardOwnedFrameIds.contains(frame.id);
      }

      bool _canAffordFrame(_FrameVariantOption frame) {
        return _crystalBalance >= frame.crystalPrice;
      }

      bool _isSkinUsable(_SkinOption skin) {
        if (skin.id == 'standard' ||
            skin.access == _SkinAccess.owned ||
            _rewardOwnedSkinIds.contains(skin.id)) {
          return true;
        }

        final user = _entitlementUser;

        if (user == null) {
          return false;
        }

        switch (skin.access) {
          case _SkinAccess.owned:
            return true;
          case _SkinAccess.crystals:
            return user.ownsSkin(skin.id) ||
                _rewardOwnedSkinIds.contains(skin.id);
          case _SkinAccess.pro:
            return user.isPremiumSubscription ||
                _rewardOwnedSkinIds.contains(skin.id);
          case _SkinAccess.locked:
            return user.hasUnlockedRewardSkin(skin.id) ||
                _rewardOwnedSkinIds.contains(skin.id);
        }
      }

      int get _crystalBalance => _entitlementUser?.crystalBalance ?? 0;

      bool _isMonthlyRewardFrame(String frameId) {
        return _rewardOwnedFrameIds.contains(frameId);
      }

      bool _isMonthlyRewardSkin(String skinId) {
        return _rewardOwnedSkinIds.contains(skinId);
      }

      bool _canAffordSkin(_SkinOption skin) {
        final price = skin.crystalPrice ?? 0;
        return price >= 0 && _crystalBalance >= price;
      }

      Future<void> _loadSelectedSkin() async {
        try {
          // Firestore is the shared source of truth between the app and website.
          // Prefer the Digital Twin skin stored on the bike document.
          var selectedSkinId = widget.bike.effectiveActiveSkin.trim();

          // Older bikes may not have a Digital Twin skin yet. Keep the local
          // preference as a compatibility fallback, then migrate it to Firestore
          // when possible.
          if (selectedSkinId.isEmpty) {
            final savedSkin =
                await StorageService.loadSelectedBikeSkin();

            selectedSkinId = savedSkin.trim();
          }

          final normalized = _skins.any(
            (skin) =>
                skin.id == selectedSkinId &&
                _isSkinUsable(skin),
          )
              ? selectedSkinId
              : 'standard';

          if (!mounted) {
            return;
          }

          setState(() {
            _selectedSkinId = normalized;
            _loadingSkin = false;
          });

          if (_skinUsesMasterModel(normalized)) {
            _scheduleMasterFrameApply();
          }

          // If this bike did not yet have a shared skin value, migrate the
          // resolved value so Munja Web can see the same Digital Twin choice.
          if (widget.bike.effectiveActiveSkin.trim().isEmpty) {
            try {
              await FirestoreBikeService.instance.updateActiveSkin(
                bikeId: widget.bike.id,
                activeSkinId: normalized,
              );
            } catch (error, stackTrace) {
              debugPrint(
                'BIKE CUSTOMIZE INITIAL SKIN SYNC ERROR: $error',
              );
              debugPrint('$stackTrace');
            }
          }
        } catch (error, stackTrace) {
          debugPrint(
            'BIKE CUSTOMIZE LOAD SKIN ERROR: $error',
          );
          debugPrint('$stackTrace');

          if (!mounted) {
            return;
          }

          setState(() {
            _selectedSkinId = 'standard';
            _loadingSkin = false;
          });
        }
      }

      bool _skinUsesMasterModel(String skinId) {
        final skin = _skinById(skinId);
        return skin?.modelPath == _masterModelPath;
      }

      _FrameVariantOption _frameById(String? frameId) {
        return _frameVariants.firstWhere(
          (frame) => frame.id == frameId,
          orElse: () => _frameVariants.first,
        );
      }

      Future<void> _ensureNativeModelReady() async {
        if (!mounted) return;

        await _frameController.waitUntilModelLoaded(
          timeout: const Duration(seconds: 20),
          pollInterval: const Duration(milliseconds: 50),
        );
      }

      Future<void> _startCustomizeNativeShowroom() async {
        if (!mounted || !_skinUsesMasterModel(_selectedSkinId)) {
          return;
        }

        try {
          await _frameController.startShowroomRotation(
            amplitudeDegrees: _customizeShowroomAmplitudeDegrees,
            cycleDuration: _customizeShowroomCycleDuration,
            resumeDelay: _customizeShowroomResumeDelay,
          );

          debugPrint(
            'BIKE CUSTOMIZE NATIVE SHOWROOM STARTED: '
            'amplitude=$_customizeShowroomAmplitudeDegrees° | '
            'duration=${_customizeShowroomCycleDuration.inMilliseconds}ms',
          );
        } catch (error, stackTrace) {
          debugPrint(
            'BIKE CUSTOMIZE NATIVE SHOWROOM START ERROR: $error',
          );
          debugPrint('$stackTrace');
        }
      }

      Future<void> _applySkinMaterialToFrame(
        _SkinOption skin,
        _FrameVariantOption targetFrame,
      ) async {
        if (!mounted) return;

        // Keep the proven reset-first sequence. Standard restores the original
        // embedded GLB material. Premium skins use real MaterialInstances.
        // Free frame colors are no longer part of Munja customization.
        await _frameController.resetEntityDirectMaterial(
          entityName: targetFrame.entityName,
        );

        if (skin.id == 'standard') {
          debugPrint(
            'BIKE CUSTOMIZE SKIN MATERIAL ACTIVE: '
            '${targetFrame.id} -> STANDARD ORIGINAL MATERIAL',
          );
          return;
        }

        final materialInstanceName =
            skin.materialInstanceForFrame(targetFrame.id);

        if (materialInstanceName == null || materialInstanceName.isEmpty) {
          throw StateError(
            'No verified GLB material mapping for ${skin.id} on ${targetFrame.id}',
          );
        }

        debugPrint(
          'BIKE CUSTOMIZE SKIN MATERIAL SEND: '
          '${skin.id} -> ${targetFrame.entityName} -> $materialInstanceName',
        );

        await _frameController.setEntityMaterialInstance(
          entityName: targetFrame.entityName,
          materialInstanceName: materialInstanceName,
        );

        debugPrint(
          'BIKE CUSTOMIZE SKIN MATERIAL ACTIVE: '
          '${skin.id} -> ${targetFrame.entityName} -> $materialInstanceName',
        );
      }

      Future<void> _applySkinVisual(
        _SkinOption skin, {
        bool preserveFrame = true,
      }) async {
        if (!_skinUsesMasterModel(skin.id)) {
          return;
        }

        final targetFrame = preserveFrame
            ? _frameById(_selectedFrameId)
            : _frameVariants.first;

        try {
          await _ensureNativeModelReady();

          if (!mounted) return;

          await _frameController.resetAllMaterialOverrides();

          await _frameController.setExclusiveEntityVisibility(
            entityNames: _nativeFrameEntityNames,
            activeEntityName: targetFrame.entityName,
          );

          if (!mounted) return;

          setState(() {
            _selectedFrameId = targetFrame.id;
            _masterFrameReady = true;
          });

          await _applySkinMaterialToFrame(
            skin,
            targetFrame,
          );

          if (!mounted) return;

          await _startCustomizeNativeShowroom();
        } catch (error, stackTrace) {
          debugPrint(
            'BIKE CUSTOMIZE REAL SKIN ERROR: '
            '${skin.id} -> ${targetFrame.id} -> $error',
          );
          debugPrint('$stackTrace');
          rethrow;
        }
      }

      void _scheduleMasterFrameApply() {
        if (!_skinUsesMasterModel(_selectedSkinId)) {
          return;
        }

        if (mounted) {
          setState(() {
            _masterFrameReady = false;
          });
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_skinUsesMasterModel(_selectedSkinId)) {
            return;
          }

          unawaited(
            _initializeMasterPreviewWhenReady(),
          );
        });
      }

      Future<void> _initializeMasterPreviewWhenReady() async {
        try {
          if (!mounted || !_skinUsesMasterModel(_selectedSkinId)) {
            return;
          }

          final activeSkin = _skinById(_selectedSkinId);
          if (activeSkin == null) return;

          await _applySkinVisual(
            activeSkin,
            preserveFrame: true,
          );

          if (!mounted) return;

          await _startCustomizeNativeShowroom();
        } on TimeoutException catch (error, stackTrace) {
          debugPrint('BIKE CUSTOMIZE MODEL READY TIMEOUT: $error');
          debugPrint('$stackTrace');

          if (!mounted) return;

          setState(() {
            _masterFrameReady = false;
          });
        } catch (error, stackTrace) {
          debugPrint('BIKE CUSTOMIZE MODEL READY INIT ERROR: $error');
          debugPrint('$stackTrace');

          if (!mounted) return;

          setState(() {
            _masterFrameReady = false;
          });
        }
      }

      Future<bool> _confirmFramePurchase(
        _FrameVariantOption frame,
      ) async {
        final price = frame.crystalPrice;
        final balanceAfter = _crystalBalance - price;
        final canAfford = _canAffordFrame(frame);

        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 22),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                decoration: BoxDecoration(
                  color: const Color(0xFF06110E),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MunjaColors.mint.withValues(alpha: 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: MunjaColors.mint.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.directions_bike_rounded,
                            color: MunjaColors.mint,
                            size: 25,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'UNLOCK FRAME',
                                style: TextStyle(
                                  color: MunjaColors.mint,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppText.t(frame.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          icon: const Icon(Icons.close_rounded),
                          color: Colors.white54,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          _PurchaseSummaryRow(
                            label: 'Frame price',
                            value: '$price Crystals',
                            valueColor: const Color(0xFF70D8FF),
                          ),
                          const SizedBox(height: 10),
                          _PurchaseSummaryRow(
                            label: 'Current balance',
                            value: '$_crystalBalance Crystals',
                          ),
                          const SizedBox(height: 10),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                          const SizedBox(height: 10),
                          _PurchaseSummaryRow(
                            label: 'Balance after',
                            value: canAfford
                                ? '$balanceAfter Crystals'
                                : 'Not enough',
                            valueColor: canAfford
                                ? MunjaColors.mint
                                : Colors.redAccent,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      canAfford
                          ? 'The frame will be unlocked permanently and equipped on this bike.'
                          : 'You do not have enough Munja Crystals for this frame.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.42),
                        fontSize: 10,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              minimumSize: const Size.fromHeight(46),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.10),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: canAfford
                                ? () => Navigator.of(dialogContext).pop(true)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor: MunjaColors.mint,
                              foregroundColor: MunjaColors.bg,
                              disabledBackgroundColor:
                                  Colors.white.withValues(alpha: 0.06),
                              disabledForegroundColor:
                                  Colors.white.withValues(alpha: 0.25),
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: Text(
                              canAfford
                                  ? 'UNLOCK · $price CRYSTALS'
                                  : 'NOT ENOUGH CRYSTALS',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.55,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

        return result ?? false;
      }

      Future<bool> _unlockFrameWithCrystals(
        _FrameVariantOption frame,
      ) async {
        final ownerId = widget.bike.ownerId.trim();

        if (ownerId.isEmpty) {
          return false;
        }

        setState(() {
          _switchingFrame = true;
          _unlockingFrameId = frame.id;
        });

        final result =
            await FirestoreSkinEntitlementService.instance
                .unlockFrameWithCrystals(
          uid: ownerId,
          frameId: frame.id,
          crystalPrice: frame.crystalPrice,
        );

        if (!mounted) return false;

        switch (result.status) {
          case FrameUnlockStatus.success:
          case FrameUnlockStatus.alreadyOwned:
            await _refreshEntitlementUser();

            if (!mounted) return false;

            setState(() {
              _ownedFrameIds = <String>{
                ..._ownedFrameIds,
                frame.id,
              };
              _switchingFrame = false;
              _unlockingFrameId = null;
            });

            if (result.status == FrameUnlockStatus.success) {
              // Same premium reward moment as a newly purchased skin.
              // Already-owned frames never trigger the celebration again.
              _showFrameUnlockCelebration(frame);
            }

            return true;

          case FrameUnlockStatus.insufficientCrystals:
            setState(() {
              _switchingFrame = false;
              _unlockingFrameId = null;
            });

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    'Not enough Munja Crystals · '
                    '${result.previousCrystalBalance ?? _crystalBalance} Crystals available',
                  ),
                ),
              );
            return false;

          case FrameUnlockStatus.userNotFound:
          case FrameUnlockStatus.invalidRequest:
          case FrameUnlockStatus.transactionFailed:
            setState(() {
              _switchingFrame = false;
              _unlockingFrameId = null;
            });

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Frame could not be unlocked. Try again.'),
                ),
              );
            return false;
        }
      }

      Future<void> _selectFrameVariant(
        String frameId,
      ) async {
        if (_switchingFrame || frameId == _selectedFrameId) {
          return;
        }

        final frame = _frameVariants.firstWhere(
          (item) => item.id == frameId,
          orElse: () => _frameVariants.first,
        );

        HapticFeedback.selectionClick();

        // Locked frames are FREE TO PREVIEW, just like premium skins.
        // Preview changes only the native 3D model and selected UI state.
        // It does NOT write activeFrameId to Firestore.
        if (!_isFrameOwned(frame)) {
          await _applyFrame(
            frameId,
            persist: false,
          );
          return;
        }

        // Owned frames can be activated immediately.
        await _applyFrame(
          frameId,
          persist: true,
        );
      }

      Future<void> _unlockSelectedFrame(String frameId) async {
        if (_switchingFrame || _loadingEntitlements) return;

        final frame = _frameVariants.firstWhere(
          (item) => item.id == frameId,
          orElse: () => _frameVariants.first,
        );

        if (_isFrameOwned(frame)) {
          if (_isMonthlyRewardFrame(frame.id)) {
            HapticFeedback.selectionClick();

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    '${AppText.t(frame.title)} · Monthly Special reward unlocked',
                  ),
                ),
              );
          }

          await _applyFrame(
            frame.id,
            persist: true,
          );
          return;
        }

        final confirmed = await _confirmFramePurchase(frame);

        if (!mounted || !confirmed) {
          return;
        }

        HapticFeedback.mediumImpact();

        final unlocked = await _unlockFrameWithCrystals(frame);

        if (!mounted || !unlocked) {
          return;
        }

        // A successfully purchased frame becomes the active frame.
        await _applyFrame(
          frame.id,
          persist: true,
        );
      }

      Future<void> _applyFrame(
        String frameId, {
        bool startup = false,
        bool persist = true,
      }) async {
        final selected = _frameVariants.firstWhere(
          (frame) => frame.id == frameId,
          orElse: () => _frameVariants.first,
        );

        if (!mounted || !_skinUsesMasterModel(_selectedSkinId)) {
          return;
        }

        setState(() {
          _switchingFrame = true;
        });

        try {
          await _ensureNativeModelReady();

          if (!mounted) return;

          await _frameController.setExclusiveEntityVisibility(
            entityNames: _nativeFrameEntityNames,
            activeEntityName: selected.entityName,
          );

          if (!mounted) return;

          final activeSkin =
              _skinById(_selectedSkinId) ?? _skinById('standard')!;

          setState(() {
            _selectedFrameId = selected.id;
            _masterFrameReady = true;
          });

          await _applySkinMaterialToFrame(activeSkin, selected);

          if (!mounted) return;

          // Keep Customize's native showroom motion alive after frame changes.
          // The native renderer still pauses automatically during finger input.
          await _startCustomizeNativeShowroom();

          // Save only when the frame is owned and the user is activating it.
          // Locked frames can be previewed without changing Firestore.
          if (!startup && persist) {
            await FirestoreBikeService.instance.updateActiveFrame(
              bikeId: widget.bike.id,
              activeFrameId: selected.id,
            );

            if (!mounted) return;

            setState(() {
              _activeFrameId = selected.id;
            });

            debugPrint(
              'BIKE CUSTOMIZE FRAME SYNCED: '
              '${selected.id} -> Firestore',
            );
          }

          debugPrint(
            persist
                ? 'BIKE CUSTOMIZE NATIVE FRAME ACTIVE: '
                    '${selected.id} -> ${selected.entityName}'
                : 'BIKE CUSTOMIZE NATIVE FRAME PREVIEW: '
                    '${selected.id} -> ${selected.entityName}',
          );
        } catch (error, stackTrace) {
          debugPrint('BIKE CUSTOMIZE NATIVE FRAME ERROR: $error');
          debugPrint('$stackTrace');

          if (mounted) {
            setState(() {
              _masterFrameReady = false;
            });

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(AppText.t('frameChangeFailed')),
                ),
              );
          }
        } finally {
          if (mounted) {
            setState(() {
              _switchingFrame = false;
            });
          }
        }
      }

      _SkinOption? _skinById(String skinId) {
        for (final skin in _skins) {
          if (skin.id == skinId) {
            return skin;
          }
        }
        return null;
      }

      bool _canPreviewSkin(_SkinOption skin) {
        if (_isSkinUsable(skin)) return true;

        return _premiumPreviewEnabled && _skinUsesMasterModel(skin.id);
      }

      bool _canPersistSkin(_SkinOption skin) => _isSkinUsable(skin);

      Future<bool> _showSkinAccessSheet(
        _SkinOption skin,
      ) async {
        if (!mounted) return false;

        final access = skin.access;

        final String eyebrow;
        final String title;
        final String description;
        final IconData icon;

        switch (access) {
          case _SkinAccess.crystals:
            eyebrow = 'MUNJA CRYSTALS';
            title = '${skin.crystalPrice ?? 0} Crystals';
            description = AppText.t('crystalSkinDescription');
            icon = Icons.diamond_outlined;
            break;
          case _SkinAccess.pro:
            eyebrow = 'MUNJA PRO';
            title = AppText.t('proExclusive');
            description = AppText.t('proSkinDescription');
            icon = Icons.workspace_premium_outlined;
            break;
          case _SkinAccess.locked:
            eyebrow = AppText.t('locked').toUpperCase();
            title = AppText.t('challengeReward');
            description = AppText.t('rewardSkinDescription');
            icon = Icons.lock_outline_rounded;
            break;
          case _SkinAccess.owned:
            return false;
        }

        final price = skin.crystalPrice ?? 0;
        final canUnlockWithCrystals =
            access == _SkinAccess.crystals &&
            !_loadingEntitlements &&
            _entitlementUser != null &&
            _canAffordSkin(skin);

        final result = await showModalBottomSheet<bool>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (sheetContext) {
            final media = MediaQuery.of(sheetContext);
            final wheelBottomSpace = media.viewPadding.bottom + 235.0;

            return Padding(
              padding: EdgeInsets.only(
               left: 14,
                right: 14,
                top: 14,
                bottom: wheelBottomSpace,
              ),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  decoration: BoxDecoration(
                    color: MunjaColors.panel,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: MunjaColors.mint.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
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
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: skin.previewColor,
                              borderRadius: BorderRadius.circular(17),
                              boxShadow: [
                                BoxShadow(
                                  color: skin.previewColor.withValues(alpha: 0.28),
                                  blurRadius: 18,
                                ),
                              ],
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  eyebrow,
                                  style: const TextStyle(
                                    color: MunjaColors.mint,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AppText.t(skin.title),
                                  style: const TextStyle(
                                    color: MunjaColors.text,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetContext).pop(false),
                            icon: const Icon(Icons.close_rounded),
                            color: Colors.white54,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.055),
                          ),
                        ),
                        child: Column(
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
                            const SizedBox(height: 6),
                            Text(
                              description,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.48),
                                fontSize: 11,
                                height: 1.45,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (access == _SkinAccess.crystals) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: const Color(0xFF70D8FF)
                                        .withValues(alpha: 0.14),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.diamond_rounded,
                                      color: Color(0xFF70D8FF),
                                      size: 16,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      'Balance',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.52),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$_crystalBalance Crystals',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: access == _SkinAccess.crystals
                              ? (canUnlockWithCrystals
                                  ? () => Navigator.of(sheetContext).pop(true)
                                  : null)
                              : () => Navigator.of(sheetContext).pop(false),
                          style: FilledButton.styleFrom(
                            backgroundColor: MunjaColors.mint,
                            foregroundColor: MunjaColors.bg,
                            disabledBackgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            disabledForegroundColor:
                                Colors.white.withValues(alpha: 0.32),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(17),
                            ),
                          ),
                          child: Text(
                            access == _SkinAccess.crystals
                                ? (canUnlockWithCrystals
                                    ? 'UNLOCK · $price CRYSTALS'
                                    : 'NEED $price CRYSTALS')
                                : access == _SkinAccess.locked
                                    ? AppText.t('gotIt').toUpperCase()
                                    : AppText.t('comingNext').toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        return result ?? false;
      }

      Future<bool> _persistActiveSkin(_SkinOption skin) async {
        await StorageService.saveSelectedBikeSkin(skin.id);
        await FirestoreBikeService.instance.updateActiveSkin(
          bikeId: widget.bike.id,
          activeSkinId: skin.id,
        );

        return true;
      }

      void _showSkinUnlockCelebration(_SkinOption skin) {
        if (!mounted) return;

        HapticFeedback.heavyImpact();

        setState(() {
          _celebrationSkinName = AppText.t(skin.title);
          _celebrationAccentColor = skin.previewColor;
          _celebrationHeadline = 'NEW SKIN UNLOCKED';
          _celebrationSubtitle = 'Equipped on your Digital Twin';
          _celebrationSequence++;
        });
      }

      void _showFrameUnlockCelebration(_FrameVariantOption frame) {
        if (!mounted) return;

        HapticFeedback.heavyImpact();

        setState(() {
          _celebrationSkinName = AppText.t(frame.title);
          _celebrationAccentColor = MunjaColors.mint;
          _celebrationHeadline = 'NEW FRAME UNLOCKED';
          _celebrationSubtitle = 'Added permanently to your Digital Twin';
          _celebrationSequence++;
        });
      }

      void _clearSkinUnlockCelebration() {
        if (!mounted) return;

        setState(() {
          _celebrationSkinName = null;
          _celebrationAccentColor = null;
        });
      }

      Future<void> _unlockCrystalSkin(
        _SkinOption skin,
      ) async {
        final ownerId = widget.bike.ownerId.trim();
        final price = skin.crystalPrice ?? 0;

        if (ownerId.isEmpty || price < 0) {
          if (!mounted) return;

          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              const SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text('Skin unlock is not available for this bike.'),
              ),
            );
          return;
        }

        setState(() {
          _savingSkin = true;
          _unlockingSkinId = skin.id;
        });

        final result =
            await FirestoreSkinEntitlementService.instance.unlockSkinWithCrystals(
          uid: ownerId,
          skinId: skin.id,
          crystalPrice: price,
        );

        if (!mounted) return;

        switch (result.status) {
          case SkinUnlockStatus.success:
          case SkinUnlockStatus.alreadyOwned:
            await _refreshEntitlementUser();

            if (!mounted) return;

            try {
              await _persistActiveSkin(skin);

              if (!mounted) return;

              setState(() {
                _selectedSkinId = skin.id;
                _savingSkin = false;
                _unlockingSkinId = null;
              });

              // Celebration is intentionally limited to a genuinely new
              // Crystal purchase. Selecting an already-owned skin stays quiet.
              if (result.status == SkinUnlockStatus.success) {
                _showSkinUnlockCelebration(skin);
              }

              if (result.status == SkinUnlockStatus.alreadyOwned) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      content: Text(
                        '${AppText.t(skin.title)} is owned and now active.',
                      ),
                    ),
                  );
              }
            } catch (error, stackTrace) {
              debugPrint(
                'BIKE CUSTOMIZE UNLOCKED SKIN ACTIVE SYNC ERROR: $error',
              );
              debugPrint('$stackTrace');

              if (!mounted) return;

              setState(() {
                _savingSkin = false;
                _unlockingSkinId = null;
              });

              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    behavior: SnackBarBehavior.floating,
                    content: Text(
                      '${AppText.t(skin.title)} is owned, but active skin sync failed. Select it again to retry.',
                    ),
                  ),
                );
            }
            break;

          case SkinUnlockStatus.insufficientCrystals:
            setState(() {
              _savingSkin = false;
              _unlockingSkinId = null;
            });

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    'Not enough Munja Crystals · ${result.previousCrystalBalance ?? _crystalBalance} Crystals available',
                  ),
                ),
              );
            break;

          case SkinUnlockStatus.userNotFound:
            setState(() {
              _savingSkin = false;
              _unlockingSkinId = null;
            });

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Munja user profile was not found.'),
                ),
              );
            break;

          case SkinUnlockStatus.invalidRequest:
          case SkinUnlockStatus.transactionFailed:
            setState(() {
              _savingSkin = false;
              _unlockingSkinId = null;
            });

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                const SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text('Skin could not be unlocked. Try again.'),
                ),
              );
            break;
        }
      }

      Future<void> _unlockSelectedSkin(String skinId) async {
        if (_savingSkin || _loadingEntitlements) return;

        final skin = _skinById(skinId);
        if (skin == null) return;

        if (_isSkinUsable(skin)) {
          if (_isMonthlyRewardSkin(skin.id)) {
            HapticFeedback.selectionClick();

            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  behavior: SnackBarBehavior.floating,
                  content: Text(
                    '${AppText.t(skin.title)} · Monthly Special reward unlocked',
                  ),
                ),
              );
          }

          await _selectSkin(skin.id);
          return;
        }

        if (skin.access != _SkinAccess.crystals) {
          HapticFeedback.lightImpact();
          return;
        }

        final confirmed = await _confirmSkinPurchase(skin);

        if (!mounted || !confirmed) {
          return;
        }

        HapticFeedback.mediumImpact();
        await _unlockCrystalSkin(skin);
      }

      Future<bool> _confirmSkinPurchase(
        _SkinOption skin,
      ) async {
        final price = skin.crystalPrice ?? 0;
        final balanceAfter = _crystalBalance - price;
        final canAfford = _crystalBalance >= price;

        final result = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (dialogContext) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 22,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  18,
                  20,
                  18,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF06110E),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: MunjaColors.mint.withValues(
                      alpha: 0.22,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MunjaColors.mint.withValues(
                        alpha: 0.08,
                      ),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: skin.previewColor.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius:
                                BorderRadius.circular(15),
                            border: Border.all(
                              color: skin.previewColor.withValues(
                                alpha: 0.30,
                              ),
                            ),
                          ),
                          child: skin.previewAsset != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Image.asset(
                                      skin.previewAsset!,
                                      fit: BoxFit.contain,
                                      filterQuality: FilterQuality.high,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.auto_awesome_rounded,
                                        color: skin.previewColor,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.auto_awesome_rounded,
                                  color: skin.previewColor,
                                  size: 22,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CONFIRM PURCHASE',
                                style: TextStyle(
                                  color: MunjaColors.mint,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AppText.t(skin.title),
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              Navigator.of(dialogContext)
                                  .pop(false),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(
                              alpha: 0.40,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(
                          alpha: 0.18,
                        ),
                        borderRadius:
                            BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: 0.055,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          _PurchaseSummaryRow(
                            label: 'Skin price',
                            value: '$price Crystals',
                            valueColor:
                                const Color(0xFF70D8FF),
                          ),
                          const SizedBox(height: 10),
                          _PurchaseSummaryRow(
                            label: 'Current balance',
                            value: '$_crystalBalance Crystals',
                          ),
                          const SizedBox(height: 10),
                          Divider(
                            height: 1,
                            color: Colors.white.withValues(
                              alpha: 0.06,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _PurchaseSummaryRow(
                            label: 'Balance after',
                            value: canAfford
                                ? '$balanceAfter Crystals'
                                : 'Not enough',
                            valueColor: canAfford
                                ? MunjaColors.mint
                                : Colors.redAccent,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    Text(
                      canAfford
                          ? 'The skin will be unlocked permanently and equipped on this bike.'
                          : 'You do not have enough Munja Crystals for this skin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(
                          alpha: 0.42,
                        ),
                        fontSize: 10,
                        height: 1.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext)
                                    .pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              minimumSize:
                                  const Size.fromHeight(46),
                              side: BorderSide(
                                color: Colors.white.withValues(
                                  alpha: 0.10,
                                ),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: canAfford
                                ? () =>
                                    Navigator.of(dialogContext)
                                        .pop(true)
                                : null,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  MunjaColors.mint,
                              foregroundColor:
                                  MunjaColors.bg,
                              disabledBackgroundColor:
                                  Colors.white.withValues(
                                alpha: 0.06,
                              ),
                              disabledForegroundColor:
                                  Colors.white.withValues(
                                alpha: 0.25,
                              ),
                              minimumSize:
                                  const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(15),
                              ),
                            ),
                            child: Text(
                              canAfford
                                  ? 'CONFIRM · $price '
                                  : 'NOT ENOUGH CRYSTALS',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.55,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );

        return result ?? false;
      }

      Future<void> _selectSkin(String skinId) async {
        if (_savingSkin) return;

        final skin = _skinById(skinId);
        if (skin == null) return;

        final previousSkinId = _selectedSkinId;
        final previousSkin = _skinById(previousSkinId);

        if (!_canPreviewSkin(skin)) {
          HapticFeedback.lightImpact();
          return;
        }

        HapticFeedback.selectionClick();
        final canPersist = _canPersistSkin(skin);

        setState(() {
          _selectedSkinId = skinId;
          _savingSkin = canPersist;
        });

        try {
          await _applySkinVisual(
            skin,
            preserveFrame: true,
          );

          // Preview-only skins are intentionally NOT persisted and do NOT
          // open a purchase modal. The user can freely swipe through every
          // preview and explicitly unlock from the button in the skin dock.
          if (!canPersist) {
            if (!mounted) return;

            final targetFrame = _frameById(_selectedFrameId);
            final materialName =
                skin.materialInstanceForFrame(targetFrame.id);

            debugPrint(
              'BIKE CUSTOMIZE SKIN PREVIEW ONLY: '
              '${skin.id} + ${targetFrame.id} -> $materialName',
            );

            setState(() {
              _savingSkin = false;
              _unlockingSkinId = null;
            });

            return;
          }

          await _persistActiveSkin(skin);

          if (!mounted) return;

          setState(() {
            _savingSkin = false;
            _unlockingSkinId = null;
          });

          debugPrint(
            'BIKE CUSTOMIZE SKIN ACTIVE AND SYNCED: ${skin.id}',
          );
        } catch (error, stackTrace) {
          debugPrint('BIKE CUSTOMIZE SAVE/SYNC SKIN ERROR: $error');
          debugPrint('$stackTrace');

          if (!mounted) return;

          setState(() {
            _selectedSkinId = previousSkinId;
            _savingSkin = false;
            _unlockingSkinId = null;
          });

          if (previousSkin != null && _masterFrameReady) {
            try {
              await _applySkinVisual(
                previousSkin,
                preserveFrame: true,
              );
            } catch (rollbackError, rollbackStackTrace) {
              debugPrint(
                'BIKE CUSTOMIZE SKIN ROLLBACK ERROR: $rollbackError',
              );
              debugPrint('$rollbackStackTrace');
            }
          }

          if (!mounted) return;

          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(AppText.t('skinActivationFailed')),
              ),
            );
        }
      }

      _SkinOption get _selectedSkin {
        return _skins.firstWhere(
          (skin) => skin.id == _selectedSkinId,
          orElse: () => _skins.first,
        );
      }

      String get _bikeTypeLabel {
        final value = widget.bike.type.name.toUpperCase();

        if (value == 'MTB') {
          return 'MTB';
        }

        return value[0] +
            value.substring(1).toLowerCase();
      }

      String get _bikeDescription {
        final values = <String>[
          _bikeTypeLabel,
          if (widget.bike.brand.trim().isNotEmpty)
            widget.bike.brand.trim(),
          if (widget.bike.model.trim().isNotEmpty)
            widget.bike.model.trim(),
        ];

        return values.join(' · ');
      }

      @override
      Widget build(BuildContext context) {
        final selectedSkin = _selectedSkin;
        final busy = _savingSkin ||
            _loadingEntitlements ||
            _switchingFrame;

        return Scaffold(
          backgroundColor: MunjaColors.bg,
          body: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF020907),
                        Color(0xFF03100D),
                        Color(0xFF010504),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _CustomizeTopBar(
                      title: AppText.t('customize'),
                      crystalBalance: _crystalBalance,
                      busy: busy,
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: ListView(
                        physics: _isPreviewInteracting
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(
                          14,
                          2,
                          14,
                          bottomWheelSafePadding,
                        ),
                        children: [
                          _MobileLegendsCustomizeStage(
                            accentColor: selectedSkin.previewColor,
                            selectedCategory: _selectedCategory,
                            onCategorySelected: (category) {
                              if (_selectedCategory == category) return;
                              HapticFeedback.selectionClick();
                              setState(() {
                                _selectedCategory = category;
                              });
                            },
                            preview: _BikePreviewCard(
                              bike: widget.bike,
                              description: _bikeDescription,
                              skin: selectedSkin,
                              loading: _loadingSkin,
                              frameController: _frameController,
                              frames: _frameVariants,
                              selectedFrameId: _selectedFrameId,
                              switchingFrame: _switchingFrame,
                              masterFrameReady: _masterFrameReady,
                              onFrameSelected: _selectFrameVariant,
                              showroomStageAngle: _showroomStageAngle,
                              onInteractionChanged: (interacting) {
                                if (!mounted ||
                                    _isPreviewInteracting == interacting) {
                                  return;
                                }

                                setState(() {
                                  _isPreviewInteracting = interacting;
                                });
                              },
                            ),
                            content: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: _buildCategoryContent(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_celebrationSkinName != null &&
                  _celebrationAccentColor != null)
                Positioned.fill(
                  child: SkinUnlockCelebration(
                    key: ValueKey<int>(_celebrationSequence),
                    skinName: _celebrationSkinName!,
                    accentColor: _celebrationAccentColor!,
                    headline: _celebrationHeadline,
                    subtitle: _celebrationSubtitle,
                    onCompleted: _clearSkinUnlockCelebration,
                  ),
                ),
            ],
          ),
        );
      }

      Widget _buildCategoryContent() {
        switch (_selectedCategory) {
          case _CustomizeCategory.skins:
            return _SkinSection(
              key: const ValueKey<String>('skins'),
              skins: _skins,
              selectedSkinId: _selectedSkinId,
              loading: _loadingSkin || _loadingEntitlements,
              saving: _savingSkin,
              crystalBalance: _crystalBalance,
              unlockingSkinId: _unlockingSkinId,
              canUseSkin: _isSkinUsable,
              onSelected: _selectSkin,
              onUnlockRequested: _unlockSelectedSkin,
            );

          case _CustomizeCategory.frame:
            return _FrameSection(
              key: const ValueKey<String>('frame'),
              frames: _frameVariants,
              selectedFrameId: _selectedFrameId,
              activeFrameId: _activeFrameId,
              switchingFrame: _switchingFrame,
              unlockingFrameId: _unlockingFrameId,
              crystalBalance: _crystalBalance,
              isFrameOwned: _isFrameOwned,
              onFrameSelected: _selectFrameVariant,
              onUnlockRequested: _unlockSelectedFrame,
            );
        }
      }
    }

    enum _CustomizeCategory {
      skins,
      frame,
    }

    enum _SkinAccess {
      owned,
      crystals,
      pro,
      locked,
    }

    class _SkinOption {
      const _SkinOption({
        required this.id,
        required this.title,
        required this.subtitle,
        required this.previewColor,
        required this.modelPath,
        required this.access,
        required this.materialInstanceByFrameId,
        this.crystalPrice,
        this.visibleInCarousel = true,
        this.previewAsset,
        this.storeSku,
      });

      final String id;
      final String title;
      final String subtitle;
      final Color previewColor;
      final String modelPath;
      final _SkinAccess access;
      final int? crystalPrice;
      final bool visibleInCarousel;
      final String? previewAsset;
      final String? storeSku;

      /// Exact MaterialInstance names embedded in the master GLB.
      /// Never infer these names. They must be confirmed from Blender/GLB.
      final Map<String, String> materialInstanceByFrameId;

      String? materialInstanceForFrame(String frameId) {
        return materialInstanceByFrameId[frameId];
      }

      bool get isOwned => access == _SkinAccess.owned;

      String get accessLabel {
        switch (access) {
          case _SkinAccess.owned:
            return AppText.t('owned').toUpperCase();
          case _SkinAccess.crystals:
            return '${crystalPrice ?? 0} ';
          case _SkinAccess.pro:
            return AppText.t('pro').toUpperCase();
          case _SkinAccess.locked:
            return AppText.t('locked').toUpperCase();
        }
      }

      IconData get accessIcon {
        switch (access) {
          case _SkinAccess.owned:
            return Icons.check_rounded;
          case _SkinAccess.crystals:
            return Icons.diamond_outlined;
          case _SkinAccess.pro:
            return Icons.workspace_premium_outlined;
          case _SkinAccess.locked:
            return Icons.lock_outline_rounded;
        }
      }
    }

    class _FrameVariantOption {
      const _FrameVariantOption({
        required this.id,
        required this.title,
        required this.entityName,
        required this.crystalPrice,
        this.included = false,
      });

      final String id;
      final String title;
      final String entityName;
      final int crystalPrice;
      final bool included;
    }

    class _PurchaseSummaryRow extends StatelessWidget {
      const _PurchaseSummaryRow({
        required this.label,
        required this.value,
        this.valueColor,
      });

      final String label;
      final String value;
      final Color? valueColor;

      @override
      Widget build(BuildContext context) {
        return Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.42),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        );
      }
    }

    class _CustomizeTopBar extends StatelessWidget {
      const _CustomizeTopBar({
        required this.title,
        required this.crystalBalance,
        required this.busy,
        required this.onBack,
      });

      final String title;
      final int crystalBalance;
      final bool busy;
      final VoidCallback onBack;

      @override
      Widget build(BuildContext context) {
        return SizedBox(
          height: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: onBack,
                      customBorder: const CircleBorder(),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 25,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 7),
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
                          color: Colors.white,
                          fontSize: 25,
                          height: 1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.65,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Container(
                            width: 22,
                            height: 2,
                            decoration: BoxDecoration(
                              color: MunjaColors.mint,
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: [
                                BoxShadow(
                                  color: MunjaColors.mint.withValues(alpha: 0.35),
                                  blurRadius: 7,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'DIGITAL TWIN',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.23),
                              fontSize: 6.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.25,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 38,
                  constraints: const BoxConstraints(minWidth: 74, maxWidth: 100),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF70D8FF).withValues(alpha: 0.075),
                        MunjaColors.mint.withValues(alpha: 0.035),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFF70D8FF).withValues(alpha: 0.19),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.diamond_rounded,
                        color: Color(0xFF70D8FF),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '$crystalBalance',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (busy) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: MunjaColors.mint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }

    class _MobileLegendsCustomizeStage extends StatelessWidget {
      const _MobileLegendsCustomizeStage({
        required this.accentColor,
        required this.selectedCategory,
        required this.onCategorySelected,
        required this.preview,
        required this.content,
      });

      final Color accentColor;
      final _CustomizeCategory selectedCategory;
      final ValueChanged<_CustomizeCategory> onCategorySelected;
      final Widget preview;
      final Widget content;

      @override
      Widget build(BuildContext context) {
        return Container(
          height: 565,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            // Intentionally no outer mint border or green glow.
            // The showroom now blends into the page and feels visually lighter.
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF061510),
                      Color(0xFF02100C),
                      Color(0xFF010604),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 28,
               left: 30,
                right: 30,
                height: 280,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, 0.10),
                        radius: 0.72,
                        colors: [
                          accentColor.withValues(alpha: 0.14),
                          MunjaColors.mint.withValues(alpha: 0.045),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: preview),
              Positioned(
               left: 0,
                right: 0,
                bottom: 0,
                height: 180,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF02100C).withValues(alpha: 0.42),
                          const Color(0xFF010705).withValues(alpha: 0.96),
                        ],
                        stops: const [0.0, 0.24, 0.53],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
               left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF010806).withValues(alpha: 0.78),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(alpha: 0.055),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CategorySelector(
                        selectedCategory: selectedCategory,
                        onSelected: onCategorySelected,
                      ),
                      content,
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }
    }

    class _HudCorner extends StatelessWidget {
      const _HudCorner({required this.alignment});
      final Alignment alignment;

      @override
      Widget build(BuildContext context) {
        final right = alignment == Alignment.topRight;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(right ? -1.0 : 1.0, 1.0, 1.0),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CustomPaint(painter: _HudCornerPainter()),
          ),
        );
      }
    }

    class _HudCornerPainter extends CustomPainter {
      @override
      void paint(Canvas canvas, Size size) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round
          ..color = MunjaColors.mint.withValues(alpha: 0.45);
        final path = Path()
          ..moveTo(0, size.height)
          ..lineTo(0, 7)
          ..quadraticBezierTo(0, 0, 7, 0)
          ..lineTo(size.width, 0);
        canvas.drawPath(path, paint);
      }

      @override
      bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
    }

    class _BikePreviewCard extends StatelessWidget {
      const _BikePreviewCard({
        required this.bike,
        required this.description,
        required this.skin,
        required this.loading,
        required this.frameController,
        required this.frames,
        required this.selectedFrameId,
        required this.switchingFrame,
        required this.masterFrameReady,
        required this.onFrameSelected,
        required this.showroomStageAngle,
        required this.onInteractionChanged,
      });

      final FirestoreBike bike;
      final String description;
      final _SkinOption skin;
      final bool loading;
      final Interactive3dController frameController;
      final List<_FrameVariantOption> frames;
      final String selectedFrameId;
      final bool switchingFrame;
      final bool masterFrameReady;
      final ValueChanged<String> onFrameSelected;
      final ValueNotifier<double> showroomStageAngle;
      final ValueChanged<bool> onInteractionChanged;

      @override
      Widget build(BuildContext context) {
        final selectedIndex = frames.indexWhere(
          (frame) => frame.id == selectedFrameId,
        );
        final safeIndex = selectedIndex < 0 ? 0 : selectedIndex;

        Future<void> selectRelative(int delta) async {
          if (switchingFrame || !masterFrameReady || frames.isEmpty) return;

          final nextIndex = (safeIndex + delta) % frames.length;
          final normalizedIndex = nextIndex < 0
              ? nextIndex + frames.length
              : nextIndex;

          await Future<void>.sync(
            () => onFrameSelected(frames[normalizedIndex].id),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Container(
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: const RadialGradient(
                center: Alignment(0, -0.05),
                radius: 0.95,
                colors: [
                  Color(0xFF0B281F),
                  Color(0xFF04110D),
                  Color(0xFF010504),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
            ),
            child: loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: MunjaColors.mint,
                    ),
                  )
                : skin.modelPath == 'assets/models/kids_mtb_master.glb'
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // IMPORTANT:
                          // Interactive3d already owns the native rotate/pan/tap
                          // gesture recognizers. Do not wrap it in our own pointer
                          // drag handler: the previous implementation only rotated
                          // the decorative showroom ring and could compete with the
                          // real native 3D gesture stream.
                          Interactive3d(
                            key: const ValueKey<String>(
                              'munja-native-master-bike',
                            ),
                            iOSEagerGestures: true,
                            controller: frameController,
                            modelPath: 'assets/models/kids_mtb_master.glb',
                            solidBackgroundColor: const <double>[
                              0.0,
                              0.0,
                              0.0,
                              0.0,
                            ],
                            backgroundColor: Colors.transparent,

                            // Restore the calmer framing from before the latest
                            // showroom experiments. This keeps the full bike inside
                            // the hero box while still leaving enough detail for
                            // material/skin inspection.
                            defaultZoom: 2.02,

                            onSelectionChanged: (entities) {
                              debugPrint(
                                'BIKE CUSTOMIZE NATIVE SELECTION: '
                                '${entities.map((e) => e.name).toList()}',
                              );
                            },
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ValueListenableBuilder<double>(
                                valueListenable: showroomStageAngle,
                                builder: (context, stageAngle, child) {
                                  return _ShowroomStageRing(
                                    rotationAngle: stageAngle,
                                  );
                                },
                              ),
                            ),
                          ),
                          Positioned(
                           left: 14,
                            top: 14,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.42),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  AppText.t(frames[safeIndex].title)
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    color: MunjaColors.mint,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 14,
                            top: 14,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${safeIndex + 1}/${frames.length}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                           left: 8,
                            top: 0,
                            bottom: 205,
                            child: Center(
                              child: _CarouselArrow(
                                icon: Icons.chevron_left_rounded,
                                disabled: switchingFrame || !masterFrameReady,
                                onTap: () => selectRelative(-1),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 0,
                            bottom: 205,
                            child: Center(
                              child: _CarouselArrow(
                                icon: Icons.chevron_right_rounded,
                                disabled: switchingFrame || !masterFrameReady,
                                onTap: () => selectRelative(1),
                              ),
                            ),
                          ),
                          if (switchingFrame || !masterFrameReady)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Container(
                                  color: Colors.black.withValues(
                                    alpha: switchingFrame ? 0.06 : 0.0,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: MunjaColors.mint,
                                      strokeWidth: 2.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      )
                    : Munja3DBikeViewer(
                        key: ValueKey<String>(skin.modelPath),
                        modelPath: skin.modelPath,
                        height: 420,
                        isLive: false,
                        brakeLightMounted: false,
                        showControls: true,
                        showSkinTester: false,
                        showBadges: false,
                        showBottomInfo: false,
                        showProductHotspot: false,
                        showroomMode: true,
                        showroomTheta: 225.0,
                        showroomPhi: 68.0,
                        showroomRadius: 2.35,
                      ),
          ),
        );
      }
    }

    class _ShowroomStageRing extends StatelessWidget {
      const _ShowroomStageRing({
        required this.rotationAngle,
      });

      final double rotationAngle;

      @override
      Widget build(BuildContext context) {
        return Align(
          alignment: const Alignment(0, 0.73),
          child: SizedBox(
            width: double.infinity,
            height: 132,
            child: CustomPaint(
              painter: _ShowroomStagePainter(
                rotationAngle: rotationAngle,
              ),
            ),
          ),
        );
      }
    }

    class _ShowroomStagePainter extends CustomPainter {
      const _ShowroomStagePainter({
        required this.rotationAngle,
      });

      final double rotationAngle;

      @override
      void paint(Canvas canvas, Size size) {
        final center = Offset(
          size.width / 2,
          size.height * 0.54,
        );

        const maxShowroomAngle = 55.0 * math.pi / 180.0;
        final normalizedRotation =
            (rotationAngle / maxShowroomAngle).clamp(-1.0, 1.0);
        final sideAmount = normalizedRotation.abs();

        // The platform stays proportional to the bike. When the bike is turned
        // toward either showroom limit, the perceived footprint becomes a little
        // narrower, which makes the stage feel attached to the 3D object instead
        // of looking like an independent oversized ring.
        final stageWidthFactor = 0.82 - (sideAmount * 0.055);
        final stageHeightFactor = 0.43 + (sideAmount * 0.035);

        final outerRect = Rect.fromCenter(
          center: center,
          width: size.width * stageWidthFactor,
          height: size.height * stageHeightFactor,
        );

        final middleRect = Rect.fromCenter(
          center: center,
          width: outerRect.width * 0.86,
          height: outerRect.height * 0.78,
        );

        final innerRect = Rect.fromCenter(
          center: center,
          width: outerRect.width * 0.69,
          height: outerRect.height * 0.60,
        );

        // Ground shadow first.
        final shadowRect = Rect.fromCenter(
          center: Offset(
            center.dx,
            center.dy + 5,
          ),
          width: size.width * 0.47,
          height: size.height * 0.16,
        );

        final shadowPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.24)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            12,
          );

        canvas.drawOval(
          shadowRect,
          shadowPaint,
        );

        // Soft glow around the floor platform.
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..color = MunjaColors.mint.withValues(alpha: 0.085)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            15,
          );

        canvas.drawOval(
          outerRect,
          glowPaint,
        );

        // Static structure: the platform remains horizontal like a real floor.
        final outerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = MunjaColors.mint.withValues(alpha: 0.58);

        canvas.drawOval(
          outerRect,
          outerPaint,
        );

        final middlePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = MunjaColors.mint.withValues(alpha: 0.22);

        canvas.drawOval(
          middleRect,
          middlePaint,
        );

        final innerPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = Colors.white.withValues(alpha: 0.07);

        canvas.drawOval(
          innerRect,
          innerPaint,
        );

        // Rotating energy segments. The ellipse itself should not physically tilt;
        // these moving arcs are what visually follow the bike's horizontal drag.
        final rotatingArcPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3.1
          ..color = MunjaColors.mint.withValues(alpha: 0.95);

        final secondaryArcPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.8
          ..color = MunjaColors.mint.withValues(alpha: 0.52);

        // Map the limited bike yaw to the floor orbit. The multiplier gives the
        // ring enough visible travel while still stopping exactly at the same
        // showroom limits as the bike gesture state.
        final startAngle = -math.pi / 2 + (normalizedRotation * math.pi * 0.72);
        const primarySweep = math.pi * 0.38;
        const secondarySweep = math.pi * 0.20;

        canvas.drawArc(
          outerRect,
          startAngle,
          primarySweep,
          false,
          rotatingArcPaint,
        );

        canvas.drawArc(
          outerRect,
          startAngle + math.pi,
          primarySweep,
          false,
          rotatingArcPaint,
        );

        canvas.drawArc(
          middleRect,
          -startAngle * 0.82 + 0.8,
          secondarySweep,
          false,
          secondaryArcPaint,
        );

        canvas.drawArc(
          middleRect,
          -startAngle * 0.82 + math.pi + 0.8,
          secondarySweep,
          false,
          secondaryArcPaint,
        );

        // Small orbit markers make the direction of rotation much easier to read.
        _drawOrbitMarker(
          canvas: canvas,
          rect: outerRect,
          angle: startAngle + primarySweep,
          radius: 3.2,
          alpha: 0.92,
        );

        _drawOrbitMarker(
          canvas: canvas,
          rect: outerRect,
          angle: startAngle + math.pi + primarySweep,
          radius: 3.2,
          alpha: 0.92,
        );

        _drawOrbitMarker(
          canvas: canvas,
          rect: middleRect,
          angle: -startAngle * 0.82 + 0.8 + secondarySweep,
          radius: 2.2,
          alpha: 0.48,
        );

        // A subtle front highlight grounds the whole showroom platform.
        final frontHighlightPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.7
          ..color = Colors.white.withValues(alpha: 0.10);

        canvas.drawArc(
          outerRect,
          0.30,
          math.pi * 0.74,
          false,
          frontHighlightPaint,
        );
      }

      void _drawOrbitMarker({
        required Canvas canvas,
        required Rect rect,
        required double angle,
        required double radius,
        required double alpha,
      }) {
        final point = Offset(
          rect.center.dx +
              math.cos(angle) *
                  (rect.width / 2),
          rect.center.dy +
              math.sin(angle) *
                  (rect.height / 2),
        );

        final glow = Paint()
          ..color = MunjaColors.mint
              .withValues(alpha: alpha * 0.24)
          ..maskFilter = const MaskFilter.blur(
            BlurStyle.normal,
            8,
          );

        canvas.drawCircle(
          point,
          radius * 2.2,
          glow,
        );

        final marker = Paint()
          ..color = MunjaColors.mint
              .withValues(alpha: alpha);

        canvas.drawCircle(
          point,
          radius,
          marker,
        );
      }

      @override
      bool shouldRepaint(
        covariant _ShowroomStagePainter oldDelegate,
      ) {
        return oldDelegate.rotationAngle !=
            rotationAngle;
      }
    }

    class _CarouselArrow extends StatelessWidget {
      const _CarouselArrow({
        required this.icon,
        required this.disabled,
        required this.onTap,
      });

      final IconData icon;
      final bool disabled;
      final VoidCallback onTap;

      @override
      Widget build(BuildContext context) {
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: disabled ? 0.35 : 1.0,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: disabled ? null : onTap,
              customBorder: const CircleBorder(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MunjaColors.mint.withValues(alpha: 0.16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: MunjaColors.mint,
                  size: 25,
                ),
              ),
            ),
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
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color:
                    Colors.white.withValues(alpha: 0.44),
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        );
      }
    }

    class _CategorySelector extends StatelessWidget {
      const _CategorySelector({
        required this.selectedCategory,
        required this.onSelected,
      });

      final _CustomizeCategory selectedCategory;
      final ValueChanged<_CustomizeCategory> onSelected;

      @override
      Widget build(BuildContext context) {
        return Container(
          height: 38,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Row(
            children: [
              _CategoryTab(
                label: 'SKINS',
                icon: Icons.auto_awesome_rounded,
                selected: selectedCategory == _CustomizeCategory.skins,
                onTap: () => onSelected(_CustomizeCategory.skins),
              ),
              const SizedBox(width: 7),
              _CategoryTab(
                label: 'FRAME',
                icon: Icons.directions_bike_rounded,
                selected: selectedCategory == _CustomizeCategory.frame,
                onTap: () => onSelected(_CustomizeCategory.frame),
              ),
            ],
          ),
        );
      }
    }

    class _CategoryTab extends StatelessWidget {
      const _CategoryTab({
        required this.label,
        required this.icon,
        required this.selected,
        required this.onTap,
      });

      final String label;
      final IconData icon;
      final bool selected;
      final VoidCallback onTap;

      @override
      Widget build(BuildContext context) {
        return Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                height: 31,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: selected
                      ? LinearGradient(
                          colors: [
                            MunjaColors.mint.withValues(alpha: 0.13),
                            MunjaColors.mint.withValues(alpha: 0.025),
                          ],
                        )
                      : null,
                  border: Border.all(
                    color: selected
                        ? MunjaColors.mint.withValues(alpha: 0.24)
                        : Colors.white.withValues(alpha: 0.035),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 11,
                      color: selected
                          ? MunjaColors.mint
                          : Colors.white.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.31),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.85,
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

    class _SkinSection extends StatefulWidget {
      const _SkinSection({
        super.key,
        required this.skins,
        required this.selectedSkinId,
        required this.loading,
        required this.saving,
        required this.crystalBalance,
        required this.unlockingSkinId,
        required this.canUseSkin,
        required this.onSelected,
        required this.onUnlockRequested,
      });

      final List<_SkinOption> skins;
      final String selectedSkinId;
      final bool loading;
      final bool saving;
      final int crystalBalance;
      final String? unlockingSkinId;
      final bool Function(_SkinOption skin) canUseSkin;
      final ValueChanged<String> onSelected;
      final ValueChanged<String> onUnlockRequested;

      @override
      State<_SkinSection> createState() => _SkinSectionState();
    }

    class _SkinSectionState extends State<_SkinSection> {
      late final PageController _controller;
      int _pageIndex = 0;

      List<_SkinOption> get _visibleSkins => widget.skins
          .where((skin) => skin.visibleInCarousel)
          .toList(growable: false);

      int _indexForSkin(String skinId) {
        final index =
            _visibleSkins.indexWhere((skin) => skin.id == skinId);
        return index < 0 ? 0 : index;
      }

      @override
      void initState() {
        super.initState();
        _pageIndex = _indexForSkin(widget.selectedSkinId);
        _controller = PageController(
          initialPage: _pageIndex,
          viewportFraction: 0.158,
        );
      }

      @override
      void didUpdateWidget(covariant _SkinSection oldWidget) {
        super.didUpdateWidget(oldWidget);

        if (oldWidget.selectedSkinId == widget.selectedSkinId) return;

        final target = _indexForSkin(widget.selectedSkinId);
        _pageIndex = target;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_controller.hasClients) return;
          _controller.animateToPage(
            target,
            duration: const Duration(milliseconds: 270),
            curve: Curves.easeOutCubic,
          );
        });
      }

      @override
      void dispose() {
        _controller.dispose();
        super.dispose();
      }

      void _goRelative(int delta) {
        final skins = _visibleSkins;

        if (skins.isEmpty || widget.loading || widget.saving) return;

        final next =
            (_pageIndex + delta).clamp(0, skins.length - 1);

        if (next == _pageIndex) return;

        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }

      String _finishLabel(_SkinOption skin) {
        switch (skin.id) {
          case 'carbon_fibre':
            return 'WOVEN CARBON';
          case 'brushed_metal':
            return 'BRUSHED ALLOY';
          case 'gold':
            return 'SIGNATURE GOLD';
          case 'ice_silver':
            return 'ICE METALLIC';
          case 'lava_red':
            return 'PERFORMANCE RED';
          case 'matt_black':
            return 'STEALTH MATTE';
          case 'neon_green':
            return 'ELECTRIC FINISH';
          case 'titanium':
            return 'TITANIUM METAL';
          default:
            return 'ORIGINAL FINISH';
        }
      }

      @override
      Widget build(BuildContext context) {
        final skins = _visibleSkins;

        if (skins.isEmpty) {
          return const SizedBox.shrink();
        }

        final selectedSkin = skins.firstWhere(
          (skin) => skin.id == widget.selectedSkinId,
          orElse: () => skins.first,
        );

        final selectedUsable = widget.canUseSkin(selectedSkin);

        String status;
        if (widget.unlockingSkinId == selectedSkin.id) {
          status = 'UNLOCKING';
        } else if (selectedUsable) {
          status =
              selectedSkin.id == 'standard' ? 'OWNED' : 'EQUIPPED';
        } else if (selectedSkin.access == _SkinAccess.crystals) {
          status = '${selectedSkin.crystalPrice ?? 0} ';
        } else if (selectedSkin.access == _SkinAccess.pro) {
          status = 'PRO';
        } else {
          status = 'CHALLENGE';
        }

        return SizedBox(
          height: 164,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 25,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(99),
                              color: selectedSkin.previewColor,
                              boxShadow: [
                                BoxShadow(
                                  color: selectedSkin.previewColor
                                      .withValues(alpha: 0.40),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(
                                  AppText.t(selectedSkin.title)
                                      .toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.15,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      _finishLabel(selectedSkin),
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.30),
                                        fontSize: 6.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.05,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Container(
                                      width: 3,
                                      height: 3,
                                      decoration: BoxDecoration(
                                        color:
                                            selectedSkin.previewColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color: selectedUsable
                                            ? MunjaColors.mint
                                            : const Color(0xFF70D8FF),
                                        fontSize: 7.2,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.55,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!selectedUsable &&
                        selectedSkin.access ==
                            _SkinAccess.crystals)
                      _SkinUnlockButton(
                        price: selectedSkin.crystalPrice ?? 0,
                        busy: widget.unlockingSkinId == selectedSkin.id,
                        disabled: widget.loading || widget.saving,
                        onTap: () =>
                            widget.onUnlockRequested(selectedSkin.id),
                      )
                    else if (!selectedUsable &&
                        selectedSkin.access == _SkinAccess.pro)
                      const _SkinAccessBadge(
                        label: 'PRO',
                        icon: Icons.workspace_premium_rounded,
                      )
                    else if (!selectedUsable &&
                        selectedSkin.access == _SkinAccess.locked)
                      const _SkinAccessBadge(
                        label: 'CHALLENGE',
                        icon: Icons.lock_rounded,
                      ),
                    if (widget.loading || widget.saving) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: MunjaColors.mint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PageView.builder(
                      controller: _controller,
                      physics: const BouncingScrollPhysics(),
                      itemCount: skins.length,
                      onPageChanged: (index) {
                        if (!mounted) return;

                        setState(() => _pageIndex = index);

                        final skin = skins[index];

                        if (skin.id != widget.selectedSkinId &&
                            !widget.loading &&
                            !widget.saving) {
                          widget.onSelected(skin.id);
                        }
                      },
                      itemBuilder: (context, index) {
                        final skin = skins[index];
                        final focused = index == _pageIndex;

                        return AnimatedPadding(
                          duration:
                              const Duration(milliseconds: 190),
                          curve: Curves.easeOutCubic,
                          padding: EdgeInsets.symmetric(
                            horizontal: focused ? 1 : 3,
                            vertical: focused ? 0 : 13,
                          ),
                          child: _SkinCarouselCard(
                            skin: skin,
                            selected:
                                skin.id == widget.selectedSkinId,
                            focused: focused,
                            usable: widget.canUseSkin(skin),
                            unlocking:
                                widget.unlockingSkinId == skin.id,
                            disabled:
                                widget.loading || widget.saving,
                            onTap: () {
                              _controller.animateToPage(
                                index,
                                duration: const Duration(
                                  milliseconds: 220,
                                ),
                                curve: Curves.easeOutCubic,
                              );

                              if (skin.id !=
                                  widget.selectedSkinId) {
                                widget.onSelected(skin.id);
                              }
                            },
                          ),
                        );
                      },
                    ),

                    Positioned(
                     left: 1,
                      child: _MiniCarouselArrow(
                        icon: Icons.chevron_left_rounded,
                        disabled: _pageIndex <= 0 ||
                            widget.loading ||
                            widget.saving,
                        onTap: () => _goRelative(-1),
                      ),
                    ),

                    Positioned(
                      right: 1,
                      child: _MiniCarouselArrow(
                        icon: Icons.chevron_right_rounded,
                        disabled:
                            _pageIndex >= skins.length - 1 ||
                                widget.loading ||
                                widget.saving,
                        onTap: () => _goRelative(1),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 1),
              _CarouselDots(
                count: skins.length,
                activeIndex: _pageIndex,
              ),
              const SizedBox(height: 4),
            ],
          ),
        );
      }
    }

    class _SkinUnlockButton extends StatelessWidget {
      const _SkinUnlockButton({
        required this.price,
        required this.busy,
        required this.disabled,
        required this.onTap,
      });

      final int price;
      final bool busy;
      final bool disabled;
      final VoidCallback onTap;

      @override
      Widget build(BuildContext context) {
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: disabled ? null : onTap,
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 31,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: disabled
                      ? [
                          Colors.white.withValues(alpha: 0.045),
                          Colors.white.withValues(alpha: 0.02),
                        ]
                      : [
                          MunjaColors.mint.withValues(alpha: 0.22),
                          const Color(0xFF70D8FF)
                              .withValues(alpha: 0.09),
                        ],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: disabled
                      ? Colors.white.withValues(alpha: 0.06)
                      : MunjaColors.mint.withValues(alpha: 0.42),
                ),
                boxShadow: disabled
                    ? null
                    : [
                        BoxShadow(
                          color: MunjaColors.mint.withValues(alpha: 0.12),
                          blurRadius: 12,
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.7,
                        color: MunjaColors.mint,
                      ),
                    )
                  else
                    const Icon(
                      Icons.lock_open_rounded,
                      color: MunjaColors.mint,
                      size: 12,
                    ),
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.diamond_rounded,
                    color: Color(0xFF70D8FF),
                    size: 10,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$price',
                    style: TextStyle(
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.30)
                          : Colors.white,
                      fontSize: 8,
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

    class _SkinAccessBadge extends StatelessWidget {
      const _SkinAccessBadge({
        required this.label,
        required this.icon,
      });

      final String label;
      final IconData icon;

      @override
      Widget build(BuildContext context) {
        return Container(
          height: 29,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFC981FF).withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFC981FF).withValues(alpha: 0.18),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 10,
                color: const Color(0xFFC981FF),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFC981FF),
                  fontSize: 7,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.45,
                ),
              ),
            ],
          ),
        );
      }
    }

    class _MiniCarouselArrow extends StatelessWidget {
      const _MiniCarouselArrow({
        required this.icon,
        required this.disabled,
        required this.onTap,
      });

      final IconData icon;
      final bool disabled;
      final VoidCallback onTap;

      @override
      Widget build(BuildContext context) {
        return IgnorePointer(
          ignoring: disabled,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: disabled ? 0.22 : 1,
            child: Material(
              color: Colors.black.withValues(alpha: 0.48),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: MunjaColors.mint.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: MunjaColors.mint,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    class _CarouselDots extends StatelessWidget {
      const _CarouselDots({
        required this.count,
        required this.activeIndex,
      });

      final int count;
      final int activeIndex;

      @override
      Widget build(BuildContext context) {
        final safeCount = count.clamp(1, 9);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(safeCount, (index) {
            final selected = index == activeIndex;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              width: selected ? 12 : 3,
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: selected
                    ? MunjaColors.mint
                    : Colors.white.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(999),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: MunjaColors.mint
                              .withValues(alpha: 0.30),
                          blurRadius: 7,
                        ),
                      ]
                    : null,
              ),
            );
          }),
        );
      }
    }

    class _SkinPreviewArtwork extends StatelessWidget {
      const _SkinPreviewArtwork({
        required this.skin,
        required this.focused,
      });

      final _SkinOption skin;
      final bool focused;

      @override
      Widget build(BuildContext context) {
        final asset = skin.previewAsset;

        if (asset == null || asset.trim().isEmpty) {
          return _fallback();
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.0),
                      radius: 0.88,
                      colors: [
                        Colors.white.withValues(
                          alpha: focused ? 0.035 : 0.015,
                        ),
                        const Color(0xFF06110E)
                            .withValues(alpha: focused ? 0.26 : 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Keep the complete rendered bike visible.
              // The Blender PNG already contains the final camera angle,
              // so the card must not apply a heavy Transform.scale.
              Padding(
                padding: EdgeInsets.fromLTRB(
                  focused ? 4 : 9,
                  focused ? 3 : 8,
                  focused ? 4 : 9,
                  focused ? 1 : 6,
                ),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => _fallback(),
                ),
              ),

              if (!focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.10),
                      ),
                    ),
                  ),
                ),


            ],
          ),
        );
      }

      Widget _fallback() {
        return Center(
          child: Icon(
            Icons.directions_bike_rounded,
            color: Colors.white.withValues(alpha: 0.65),
            size: focused ? 28 : 20,
          ),
        );
      }
    }

    class _SkinCarouselCard extends StatelessWidget {
      const _SkinCarouselCard({
        required this.skin,
        required this.selected,
        required this.focused,
        required this.usable,
        required this.unlocking,
        required this.disabled,
        required this.onTap,
      });

      final _SkinOption skin;
      final bool selected;
      final bool focused;
      final bool usable;
      final bool unlocking;
      final bool disabled;
      final VoidCallback onTap;

      @override
      Widget build(BuildContext context) {
        final isCrystal = skin.access == _SkinAccess.crystals;
        final isPro = skin.access == _SkinAccess.pro;
        final isLocked = skin.access == _SkinAccess.locked;

        String status;

        if (unlocking) {
          status = '...';
        } else if (selected && usable) {
          status = 'ON';
        } else if (usable) {
          status = 'OWNED';
        } else if (isCrystal) {
          status = '${skin.crystalPrice ?? 0}';
        } else if (isPro) {
          status = 'PRO';
        } else {
          status = 'LOCK';
        }

        final accent = skin.previewColor;

        return AnimatedScale(
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeOutBack,
          scale: focused ? 1.10 : 0.80,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: disabled ? null : onTap,
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 210),
                curve: Curves.easeOutCubic,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(
                        alpha: focused ? 0.045 : 0.018,
                      ),
                      const Color(0xFF07130F)
                          .withValues(alpha: 0.94),
                      const Color(0xFF010604),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: selected ? 0.12 : focused ? 0.08 : 0.04,
                    ),
                    width: 0.8,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.32),
                            blurRadius: 16,
                            spreadRadius: -4,
                            offset: const Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (focused)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, -0.20),
                                radius: 0.85,
                                colors: [
                                  accent.withValues(alpha: 0.20),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),

                    Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              focused ? 2 : 4,
                              4,
                              focused ? 2 : 4,
                              0,
                            ),
                            child: _SkinPreviewArtwork(
                              skin: skin,
                              focused: focused,
                            ),
                          ),
                        ),



                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(3, 3, 3, 4),
                          child: Column(
                            children: [
                              Text(
                                AppText.t(skin.title).toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: focused
                                      ? Colors.white
                                      : Colors.white.withValues(
                                          alpha: 0.46,
                                        ),
                                  fontSize:
                                      focused ? 6.9 : 5.6,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.02,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!usable && isCrystal) ...[
                                    const Icon(
                                      Icons.diamond_rounded,
                                      color: Color(0xFF70D8FF),
                                      size: 7,
                                    ),
                                    const SizedBox(width: 2),
                                  ],
                                  Flexible(
                                    child: Text(
                                      status,
                                      maxLines: 1,
                                      overflow:
                                          TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: usable
                                            ? MunjaColors.mint
                                            : isPro || isLocked
                                                ? const Color(
                                                    0xFFC981FF,
                                                  )
                                                : const Color(
                                                    0xFF70D8FF,
                                                  ),
                                        fontSize:
                                            focused ? 6.5 : 5.4,
                                        fontWeight:
                                            FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    if (selected)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: MunjaColors.mint,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: MunjaColors.mint
                                    .withValues(alpha: 0.38),
                                blurRadius: 9,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: MunjaColors.bg,
                            size: 10,
                          ),
                        ),
                      )
                    else if (!usable && (isLocked || isPro))
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Icon(
                          Icons.lock_rounded,
                          size: 9,
                          color: Colors.white
                              .withValues(alpha: 0.42),
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

    class _FrameSection extends StatelessWidget {
      const _FrameSection({
        super.key,
        required this.frames,
        required this.selectedFrameId,
        required this.activeFrameId,
        required this.switchingFrame,
        required this.unlockingFrameId,
        required this.crystalBalance,
        required this.isFrameOwned,
        required this.onFrameSelected,
        required this.onUnlockRequested,
      });

      final List<_FrameVariantOption> frames;
      final String selectedFrameId;
      final String activeFrameId;
      final bool switchingFrame;
      final String? unlockingFrameId;
      final int crystalBalance;
      final bool Function(_FrameVariantOption frame) isFrameOwned;
      final ValueChanged<String> onFrameSelected;
      final ValueChanged<String> onUnlockRequested;

      @override
      Widget build(BuildContext context) {
        final selectedFrame = frames.firstWhere(
          (frame) => frame.id == selectedFrameId,
          orElse: () => frames.first,
        );

        final selectedOwned = isFrameOwned(selectedFrame);
        final selectedIsActive = selectedFrame.id == activeFrameId;
        final selectedCanAfford =
            selectedFrame.included ||
            crystalBalance >= selectedFrame.crystalPrice;
        final selectedUnlocking =
            unlockingFrameId == selectedFrame.id;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppText.t(selectedFrame.title).toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.25,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          selectedOwned
                              ? (selectedIsActive
                                  ? 'ACTIVE FRAME'
                                  : 'OWNED · TAP TO ACTIVATE')
                              : 'PREVIEW · UNLOCK TO ACTIVATE',
                          style: TextStyle(
                            color: selectedOwned
                                ? MunjaColors.mint
                                : const Color(0xFF70D8FF),
                            fontSize: 9.2,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.65,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.diamond_rounded,
                        color: Color(0xFF70D8FF),
                        size: 14,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$crystalBalance',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: frames.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final frame = frames[index];
                    final selected = frame.id == selectedFrameId;
                    final active = frame.id == activeFrameId;
                    final owned = isFrameOwned(frame);
                    final unlocking = unlockingFrameId == frame.id;
                    final canAfford =
                        frame.included ||
                        crystalBalance >= frame.crystalPrice;

                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: switchingFrame
                            ? null
                            : () => onFrameSelected(frame.id),
                        borderRadius: BorderRadius.circular(17),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: selected ? 132 : 116,
                          padding: const EdgeInsets.fromLTRB(
                            11,
                            10,
                            11,
                            9,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: selected
                                  ? [
                                      MunjaColors.mint
                                          .withValues(alpha: 0.14),
                                      Colors.black
                                          .withValues(alpha: 0.46),
                                    ]
                                  : [
                                      Colors.white
                                          .withValues(alpha: 0.03),
                                      Colors.black
                                          .withValues(alpha: 0.34),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(17),
                            border: Border.all(
                              color: selected
                                  ? MunjaColors.mint
                                      .withValues(alpha: 0.78)
                                  : Colors.white
                                      .withValues(alpha: 0.06),
                              width: selected ? 1.25 : 0.8,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    owned
                                        ? Icons.directions_bike_rounded
                                        : Icons.visibility_outlined,
                                    size: 17,
                                    color: selected || owned
                                        ? MunjaColors.mint
                                        : Colors.white
                                            .withValues(alpha: 0.42),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      AppText.t(frame.title)
                                          .toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white
                                            : Colors.white
                                                .withValues(alpha: 0.62),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (unlocking)
                                const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: MunjaColors.mint,
                                  ),
                                )
                              else if (owned)
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      active
                                          ? Icons.check_rounded
                                          : Icons.lock_open_rounded,
                                      color: MunjaColors.mint,
                                      size: 12,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      active ? 'ACTIVE' : 'OWNED',
                                      style: TextStyle(
                                        color: MunjaColors.mint
                                            .withValues(alpha: 0.90),
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.55,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.diamond_rounded,
                                      size: 12,
                                      color: canAfford
                                          ? const Color(0xFF70D8FF)
                                          : Colors.white30,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${frame.crystalPrice}',
                                      style: TextStyle(
                                        color: canAfford
                                            ? Colors.white
                                            : Colors.white30,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              if (!selectedOwned) ...[
                const SizedBox(height: 11),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: switchingFrame || selectedUnlocking
                        ? null
                        : () =>
                            onUnlockRequested(selectedFrame.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: MunjaColors.mint,
                      foregroundColor: MunjaColors.bg,
                      disabledBackgroundColor:
                          Colors.white.withValues(alpha: 0.07),
                      disabledForegroundColor:
                          Colors.white.withValues(alpha: 0.30),
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: selectedUnlocking
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MunjaColors.bg,
                            ),
                          )
                        : Row(
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.diamond_rounded,
                                size: 15,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                selectedCanAfford
                                    ? 'UNLOCK · ${selectedFrame.crystalPrice} CRYSTALS'
                                    : 'NEED ${selectedFrame.crystalPrice} CRYSTALS',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.55,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],

              const SizedBox(height: 10),
              Text(
                selectedOwned
                    ? 'Owned frames can be activated at any time. Skins control the bike finish.'
                    : 'You are previewing this frame. Buying it unlocks permanent activation.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.34),
                  fontSize: 8.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }
    }

    class _ComingSoonPanel extends StatelessWidget {
      const _ComingSoonPanel({
        super.key,
        required this.icon,
        required this.title,
        required this.subtitle,
      });

      final IconData icon;
      final String title;
      final String subtitle;

      @override
      Widget build(BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            color:
                MunjaColors.panel.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(27),
            border: Border.all(
              color:
                  Colors.white.withValues(alpha: 0.07),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: MunjaColors.mint
                      .withValues(alpha: 0.10),
                  borderRadius:
                      BorderRadius.circular(17),
                ),
                child: Icon(
                  icon,
                  color: MunjaColors.mint,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: MunjaColors.text,
                              fontSize: 15,
                              fontWeight:
                                  FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: MunjaColors.mint
                                .withValues(alpha: 0.09),
                            borderRadius:
                                BorderRadius.circular(999),
                          ),
                          child: Text(
                            AppText.t('comingSoon').toUpperCase(),
                            style: TextStyle(
                              color: MunjaColors.mint,
                              fontSize: 8,
                              fontWeight:
                                  FontWeight.w900,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white
                            .withValues(alpha: 0.42),
                        fontSize: 10,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
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
