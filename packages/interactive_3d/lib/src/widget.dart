import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'controller.dart';
import 'method_channel.dart';
import 'models.dart';
import 'platform_interface.dart';

/// A widget for rendering and interacting with 3D models.
///
/// On Android, renders via Flutter's Texture widget backed by a Filament
/// SurfaceProducer. On iOS, renders via a native SCNView embedded through
/// UiKitView.
///
/// ```dart
/// Interactive3d(
///   modelPath: 'assets/models/tooth.glb',
///   iblPath: 'assets/models/env_ibl.ktx',
///   skyboxPath: 'assets/models/env_skybox.ktx',
///   selectionColor: [0.0, 0.4, 1.0, 1.0],
///   onSelectionChanged: (entities) => print(entities),
/// )
/// ```
class Interactive3d extends StatefulWidget {
  /// Path to the 3D model (.glb/.gltf) in the asset bundle.
  final String? modelPath;

  /// URL to download the 3D model (.glb/.gltf) from the network.
  final String? modelUrl;

  /// Asset path for the IBL lighting file (.ktx).
  final String? iblPath;

  /// URL for the IBL lighting file (.ktx).
  final String? iblUrl;

  /// Asset path for the skybox texture (.ktx).
  final String? skyboxPath;

  /// URL for the skybox texture (.ktx).
  final String? skyboxUrl;

  /// Asset path for the iOS HDR/EXR background environment.
  final String? iOSBackgroundEnvPath;

  /// URL for the iOS HDR/EXR background environment.
  final String? iOSBackgroundEnvUrl;

  /// Additional resource paths for multi-file .gltf models (textures, .bin).
  final List<String> resources;

  /// Called when the set of selected entities changes.
  final void Function(List<EntityData>)? onSelectionChanged;

  /// Entity names to highlight when the model first loads.
  final List<String>? preselectedEntities;

  /// Default highlight color for selected entities. RGBA 0.0–1.0.
  final List<double>? selectionColor;

  /// Initial camera zoom level.
  final double? defaultZoom;

  /// Solid background color (RGBA 0.0–1.0). When set, replaces the skybox.
  final List<double>? solidBackgroundColor;

  /// Per-entity color overrides for selection highlights.
  final List<PatchColor>? patchColors;

  /// Controller for programmatic interaction with the 3D view.
  final Interactive3dController? controller;

  /// Enables persistent selection caching across sessions.
  final bool enableCache;

  /// Color used for cached entity highlights. RGBA 0.0–1.0.
  final List<double>? cacheColor;

  /// Called when the cached selection set changes.
  final void Function(List<String>)? onCacheSelectionChanged;

  /// When true, clears active selections when cache highlights are applied.
  final bool clearSelectionOnHighlight;

  /// Ordered selection rules that constrain which entities can be tapped next.
  final List<SequenceConfig>? selectionSequence;

  /// Background color shown while the model is loading.
  final Color backgroundColor;

  /// Widget displayed while the model is loading.
  final Widget? loadingWidget;

  /// PBR overrides to apply once when the model first loads. Selection wins
  /// visually; deselect restores the override.
  final List<MaterialOverride>? initialMaterialOverrides;

  /// iOS only:
  /// When true, the native UiKitView eagerly receives touch gestures.
  /// Used by Munja Customize so one-finger drag reaches SceneKit reliably.
  final bool iOSEagerGestures;

  const Interactive3d({
    super.key,
    this.modelPath,
    this.modelUrl,
    this.iblPath,
    this.iblUrl,
    this.skyboxPath,
    this.skyboxUrl,
    this.iOSBackgroundEnvPath,
    this.iOSBackgroundEnvUrl,
    this.onSelectionChanged,
    this.resources = const [],
    this.preselectedEntities,
    this.selectionColor,
    this.defaultZoom,
    this.solidBackgroundColor,
    this.patchColors,
    this.controller,
    this.enableCache = false,
    this.cacheColor,
    this.onCacheSelectionChanged,
    this.clearSelectionOnHighlight = false,
    this.selectionSequence,
    this.backgroundColor = Colors.black,
    this.loadingWidget,
    this.initialMaterialOverrides,
    this.iOSEagerGestures = false,
  });

  @override
  Interactive3dState createState() => Interactive3dState();
}

/// State for [Interactive3d].
///
/// Public methods ([setZoom], [clearCache], etc.) are called by
/// [Interactive3dController] and route to the correct platform.
class Interactive3dState extends State<Interactive3d> {
  // Android (Texture API)
  Interactive3dPlatform? _platform;
  int? _textureId;
  bool _isInitializing = false;
  double _renderRatio = 1.0;

  // iOS (PlatformView)
  MethodChannel? _iosMethodChannel;
  StreamSubscription? _iosEventSubscription;

  // Shared
  StreamSubscription<List<EntityData>>? _selectionSubscription;
  StreamSubscription<List<String>>? _cacheSelectionSubscription;
  Size? _currentSize;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(this);
  }

  @override
  void didUpdateWidget(Interactive3d oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      widget.controller?.attach(this);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) return _buildIOSPlatformView();

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        if (_textureId == null &&
            !_isInitializing &&
            size.width > 0 &&
            size.height > 0) {
          final dpr = MediaQuery.of(context).devicePixelRatio;
          // High-end: near-native quality, Mid: balanced, Low: max performance
          // The native DeviceCapability tier is detected on init — here we approximate
          // based on pixel ratio as a proxy (high DPR devices tend to be flagship)
          _renderRatio = dpr >= 3.0 ? dpr.clamp(1.0, 2.0) : dpr.clamp(1.0, 1.5);
          _initializeTexture(size);
        }

        if (_currentSize != size && _textureId != null) {
          _currentSize = size;
          _updateTextureSize(size);
        }

        return Container(
          color: widget.backgroundColor,
          child: _textureId != null
              ? _buildTextureWidget()
              : (widget.loadingWidget ??
                  const Center(child: CircularProgressIndicator())),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // iOS — PlatformView
  // ---------------------------------------------------------------------------

  Widget _buildIOSPlatformView() {
    return UiKitView(
      viewType: 'interactive_3d',
      creationParams: {
        'modelPath': widget.modelPath,
        'modelUrl': widget.modelUrl,
        'solidBackgroundColor': widget.solidBackgroundColor,
      },
      creationParamsCodec: const StandardMessageCodec(),
      gestureRecognizers: widget.iOSEagerGestures
          ? <Factory<OneSequenceGestureRecognizer>>{
              Factory<OneSequenceGestureRecognizer>(
                () => EagerGestureRecognizer(),
              ),
            }
          : const <Factory<OneSequenceGestureRecognizer>>{},
      onPlatformViewCreated: _onIOSPlatformViewCreated,
    );
  }

  void _onIOSPlatformViewCreated(int viewId) {
    _iosMethodChannel = MethodChannel('interactive_3d_$viewId');
    final eventChannel = EventChannel('interactive_3d_events_$viewId');

    _iosEventSubscription =
        eventChannel.receiveBroadcastStream().listen((event) {
      final map = event as Map<dynamic, dynamic>;
      final String eventType = map['event'];

      if (eventType == 'selectionChanged') {
        final List<dynamic> selected = map['selectedEntities'];
        final entities = selected
            .map((e) =>
                EntityData(id: e['id'] as int, name: e['name'] as String))
            .toList();
        widget.onSelectionChanged?.call(entities);
      } else if (eventType == 'cacheSelectionChanged') {
        final List<dynamic> cached = map['cachedEntities'];
        final names = cached.map<String>((e) => e['name'] as String).toList();
        widget.onCacheSelectionChanged?.call(names);
      }
    });

    _loadIOSModelAndEnvironment();
  }

  Future<void> _loadIOSModelAndEnvironment() async {
    final channel = _iosMethodChannel;
    if (channel == null) return;

    try {
      Uint8List modelBytes;
      String modelName;

      if (widget.modelPath != null) {
        final data = await rootBundle.load(widget.modelPath!);
        modelBytes = data.buffer.asUint8List();
        modelName = widget.modelPath!.split('/').last;
      } else if (widget.modelUrl != null) {
        final response = await http.get(Uri.parse(widget.modelUrl!));
        if (response.statusCode != 200) {
          throw Exception('Failed to load model: ${widget.modelUrl}');
        }
        modelBytes = response.bodyBytes;
        modelName = widget.modelUrl!.split('/').last;
      } else {
        return;
      }

      await channel.invokeMethod('loadModel', {
        'modelBytes': modelBytes,
        'name': modelName,
        'preselectedEntities': widget.preselectedEntities,
        'selectionColor': widget.selectionColor,
        'patchColors': widget.patchColors
            ?.map((p) => {'name': p.name, 'color': p.color})
            .toList(),
        'enableCache': widget.enableCache,
        'cacheColor': widget.cacheColor,
        'clearSelectionsOnHighlight': widget.clearSelectionOnHighlight,
        'selectionSequence':
            widget.selectionSequence?.map((c) => c.toJson()).toList(),
        'backgroundColor': widget.solidBackgroundColor,
        'initialMaterialOverrides':
            widget.initialMaterialOverrides?.map((o) => o.toMap()).toList(),
      });

      // iOS HDR/EXR background
      if (widget.iOSBackgroundEnvPath != null ||
          widget.iOSBackgroundEnvUrl != null) {
        Uint8List? bgBytes;
        if (widget.iOSBackgroundEnvPath != null) {
          bgBytes = (await rootBundle.load(widget.iOSBackgroundEnvPath!))
              .buffer
              .asUint8List();
        } else if (widget.iOSBackgroundEnvUrl != null) {
          final response =
              await http.get(Uri.parse(widget.iOSBackgroundEnvUrl!));
          if (response.statusCode == 200) bgBytes = response.bodyBytes;
        }
        if (bgBytes != null) {
          await channel
              .invokeMethod('loadHdrBackground', {'backgroundBytes': bgBytes});
        }
      }

      if (widget.defaultZoom != null) {
        await channel
            .invokeMethod('setZoomLevel', {'zoom': widget.defaultZoom});
      }
    } catch (e) {
      debugPrint('Error loading iOS model: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Android — Texture API
  // ---------------------------------------------------------------------------

  Widget _buildTextureWidget() {
    return GestureDetector(
      onTapUp: _handleTapUp,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      child: Texture(textureId: _textureId!),
    );
  }

  Future<void> _initializeTexture(Size size) async {
    if (_isInitializing) {
      debugPrint(
        'MUNJA INIT SKIP: already initializing',
      );
      return;
    }

    _isInitializing = true;

    debugPrint(
      'MUNJA INIT 1: START | '
      'size=${size.width}x${size.height} | '
      'modelPath=${widget.modelPath} | '
      'modelUrl=${widget.modelUrl}',
    );

    try {
      _platform = MethodChannelInteractive3d();

      debugPrint(
        'MUNJA INIT 2: PLATFORM CREATED',
      );

      final result = await _platform!.createTexture(
        width: (size.width * _renderRatio).toInt(),
        height: (size.height * _renderRatio).toInt(),
      );

      debugPrint(
        'MUNJA INIT 3: TEXTURE RESULT=$result',
      );

      _textureId = result['textureId'] as int?;

      if (_textureId == null) {
        throw Exception(
          'Failed to create texture',
        );
      }

      debugPrint(
        'MUNJA INIT 4: TEXTURE CREATED | '
        'textureId=$_textureId',
      );

      _currentSize = size;

      if (mounted) {
        setState(() {});
      }

      debugPrint(
        'MUNJA INIT 5: BEFORE SELECTION STREAM | '
        'textureId=$_textureId',
      );

      _selectionSubscription = _platform!.selectionStream(_textureId!).listen(
        _onSelectionChanged,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'MUNJA SELECTION STREAM ERROR: $error',
          );
          debugPrint(
            '$stackTrace',
          );
        },
      );

      debugPrint(
        'MUNJA INIT 6: SELECTION STREAM READY',
      );

      if (widget.onCacheSelectionChanged != null) {
        debugPrint(
          'MUNJA INIT 7: BEFORE CACHE STREAM',
        );

        _cacheSelectionSubscription =
            _platform!.cacheSelectionStream(_textureId!).listen(
          widget.onCacheSelectionChanged!,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              'MUNJA CACHE STREAM ERROR: $error',
            );
            debugPrint(
              '$stackTrace',
            );
          },
        );

        debugPrint(
          'MUNJA INIT 8: CACHE STREAM READY',
        );
      }

      debugPrint(
        'MUNJA INIT 9: BEFORE MODEL/ENVIRONMENT LOAD',
      );

      await _loadAndroidModelAndEnvironment();

      debugPrint(
        'MUNJA INIT 10: MODEL/ENVIRONMENT FUNCTION RETURNED',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA INIT ERROR: $error',
      );
      debugPrint(
        '$stackTrace',
      );
    } finally {
      _isInitializing = false;

      debugPrint(
        'MUNJA INIT 11: FINISHED | '
        'textureId=$_textureId',
      );
    }
  }

  Future<void> _loadAndroidModelAndEnvironment() async {
    debugPrint(
      'MUNJA ANDROID LOAD 1: ENTER | '
      'textureId=$_textureId | '
      'platform=${_platform != null} | '
      'modelPath=${widget.modelPath} | '
      'modelUrl=${widget.modelUrl}',
    );

    if (_platform == null) {
      debugPrint(
        'MUNJA ANDROID LOAD STOP: platform=null',
      );
      return;
    }

    if (_textureId == null) {
      debugPrint(
        'MUNJA ANDROID LOAD STOP: textureId=null',
      );
      return;
    }

    try {
      Map<String, ByteData> resources = {};

      final modelSource = widget.modelPath ?? widget.modelUrl ?? '';

      debugPrint(
        'MUNJA ANDROID LOAD 2: SOURCE=$modelSource',
      );

      if (modelSource.endsWith('.gltf')) {
        debugPrint(
          'MUNJA ANDROID LOAD 3: LOADING GLTF RESOURCES',
        );

        resources = await _loadGltfResources();

        debugPrint(
          'MUNJA ANDROID LOAD 4: GLTF RESOURCES READY | '
          'count=${resources.length}',
        );
      }

      debugPrint(
        'MUNJA ANDROID LOAD 5: BEFORE PLATFORM LOADMODEL | '
        'textureId=$_textureId | '
        'modelPath=${widget.modelPath}',
      );

      await _platform!.loadModel(
        textureId: _textureId!,
        modelPath: widget.modelPath,
        modelUrl: widget.modelUrl,
        resources: resources,
        preselectedEntities: widget.preselectedEntities,
        selectionColor: widget.selectionColor,
        patchColors: widget.patchColors,
        enableCache: widget.enableCache,
        cacheColor: widget.cacheColor,
        clearSelectionsOnHighlight: widget.clearSelectionOnHighlight,
        selectionSequence: widget.selectionSequence,
        backgroundColor: widget.solidBackgroundColor,
        initialMaterialOverrides: widget.initialMaterialOverrides,
      );

      debugPrint(
        'MUNJA ANDROID LOAD 6: PLATFORM LOADMODEL RETURNED',
      );

      debugPrint(
        'MUNJA ANDROID LOAD 7: BEFORE ENVIRONMENT',
      );

      await _platform!.loadEnvironment(
        textureId: _textureId!,
        iblPath: widget.iblPath,
        iblUrl: widget.iblUrl,
        skyboxPath: widget.skyboxPath,
        skyboxUrl: widget.skyboxUrl,
      );

      debugPrint(
        'MUNJA ANDROID LOAD 8: ENVIRONMENT RETURNED',
      );

      if (widget.defaultZoom != null) {
        debugPrint(
          'MUNJA ANDROID LOAD 9: APPLY ZOOM '
          '${widget.defaultZoom}',
        );

        await setZoom(
          widget.defaultZoom,
        );
      }

      debugPrint(
        'MUNJA ANDROID LOAD 10: COMPLETE',
      );
    } catch (error, stackTrace) {
      debugPrint(
        'MUNJA ANDROID LOAD ERROR: $error',
      );
      debugPrint(
        '$stackTrace',
      );
      rethrow;
    }
  }

  Future<void> _updateTextureSize(Size size) async {
    // Future: update texture size on native side
  }

  // ---------------------------------------------------------------------------
  // Gesture Handling (Android only — iOS handles natively)
  // ---------------------------------------------------------------------------

  void _handleTapUp(TapUpDetails details) {
    if (_platform == null || _textureId == null) return;
    _platform!.onTouchEvent(
      textureId: _textureId!,
      action: 'tap',
      x: details.localPosition.dx * _renderRatio,
      y: details.localPosition.dy * _renderRatio,
    );
  }

  Offset? _lastFocalPoint;

  void _handleScaleStart(ScaleStartDetails details) {
    _lastFocalPoint = details.localFocalPoint;
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (_platform == null || _textureId == null) return;

    if (details.scale != 1.0) {
      _platform!.onTouchEvent(
        textureId: _textureId!,
        action: 'scale',
        scale: details.scale,
      );
    }

    if (_lastFocalPoint != null) {
      final delta = details.localFocalPoint - _lastFocalPoint!;
      if (delta.distance > 0.5) {
        _platform!.onTouchEvent(
          textureId: _textureId!,
          action: 'pan',
          deltaX: delta.dx * _renderRatio,
          deltaY: delta.dy * _renderRatio,
        );
      }
    }
    _lastFocalPoint = details.localFocalPoint;
  }

  // ---------------------------------------------------------------------------
  // Public API — routes to correct platform
  // ---------------------------------------------------------------------------

  /// MUNJA native model readiness.
  ///
  /// On Android this queries the real Filament load state for the current
  /// texture. This is the readiness signal used before frame visibility,
  /// frame-color and direct material operations are sent.
  ///
  /// iOS currently uses its own PlatformView pipeline and does not yet expose
  /// the same native readiness method. Once the iOS view channel exists we
  /// treat it as attached/ready for compatibility with the current API.
  Future<bool> isModelLoaded() async {
    if (Platform.isIOS) {
      return _iosMethodChannel != null;
    }

    final platform = _platform;
    final textureId = _textureId;

    if (platform == null || textureId == null) {
      debugPrint(
        'MUNJA MODEL READY WIDGET: '
        'texture unavailable | ready=false',
      );
      return false;
    }

    final ready = await platform.isModelLoaded(
      textureId: textureId,
    );

    debugPrint(
      'MUNJA MODEL READY WIDGET: '
      'textureId=$textureId | ready=$ready',
    );

    return ready;
  }

  /// Starts Munja's native showroom camera oscillation.
  ///
  /// Android: routed to the Texture-backed Filament renderer.
  /// iOS: intentionally left as a no-op until the SceneKit implementation
  /// exposes the matching native API.
  Future<void> startShowroomRotation({
    double amplitudeDegrees = 10.0,
    Duration cycleDuration = const Duration(milliseconds: 2600),
    Duration resumeDelay = const Duration(seconds: 2),
  }) async {
    if (Platform.isIOS) {
      debugPrint(
        'MUNJA SHOWROOM ROTATION: iOS native implementation not added yet.',
      );
      return;
    }

    final platform = _platform;
    final textureId = _textureId;

    if (platform == null || textureId == null) {
      debugPrint(
        'MUNJA SHOWROOM ROTATION START SKIP: '
        'texture/platform unavailable',
      );
      return;
    }

    await platform.startShowroomRotation(
      textureId: textureId,
      amplitudeDegrees: amplitudeDegrees,
      durationMs: cycleDuration.inMilliseconds,
      resumeDelayMs: resumeDelay.inMilliseconds,
    );

    debugPrint(
      'MUNJA SHOWROOM ROTATION STARTED: '
      'textureId=$textureId | '
      'amplitude=${amplitudeDegrees}deg | '
      'duration=${cycleDuration.inMilliseconds}ms | '
      'resumeDelay=${resumeDelay.inMilliseconds}ms',
    );
  }

  /// Stops the native showroom camera motion while preserving the current
  /// horizontal orbit.
  Future<void> stopShowroomRotation() async {
    if (Platform.isIOS) {
      return;
    }

    final platform = _platform;
    final textureId = _textureId;

    if (platform == null || textureId == null) {
      return;
    }

    await platform.stopShowroomRotation(
      textureId: textureId,
    );

    debugPrint(
      'MUNJA SHOWROOM ROTATION STOPPED: textureId=$textureId',
    );
  }

  Future<void> setZoom(double? level) async {
    if (level == null) return;
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('setZoomLevel', {'zoom': level});
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.setCameraZoomLevel(_textureId!, level);
    }
  }

  Future<void> setCameraPose({
    required double horizontalDegrees,
    required double verticalDegrees,
    required double targetHeightFactor,
    required double zoom,
  }) async {
    if (Platform.isIOS) {
      return;
    }

    if (_platform == null || _textureId == null) return;

    await _platform!.setCameraPose(
      textureId: _textureId!,
      horizontalDegrees: horizontalDegrees,
      verticalDegrees: verticalDegrees,
      targetHeightFactor: targetHeightFactor,
      zoom: zoom,
    );
  }

  Future<void> clearCache() async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('clearCache');
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.clearCache(_textureId!);
    }
  }

  Future<void> refreshCacheHighlights() async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('refreshCacheHighlights');
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.refreshCacheHighlights(_textureId!);
    }
  }

  Future<void> removeFromCache(List<String> names) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('removeFromCache', names);
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.removeFromCache(_textureId!, names);
    }
  }

  Future<void> updatePartGroupConfig({
    required bool isVisible,
    required ModelPartGroup group,
  }) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('setPartGroupVisibility', {
        'group': group.toMap(),
        'visibility': {group.title: isVisible},
      });
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.updatePartGroupConfig(
        textureId: _textureId!,
        isVisible: isVisible,
        group: group,
      );
    }
  }

  /// MUNJA EXCLUSIVE FRAME VISIBILITY
  ///
  /// Keeps exactly one of [entityNames] visible and hides the remaining
  /// entities. This lets Munja use the real frame meshes/materials already
  /// exported inside the GLB instead of trying to recreate a skin by changing
  /// PBR parameters at runtime.
  Future<void> setExclusiveEntityVisibility({
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
      'MUNJA FRAME VISIBILITY WIDGET: '
      'active=$activeEntityName | managed=$entityNames',
    );

    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod(
        'setExclusiveEntityVisibility',
        {
          'entityNames': entityNames,
          'activeEntityName': activeEntityName,
        },
      );
    } else {
      if (_platform == null || _textureId == null) return;

      await _platform!.setExclusiveEntityVisibility(
        textureId: _textureId!,
        entityNames: entityNames,
        activeEntityName: activeEntityName,
      );
    }
  }

  Future<void> unselectEntities({List<int>? entityIds}) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('unselectEntities', entityIds);
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!
          .unselectEntities(textureId: _textureId!, entityIds: entityIds);
    }
  }

  Future<void> setEntityMaterials(List<MaterialOverride> overrides) async {
    if (overrides.isEmpty) return;
    final payload = overrides.map((o) => o.toMap()).toList();
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('setEntityMaterials', payload);
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.setEntityMaterials(
        textureId: _textureId!,
        overrides: overrides,
      );
    }
  }

  /// Null [names] resets every active override.
  Future<void> resetEntityMaterials(List<String>? names) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod('resetEntityMaterials', names);
    } else {
      if (_platform == null || _textureId == null) return;
      await _platform!.resetEntityMaterials(
        textureId: _textureId!,
        names: names,
      );
    }
  }

  /// MUNJA safe base-color update.
  ///
  /// Updates the baseColorFactor on the material instance that is already
  /// assigned to [entityName]. No MaterialInstance is created, replaced,
  /// cloned or destroyed by this API.
  ///
  /// [rgba] must contain exactly four normalized values:
  /// red, green, blue and alpha, each from 0.0 to 1.0.
  Future<void> setEntityBaseColor({
    required String entityName,
    required List<double> rgba,
  }) async {
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

    debugPrint(
      'MUNJA BASE COLOR WIDGET: '
      '$cleanEntityName -> $rgba',
    );

    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod(
        'setEntityBaseColor',
        {
          'entityName': cleanEntityName,
          'rgba': rgba,
        },
      );
    } else {
      if (_platform == null || _textureId == null) return;

      await _platform!.setEntityBaseColor(
        textureId: _textureId!,
        entityName: cleanEntityName,
        rgba: rgba,
      );
    }
  }

  /// MUNJA direct material swap.
  ///
  /// Assigns an existing MaterialInstance already embedded in the loaded GLB
  /// to the renderable entity named [entityName].
  ///
  /// Android uses the Filament direct-material pipeline added for Munja.
  /// iOS receives the same method name so native iOS support can be added
  /// without changing the public controller API later.
  Future<void> setEntityMaterialInstance({
    required String entityName,
    required String materialInstanceName,
  }) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod(
        'setEntityMaterialInstance',
        {
          'entityName': entityName,
          'materialInstanceName': materialInstanceName,
        },
      );
    } else {
      if (_platform == null || _textureId == null) return;

      await _platform!.setEntityMaterialInstance(
        textureId: _textureId!,
        entityName: entityName,
        materialInstanceName: materialInstanceName,
      );
    }
  }

  /// Restores the original GLB material(s) for a single entity that was
  /// previously changed with [setEntityMaterialInstance].
  Future<void> resetEntityDirectMaterial({
    required String entityName,
  }) async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod(
        'resetEntityDirectMaterial',
        {
          'entityName': entityName,
        },
      );
    } else {
      if (_platform == null || _textureId == null) return;

      await _platform!.resetEntityDirectMaterial(
        textureId: _textureId!,
        entityName: entityName,
      );
    }
  }

  /// Restores all direct material swaps for the current 3D view.
  Future<void> resetAllDirectMaterials() async {
    if (Platform.isIOS) {
      await _iosMethodChannel?.invokeMethod(
        'resetAllDirectMaterials',
      );
    } else {
      if (_platform == null || _textureId == null) return;

      await _platform!.resetAllDirectMaterials(
        textureId: _textureId!,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, ByteData>> _loadGltfResources() async {
    Map<String, ByteData> resources = {};

    String baseDir = '';
    if (widget.modelPath != null) {
      baseDir = widget.modelPath!
          .substring(0, widget.modelPath!.lastIndexOf('/') + 1);
    } else if (widget.modelUrl != null) {
      baseDir =
          widget.modelUrl!.substring(0, widget.modelUrl!.lastIndexOf('/') + 1);
    }

    for (final file in widget.resources) {
      try {
        if (widget.modelPath != null) {
          resources[file] = await rootBundle.load('$baseDir$file');
        } else if (widget.modelUrl != null) {
          final uri = Uri.parse('$baseDir$file');
          resources[file] = await _loadNetworkResource(uri.toString());
        }
      } catch (e) {
        debugPrint('Optional resource not found: $file ($e)');
      }
    }

    return resources;
  }

  Future<ByteData> _loadNetworkResource(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return ByteData.view(response.bodyBytes.buffer);
    }
    throw Exception('Failed to load resource: $url (${response.statusCode})');
  }

  void _onSelectionChanged(List<EntityData> selectedEntities) {
    widget.onSelectionChanged?.call(selectedEntities);
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    _cacheSelectionSubscription?.cancel();
    _iosEventSubscription?.cancel();
    widget.controller?.detach(this);

    if (Platform.isIOS) {
      _iosMethodChannel?.invokeMethod('dispose');
      _iosMethodChannel = null;
    } else {
      if (_platform != null && _textureId != null) {
        _platform!.disposeTexture(_textureId!);
      }
    }

    super.dispose();
  }
}
