import 'dart:async';

import 'package:flutter/material.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../core/theme/munja_colors.dart';

/// Munja Digital Twin viewer used on Home and during navigation.
///
/// IMPORTANT:
/// This viewer now uses the same native `interactive_3d` renderer as
/// BikeCustomizeScreen. That is what allows Home/navigation to show the
/// user's REAL selected frame + skin instead of always showing a fixed GLB.
///
/// The parent (normally HomeScreen) should pass:
///
/// ```dart
/// MunjaNavigationBikeViewer(
///   navigationMode: isLive,
///   activeFrameId: activeBike.effectiveActiveFrameId,
///   activeSkinId: activeBike.effectiveActiveSkinId,
///   activeFrameColor: activeBike.frameColor,
/// )
/// ```
///
/// The widget is backward compatible: if no setup is supplied it falls back
/// to Frame 1 + Standard.
class MunjaNavigationBikeViewer extends StatefulWidget {
  const MunjaNavigationBikeViewer({
    super.key,
    this.navigationMode = false,
    this.height = 500,
    this.modelPath = defaultModelPath,
    this.enableTouch = true,
    this.backgroundColor = Colors.transparent,
    this.borderRadius = 34,
    this.showGrid = true,
    this.showGlow = true,

    // Kept for API compatibility with the previous ModelViewer version.
    this.homeCameraOrbit = '0deg 72deg 105%',
    this.homeCameraTarget = 'auto auto auto',
    this.homeFieldOfView = '38deg',
    this.navigationCameraOrbit = '180deg 72deg 105%',
    this.navigationCameraTarget = '0m 0.72m 0m',
    this.navigationFieldOfView = '32deg',
    this.ridingCameraOrbit = '180deg 86deg 32%',
    this.ridingCameraTarget = '0m 1.28m 0.16m',
    this.ridingFieldOfView = '22deg',

    this.rideSpeedKmh = 0.0,
    this.ridingSpeedThresholdKmh = 2.0,
    this.interpolationDecay = 900,
    this.exposure = 1.0,
    this.shadowIntensity = 0.0,
    this.shadowSoftness = 1.0,
    this.steeringAngleDegrees = 0.0,
    this.maxSteeringAngleDegrees = 14.0,
    this.steeringAnimationDuration =
        const Duration(milliseconds: 420),
    this.enableSteeringLean = true,
    this.steeringLeanFactor = 0.32,

    // NEW: Digital Twin setup.
    this.activeFrameId = 'frame_1',
    this.activeSkinId = 'standard',
    this.activeFrameColor = '#9AA2A0',

    this.onTap,
  });

  /// The master GLB contains all 4 frame entities and all embedded skin
  /// MaterialInstances. This MUST be the default if Home/navigation should
  /// match Garage/Customize.
  static const String defaultModelPath =
      'assets/models/kids_mtb_master.glb';

  final bool navigationMode;

  final double height;
  final String modelPath;
  final bool enableTouch;
  final Color backgroundColor;
  final double borderRadius;
  final bool showGrid;
  final bool showGlow;

  // Legacy camera API retained so existing HomeScreen calls still compile.
  final String homeCameraOrbit;
  final String homeCameraTarget;
  final String homeFieldOfView;

  final String navigationCameraOrbit;
  final String navigationCameraTarget;
  final String navigationFieldOfView;

  final String ridingCameraOrbit;
  final String ridingCameraTarget;
  final String ridingFieldOfView;

  final double rideSpeedKmh;
  final double ridingSpeedThresholdKmh;
  final num interpolationDecay;

  final num exposure;
  final num shadowIntensity;
  final num shadowSoftness;

  /// Visual steering input in degrees.
  ///
  /// Negative values steer/lean left.
  /// Positive values steer/lean right.
  final double steeringAngleDegrees;

  final double maxSteeringAngleDegrees;
  final Duration steeringAnimationDuration;
  final bool enableSteeringLean;
  final double steeringLeanFactor;

  /// Firestore Digital Twin frame id.
  ///
  /// Supported:
  /// frame_1 / frame_2 / frame_3 / frame_4
  final String activeFrameId;

  /// Firestore / Storage active skin id.
  ///
  /// Supported mappings below match BikeCustomizeScreen.
  final String activeSkinId;

  /// Used only for the Standard skin.
  ///
  /// Example: #79F2C0
  final String activeFrameColor;

  final VoidCallback? onTap;

  @override
  State<MunjaNavigationBikeViewer> createState() =>
      _MunjaNavigationBikeViewerState();
}

class _MunjaNavigationBikeViewerState
    extends State<MunjaNavigationBikeViewer> {
  final Interactive3dController _controller =
      Interactive3dController();

  bool _modelReady = false;
  bool _applyingSetup = false;
  bool _initializing = false;
  bool _disposed = false;
  bool _pendingDigitalTwinApply = false;
  bool _pendingCameraApply = false;

  int _lifecycleGeneration = 0;

  String? _lastAppliedFrameId;
  String? _lastAppliedSkinId;
  String? _lastAppliedFrameColor;

  static const List<String> _frameEntityNames = <String>[
    'Frame 1',
    'FRAME 2',
    'FRAME 3',
    'frame 4',
  ];

  static const Map<String, String> _frameEntityById =
      <String, String>{
    'frame_1': 'Frame 1',
    'frame_2': 'FRAME 2',
    'frame_3': 'FRAME 3',
    'frame_4': 'frame 4',
  };

  /// These names MUST remain identical to the MaterialInstance names exported
  /// inside kids_mtb_master.glb.
  static const Map<String, Map<String, String>>
      _materialBySkinAndFrame =
      <String, Map<String, String>>{
    'standard': <String, String>{
      'frame_1': 'Standard_Frame 1',
      'frame_2': 'Standard_Texture_Frame 2',
      'frame_3': 'Standard_Texture_Frame 3',
      'frame_4': 'Standard_Texture_Frame 4',
    },
    'brushed_metal': <String, String>{
      'frame_1': 'Brushed_Metal_Frame 1',
      'frame_2': 'Brushed_Metal_Frame 2',
      'frame_3': 'Brushed_Metal_Frame 3',
      'frame_4': 'Brushed_Metal_Frame 4',
    },
    'carbon_fibre': <String, String>{
      'frame_1': 'Carbon_Fibre_Frame 1',
      'frame_2': 'Carbon_Fibre_Frame 2',
      'frame_3': 'Carbon_Fibre_Frame 3',
      'frame_4': 'Carbon_Fibre_Frame 4',
    },
    'gold': <String, String>{
      'frame_1': 'Gold_frame 1',
      'frame_2': 'Gold_Frame 2',
      'frame_3': 'Gold_Frame 3',
      'frame_4': 'Gold_Frame 4',
    },
    'ice_silver': <String, String>{
      'frame_1': 'Ice_Silver_Frame 1',
      'frame_2': 'Ice_Silver_Frame 2',
      'frame_3': 'Ice_Silver_Frame 3',
      'frame_4': 'Ice_Silver_Frame 4',
    },
    'lava_red': <String, String>{
      'frame_1': 'Lava_Red_Frame 1',
      'frame_2': 'Lava_Red_Frame 2',
      'frame_3': 'Lava_Red_Frame 3',
      'frame_4': 'Lava_Red_Frame 4',
    },
    'matt_black': <String, String>{
      'frame_1': 'Matt_Black_Frame 1',
      'frame_2': 'Matt_Black_Frame 2',
      'frame_3': 'Matt_Black_Frame 3',
      'frame_4': 'Matt_Black_Frame 4',
    },
    'neon_green': <String, String>{
      'frame_1': 'Neon_Green_Frame 1',
      'frame_2': 'Neon_Green_Frame 2',
      'frame_3': 'Neon_Green_Frame 3',
      'frame_4': 'Neon_Green_Frame 4',
    },
  };

  @override
  void initState() {
    super.initState();

    _scheduleInitialization();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycleGeneration++;

    // Do not send native renderer commands from dispose().
    // Interactive3d detaches and releases its own native texture/render state.
    super.dispose();
  }

  void _scheduleInitialization() {
    final generation = ++_lifecycleGeneration;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isGenerationActive(generation)) {
        return;
      }

      // Give Interactive3d one additional event-loop turn to attach its
      // controller and create the native texture before we start polling.
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () {
          if (!_isGenerationActive(generation)) {
            return;
          }

          unawaited(
            _initializeAndApplySetup(
              generation: generation,
            ),
          );
        },
      );
    });
  }

  bool _isGenerationActive(int generation) {
    return mounted &&
        !_disposed &&
        generation == _lifecycleGeneration;
  }

  bool _isDetachedControllerError(Object error) {
    return error is StateError &&
        error.toString().contains(
          'Interactive3dController is not attached to a widget',
        );
  }

  Future<bool> _waitForNativeModel({
    required int generation,
    Duration timeout = const Duration(seconds: 25),
  }) async {
    final stopwatch = Stopwatch()..start();

    while (_isGenerationActive(generation) &&
        stopwatch.elapsed < timeout) {
      try {
        await _controller.waitUntilModelLoaded(
          timeout: const Duration(milliseconds: 900),
          pollInterval: const Duration(milliseconds: 75),
        );

        if (!_isGenerationActive(generation)) {
          return false;
        }

        return true;
      } catch (error) {
        if (!_isGenerationActive(generation)) {
          return false;
        }

        // During a rebuild Interactive3d can briefly detach the controller
        // before the replacement state attaches it. That is normal lifecycle
        // behaviour and must not be treated as a failed 3D model.
        if (_isDetachedControllerError(error) ||
            error is TimeoutException) {
          await Future<void>.delayed(
            const Duration(milliseconds: 120),
          );
          continue;
        }

        rethrow;
      }
    }

    return false;
  }

  @override
  void didUpdateWidget(
    covariant MunjaNavigationBikeViewer oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    final modelChanged =
        oldWidget.modelPath != widget.modelPath;

    final digitalTwinChanged =
        modelChanged ||
        oldWidget.activeFrameId != widget.activeFrameId ||
        oldWidget.activeSkinId != widget.activeSkinId ||
        oldWidget.activeFrameColor != widget.activeFrameColor;

    final cameraChanged =
        oldWidget.navigationMode != widget.navigationMode;

    if (modelChanged) {
      // The Interactive3d child gets a new key when modelPath changes.
      // Invalidate every async operation associated with the old renderer.
      _lifecycleGeneration++;
      _modelReady = false;
      _initializing = false;
      _applyingSetup = false;
      _lastAppliedFrameId = null;
      _lastAppliedSkinId = null;
      _lastAppliedFrameColor = null;
      _pendingDigitalTwinApply = true;
      _pendingCameraApply = true;

      _scheduleInitialization();
    } else {
      if (digitalTwinChanged) {
        _pendingDigitalTwinApply = true;
      }

      if (cameraChanged) {
        _pendingCameraApply = true;
      }

      if (_modelReady) {
        final generation = _lifecycleGeneration;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isGenerationActive(generation)) {
            return;
          }

          if (_pendingDigitalTwinApply) {
            unawaited(
              _applyDigitalTwinSetup(
                force: true,
                generation: generation,
              ),
            );
          }

          if (_pendingCameraApply) {
            unawaited(
              _applyNativeCameraPose(
                generation: generation,
              ),
            );
          }
        });
      } else if (!_initializing) {
        _scheduleInitialization();
      }
    }

    if (oldWidget.steeringAngleDegrees !=
        widget.steeringAngleDegrees) {
      debugPrint(
        'MUNJA STEERING: '
        '${oldWidget.steeringAngleDegrees.toStringAsFixed(1)}° '
        '→ ${widget.steeringAngleDegrees.toStringAsFixed(1)}°',
      );
    }
  }

  String get _safeFrameId {
    final value = widget.activeFrameId.trim();
    return _frameEntityById.containsKey(value)
        ? value
        : 'frame_1';
  }

  String get _safeSkinId {
    final value = widget.activeSkinId.trim();

    return _materialBySkinAndFrame.containsKey(value)
        ? value
        : 'standard';
  }

  String get _activeFrameEntity =>
      _frameEntityById[_safeFrameId]!;

  Future<void> _initializeAndApplySetup({
    required int generation,
  }) async {
    if (!_isGenerationActive(generation) || _initializing) {
      return;
    }

    _initializing = true;

    try {
      final ready = await _waitForNativeModel(
        generation: generation,
      );

      if (!_isGenerationActive(generation) || !ready) {
        return;
      }

      _modelReady = true;
      _pendingDigitalTwinApply = true;
      _pendingCameraApply = true;

      await _applyDigitalTwinSetup(
        force: true,
        generation: generation,
      );

      if (!_isGenerationActive(generation)) {
        return;
      }

      await _applyNativeCameraPose(
        generation: generation,
      );

      debugPrint(
        'MUNJA NAVIGATION DIGITAL TWIN READY: '
        'generation=$generation',
      );
    } catch (error, stackTrace) {
      if (!_isGenerationActive(generation)) {
        return;
      }

      if (_isDetachedControllerError(error)) {
        debugPrint(
          'MUNJA NAVIGATION DIGITAL TWIN READY CANCELLED: '
          'controller temporarily detached',
        );
        return;
      }

      debugPrint(
        'MUNJA NAVIGATION DIGITAL TWIN READY ERROR: $error',
      );
      debugPrint('$stackTrace');
    } finally {
      if (_isGenerationActive(generation)) {
        _initializing = false;
      }
    }
  }

  Future<void> _applyNativeCameraPose({
    required int generation,
  }) async {
    if (!_isGenerationActive(generation) || !_modelReady) {
      return;
    }

    try {
      if (widget.navigationMode) {
        // This reproduces the OLD working cockpit direction:
        //
        // ModelViewer:
        //   ridingCameraOrbit  = 180deg 86deg ...
        //   ridingCameraTarget = high on the bike
        //
        // Native Filament:
        //   horizontal 180° = rider-facing side
        //   vertical 4°     = equivalent to ~86° polar orbit
        //   target 1.22     = move the bicycle slightly lower in the viewport
        //                     while keeping focus around the handlebar area
        //   zoom 3.20       = slightly smaller / wider cockpit composition
        await _controller.setCameraPose(
          horizontalDegrees: 180.0,
          verticalDegrees: 4.0,
          targetHeightFactor: 1.22,
          zoom: 3.20,
        );

        if (!_isGenerationActive(generation)) {
          return;
        }

        debugPrint(
          'MUNJA NAVIGATION CAMERA: HANDLEBAR ONLY '
          'yaw=180 pitch=4 targetHeight=1.22 zoom=3.20',
        );
      } else {
        await _controller.setCameraPose(
          horizontalDegrees: 0.0,
          verticalDegrees: 0.0,
          targetHeightFactor: 0.0,
          zoom: 2.25,
        );

        if (!_isGenerationActive(generation)) {
          return;
        }
      }

      _pendingCameraApply = false;
    } catch (error, stackTrace) {
      if (!_isGenerationActive(generation) ||
          _isDetachedControllerError(error)) {
        return;
      }

      debugPrint(
        'MUNJA NAVIGATION CAMERA POSE ERROR: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<void> _applyDigitalTwinSetup({
    bool force = false,
    required int generation,
  }) async {
    if (!_isGenerationActive(generation) ||
        _applyingSetup ||
        !_modelReady) {
      return;
    }

    final frameId = _safeFrameId;
    final skinId = _safeSkinId;
    final frameColor = widget.activeFrameColor.trim();

    final unchanged =
        _lastAppliedFrameId == frameId &&
        _lastAppliedSkinId == skinId &&
        _lastAppliedFrameColor == frameColor;

    if (!force && unchanged) {
      _pendingDigitalTwinApply = false;
      return;
    }

    _applyingSetup = true;

    try {
      final entityName =
          _frameEntityById[frameId]!;

      await _controller.resetAllMaterialOverrides();

      if (!_isGenerationActive(generation)) {
        return;
      }

      await _controller.setExclusiveEntityVisibility(
        entityNames: _frameEntityNames,
        activeEntityName: entityName,
      );

      if (!_isGenerationActive(generation)) {
        return;
      }

      await _controller.resetEntityDirectMaterial(
        entityName: entityName,
      );

      if (!_isGenerationActive(generation)) {
        return;
      }

      if (skinId == 'standard') {
        final rgba = _hexToRgba(
          frameColor.isEmpty ? '#9AA2A0' : frameColor,
        );

        await _controller.setEntityBaseColor(
          entityName: entityName,
          rgba: rgba,
        );

        if (!_isGenerationActive(generation)) {
          return;
        }

        debugPrint(
          'MUNJA NAVIGATION DIGITAL TWIN ACTIVE: '
          '$frameId + standard + $frameColor',
        );
      } else {
        final materialInstanceName =
            _materialBySkinAndFrame[skinId]?[frameId];

        if (materialInstanceName == null ||
            materialInstanceName.trim().isEmpty) {
          throw StateError(
            'No material mapping for $skinId / $frameId',
          );
        }

        await _controller.setEntityMaterialInstance(
          entityName: entityName,
          materialInstanceName: materialInstanceName,
        );

        if (!_isGenerationActive(generation)) {
          return;
        }

        debugPrint(
          'MUNJA NAVIGATION DIGITAL TWIN ACTIVE: '
          '$frameId + $skinId -> $materialInstanceName',
        );
      }

      _lastAppliedFrameId = frameId;
      _lastAppliedSkinId = skinId;
      _lastAppliedFrameColor = frameColor;
      _pendingDigitalTwinApply = false;
    } catch (error, stackTrace) {
      if (!_isGenerationActive(generation) ||
          _isDetachedControllerError(error)) {
        return;
      }

      debugPrint(
        'MUNJA NAVIGATION DIGITAL TWIN APPLY ERROR: '
        'frame=$_safeFrameId '
        'skin=$_safeSkinId '
        'color=${widget.activeFrameColor} '
        'error=$error',
      );
      debugPrint('$stackTrace');
    } finally {
      if (_isGenerationActive(generation)) {
        _applyingSetup = false;
      }
    }
  }

  List<double> _hexToRgba(String value) {
    var hex = value.trim().replaceFirst('#', '');

    if (hex.length == 3) {
      hex = hex
          .split('')
          .map((character) => '$character$character')
          .join();
    }

    if (hex.length != 6 && hex.length != 8) {
      hex = '9AA2A0';
    }

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    final argb = int.tryParse(hex, radix: 16) ??
        0xFF9AA2A0;

    final a = ((argb >> 24) & 0xFF) / 255.0;
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;

    return <double>[r, g, b, a];
  }

  double get _clampedSteeringAngle {
    final maxAngle =
        widget.maxSteeringAngleDegrees.abs();

    if (!widget.navigationMode ||
        maxAngle <= 0) {
      return 0.0;
    }

    return widget.steeringAngleDegrees.clamp(
      -maxAngle,
      maxAngle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final glowOpacity =
        widget.navigationMode ? 0.06 : 0.11;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.navigationMode
              ? Colors.transparent
              : MunjaColors.panel.withOpacity(0.72),
          borderRadius:
              BorderRadius.circular(
            widget.borderRadius,
          ),
          border: Border.all(
            color: MunjaColors.mint.withOpacity(
              widget.navigationMode
                  ? 0.10
                  : 0.12,
            ),
          ),
          boxShadow: [
            if (widget.showGlow)
              BoxShadow(
                color: MunjaColors.mint.withOpacity(
                  glowOpacity,
                ),
                blurRadius:
                    widget.navigationMode ? 44 : 32,
                spreadRadius:
                    widget.navigationMode ? 2 : 1,
                offset: const Offset(0, 16),
              ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.showGlow)
              Positioned.fill(
                child: _NavigationBikeGlow(
                  navigationMode:
                      widget.navigationMode,
                ),
              ),

            if (widget.showGrid &&
                !widget.navigationMode)
              const Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter:
                        _NavigationBikeGridPainter(),
                  ),
                ),
              ),

            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  end: _clampedSteeringAngle,
                ),
                duration:
                    widget.steeringAnimationDuration,
                curve: Curves.easeOutCubic,
                builder: (
                  context,
                  animatedSteering,
                  child,
                ) {
                  final maxAngle = widget
                      .maxSteeringAngleDegrees
                      .abs();

                  final normalizedSteering =
                      maxAngle <= 0
                          ? 0.0
                          : (animatedSteering /
                                  maxAngle)
                              .clamp(-1.0, 1.0);

                  final leanDegrees =
                      widget.enableSteeringLean
                          ? animatedSteering *
                              widget
                                  .steeringLeanFactor
                          : 0.0;

                  final horizontalOffset =
                      widget.navigationMode
                          ? animatedSteering * 0.45
                          : 0.0;

                  return Transform.translate(
                    offset: Offset(
                      horizontalOffset,
                      0,
                    ),
                    child: Transform.rotate(
                      angle: leanDegrees *
                          0.017453292519943295,
                      alignment:
                          const Alignment(0, 0.72),
                      child: Transform(
                        alignment:
                            const Alignment(0, 0.72),
                        transform:
                            Matrix4.identity()
                              ..setEntry(
                                3,
                                2,
                                0.001,
                              )
                              ..rotateY(
                                normalizedSteering *
                                    0.045,
                              ),
                        child: child,
                      ),
                    ),
                  );
                },

                // Native renderer = same renderer used in Customize.
                child: _DigitalTwinNativeModel(
                  controller: _controller,
                  modelPath: widget.modelPath,
                  navigationMode:
                      widget.navigationMode,
                  enableTouch:
                      widget.enableTouch,
                  backgroundColor:
                      widget.backgroundColor,
                ),
              ),
            ),

            if (_applyingSetup)
              const Positioned(
                right: 12,
                top: 12,
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: MunjaColors.mint,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DigitalTwinNativeModel
    extends StatelessWidget {
  const _DigitalTwinNativeModel({
    required this.controller,
    required this.modelPath,
    required this.navigationMode,
    required this.enableTouch,
    required this.backgroundColor,
  });

  final Interactive3dController controller;
  final String modelPath;
  final bool navigationMode;
  final bool enableTouch;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    Widget model = Interactive3d(
      key: ValueKey<String>(
        'munja-navigation-native-$modelPath',
      ),
      controller: controller,
      modelPath: modelPath,
      solidBackgroundColor:
          const <double>[
        0.0,
        0.0,
        0.0,
        0.0,
      ],
      backgroundColor: backgroundColor,
      defaultZoom: 2.25,
      onSelectionChanged: (entities) {
        debugPrint(
          'MUNJA NAVIGATION NATIVE SELECTION: '
          '${entities.map((e) => e.name).toList()}',
        );
      },
    );

    // IMPORTANT:
    // No Flutter scale/translate hack in navigation mode.
    // The native Filament camera is rotated 180° and aimed directly at the
    // cockpit through Interactive3dController.setCameraPose().
    // This preserves the correct perspective from the old working version.

    if (!enableTouch) {
      return IgnorePointer(
        child: model,
      );
    }

    return model;
  }
}

class _NavigationBikeGlow
    extends StatelessWidget {
  const _NavigationBikeGlow({
    required this.navigationMode,
  });

  final bool navigationMode;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, 0.12),
          radius: 0.88,
          colors: [
            MunjaColors.mint.withOpacity(
              navigationMode ? 0.05 : 0.12,
            ),
            MunjaColors.mint.withOpacity(
              navigationMode
                  ? 0.015
                  : 0.035,
            ),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _NavigationBikeGridPainter
    extends CustomPainter {
  const _NavigationBikeGridPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color =
          Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;

    const spacing = 34.0;

    for (
      double x = 0;
      x <= size.width;
      x += spacing
    ) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        paint,
      );
    }

    for (
      double y = 0;
      y <= size.height;
      y += spacing
    ) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _NavigationBikeGridPainter
        oldDelegate,
  ) {
    return false;
  }
}
