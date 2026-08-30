import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'platform_interface.dart';

/// Android method channel implementation using Flutter's Texture API.
///
/// Communicates with the Kotlin plugin over a single [MethodChannel]
/// (`interactive_3d_plugin`) and per-texture [EventChannel]s for
/// selection and cache change events.
class MethodChannelInteractive3d extends Interactive3dPlatform {
  static const _pluginChannel = MethodChannel('interactive_3d_plugin');

  final Map<int, EventChannel> _eventChannels = {};
  final Map<int, StreamController<List<EntityData>>> _selectionControllers = {};
  final Map<int, StreamController<List<String>>> _cacheSelectionControllers = {};

  @override
  Future<Map<String, dynamic>> createTexture({
    required int width,
    required int height,
  }) async {
    final result = await _pluginChannel.invokeMethod<Map<dynamic, dynamic>>(
      'createTexture',
      {
        'width': width,
        'height': height,
      },
    );

    if (result == null) {
      throw Exception('Failed to create texture');
    }

    final textureId = result['textureId'] as int;
    _setupEventChannel(textureId);

    return {
      'textureId': textureId,
    };
  }

  @override
  Future<void> disposeTexture(int textureId) async {
    _selectionControllers[textureId]?.close();
    _cacheSelectionControllers[textureId]?.close();

    _selectionControllers.remove(textureId);
    _cacheSelectionControllers.remove(textureId);
    _eventChannels.remove(textureId);

    await _pluginChannel.invokeMethod(
      'disposeTexture',
      {
        'textureId': textureId,
      },
    );
  }

  void _setupEventChannel(int textureId) {
    final eventChannel = EventChannel(
      'interactive_3d_events_$textureId',
    );

    _eventChannels[textureId] = eventChannel;
    _selectionControllers[textureId] =
        StreamController<List<EntityData>>.broadcast();
    _cacheSelectionControllers[textureId] =
        StreamController<List<String>>.broadcast();

    eventChannel.receiveBroadcastStream().listen(
      (event) {
        _onEvent(textureId, event);
      },
    );
  }

  void _onEvent(
    int textureId,
    dynamic event,
  ) {
    final map = event as Map<dynamic, dynamic>;
    final String eventType = map['event'];

    if (eventType == 'selectionChanged') {
      final List<dynamic> selected = map['selectedEntities'];

      final entities = selected
          .map(
            (e) => EntityData(
              id: e['id'] as int,
              name: e['name'] as String,
            ),
          )
          .toList();

      _selectionControllers[textureId]?.add(entities);
    } else if (eventType == 'cacheSelectionChanged') {
      final List<dynamic> cached = map['cachedEntities'];

      final names = cached
          .map<String>(
            (e) => e['name'] as String,
          )
          .toList();

      _cacheSelectionControllers[textureId]?.add(names);
    }
  }

  @override
  Stream<List<EntityData>> selectionStream(int textureId) =>
      _selectionControllers[textureId]?.stream ??
      const Stream<List<EntityData>>.empty();

  @override
  Stream<List<String>> cacheSelectionStream(int textureId) =>
      _cacheSelectionControllers[textureId]?.stream ??
      const Stream<List<String>>.empty();

  @override
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
  }) async {
    debugPrint(
      'MUNJA MODEL LOAD DART START: '
      'textureId=$textureId | modelPath=$modelPath | modelUrl=$modelUrl',
    );

    Uint8List modelBytes;
    String modelName;

    if (modelPath != null) {
      final data = await rootBundle.load(modelPath);

      debugPrint(
        'MUNJA MODEL LOAD ASSET READ: '
        '$modelPath | bytes=${data.lengthInBytes}',
      );

      modelBytes = data.buffer.asUint8List();
      modelName = modelPath.split('/').last;
    } else if (modelUrl != null) {
      final response = await http.get(
        Uri.parse(modelUrl),
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load model: $modelUrl (${response.statusCode})',
        );
      }

      modelBytes = response.bodyBytes;
      modelName = modelUrl.split('/').last;
    } else {
      throw ArgumentError(
        'Must provide either modelPath or modelUrl',
      );
    }

    final resourceMap = resources.map(
      (key, value) => MapEntry(
        key,
        value.buffer.asUint8List(),
      ),
    );

    debugPrint(
      'MUNJA MODEL LOAD CHANNEL SEND: '
      'textureId=$textureId | name=$modelName | bytes=${modelBytes.length}',
    );

    await _pluginChannel.invokeMethod(
      'loadModel',
      {
        'textureId': textureId,
        'modelBytes': modelBytes,
        'name': modelName,
        'resources': resourceMap,
        'preselectedEntities': preselectedEntities,
        'selectionColor': selectionColor,
        'patchColors': patchColors
            ?.map(
              (p) => {
                'name': p.name,
                'color': p.color,
              },
            )
            .toList(),
        'enableCache': enableCache,
        'cacheColor': cacheColor,
        'clearSelectionsOnHighlight': clearSelectionsOnHighlight,
        'selectionSequence':
            selectionSequence?.map((c) => c.toJson()).toList(),
        'backgroundColor': backgroundColor,
        'initialMaterialOverrides':
            initialMaterialOverrides?.map((o) => o.toMap()).toList(),
      },
    );

    debugPrint(
      'MUNJA MODEL LOAD CHANNEL COMPLETE: '
      'textureId=$textureId | name=$modelName',
    );
  }

  /// MUNJA MODEL READINESS
  ///
  /// Queries the Android plugin for the real native Filament load state tied
  /// to this texture. Returns false while the texture/renderer/model is still
  /// being created.
  @override
  Future<bool> isModelLoaded({
    required int textureId,
  }) async {
    final ready = await _pluginChannel.invokeMethod<bool>(
      'isModelLoaded',
      {
        'textureId': textureId,
      },
    );

    final value = ready ?? false;

    debugPrint(
      'MUNJA MODEL READY DART CHANNEL: '
      'textureId=$textureId | ready=$value',
    );

    return value;
  }

  /// MUNJA NATIVE SHOWROOM ROTATION
  ///
  /// Sends one configuration call to Android. The actual per-frame camera
  /// animation then runs natively inside Filament/Choreographer.
  @override
  Future<void> startShowroomRotation({
    required int textureId,
    required double amplitudeDegrees,
    required int durationMs,
    required int resumeDelayMs,
  }) async {
    debugPrint(
      'MUNJA SHOWROOM DART CHANNEL START: '
      'textureId=$textureId | '
      'amplitude=${amplitudeDegrees}deg | '
      'duration=${durationMs}ms | '
      'resumeDelay=${resumeDelayMs}ms',
    );

    await _pluginChannel.invokeMethod(
      'startShowroomRotation',
      {
        'textureId': textureId,
        'amplitudeDegrees': amplitudeDegrees,
        'durationMs': durationMs,
        'resumeDelayMs': resumeDelayMs,
      },
    );
  }

  /// Stops the native showroom animation for this texture.
  @override
  Future<void> stopShowroomRotation({
    required int textureId,
  }) async {
    debugPrint(
      'MUNJA SHOWROOM DART CHANNEL STOP: textureId=$textureId',
    );

    await _pluginChannel.invokeMethod(
      'stopShowroomRotation',
      {
        'textureId': textureId,
      },
    );
  }

  @override
  Future<void> setEntityMaterials({
    required int textureId,
    required List<MaterialOverride> overrides,
  }) async {
    await _pluginChannel.invokeMethod(
      'setEntityMaterials',
      {
        'textureId': textureId,
        'overrides': overrides.map((o) => o.toMap()).toList(),
      },
    );
  }

  @override
  Future<void> resetEntityMaterials({
    required int textureId,
    List<String>? names,
  }) async {
    await _pluginChannel.invokeMethod(
      'resetEntityMaterials',
      {
        'textureId': textureId,
        'names': names,
      },
    );
  }

  /// MUNJA SAFE FRAME COLOR
  ///
  /// Sends an RGBA base color directly to the native renderer for the
  /// currently assigned MaterialInstance on [entityName].
  ///
  /// This is intentionally separate from [setEntityMaterials], because the
  /// native implementation updates baseColorFactor on the live material
  /// instance instead of creating or destroying replacement materials.
  @override
  Future<void> setEntityBaseColor({
    required int textureId,
    required String entityName,
    required List<double> rgba,
  }) async {
    if (entityName.trim().isEmpty) {
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
        'Must contain exactly four values',
      );
    }

    final normalized = rgba
        .map((value) => value.clamp(0.0, 1.0).toDouble())
        .toList(growable: false);

    debugPrint(
      'MUNJA FRAME COLOR DART CHANNEL: '
      '$entityName | rgba=$normalized | textureId=$textureId',
    );

    await _pluginChannel.invokeMethod(
      'setEntityBaseColor',
      {
        'textureId': textureId,
        'entityName': entityName,
        'rgba': normalized,
      },
    );
  }

  /// MUNJA DIRECT MATERIAL SWAP
  ///
  /// Sends the entity name and an existing GLB MaterialInstance name to the
  /// Android plugin. The native Filament renderer then assigns that material
  /// instance directly to the renderable entity.
  ///
  /// Example:
  ///   entityName: 'Frame 1'
  ///   materialInstanceName: 'Titanium_Frame_1'
  @override
  Future<void> setEntityMaterialInstance({
    required int textureId,
    required String entityName,
    required String materialInstanceName,
  }) async {
    debugPrint(
      'MUNJA DIRECT MATERIAL DART CHANNEL: '
      '$entityName -> $materialInstanceName | textureId=$textureId',
    );

    await _pluginChannel.invokeMethod(
      'setEntityMaterialInstance',
      {
        'textureId': textureId,
        'entityName': entityName,
        'materialInstanceName': materialInstanceName,
      },
    );
  }

  /// Restores the original GLB material(s) for a single entity after a direct
  /// material swap.
  @override
  Future<void> resetEntityDirectMaterial({
    required int textureId,
    required String entityName,
  }) async {
    debugPrint(
      'MUNJA DIRECT MATERIAL RESET DART CHANNEL: '
      '$entityName | textureId=$textureId',
    );

    await _pluginChannel.invokeMethod(
      'resetEntityDirectMaterial',
      {
        'textureId': textureId,
        'entityName': entityName,
      },
    );
  }

  /// Restores every direct material swap associated with this texture.
  @override
  Future<void> resetAllDirectMaterials({
    required int textureId,
  }) async {
    debugPrint(
      'MUNJA DIRECT MATERIAL RESET ALL DART CHANNEL: '
      'textureId=$textureId',
    );

    await _pluginChannel.invokeMethod(
      'resetAllDirectMaterials',
      {
        'textureId': textureId,
      },
    );
  }

  @override
  Future<void> loadEnvironment({
    required int textureId,
    String? iblPath,
    String? iblUrl,
    String? skyboxPath,
    String? skyboxUrl,
  }) async {
    Uint8List? iblBytes;
    Uint8List? skyboxBytes;

    try {
      if (iblPath != null) {
        iblBytes = (await rootBundle.load(iblPath))
            .buffer
            .asUint8List();
      } else if (iblUrl != null) {
        final response = await http.get(
          Uri.parse(iblUrl),
        );

        if (response.statusCode == 200) {
          iblBytes = response.bodyBytes;
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading IBL: $e',
      );
    }

    try {
      if (skyboxPath != null) {
        skyboxBytes = (await rootBundle.load(skyboxPath))
            .buffer
            .asUint8List();
      } else if (skyboxUrl != null) {
        final response = await http.get(
          Uri.parse(skyboxUrl),
        );

        if (response.statusCode == 200) {
          skyboxBytes = response.bodyBytes;
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading skybox: $e',
      );
    }

    if (iblBytes == null || skyboxBytes == null) {
      debugPrint(
        'Warning: Environment not fully loaded',
      );
      return;
    }

    await _pluginChannel.invokeMethod(
      'loadEnvironment',
      {
        'textureId': textureId,
        'iblBytes': iblBytes,
        'skyboxBytes': skyboxBytes,
      },
    );
  }

  @override
  Future<void> loadHdrBackground({
    required int textureId,
    String? backgroundPath,
    String? backgroundUrl,
  }) async {
    Uint8List? backgroundBytes;

    if (backgroundPath != null) {
      backgroundBytes = (await rootBundle.load(backgroundPath))
          .buffer
          .asUint8List();
    } else if (backgroundUrl != null) {
      final response = await http.get(
        Uri.parse(backgroundUrl),
      );

      if (response.statusCode == 200) {
        backgroundBytes = response.bodyBytes;
      } else {
        throw Exception(
          'Failed to load HDR/EXR from $backgroundUrl',
        );
      }
    } else {
      throw ArgumentError(
        'Must provide backgroundPath or backgroundUrl',
      );
    }

    await _pluginChannel.invokeMethod(
      'loadHdrBackground',
      {
        'textureId': textureId,
        'backgroundBytes': backgroundBytes,
      },
    );
  }

  @override
  Future<void> unselectEntities({
    required int textureId,
    List<int>? entityIds,
  }) async {
    await _pluginChannel.invokeMethod(
      'unselectEntities',
      {
        'textureId': textureId,
        'entityIds': entityIds
            ?.map(
              (id) => id.toInt(),
            )
            .toList(),
      },
    );
  }

  @override
  Future<void> updatePartGroupConfig({
    required int textureId,
    required bool isVisible,
    required ModelPartGroup group,
  }) async {
    await _pluginChannel.invokeMethod(
      'setPartGroupVisibility',
      {
        'textureId': textureId,
        'group': group.toMap(),
        'visibility': {
          group.title: isVisible,
        },
      },
    );
  }


  /// MUNJA EXCLUSIVE FRAME VISIBILITY
  ///
  /// Keeps exactly one entity from [entityNames] visible and hides the rest.
  /// This preserves the original mesh/material relationship exported in the
  /// GLB instead of replacing the material at runtime.
  ///
  /// Example:
  /// entityNames:
  ///   ['Frame 1', 'FRAME 2', 'FRAME 3', 'frame 4']
  ///
  /// activeEntityName:
  ///   'FRAME 2'
  @override
  Future<void> setExclusiveEntityVisibility({
    required int textureId,
    required List<String> entityNames,
    required String activeEntityName,
  }) async {
    if (entityNames.isEmpty) {
      throw ArgumentError.value(
        entityNames,
        'entityNames',
        'Must contain at least one entity name',
      );
    }

    if (activeEntityName.trim().isEmpty) {
      throw ArgumentError.value(
        activeEntityName,
        'activeEntityName',
        'Must not be empty',
      );
    }

    if (!entityNames.contains(activeEntityName)) {
      throw ArgumentError.value(
        activeEntityName,
        'activeEntityName',
        'Must be included in entityNames',
      );
    }

    debugPrint(
      'MUNJA FRAME VISIBILITY DART CHANNEL: '
      'active=$activeEntityName | '
      'managed=$entityNames | '
      'textureId=$textureId',
    );

    await _pluginChannel.invokeMethod(
      'setExclusiveEntityVisibility',
      {
        'textureId': textureId,
        'entityNames': entityNames,
        'activeEntityName': activeEntityName,
      },
    );
  }

  @override
  Future<void> setCameraZoomLevel(
    int textureId,
    double zoom,
  ) async {
    await _pluginChannel.invokeMethod(
      'setZoomLevel',
      {
        'textureId': textureId,
        'zoom': zoom,
      },
    );
  }

  @override
  Future<void> setCameraPose({
    required int textureId,
    required double horizontalDegrees,
    required double verticalDegrees,
    required double targetHeightFactor,
    required double zoom,
  }) async {
    await _pluginChannel.invokeMethod(
      'setCameraPose',
      {
        'textureId': textureId,
        'horizontalDegrees': horizontalDegrees,
        'verticalDegrees': verticalDegrees,
        'targetHeightFactor': targetHeightFactor,
        'zoom': zoom,
      },
    );
  }

  @override
  Future<void> clearCache(int textureId) async {
    await _pluginChannel.invokeMethod(
      'clearCache',
      {
        'textureId': textureId,
      },
    );
  }

  @override
  Future<void> refreshCacheHighlights(
    int textureId,
  ) async {
    await _pluginChannel.invokeMethod(
      'refreshCacheHighlights',
      {
        'textureId': textureId,
      },
    );
  }

  @override
  Future<void> removeFromCache(
    int textureId,
    List<String> names,
  ) async {
    await _pluginChannel.invokeMethod(
      'removeFromCache',
      {
        'textureId': textureId,
        'names': names,
      },
    );
  }

  @override
  Future<void> onTouchEvent({
    required int textureId,
    required String action,
    double? x,
    double? y,
    double? deltaX,
    double? deltaY,
    double? scale,
  }) async {
    await _pluginChannel.invokeMethod(
      'onTouchEvent',
      {
        'textureId': textureId,
        'action': action,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (deltaX != null) 'deltaX': deltaX,
        if (deltaY != null) 'deltaY': deltaY,
        if (scale != null) 'scale': scale,
      },
    );
  }
}
