import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';

/// Platform interface for the interactive_3d plugin.
///
/// Defines the contract that platform-specific implementations must fulfil.
/// Currently only [MethodChannelInteractive3d] (Android Texture API) implements
/// this interface. iOS uses a PlatformView with its own method channel.
abstract class Interactive3dPlatform extends PlatformInterface {
  Interactive3dPlatform() : super(token: _token);

  static final Object _token = Object();

  static void verify(Interactive3dPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
  }

  /// Creates a GPU-backed texture and returns `{'textureId': int}`.
  Future<Map<String, dynamic>> createTexture({
    required int width,
    required int height,
  });

  /// Releases the texture and all associated native resources.
  Future<void> disposeTexture(int textureId);

  /// Loads a 3D model into the renderer bound to [textureId].
  Future<void> loadModel({
    required int textureId,
    String? modelPath,
    String? modelUrl,
    required Map<String, ByteData> resources,
    List<String>? preselectedEntities,
    List<double>? selectionColor,
    List<PatchColor>? patchColors,
    bool enableCache = false,
    List<double>? cacheColor,
    bool clearSelectionsOnHighlight = false,
    List<SequenceConfig>? selectionSequence,
    List<double>? backgroundColor,
    List<MaterialOverride>? initialMaterialOverrides,
  });

  /// MUNJA native model readiness.
  ///
  /// Returns true only when the renderer bound to [textureId] has finished
  /// loading its Filament model and has a live current asset.
  ///
  /// Callers can poll this before sending visibility, frame-color or direct
  /// material operations to avoid startup races with the native model loader.
  Future<bool> isModelLoaded({
    required int textureId,
  });

  /// Loads IBL and skybox environment lighting.
  Future<void> loadEnvironment({
    required int textureId,
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  });

  /// Loads an HDR/EXR background (iOS only).
  Future<void> loadHdrBackground({
    required int textureId,
    String? backgroundPath,
    String? backgroundUrl,
  });

  /// Sets the camera zoom level.
  Future<void> setCameraZoomLevel(
    int textureId,
    double zoom,
  );

  Future<void> setCameraPose({
    required int textureId,
    required double horizontalDegrees,
    required double verticalDegrees,
    required double targetHeightFactor,
    required double zoom,
  });

  /// Starts native showroom camera motion for [textureId].
  ///
  /// Android performs the animation directly in Filament's render loop.
  Future<void> startShowroomRotation({
    required int textureId,
    required double amplitudeDegrees,
    required int durationMs,
    required int resumeDelayMs,
  });

  /// Stops native showroom camera motion while keeping the current orbit.
  Future<void> stopShowroomRotation({
    required int textureId,
  });

  /// Toggles visibility for a group of model parts.
  Future<void> updatePartGroupConfig({
    required int textureId,
    required bool isVisible,
    required ModelPartGroup group,
  });

  /// MUNJA exclusive entity visibility.
  ///
  /// Keeps exactly one entity from [entityNames] visible and hides the rest.
  ///
  /// This is used for the native Munja frame system so each exported frame mesh
  /// keeps its original GLB material, UVs, textures, normal map, metallic map
  /// and roughness map.
  ///
  /// Example:
  /// entityNames:
  ///   ['Frame 1', 'FRAME 2', 'FRAME 3', 'frame 4']
  ///
  /// activeEntityName:
  ///   'FRAME 2'
  Future<void> setExclusiveEntityVisibility({
    required int textureId,
    required List<String> entityNames,
    required String activeEntityName,
  });

  /// Unselects entities by ID, or all if [entityIds] is null.
  Future<void> unselectEntities({
    required int textureId,
    List<int>? entityIds,
  });

  /// Clears the persistent selection cache.
  Future<void> clearCache(int textureId);

  /// Re-applies cache highlight colors.
  Future<void> refreshCacheHighlights(int textureId);

  /// Removes specific entities from the cache by name.
  Future<void> removeFromCache(
    int textureId,
    List<String> names,
  );

  /// Applies one or more PBR overrides.
  ///
  /// Each override merges into per-entity state and operates on the currently
  /// assigned material instance for that entity.
  Future<void> setEntityMaterials({
    required int textureId,
    required List<MaterialOverride> overrides,
  });

  /// Removes overrides for [names], or all when [names] is null.
  Future<void> resetEntityMaterials({
    required int textureId,
    List<String>? names,
  });

  /// MUNJA safe frame base-color update.
  ///
  /// Updates the baseColorFactor on the MaterialInstance that is already
  /// assigned to [entityName]. This avoids creating, replacing, cloning or
  /// destroying a MaterialInstance that may still be referenced by Filament.
  ///
  /// [rgba] must contain exactly four normalized values in the range 0.0-1.0:
  /// red, green, blue and alpha.
  Future<void> setEntityBaseColor({
    required int textureId,
    required String entityName,
    required List<double> rgba,
  });

  /// MUNJA direct material swap.
  ///
  /// Assigns an existing MaterialInstance already embedded in the loaded GLB
  /// to all renderable primitives of the entity identified by [entityName].
  ///
  /// This path is retained for compatibility and material experiments. The
  /// Munja frame/skin flow can instead use [setExclusiveEntityVisibility]
  /// whenever the desired look is already exported as a dedicated frame mesh.
  ///
  /// Example:
  /// entityName: 'Frame 1'
  /// materialInstanceName: 'Titanium_Frame_1'
  Future<void> setEntityMaterialInstance({
    required int textureId,
    required String entityName,
    required String materialInstanceName,
  });

  /// Restores the original GLB material(s) for one entity that was previously
  /// modified through [setEntityMaterialInstance].
  Future<void> resetEntityDirectMaterial({
    required int textureId,
    required String entityName,
  });

  /// Restores every direct material swap associated with [textureId].
  Future<void> resetAllDirectMaterials({
    required int textureId,
  });

  /// Forwards a touch event to the native renderer.
  Future<void> onTouchEvent({
    required int textureId,
    required String action,
    double? x,
    double? y,
    double? deltaX,
    double? deltaY,
    double? scale,
  });

  /// Stream of selection changes for a given texture.
  Stream<List<EntityData>> selectionStream(int textureId);

  /// Stream of cache selection changes for a given texture.
  Stream<List<String>> cacheSelectionStream(int textureId);
}
