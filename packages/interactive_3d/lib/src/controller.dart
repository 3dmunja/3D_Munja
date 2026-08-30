import 'dart:async';

import 'widget.dart';
import 'models.dart';

/// Programmatic controller for the [Interactive3d] widget.
///
/// Attach to a widget via [Interactive3d.controller]. The controller
/// forwards calls to the underlying platform view (iOS) or texture
/// renderer (Android) through [Interactive3dState].
///
/// ```dart
/// final controller = Interactive3dController();
///
/// Interactive3d(
///   controller: controller,
///   modelPath: 'assets/model.glb',
/// );
///
/// // Later:
/// await controller.clearSelections();
/// ```
class Interactive3dController {
  Interactive3dState? _state;

  /// Attaches to the given [Interactive3dState]. Called automatically
  /// by the widget, do not call manually.
  void attach(Interactive3dState state) {
    _state = state;
  }

  /// Detaches if currently attached to [state], or unconditionally if [state]
  /// is null. The identity check guards against an old state's dispose
  /// stomping a new state's attach when the widget rebuilds with a new key.
  void detach([Interactive3dState? state]) {
    if (state == null || identical(_state, state)) {
      _state = null;
    }
  }

  void _ensureAttached() {
    if (_state == null) {
      throw StateError(
        'Interactive3dController is not attached to a widget',
      );
    }
  }

  /// MUNJA native model readiness.
  ///
  /// Returns the current native renderer readiness state.
  Future<bool> isModelLoaded() async {
    _ensureAttached();
    return _state!.isModelLoaded();
  }

  /// Waits until the native Filament model is actually loaded.
  ///
  /// This prevents frame visibility, frame-color and direct material commands
  /// from racing the Android model loader during startup.
  Future<void> waitUntilModelLoaded({
    Duration timeout = const Duration(seconds: 15),
    Duration pollInterval = const Duration(milliseconds: 50),
  }) async {
    _ensureAttached();

    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'Must be greater than zero',
      );
    }

    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'Must be greater than zero',
      );
    }

    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed < timeout) {
      _ensureAttached();

      if (await _state!.isModelLoaded()) {
        stopwatch.stop();
        return;
      }

      await Future<void>.delayed(pollInterval);
    }

    stopwatch.stop();

    throw TimeoutException(
      'Interactive3d native model was not ready within '
      '${timeout.inMilliseconds} ms.',
      timeout,
    );
  }

  /// Unselects specific entities by ID, or all if [entityIds] is null.
  Future<void> unselectEntities({
    List<int>? entityIds,
  }) async {
    _ensureAttached();
    await _state!.unselectEntities(
      entityIds: entityIds,
    );
  }

  /// Clears all current selections.
  Future<void> clearSelections() async {
    await unselectEntities();
  }

  /// Sets the camera zoom level. Values above 1.0 zoom in, below zoom out.
  Future<void> setCameraZoomLevel(
    double zoomLevel,
  ) async {
    _ensureAttached();
    await _state!.setZoom(
      zoomLevel,
    );
  }

  Future<void> setCameraPose({
    required double horizontalDegrees,
    required double verticalDegrees,
    required double targetHeightFactor,
    required double zoom,
  }) async {
    _ensureAttached();

    await _state!.setCameraPose(
      horizontalDegrees: horizontalDegrees,
      verticalDegrees: verticalDegrees,
      targetHeightFactor: targetHeightFactor,
      zoom: zoom,
    );
  }

  /// Starts Munja's native showroom camera animation.
  ///
  /// Android runs the oscillation directly inside Filament's render loop,
  /// avoiding frame-by-frame MethodChannel traffic from Dart.
  ///
  /// [amplitudeDegrees] controls how far the camera swings to either side of
  /// its current horizontal orbit. A value around 8-12 degrees gives a subtle
  /// premium showroom effect.
  ///
  /// [cycleDuration] is one complete left -> right -> left cycle.
  ///
  /// [resumeDelay] is how long native rendering waits after manual camera
  /// interaction before the showroom motion starts again.
  Future<void> startShowroomRotation({
    double amplitudeDegrees = 10.0,
    Duration cycleDuration = const Duration(milliseconds: 2600),
    Duration resumeDelay = const Duration(seconds: 2),
  }) async {
    _ensureAttached();

    if (!amplitudeDegrees.isFinite ||
        amplitudeDegrees < 2.0 ||
        amplitudeDegrees > 30.0) {
      throw ArgumentError.value(
        amplitudeDegrees,
        'amplitudeDegrees',
        'Must be finite and between 2.0 and 30.0 degrees',
      );
    }

    if (cycleDuration.inMilliseconds < 900 ||
        cycleDuration.inMilliseconds > 12000) {
      throw ArgumentError.value(
        cycleDuration,
        'cycleDuration',
        'Must be between 900 ms and 12000 ms',
      );
    }

    if (resumeDelay.isNegative ||
        resumeDelay.inMilliseconds > 10000) {
      throw ArgumentError.value(
        resumeDelay,
        'resumeDelay',
        'Must be between 0 ms and 10000 ms',
      );
    }

    await _state!.startShowroomRotation(
      amplitudeDegrees: amplitudeDegrees,
      cycleDuration: cycleDuration,
      resumeDelay: resumeDelay,
    );
  }

  /// Stops the native showroom camera animation while preserving the current
  /// camera angle. Manual 360-degree rotation remains available.
  Future<void> stopShowroomRotation() async {
    _ensureAttached();
    await _state!.stopShowroomRotation();
  }

  /// Toggles visibility for a group of model parts.
  Future<void> updatePartGroupConfig({
    required bool isVisible,
    required ModelPartGroup group,
  }) async {
    _ensureAttached();
    await _state!.updatePartGroupConfig(
      isVisible: isVisible,
      group: group,
    );
  }

  /// MUNJA exclusive entity visibility.
  ///
  /// Keeps exactly one entity from [entityNames] visible and hides the rest.
  /// This is the preferred path for Munja frames that already exist as separate
  /// meshes inside the GLB with their own original PBR materials/textures.
  ///
  /// Example:
  ///
  /// ```dart
  /// await controller.setExclusiveEntityVisibility(
  ///   entityNames: [
  ///     'Frame 1',
  ///     'FRAME 2',
  ///     'FRAME 3',
  ///     'frame 4',
  ///   ],
  ///   activeEntityName: 'FRAME 2',
  /// );
  /// ```
  Future<void> setExclusiveEntityVisibility({
    required List<String> entityNames,
    required String activeEntityName,
  }) async {
    _ensureAttached();

    await _state!.setExclusiveEntityVisibility(
      entityNames: entityNames,
      activeEntityName: activeEntityName,
    );
  }

  /// Clears the persistent selection cache for the current model.
  Future<void> clearCache() async {
    _ensureAttached();
    await _state!.clearCache();
  }

  /// Re-applies cache highlight colors to all cached entities.
  Future<void> refreshCacheHighlights() async {
    _ensureAttached();
    await _state!.refreshCacheHighlights();
  }

  /// Removes specific entities from the persistent cache by name.
  Future<void> removeFromCache(
    List<String> names,
  ) async {
    _ensureAttached();
    await _state!.removeFromCache(
      names,
    );
  }

  /// Applies a persistent PBR override to a single entity.
  ///
  /// Null fields keep their prior value; pass any combination of fields.
  Future<void> setEntityMaterial({
    required String name,
    List<double>? color,
    double? metallic,
    double? roughness,
    List<double>? emissive,
  }) async {
    _ensureAttached();

    await _state!.setEntityMaterials(
      [
        MaterialOverride(
          name: name,
          color: color,
          metallic: metallic,
          roughness: roughness,
          emissive: emissive,
        ),
      ],
    );
  }

  /// Applies persistent PBR overrides to many entities in one call.
  Future<void> setEntityMaterials(
    List<MaterialOverride> overrides,
  ) async {
    _ensureAttached();

    await _state!.setEntityMaterials(
      overrides,
    );
  }

  /// Removes the override on [name], restoring the GLB original.
  Future<void> resetEntityMaterial(
    String name,
  ) async {
    _ensureAttached();

    await _state!.resetEntityMaterials(
      [name],
    );
  }

  /// Removes all active PBR overrides, restoring every overridden entity.
  Future<void> resetAllMaterialOverrides() async {
    _ensureAttached();

    await _state!.resetEntityMaterials(
      null,
    );
  }

  /// MUNJA safe frame base-color update.
  ///
  /// Updates the baseColorFactor on the MaterialInstance already assigned to
  /// [entityName]. This path avoids creating, cloning, replacing or destroying
  /// MaterialInstances while they may still be referenced by Filament.
  ///
  /// [rgba] must contain exactly four normalized values:
  /// red, green, blue and alpha, each from 0.0 to 1.0.
  Future<void> setEntityBaseColor({
    required String entityName,
    required List<double> rgba,
  }) async {
    _ensureAttached();

    final cleanEntityName = entityName.trim();

    if (cleanEntityName.isEmpty) {
      throw ArgumentError.value(
        entityName,
        'entityName',
        'Must not be empty',
      );
    }

    if (rgba.length != 4) {
      throw ArgumentError.value(
        rgba,
        'rgba',
        'Must contain exactly 4 values: red, green, blue, alpha',
      );
    }

    for (final value in rgba) {
      if (!value.isFinite || value < 0.0 || value > 1.0) {
        throw ArgumentError.value(
          rgba,
          'rgba',
          'Every color value must be finite and between 0.0 and 1.0',
        );
      }
    }

    await _state!.setEntityBaseColor(
      entityName: cleanEntityName,
      rgba: rgba,
    );
  }

  /// MUNJA direct material swap.
  ///
  /// Assigns an existing MaterialInstance that is already embedded in the
  /// loaded GLB to the renderable entity identified by [entityName].
  ///
  /// This is separate from [setEntityMaterial]:
  /// - [setEntityMaterial] modifies PBR parameters on a material.
  /// - [setEntityMaterialInstance] swaps to a real material instance from
  ///   the GLB, preserving the real skin texture / normal / roughness maps.
  ///
  /// Example:
  ///
  /// ```dart
  /// await controller.setEntityMaterialInstance(
  ///   entityName: 'Frame 1',
  ///   materialInstanceName: 'Titanium_Frame_1',
  /// );
  /// ```
  Future<void> setEntityMaterialInstance({
    required String entityName,
    required String materialInstanceName,
  }) async {
    _ensureAttached();

    await _state!.setEntityMaterialInstance(
      entityName: entityName,
      materialInstanceName: materialInstanceName,
    );
  }

  /// Restores the original GLB material(s) for one entity after a direct
  /// material swap.
  Future<void> resetEntityDirectMaterial({
    required String entityName,
  }) async {
    _ensureAttached();

    await _state!.resetEntityDirectMaterial(
      entityName: entityName,
    );
  }

  /// Restores every direct material swap currently active in the 3D view.
  Future<void> resetAllDirectMaterials() async {
    _ensureAttached();

    await _state!.resetAllDirectMaterials();
  }
}
