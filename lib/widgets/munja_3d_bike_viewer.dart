import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'package:interactive_3d/interactive_3d.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class Munja3DBikeViewer extends StatefulWidget {
  final bool isLive;
  final bool brakeLightMounted;
  final bool showControls;
  final bool showSkinTester;
  final bool showBadges;
  final bool showBottomInfo;
  final bool showProductHotspot;
  final bool cockpitMode;
  final bool enableTouch;

  /// Automatic showroom rotation for Flutter3DViewer-based scenes.
  /// Digital Twin / Interactive3d scenes keep their native touch rotation.
  final bool autoRotate;
  final int autoRotateSpeed;
  final bool resumeAutoRotateAfterInteraction;
  final Duration autoRotateResumeDelay;

  /// Gentle back-and-forth showroom motion for the native Interactive3d
  /// Digital Twin. This is intentionally a swing, not a full spin.
  final bool showroomSwing;
  final double showroomSwingDegrees;
  final Duration showroomSwingDuration;
  final Duration showroomSwingResumeDelay;

  final double cockpitTargetX;
  final double cockpitTargetY;
  final double cockpitTargetZ;
  final double cockpitTheta;
  final double cockpitPhi;
  final double cockpitRadius;
  final double heroTheta;
  final double heroPhi;
  final double heroRadius;
  final bool showroomMode;
  final double showroomTheta;
  final double showroomPhi;
  final double showroomRadius;
  final bool navigationMode;
  final bool animateToRiderView;
  final Duration riderViewAnimationDuration;
  final Duration riderViewAnimationDelay;
  final double height;
  final String modelPath;
  final VoidCallback? onOpenGarage;
  final VoidCallback? onBikeTap;

  /// When true, Garage/Home use the same master GLB + embedded
  /// MaterialInstances as Customize.
  final bool useDigitalTwinMaterials;
  final String activeSkinId;
  final String activeFrameId;
  final String frameColor;

  const Munja3DBikeViewer({
    super.key,
    this.isLive = false,
    this.brakeLightMounted = false,
    this.showControls = true,
    this.showSkinTester = false,
    this.showBadges = true,
    this.showBottomInfo = true,
    this.showProductHotspot = true,
    this.cockpitMode = false,
    this.enableTouch = true,
    this.autoRotate = false,
    this.autoRotateSpeed = 8,
    this.resumeAutoRotateAfterInteraction = true,
    this.autoRotateResumeDelay = const Duration(seconds: 3),
    this.showroomSwing = false,
    this.showroomSwingDegrees = 16.0,
    this.showroomSwingDuration = const Duration(milliseconds: 2400),
    this.showroomSwingResumeDelay = const Duration(seconds: 2),
    this.cockpitTargetX = 0.0,
    this.cockpitTargetY = 0.72,
    this.cockpitTargetZ = 0.0,
    this.cockpitTheta = 0.0,
    this.cockpitPhi = 82.0,
    this.cockpitRadius = 1.45,
    // Garage/Home defaults restored to the pre-showroom camera.
    this.heroTheta = 180.0,
    this.heroPhi = 72.0,
    this.heroRadius = 2.85,

    // Customize can opt into its own independent premium showroom camera.
    this.showroomMode = false,
    this.showroomTheta = 225.0,
    this.showroomPhi = 68.0,
    this.showroomRadius = 2.35,

    this.navigationMode = false,
    this.animateToRiderView = false,
    this.riderViewAnimationDuration = const Duration(milliseconds: 1050),
    this.riderViewAnimationDelay = const Duration(milliseconds: 750),
    this.height = 320,
    this.modelPath = defaultModelPath,
    this.onOpenGarage,
    this.onBikeTap,
    this.useDigitalTwinMaterials = false,
    this.activeSkinId = 'standard',
    this.activeFrameId = 'frame_1',
    this.frameColor = '#9AA2A0',
  });

  static const String defaultModelPath = 'assets/models/kids_mtb_forest.glb';
  static const String digitalTwinMasterModelPath =
      'assets/models/kids_mtb_master.glb';

  @override
  State<Munja3DBikeViewer> createState() => _Munja3DBikeViewerState();
}

class _Munja3DBikeViewerState extends State<Munja3DBikeViewer> {
  final Flutter3DController _controller = Flutter3DController();

  Timer? _loadingFallbackTimer;
  Timer? _cameraSettleTimer;
  Timer? _cameraAnimationTimer;
  Timer? _cameraAnimationDelayTimer;
  Timer? _autoRotateResumeTimer;
  Timer? _modelReadyPollTimer;
  Timer? _legacyRotationStartTimer;

  bool _riderViewAnimationPlayed = false;
  bool _pointerInteracting = false;

  bool _modelLoaded = false;
  bool _modelFailed = false;
  double _loadingProgress = 0;

  List<String> _availableTextures = const [];
  String? _selectedTexture;
  bool _loadingTextures = false;
  String? _textureError;

  @override
  void initState() {
    super.initState();

    // IMPORTANT: the legacy Flutter3DController lifecycle must stay completely
    // dormant while the native Digital Twin / Interactive3d renderer is used.
    // Running both lifecycles from the same widget can leave a second renderer
    // loading or issuing camera commands while Filament is being detached.
    if (!widget.useDigitalTwinMaterials) {
      _controller.onModelLoaded.addListener(_onModelLoadedChanged);
      _startLoadingFallbackTimer();
    }
  }

  @override
  void didUpdateWidget(covariant Munja3DBikeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final switchedToDigitalTwin =
        !oldWidget.useDigitalTwinMaterials && widget.useDigitalTwinMaterials;
    final switchedToLegacy =
        oldWidget.useDigitalTwinMaterials && !widget.useDigitalTwinMaterials;

    if (switchedToDigitalTwin) {
      // Shut the complete legacy lifecycle down before Interactive3d owns the
      // rendering slot. No legacy timer/camera/rotation callback may survive.
      _loadingFallbackTimer?.cancel();
      _cameraSettleTimer?.cancel();
      _cameraAnimationTimer?.cancel();
      _cameraAnimationDelayTimer?.cancel();
      _autoRotateResumeTimer?.cancel();
      _modelReadyPollTimer?.cancel();
      _legacyRotationStartTimer?.cancel();
      _controller.onModelLoaded.removeListener(_onModelLoadedChanged);
      _pointerInteracting = false;
      return;
    }

    if (switchedToLegacy) {
      // Re-enable the old renderer only when the widget explicitly leaves the
      // Digital Twin path.
      _modelLoaded = false;
      _modelFailed = false;
      _loadingProgress = 0;
      _availableTextures = const [];
      _selectedTexture = null;
      _loadingTextures = false;
      _textureError = null;
      _riderViewAnimationPlayed = false;
      _controller.onModelLoaded.addListener(_onModelLoadedChanged);
      _startLoadingFallbackTimer();
      return;
    }

    // From here on everything belongs exclusively to the legacy
    // Flutter3DViewer path.
    if (widget.useDigitalTwinMaterials) return;

    if (oldWidget.modelPath != widget.modelPath) {
      _loadingFallbackTimer?.cancel();
      _modelReadyPollTimer?.cancel();
      _legacyRotationStartTimer?.cancel();

      setState(() {
        _modelLoaded = false;
        _modelFailed = false;
        _loadingProgress = 0;
        _availableTextures = const [];
        _selectedTexture = null;
        _loadingTextures = false;
        _textureError = null;
        _riderViewAnimationPlayed = false;
      });

      _startLoadingFallbackTimer();
      return;
    }

    final cameraChanged =
        oldWidget.cockpitMode != widget.cockpitMode ||
        oldWidget.isLive != widget.isLive ||
        oldWidget.cockpitTargetX != widget.cockpitTargetX ||
        oldWidget.cockpitTargetY != widget.cockpitTargetY ||
        oldWidget.cockpitTargetZ != widget.cockpitTargetZ ||
        oldWidget.cockpitTheta != widget.cockpitTheta ||
        oldWidget.cockpitPhi != widget.cockpitPhi ||
        oldWidget.cockpitRadius != widget.cockpitRadius ||
        oldWidget.heroTheta != widget.heroTheta ||
        oldWidget.heroPhi != widget.heroPhi ||
        oldWidget.heroRadius != widget.heroRadius ||
        oldWidget.showroomMode != widget.showroomMode ||
        oldWidget.showroomTheta != widget.showroomTheta ||
        oldWidget.showroomPhi != widget.showroomPhi ||
        oldWidget.showroomRadius != widget.showroomRadius ||
        oldWidget.navigationMode != widget.navigationMode ||
        oldWidget.animateToRiderView != widget.animateToRiderView ||
        oldWidget.riderViewAnimationDuration !=
            widget.riderViewAnimationDuration ||
        oldWidget.riderViewAnimationDelay != widget.riderViewAnimationDelay;

    final autoRotationChanged =
        oldWidget.autoRotate != widget.autoRotate ||
        oldWidget.autoRotateSpeed != widget.autoRotateSpeed ||
        oldWidget.resumeAutoRotateAfterInteraction !=
            widget.resumeAutoRotateAfterInteraction ||
        oldWidget.autoRotateResumeDelay != widget.autoRotateResumeDelay ||
        oldWidget.enableTouch != widget.enableTouch;

    if (_modelLoaded && autoRotationChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.useDigitalTwinMaterials) {
          _syncLegacyAutoRotation();
        }
      });
    }

    if (_modelLoaded && cameraChanged) {
      final navigationJustStarted =
          !oldWidget.navigationMode && widget.navigationMode;
      final animationJustEnabled =
          !oldWidget.animateToRiderView && widget.animateToRiderView;

      if (navigationJustStarted || animationJustEnabled) {
        _riderViewAnimationPlayed = false;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !widget.useDigitalTwinMaterials) {
          _applyInitialCamera();
        }
      });
    }
  }

  @override
  void dispose() {
    _loadingFallbackTimer?.cancel();
    _cameraSettleTimer?.cancel();
    _cameraAnimationTimer?.cancel();
    _cameraAnimationDelayTimer?.cancel();
    _autoRotateResumeTimer?.cancel();
    _modelReadyPollTimer?.cancel();
    _legacyRotationStartTimer?.cancel();
    _controller.onModelLoaded.removeListener(_onModelLoadedChanged);
    super.dispose();
  }

  void _startLoadingFallbackTimer() {
    _loadingFallbackTimer?.cancel();
    _modelReadyPollTimer?.cancel();

    if (widget.useDigitalTwinMaterials) return;

    _loadingFallbackTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted || _modelLoaded || _modelFailed) return;

      // A timeout is not model-ready. Do NOT send camera or rotation commands
      // from here. Instead, poll only the controller's official ready flag.
      debugPrint(
        'MUNJA 3D LOADING FALLBACK: waiting for controller ready | '
        'model=${widget.modelPath}',
      );

      _startControllerReadyPoll();
    });
  }

  void _startControllerReadyPoll() {
    _modelReadyPollTimer?.cancel();

    if (!mounted ||
        widget.useDigitalTwinMaterials ||
        _modelLoaded ||
        _modelFailed) {
      return;
    }

    var checks = 0;

    _modelReadyPollTimer = Timer.periodic(const Duration(milliseconds: 250), (
      timer,
    ) {
      if (!mounted ||
          widget.useDigitalTwinMaterials ||
          _modelLoaded ||
          _modelFailed) {
        timer.cancel();
        return;
      }

      checks++;

      if (_controller.onModelLoaded.value) {
        timer.cancel();
        _handleLegacyControllerReady('controller-poll');
        return;
      }

      // Stop quietly after 30 seconds. We intentionally do not call camera
      // methods while the controller still reports "not loaded".
      if (checks >= 120) {
        timer.cancel();
        debugPrint(
          'MUNJA 3D READY POLL TIMEOUT: controller never confirmed ready | '
          'model=${widget.modelPath}',
        );
      }
    });
  }

  void _onModelLoadedChanged() {
    if (!mounted || widget.useDigitalTwinMaterials) return;
    if (!_controller.onModelLoaded.value) return;

    _handleLegacyControllerReady('controller-onModelLoaded');
  }

  void _handleLegacyControllerReady(String reason) {
    if (!mounted || widget.useDigitalTwinMaterials || _modelFailed) return;

    _loadingFallbackTimer?.cancel();
    _modelReadyPollTimer?.cancel();
    _legacyRotationStartTimer?.cancel();

    if (!_modelLoaded || _loadingProgress < 1) {
      setState(() {
        _modelLoaded = true;
        _modelFailed = false;
        _loadingProgress = 1;
      });
    }

    debugPrint(
      'MUNJA 3D CONTROLLER READY: '
      'reason=$reason | model=${widget.modelPath}',
    );

    // Wait for the platform view to settle after the official ready event.
    // Then set the deterministic front/showroom camera exactly once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.useDigitalTwinMaterials ||
          !_modelLoaded ||
          _modelFailed) {
        return;
      }

      _cameraSettleTimer?.cancel();
      _cameraSettleTimer = Timer(const Duration(milliseconds: 260), () {
        if (!mounted ||
            widget.useDigitalTwinMaterials ||
            !_modelLoaded ||
            _modelFailed) {
          return;
        }

        _applyInitialCamera();

        if (!widget.autoRotate || _pointerInteracting) return;

        // Let the user see the requested front pose before the slow spin starts.
        _legacyRotationStartTimer?.cancel();
        _legacyRotationStartTimer = Timer(
          const Duration(milliseconds: 700),
          () {
            if (!mounted ||
                widget.useDigitalTwinMaterials ||
                !_modelLoaded ||
                _modelFailed ||
                _pointerInteracting ||
                !widget.autoRotate) {
              return;
            }

            _syncLegacyAutoRotation();
          },
        );
      });
    });

    unawaited(_loadAvailableTextures());
  }

  void _markModelLoadedFromProgress(double progressValue) {
    if (!mounted || widget.useDigitalTwinMaterials || _modelFailed) {
      return;
    }

    final normalizedProgress = _normalizeProgress(progressValue);

    if ((_loadingProgress - normalizedProgress).abs() > 0.001) {
      setState(() {
        _loadingProgress = normalizedProgress;
      });
    }

    // IMPORTANT:
    // Progress is only visual information. Even 100% is not permission to call
    // Flutter3DController camera/rotation methods.
  }

  double _normalizeProgress(double progressValue) {
    if (progressValue <= 0) return 0;

    if (progressValue > 1) {
      return (progressValue / 100).clamp(0.0, 1.0);
    }

    return progressValue.clamp(0.0, 1.0);
  }

  bool get _useCockpitCamera {
    return widget.cockpitMode || widget.isLive;
  }

  bool get _looksLikeNavigationOverlay {
    return !widget.enableTouch &&
        !widget.showControls &&
        !widget.showBadges &&
        !widget.showBottomInfo &&
        !widget.showProductHotspot &&
        !widget.cockpitMode &&
        !widget.isLive;
  }

  bool get _shouldAnimateToRiderView {
    return widget.navigationMode ||
        widget.animateToRiderView ||
        _looksLikeNavigationOverlay;
  }

  void _applyInitialCamera() {
    if (widget.useDigitalTwinMaterials) return;
    _cameraSettleTimer?.cancel();
    _cameraAnimationTimer?.cancel();
    _cameraAnimationDelayTimer?.cancel();

    if (_shouldAnimateToRiderView && !_riderViewAnimationPlayed) {
      // Show the model first from the normal front/hero angle.
      // The old implementation started rotating while the loading
      // overlay was still visible, so the user never saw it.
      _applyNavigationStartCamera();

      _cameraAnimationDelayTimer = Timer(widget.riderViewAnimationDelay, () {
        if (!mounted ||
            !_modelLoaded ||
            _modelFailed ||
            _riderViewAnimationPlayed) {
          return;
        }

        _startRiderViewAnimation();
      });

      return;
    }

    _applyCameraNow();

    _cameraSettleTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted && _modelLoaded && !_modelFailed) {
        _applyCameraNow();
      }
    });
  }

  void _applyNavigationStartCamera() {
    try {
      _controller.resetCameraTarget();
      _controller.setCameraOrbit(0.0, widget.heroPhi, widget.heroRadius);

      debugPrint(
        'MUNJA 3D NAVIGATION START CAMERA: '
        'orbit=(0.0, ${widget.heroPhi}, ${widget.heroRadius})',
      );
    } catch (error, stackTrace) {
      debugPrint('MUNJA 3D NAVIGATION START CAMERA ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  void _startRiderViewAnimation() {
    _cameraAnimationTimer?.cancel();
    _cameraSettleTimer?.cancel();

    final endTheta = widget.heroTheta;

    // IMPORTANT FOR OLDER iPHONES:
    // Do not stream camera commands every 16 ms through the platform channel.
    // Older devices can fall behind and end the transition at an intermediate
    // orbit. Instead, apply the final rider-facing pose deterministically and
    // re-apply it after the native view has had time to settle.
    try {
      _controller.resetCameraTarget();
      _controller.setCameraOrbit(endTheta, widget.heroPhi, widget.heroRadius);

      _riderViewAnimationPlayed = true;

      debugPrint(
        'MUNJA 3D RIDER VIEW APPLIED: '
        'theta=$endTheta°, phi=${widget.heroPhi}°, '
        'radius=${widget.heroRadius}',
      );
    } catch (error, stackTrace) {
      debugPrint('MUNJA 3D RIDER VIEW APPLY ERROR: $error');
      debugPrint('$stackTrace');
      return;
    }

    // First settle pass.
    _cameraSettleTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted ||
          widget.useDigitalTwinMaterials ||
          !_modelLoaded ||
          _modelFailed ||
          !_riderViewAnimationPlayed) {
        return;
      }

      try {
        _controller.resetCameraTarget();
        _controller.setCameraOrbit(endTheta, widget.heroPhi, widget.heroRadius);
      } catch (error) {
        debugPrint('MUNJA 3D RIDER VIEW SETTLE ERROR: $error');
        return;
      }

      // Second settle pass. This is intentionally low-frequency; it protects
      // older iOS platform views from ending at a stale/intermediate orbit.
      _cameraAnimationTimer?.cancel();
      _cameraAnimationTimer = Timer(const Duration(milliseconds: 260), () {
        if (!mounted ||
            widget.useDigitalTwinMaterials ||
            !_modelLoaded ||
            _modelFailed ||
            !_riderViewAnimationPlayed) {
          return;
        }

        try {
          _controller.resetCameraTarget();
          _controller.setCameraOrbit(
            endTheta,
            widget.heroPhi,
            widget.heroRadius,
          );
        } catch (error) {
          debugPrint('MUNJA 3D RIDER VIEW FINAL SETTLE ERROR: $error');
        }
      });
    });
  }

  bool _applyCameraNow() {
    try {
      if (widget.isLive) {
        // Navigation cockpit:
        // rotate the camera to the rider-facing side and move it
        // close to the handlebar, fork crown and top of the wheel.
        const targetX = 0.0;
        const targetY = 0.93;
        const targetZ = -0.08;
        const theta = 180.0;
        const phi = 73.0;
        const radius = 0.78;

        _controller.setCameraTarget(targetX, targetY, targetZ);

        _controller.setCameraOrbit(theta, phi, radius);

        debugPrint(
          'MUNJA 3D LIVE COCKPIT CAMERA: '
          'target=($targetX, $targetY, $targetZ), '
          'orbit=($theta, $phi, $radius)',
        );

        return true;
      }

      if (widget.cockpitMode) {
        _controller.setCameraTarget(
          widget.cockpitTargetX,
          widget.cockpitTargetY,
          widget.cockpitTargetZ,
        );

        _controller.setCameraOrbit(
          widget.cockpitTheta,
          widget.cockpitPhi,
          widget.cockpitRadius,
        );

        debugPrint(
          'MUNJA 3D CUSTOM COCKPIT CAMERA: '
          'target=('
          '${widget.cockpitTargetX}, '
          '${widget.cockpitTargetY}, '
          '${widget.cockpitTargetZ}), '
          'orbit=('
          '${widget.cockpitTheta}, '
          '${widget.cockpitPhi}, '
          '${widget.cockpitRadius})',
        );

        return true;
      }

      if (widget.showroomMode) {
        _controller.resetCameraTarget();
        _controller.setCameraOrbit(
          widget.showroomTheta,
          widget.showroomPhi,
          widget.showroomRadius,
        );

        debugPrint(
          'MUNJA 3D SHOWROOM CAMERA: '
          'orbit=('
          '${widget.showroomTheta}, '
          '${widget.showroomPhi}, '
          '${widget.showroomRadius})',
        );

        return true;
      }

      // Normal Home/Garage hero view.
      // These defaults are intentionally independent from Customize.
      _controller.resetCameraTarget();
      _controller.setCameraOrbit(
        widget.heroTheta,
        widget.heroPhi,
        widget.heroRadius,
      );

      debugPrint(
        'MUNJA 3D HERO CAMERA: '
        'orbit=('
        '${widget.heroTheta}, '
        '${widget.heroPhi}, '
        '${widget.heroRadius})',
      );

      return true;
    } catch (error, stackTrace) {
      debugPrint('MUNJA 3D CAMERA ERROR: $error');
      debugPrint('$stackTrace');
      return false;
    }
  }

  void _stopAutoRotation() {
    try {
      _controller.stopRotation();
    } catch (e) {
      debugPrint('MUNJA 3D STOP ROTATION ERROR: $e');
    }
  }

  bool _syncLegacyAutoRotation() {
    _autoRotateResumeTimer?.cancel();
    if (widget.useDigitalTwinMaterials) return true;

    if (!_modelLoaded ||
        _modelFailed ||
        _pointerInteracting ||
        !widget.autoRotate) {
      _pauseLegacyAutoRotation();
      return true;
    }

    try {
      _controller.startRotation(rotationSpeed: widget.autoRotateSpeed);

      debugPrint(
        'MUNJA 3D AUTO ROTATION START: '
        '${widget.autoRotateSpeed} deg/s',
      );
      return true;
    } catch (error) {
      debugPrint('MUNJA 3D AUTO ROTATION START ERROR: $error');
      return false;
    }
  }

  void _pauseLegacyAutoRotation() {
    try {
      _controller.pauseRotation();
    } catch (_) {
      // Older platform implementations may not expose pause cleanly.
      // stopRotation is the safe fallback.
      try {
        _controller.stopRotation();
      } catch (error) {
        debugPrint('MUNJA 3D AUTO ROTATION PAUSE ERROR: $error');
      }
    }
  }

  void _handleLegacyPointerDown(PointerDownEvent event) {
    if (!widget.enableTouch) return;

    _pointerInteracting = true;
    _autoRotateResumeTimer?.cancel();

    if (widget.autoRotate) {
      _pauseLegacyAutoRotation();
    }
  }

  void _handleLegacyPointerEnd(PointerEvent event) {
    if (!widget.enableTouch) return;

    _pointerInteracting = false;

    if (!widget.autoRotate || !widget.resumeAutoRotateAfterInteraction) {
      return;
    }

    _autoRotateResumeTimer?.cancel();
    _autoRotateResumeTimer = Timer(widget.autoRotateResumeDelay, () {
      if (mounted && _modelLoaded && !_modelFailed && !_pointerInteracting) {
        _syncLegacyAutoRotation();
      }
    });
  }

  void _retryLoad() {
    if (!mounted || widget.useDigitalTwinMaterials) return;

    _cameraSettleTimer?.cancel();
    _cameraAnimationTimer?.cancel();
    _cameraAnimationDelayTimer?.cancel();
    _modelReadyPollTimer?.cancel();
    _legacyRotationStartTimer?.cancel();

    setState(() {
      _modelLoaded = false;
      _modelFailed = false;
      _loadingProgress = 0;
      _availableTextures = const [];
      _selectedTexture = null;
      _loadingTextures = false;
      _textureError = null;
      _riderViewAnimationPlayed = false;
    });

    _startLoadingFallbackTimer();
  }

  Future<void> _loadAvailableTextures() async {
    if (!widget.showSkinTester || _loadingTextures || _modelFailed) return;
    setState(() {
      _loadingTextures = true;
      _textureError = null;
    });
    try {
      final textures = await _controller.getAvailableTextures();
      final cleaned = textures
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      debugPrint('MUNJA AVAILABLE TEXTURES (${widget.modelPath}): $cleaned');
      if (!mounted) return;
      setState(() {
        _availableTextures = cleaned;
        _selectedTexture = cleaned.isEmpty
            ? null
            : (_selectedTexture != null && cleaned.contains(_selectedTexture)
                  ? _selectedTexture
                  : cleaned.first);
        _loadingTextures = false;
        _textureError = cleaned.isEmpty
            ? 'Ingen skiftbare textures blev fundet i GLB-filen.'
            : null;
      });
    } catch (e, st) {
      debugPrint('MUNJA TEXTURE LIST ERROR: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      setState(() {
        _availableTextures = const [];
        _selectedTexture = null;
        _loadingTextures = false;
        _textureError = 'Textures kunne ikke læses fra modellen.';
      });
    }
  }

  void _applyTexture(String name) {
    final value = name.trim();
    if (value.isEmpty || value == _selectedTexture) return;
    try {
      _controller.setTexture(textureName: value);
      if (!mounted) return;
      setState(() {
        _selectedTexture = value;
        _textureError = null;
      });
      debugPrint('MUNJA TEXTURE APPLIED: $value');
    } catch (e, st) {
      debugPrint('MUNJA SET TEXTURE ERROR: $e');
      debugPrintStack(stackTrace: st);
      if (mounted)
        setState(() => _textureError = 'Skinet kunne ikke anvendes.');
    }
  }

  Future<void> _openSkinTester() async {
    if (!_modelLoaded || _modelFailed) return;
    if (_availableTextures.isEmpty && !_loadingTextures)
      await _loadAvailableTextures();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SkinTesterSheet(
        modelPath: widget.modelPath,
        textures: _availableTextures,
        selectedTexture: _selectedTexture,
        loading: _loadingTextures,
        errorMessage: _textureError,
        onSelectTexture: _applyTexture,
        onRefresh: _loadAvailableTextures,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useDigitalTwinMaterials) {
      // iOS uses Flutter3DViewer because its touch/orbit handling is reliable.
      // Android keeps the native Interactive3d path for materials and frames.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return _MunjaIosDigitalTwinViewer(
          height: widget.height,
          isLive: widget.isLive,
          enableTouch: widget.enableTouch,
          modelPath: widget.modelPath,
          autoRotate: widget.autoRotate,
          autoRotateSpeed: widget.autoRotateSpeed,
          resumeAutoRotateAfterInteraction:
              widget.resumeAutoRotateAfterInteraction,
          autoRotateResumeDelay: widget.autoRotateResumeDelay,
          onBikeTap: widget.onBikeTap,
        );
      }

      return _MunjaNativeDigitalTwinViewer(
        height: widget.height,
        isLive: widget.isLive,
        enableTouch: widget.enableTouch,
        activeSkinId: widget.activeSkinId,
        activeFrameId: widget.activeFrameId,
        frameColor: widget.frameColor,
        autoRotate: widget.autoRotate,
        autoRotateSpeed: widget.autoRotateSpeed,
        resumeAutoRotateAfterInteraction:
            widget.resumeAutoRotateAfterInteraction,
        autoRotateResumeDelay: widget.autoRotateResumeDelay,
        showroomSwing: widget.showroomSwing,
        showroomSwingDegrees: widget.showroomSwingDegrees,
        showroomSwingDuration: widget.showroomSwingDuration,
        showroomSwingResumeDelay: widget.showroomSwingResumeDelay,
        onBikeTap: widget.onBikeTap,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onBikeTap,
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: MunjaColors.panel.withOpacity(0.78),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(
            color: MunjaColors.mint.withOpacity(widget.isLive ? 0.28 : 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(widget.isLive ? 0.20 : 0.10),
              blurRadius: widget.isLive ? 48 : 34,
              spreadRadius: widget.isLive ? 3 : 1,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: _BackgroundGlow(isLive: widget.isLive)),
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _handleLegacyPointerDown,
                onPointerUp: _handleLegacyPointerEnd,
                onPointerCancel: _handleLegacyPointerEnd,
                child: Flutter3DViewer(
                  controller: _controller,
                  src: widget.modelPath,
                  activeGestureInterceptor: widget.enableTouch,
                  enableTouch: widget.enableTouch,
                  progressBarColor: Colors.transparent,
                  onProgress: (double progressValue) {
                    debugPrint('MUNJA 3D PROGRESS: $progressValue');
                    _markModelLoadedFromProgress(progressValue);
                  },
                  onLoad: (String modelAddress) {
                    debugPrint('MUNJA 3D MODEL LOADED: $modelAddress');

                    if (!mounted) return;

                    _loadingFallbackTimer?.cancel();

                    _handleLegacyControllerReady('viewer-onLoad');
                  },
                  onError: (String error) {
                    debugPrint('MUNJA 3D MODEL ERROR: $error');

                    if (!mounted) return;

                    _loadingFallbackTimer?.cancel();
                    _modelReadyPollTimer?.cancel();
                    _legacyRotationStartTimer?.cancel();

                    setState(() {
                      _modelLoaded = false;
                      _modelFailed = true;
                    });
                  },
                ),
              ),
            ),
            if (!_modelLoaded && !_modelFailed)
              Positioned.fill(
                child: _LoadingOverlay(progress: _loadingProgress),
              ),
            if (_modelFailed)
              Positioned.fill(child: _ErrorOverlay(onRetry: _retryLoad)),
            if (widget.showBadges)
              Positioned(
                left: 16,
                top: 16,
                child: _StatusBadge(
                  label: widget.isLive
                      ? AppText.t('liveRide').toUpperCase()
                      : AppText.t('ready').toUpperCase(),
                  icon: widget.isLive
                      ? Icons.radio_button_checked_rounded
                      : Icons.check_circle_rounded,
                  active: true,
                ),
              ),
            if (widget.showBadges)
              Positioned(
                right: 16,
                top: 16,
                child: _StatusBadge(
                  label: widget.brakeLightMounted
                      ? AppText.t('mounted').toUpperCase()
                      : AppText.t('garage').toUpperCase(),
                  icon: widget.brakeLightMounted
                      ? Icons.light_mode_rounded
                      : Icons.inventory_2_rounded,
                  active: widget.brakeLightMounted,
                ),
              ),
            if (widget.showSkinTester && _modelLoaded && !_modelFailed)
              Positioned(
                right: 16,
                top: 62,
                child: _SkinTesterButton(
                  textureCount: _availableTextures.length,
                  loading: _loadingTextures,
                  onTap: _openSkinTester,
                ),
              ),
            if (widget.showProductHotspot && widget.brakeLightMounted)
              Positioned(
                right: 22,
                bottom: 118,
                child: _ProductHotspot(
                  label: AppText.t('brake').toUpperCase(),
                  icon: Icons.light_mode_rounded,
                  active: true,
                  onTap: widget.onOpenGarage,
                ),
              ),
            if (widget.showBottomInfo)
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: _BottomInfoBar(
                  isLive: widget.isLive,
                  brakeLightMounted: widget.brakeLightMounted,
                  onOpenGarage: widget.onOpenGarage,
                ),
              ),
            if (widget.showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: widget.showBottomInfo ? 86 : 24,
                child: IgnorePointer(
                  child: Text(
                    AppText.t('dragToRotate'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SkinTesterButton extends StatelessWidget {
  final int textureCount;
  final bool loading;
  final VoidCallback onTap;
  const _SkinTesterButton({
    required this.textureCount,
    required this.loading,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF06130F).withValues(alpha: 0.90),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MunjaColors.mint.withValues(alpha: 0.34)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MunjaColors.mint,
                  ),
                )
              else
                const Icon(
                  Icons.palette_outlined,
                  color: MunjaColors.mint,
                  size: 18,
                ),
              const SizedBox(width: 8),
              Text(
                loading
                    ? 'LÆSER SKINS'
                    : textureCount > 0
                    ? 'SKINS · $textureCount'
                    : 'TEST SKINS',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkinTesterSheet extends StatelessWidget {
  final String modelPath;
  final List<String> textures;
  final String? selectedTexture;
  final bool loading;
  final String? errorMessage;
  final ValueChanged<String> onSelectTexture;
  final Future<void> Function() onRefresh;
  const _SkinTesterSheet({
    required this.modelPath,
    required this.textures,
    required this.selectedTexture,
    required this.loading,
    required this.errorMessage,
    required this.onSelectTexture,
    required this.onRefresh,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF03100D),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        border: Border(
          top: BorderSide(color: MunjaColors.mint.withValues(alpha: 0.25)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(
                Icons.palette_outlined,
                color: MunjaColors.mint,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Skin Test v1',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Textures indlejret i den aktuelle GLB',
                      style: TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: loading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            modelPath,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: CircularProgressIndicator(color: MunjaColors.mint),
              ),
            )
          else if (textures.isEmpty)
            _EmptyTextureState(message: errorMessage)
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: textures.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final texture = textures[i];
                  final selected = texture == selectedTexture;
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => onSelectTexture(texture),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: selected
                              ? MunjaColors.mint.withValues(alpha: 0.13)
                              : Colors.white.withValues(alpha: 0.035),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? MunjaColors.mintStrong
                                : Colors.white.withValues(alpha: 0.07),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.texture_rounded,
                              color: selected
                                  ? MunjaColors.mint
                                  : Colors.white54,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                texture,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (selected)
                              const Text(
                                'AKTIV',
                                style: TextStyle(
                                  color: MunjaColors.mint,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (errorMessage != null && textures.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              errorMessage!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyTextureState extends StatelessWidget {
  final String? message;
  const _EmptyTextureState({this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.layers_clear_rounded,
            color: Colors.white38,
            size: 34,
          ),
          const SizedBox(height: 12),
          const Text(
            'Ingen skiftbare textures fundet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message ??
                'GLB-filen indeholder muligvis kun ét aktivt texture-sæt.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Se Terminal efter: MUNJA AVAILABLE TEXTURES',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: MunjaColors.mint,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final double progress;

  const _LoadingOverlay({required this.progress});

  @override
  Widget build(BuildContext context) {
    final safeProgress = progress.clamp(0.0, 1.0);

    return Container(
      color: Colors.black.withOpacity(0.10),
      child: Center(
        child: SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: safeProgress == 0 ? null : safeProgress,
                strokeWidth: 3,
                color: MunjaColors.mint,
                backgroundColor: Colors.white.withOpacity(0.08),
              ),
              const Icon(
                Icons.directions_bike_rounded,
                color: MunjaColors.mint,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorOverlay({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.34),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onRetry,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.42),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: MunjaColors.mint.withOpacity(0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.refresh_rounded,
                    color: MunjaColors.mint,
                    size: 19,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    AppText.t('retry'),
                    style: const TextStyle(
                      color: MunjaColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS-only Digital Twin renderer.
///
/// This deliberately uses Flutter3DViewer instead of Interactive3d on iPhone.
/// It is isolated from the Android Digital Twin renderer so Android's native
/// material/frame behavior remains untouched.
///
/// Important:
/// - Manual one-finger orbit is handled by Flutter3DViewer.
/// - No GestureDetector is placed above the 3D view.
/// - A raw Listener only observes pointer start/end so it cannot win the gesture
///   arena or block the viewer's own drag recognizer.
/// - The camera is never re-applied while the user is dragging.
class _MunjaIosDigitalTwinViewer extends StatefulWidget {
  const _MunjaIosDigitalTwinViewer({
    required this.height,
    required this.isLive,
    required this.enableTouch,
    required this.modelPath,
    required this.autoRotate,
    required this.autoRotateSpeed,
    required this.resumeAutoRotateAfterInteraction,
    required this.autoRotateResumeDelay,
    this.onBikeTap,
  });

  final double height;
  final bool isLive;
  final bool enableTouch;
  final String modelPath;
  final bool autoRotate;
  final int autoRotateSpeed;
  final bool resumeAutoRotateAfterInteraction;
  final Duration autoRotateResumeDelay;
  final VoidCallback? onBikeTap;

  @override
  State<_MunjaIosDigitalTwinViewer> createState() =>
      _MunjaIosDigitalTwinViewerState();
}

class _MunjaIosDigitalTwinViewerState
    extends State<_MunjaIosDigitalTwinViewer> {
  final Flutter3DController _controller = Flutter3DController();

  Timer? _cameraSettleTimer;
  Timer? _autoRotateResumeTimer;
  Timer? _readyFallbackTimer;

  bool _loaded = false;
  bool _failed = false;
  bool _pointerInteracting = false;
  double _progress = 0.0;

  int? _tapPointer;
  Offset? _tapDownPosition;
  bool _tapMoved = false;

  // Same deterministic front-facing camera used by the stable legacy viewer.
  static const double _frontTheta = 180.0;
  static const double _frontPhi = 72.0;
  static const double _frontRadius = 2.85;

  @override
  void initState() {
    super.initState();
    _controller.onModelLoaded.addListener(_onControllerReady);

    // Some iOS versions report onLoad before the controller notifier changes.
    // This timer only checks readiness; it never sends camera commands early.
    _readyFallbackTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      if (!mounted || _loaded || _failed) {
        timer.cancel();
        return;
      }

      if (_controller.onModelLoaded.value) {
        timer.cancel();
        _markReady('controller-poll');
      }
    });
  }

  @override
  void didUpdateWidget(covariant _MunjaIosDigitalTwinViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.modelPath != widget.modelPath) {
      _cameraSettleTimer?.cancel();
      _autoRotateResumeTimer?.cancel();

      setState(() {
        _loaded = false;
        _failed = false;
        _progress = 0.0;
        _pointerInteracting = false;
      });
    }

    final rotationChanged =
        oldWidget.autoRotate != widget.autoRotate ||
        oldWidget.autoRotateSpeed != widget.autoRotateSpeed ||
        oldWidget.enableTouch != widget.enableTouch;

    if (_loaded && rotationChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncAutoRotation();
        }
      });
    }
  }

  @override
  void dispose() {
    _cameraSettleTimer?.cancel();
    _autoRotateResumeTimer?.cancel();
    _readyFallbackTimer?.cancel();
    _controller.onModelLoaded.removeListener(_onControllerReady);
    super.dispose();
  }

  void _onControllerReady() {
    if (!mounted || !_controller.onModelLoaded.value) return;
    _markReady('controller-notifier');
  }

  void _markReady(String reason) {
    if (!mounted || _failed) return;

    _readyFallbackTimer?.cancel();

    if (!_loaded) {
      setState(() {
        _loaded = true;
        _failed = false;
        _progress = 1.0;
      });
    }

    debugPrint('MUNJA iOS 3D READY: $reason | ${widget.modelPath}');

    // Wait for the iOS 3D view to settle before applying the first camera.
    // Crucially, this only happens once after load and never during a drag.
    _cameraSettleTimer?.cancel();
    _cameraSettleTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted || !_loaded || _failed || _pointerInteracting) return;

      _applyInitialCamera();

      if (widget.autoRotate) {
        _autoRotateResumeTimer?.cancel();
        _autoRotateResumeTimer = Timer(const Duration(milliseconds: 550), () {
          if (mounted &&
              _loaded &&
              !_failed &&
              !_pointerInteracting &&
              widget.autoRotate) {
            _syncAutoRotation();
          }
        });
      }
    });
  }

  void _applyInitialCamera() {
    if (!_loaded || _failed || _pointerInteracting) return;

    try {
      _controller.resetCameraTarget();
      _controller.setCameraOrbit(_frontTheta, _frontPhi, _frontRadius);

      debugPrint(
        'MUNJA iOS 3D INITIAL CAMERA: '
        'theta=$_frontTheta phi=$_frontPhi radius=$_frontRadius',
      );
    } catch (error) {
      debugPrint('MUNJA iOS 3D INITIAL CAMERA ERROR: $error');
    }
  }

  void _pauseAutoRotation() {
    try {
      _controller.pauseRotation();
    } catch (_) {
      try {
        _controller.stopRotation();
      } catch (error) {
        debugPrint('MUNJA iOS 3D PAUSE ROTATION ERROR: $error');
      }
    }
  }

  void _syncAutoRotation() {
    _autoRotateResumeTimer?.cancel();

    if (!_loaded || _failed || _pointerInteracting || !widget.autoRotate) {
      _pauseAutoRotation();
      return;
    }

    try {
      _controller.startRotation(rotationSpeed: widget.autoRotateSpeed);
    } catch (error) {
      debugPrint('MUNJA iOS 3D AUTO ROTATION ERROR: $error');
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.enableTouch || !_loaded || _failed) return;

    _pointerInteracting = true;
    _autoRotateResumeTimer?.cancel();

    _tapPointer = event.pointer;
    _tapDownPosition = event.localPosition;
    _tapMoved = false;

    if (widget.autoRotate) {
      _pauseAutoRotation();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.enableTouch || event.pointer != _tapPointer) return;

    final down = _tapDownPosition;
    if (down != null && (event.localPosition - down).distanceSquared > 36.0) {
      _tapMoved = true;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!widget.enableTouch) return;

    final isTracked = event.pointer == _tapPointer;
    final wasTap = isTracked && !_tapMoved;

    _pointerInteracting = false;
    _tapPointer = null;
    _tapDownPosition = null;
    _tapMoved = false;

    if (wasTap && widget.onBikeTap != null) {
      widget.onBikeTap!();
    }

    if (!widget.autoRotate || !widget.resumeAutoRotateAfterInteraction) {
      return;
    }

    _autoRotateResumeTimer?.cancel();
    _autoRotateResumeTimer = Timer(widget.autoRotateResumeDelay, () {
      if (mounted && _loaded && !_failed && !_pointerInteracting) {
        _syncAutoRotation();
      }
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!widget.enableTouch) return;

    _pointerInteracting = false;
    _tapPointer = null;
    _tapDownPosition = null;
    _tapMoved = false;

    if (!widget.autoRotate || !widget.resumeAutoRotateAfterInteraction) {
      return;
    }

    _autoRotateResumeTimer?.cancel();
    _autoRotateResumeTimer = Timer(widget.autoRotateResumeDelay, () {
      if (mounted && _loaded && !_failed && !_pointerInteracting) {
        _syncAutoRotation();
      }
    });
  }

  double _normalizeProgress(double value) {
    if (value <= 0) return 0.0;
    if (value > 1.0) {
      return (value / 100.0).clamp(0.0, 1.0);
    }
    return value.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final compactHeight = (widget.height * 0.88).clamp(270.0, 330.0);

    return Container(
      height: compactHeight,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF071914),
            Color(0xFF03100D),
            Color(0xFF010806),
          ],
          stops: <double>[0.0, 0.58, 1.0],
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(widget.isLive ? 0.34 : 0.20),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(widget.isLive ? 0.20 : 0.10),
            blurRadius: widget.isLive ? 44 : 28,
            spreadRadius: widget.isLive ? 2 : 0,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.46),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _BackgroundGlow(isLive: widget.isLive)),

          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MunjaColors.mint.withOpacity(0.08)),
                ),
              ),
            ),
          ),

          Positioned(
            left: 36,
            right: 36,
            bottom: 18,
            child: IgnorePointer(
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: RadialGradient(
                    radius: 1.0,
                    colors: <Color>[
                      MunjaColors.mint.withOpacity(0.18),
                      MunjaColors.mint.withOpacity(0.06),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _onPointerDown,
              onPointerMove: _onPointerMove,
              onPointerUp: _onPointerUp,
              onPointerCancel: _onPointerCancel,
              child: Flutter3DViewer(
                controller: _controller,
                src: widget.modelPath,
                activeGestureInterceptor: widget.enableTouch,
                enableTouch: widget.enableTouch,
                progressBarColor: Colors.transparent,
                onProgress: (double value) {
                  if (!mounted || _loaded || _failed) return;

                  final normalized = _normalizeProgress(value);
                  if ((_progress - normalized).abs() > 0.001) {
                    setState(() => _progress = normalized);
                  }
                },
                onLoad: (String modelAddress) {
                  debugPrint('MUNJA iOS 3D MODEL LOADED: $modelAddress');
                  _markReady('viewer-onLoad');
                },
                onError: (String error) {
                  debugPrint('MUNJA iOS 3D MODEL ERROR: $error');

                  if (!mounted) return;

                  _cameraSettleTimer?.cancel();
                  _autoRotateResumeTimer?.cancel();
                  _readyFallbackTimer?.cancel();

                  setState(() {
                    _loaded = false;
                    _failed = true;
                  });
                },
              ),
            ),
          ),

          if (!_loaded && !_failed)
            Center(
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  value: _progress <= 0 ? null : _progress,
                  color: MunjaColors.mint,
                  strokeWidth: 2.4,
                  backgroundColor: Colors.white.withOpacity(0.08),
                ),
              ),
            ),

          if (_failed)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Digital Twin could not be loaded',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MunjaNativeDigitalTwinViewer extends StatefulWidget {
  const _MunjaNativeDigitalTwinViewer({
    required this.height,
    required this.isLive,
    required this.enableTouch,
    required this.activeSkinId,
    required this.activeFrameId,
    required this.frameColor,
    required this.autoRotate,
    required this.autoRotateSpeed,
    required this.resumeAutoRotateAfterInteraction,
    required this.autoRotateResumeDelay,
    required this.showroomSwing,
    required this.showroomSwingDegrees,
    required this.showroomSwingDuration,
    required this.showroomSwingResumeDelay,
    this.onBikeTap,
  });

  final double height;
  final bool isLive;
  final bool enableTouch;
  final String activeSkinId;
  final String activeFrameId;
  final String frameColor;
  final bool autoRotate;
  final int autoRotateSpeed;
  final bool resumeAutoRotateAfterInteraction;
  final Duration autoRotateResumeDelay;
  final bool showroomSwing;
  final double showroomSwingDegrees;
  final Duration showroomSwingDuration;
  final Duration showroomSwingResumeDelay;
  final VoidCallback? onBikeTap;

  @override
  State<_MunjaNativeDigitalTwinViewer> createState() =>
      _MunjaNativeDigitalTwinViewerState();
}

class _MunjaNativeDigitalTwinViewerState
    extends State<_MunjaNativeDigitalTwinViewer> {
  final Interactive3dController _nativeController = Interactive3dController();

  // Keep the native Home showroom camera deterministic after a live ride.
  //
  // Interactive3d applies defaultZoom during model loading, but Home destroys
  // the showroom renderer while navigation is active and creates it again when
  // the ride stops. On some Android/Filament lifecycles the first camera update
  // can race material/frame restoration and the new renderer can briefly keep a
  // stale framing. Re-applying the exact same Home zoom after the model and
  // Digital Twin materials are settled makes the post-ride Home position match
  // a clean app launch.
  static const double _nativeHomeZoom = 2.42;

  // Explicit Home pose for the native Interactive3d / Filament renderer.
  //
  // The previous fix only re-applied zoom. That cannot repair a changed camera
  // target (vertical framing). A round-trip/live session can recreate the
  // native texture with a different target/orbit state, so Home must restore
  // the complete camera pose: horizontal orbit, vertical orbit, target height
  // and zoom.
  static const double _nativeHomeHorizontalDegrees = 0.0;
  static const double _nativeHomeVerticalDegrees = 0.0;
  static const double _nativeHomeTargetHeightFactor = 0.0;

  static const Duration _nativeCameraSettleDelay = Duration(milliseconds: 220);

  bool _ready = false;
  bool _failed = false;
  bool _disposing = false;
  int _lifecycleGeneration = 0;
  int _applyGeneration = 0;
  String? _lastAppliedSignature;

  // ---------------------------------------------------------------------------
  // iOS touch fallback
  // ---------------------------------------------------------------------------
  //
  // Interactive3d renders correctly on iOS, but on some iPhones its native
  // SceneKit drag recognizer can lose the gesture arena inside a complex Flutter
  // Stack. Android is left completely unchanged. On iOS we listen to raw pointer
  // movement in Flutter and drive Interactive3d's own camera through
  // setCameraPose(). This gives deterministic 360-degree horizontal rotation
  // without changing the GLB, materials, frames, Home layout, or Android path.
  Timer? _iosGestureResumeTimer;
  Future<void>? _iosStopShowroomFuture;

  bool _iosPointerActive = false;
  int? _iosPointerId;
  Offset? _iosLastPointerPosition;
  Offset? _iosPointerDownPosition;
  bool _iosPointerMoved = false;

  double _iosManualHorizontalDegrees = _nativeHomeHorizontalDegrees;
  double _iosManualVerticalDegrees = _nativeHomeVerticalDegrees;

  bool _iosCameraCommandInFlight = false;
  bool _iosCameraCommandDirty = false;

  bool get _useIosTouchFallback =>
      widget.enableTouch && defaultTargetPlatform == TargetPlatform.iOS;

  bool _isCurrent(int generation) =>
      mounted && !_disposing && generation == _lifecycleGeneration;

  static const List<String> _frameEntities = <String>[
    'Frame 1',
    'FRAME 2',
    'FRAME 3',
    'frame 4',
  ];

  static const Map<String, String> _frameEntityById = <String, String>{
    'frame_1': 'Frame 1',
    'frame_2': 'FRAME 2',
    'frame_3': 'FRAME 3',
    'frame_4': 'frame 4',
  };

  static const Map<String, Map<String, String>> _materialBySkinAndFrame =
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
          'frame_2': 'Neon_Green_frame 2',
          'frame_3': 'Neon_Green_Frame 3',
          'frame_4': 'Neon_Green_Frame 4',
        },
        'titanium': <String, String>{
          'frame_1': 'Titanium_Frame_1',
          'frame_2': 'Titanium_Frame_2',
          'frame_3': 'Titanium_Metal_Frame 3',
          'frame_4': 'Titanium_Frame 4',
        },
      };

  @override
  void dispose() {
    // IMPORTANT: do not send any asynchronous native command from dispose().
    // At this point Interactive3d may already have detached the controller and
    // Android may already be destroying the Filament renderer/texture.
    _disposing = true;
    _lifecycleGeneration++;
    _applyGeneration++;
    _iosGestureResumeTimer?.cancel();
    _iosPointerActive = false;
    _iosPointerId = null;
    _iosCameraCommandDirty = false;
    _ready = false;
    _failed = false;
    super.dispose();
  }

  String get _normalizedFrameId {
    final value = widget.activeFrameId.trim();
    return _frameEntityById.containsKey(value) ? value : 'frame_1';
  }

  String get _normalizedSkinId {
    final value = widget.activeSkinId.trim();
    return _materialBySkinAndFrame.containsKey(value) ? value : 'standard';
  }

  String get _signature =>
      '$_normalizedSkinId|$_normalizedFrameId|${widget.frameColor.trim()}';

  @override
  void initState() {
    super.initState();
    final generation = _lifecycleGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent(generation)) {
        unawaited(_initializeAndApply(generation));
      }
    });
  }

  @override
  void didUpdateWidget(covariant _MunjaNativeDigitalTwinViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final changed =
        oldWidget.activeSkinId != widget.activeSkinId ||
        oldWidget.activeFrameId != widget.activeFrameId ||
        oldWidget.frameColor != widget.frameColor;

    final swingChanged =
        oldWidget.showroomSwing != widget.showroomSwing ||
        oldWidget.showroomSwingDegrees != widget.showroomSwingDegrees ||
        oldWidget.showroomSwingDuration != widget.showroomSwingDuration ||
        oldWidget.showroomSwingResumeDelay != widget.showroomSwingResumeDelay ||
        oldWidget.isLive != widget.isLive;

    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposing) {
          unawaited(_applyDigitalTwin());
        }
      });
    }

    if (swingChanged && _ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _disposing) {
          return;
        }

        unawaited(() async {
          if (oldWidget.isLive && !widget.isLive) {
            await _stabilizeNativeHomeCamera();

            if (!mounted || _disposing) {
              return;
            }
          }

          await _syncNativeShowroomRotation();
        }());
      });
    }
  }

  Future<void> _initializeAndApply(int generation) async {
    // The parent post-frame callback can run before Interactive3d has attached
    // its controller. Retry that short lifecycle window instead of treating it
    // as a model failure.
    final attachDeadline = DateTime.now().add(const Duration(seconds: 2));

    while (_isCurrent(generation)) {
      try {
        await _nativeController.waitUntilModelLoaded(
          timeout: const Duration(seconds: 20),
          pollInterval: const Duration(milliseconds: 50),
        );
        break;
      } on StateError catch (error) {
        if (!_isCurrent(generation)) return;

        final detached = error.toString().contains('not attached to a widget');
        if (!detached || DateTime.now().isAfter(attachDeadline)) {
          rethrow;
        }

        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    if (!_isCurrent(generation)) return;

    try {
      setState(() {
        _ready = true;
        _failed = false;
      });

      await _applyDigitalTwin(force: true, lifecycleGeneration: generation);
      if (!_isCurrent(generation)) return;

      // IMPORTANT:
      // Do this only after the selected frame/material is restored. Native
      // camera framing can otherwise settle against the pre-restoration model
      // bounds and appear lower/closer after returning from a ride.
      await _stabilizeNativeHomeCamera(lifecycleGeneration: generation);
      if (!_isCurrent(generation)) return;

      await _syncNativeShowroomRotation(lifecycleGeneration: generation);
    } catch (error, stackTrace) {
      if (!_isCurrent(generation)) return;

      debugPrint('MUNJA DIGITAL TWIN VIEWER INIT ERROR: $error');
      debugPrint('$stackTrace');

      if (!_isCurrent(generation)) return;
      setState(() {
        _failed = true;
        _ready = false;
      });
    }
  }

  Future<void> _stabilizeNativeHomeCamera({int? lifecycleGeneration}) async {
    final generation = lifecycleGeneration ?? _lifecycleGeneration;

    if (!_isCurrent(generation) || !_ready || _failed || widget.isLive) {
      return;
    }

    try {
      // Stop showroom motion first. Native showroom rotation deliberately uses
      // the CURRENT orbit as its centre; restarting it before the Home pose is
      // restored would preserve the wrong post-navigation framing.
      await _nativeController.stopShowroomRotation();

      if (!_isCurrent(generation)) {
        return;
      }

      // IMPORTANT:
      // Restore the COMPLETE camera pose, not only zoom.
      //
      // targetHeightFactor = 0.0 means the exact fitted GLB center. This is what
      // prevents the bike from staying visually lower after a ride.
      await _nativeController.setCameraPose(
        horizontalDegrees: _nativeHomeHorizontalDegrees,
        verticalDegrees: _nativeHomeVerticalDegrees,
        targetHeightFactor: _nativeHomeTargetHeightFactor,
        zoom: _nativeHomeZoom,
      );

      if (!_isCurrent(generation)) {
        return;
      }

      // A visibility/material update may finish a frame later. Enforce the exact
      // same Home pose once more after a short native settle window.
      await Future<void>.delayed(_nativeCameraSettleDelay);

      if (!_isCurrent(generation)) {
        return;
      }

      await _nativeController.setCameraPose(
        horizontalDegrees: _nativeHomeHorizontalDegrees,
        verticalDegrees: _nativeHomeVerticalDegrees,
        targetHeightFactor: _nativeHomeTargetHeightFactor,
        zoom: _nativeHomeZoom,
      );

      if (!_isCurrent(generation)) {
        return;
      }

      _iosManualHorizontalDegrees = _nativeHomeHorizontalDegrees;
      _iosManualVerticalDegrees = _nativeHomeVerticalDegrees;

      debugPrint(
        'MUNJA DIGITAL TWIN HOME POSE RESTORED: '
        'horizontal=$_nativeHomeHorizontalDegrees°, '
        'vertical=$_nativeHomeVerticalDegrees°, '
        'targetHeight=$_nativeHomeTargetHeightFactor, '
        'zoom=$_nativeHomeZoom',
      );
    } on StateError catch (error) {
      if (!_isCurrent(generation) ||
          error.toString().contains('not attached to a widget')) {
        debugPrint(
          'MUNJA DIGITAL TWIN HOME POSE RESET CANCELLED: '
          '$error',
        );
        return;
      }

      rethrow;
    }
  }

  /// Synchronizes Munja's showroom setting with the native Interactive3d
  /// Filament renderer.
  ///
  /// The actual animation now runs natively through Choreographer. This means
  /// the camera itself orbits around the bike instead of visually skewing the
  /// Flutter Texture widget.
  ///
  /// Native behavior:
  /// - gentle left/right orbit around the current camera angle
  /// - manual 360-degree drag remains available
  /// - manual interaction temporarily pauses the animation
  /// - after [showroomSwingResumeDelay], motion resumes around the user's new
  ///   viewing angle without jumping back to the original position
  Future<void> _syncNativeShowroomRotation({int? lifecycleGeneration}) async {
    final generation = lifecycleGeneration ?? _lifecycleGeneration;
    if (!_isCurrent(generation) || !_ready || _failed) {
      return;
    }

    final shouldRun = widget.showroomSwing && !widget.isLive;

    try {
      if (!shouldRun) {
        await _nativeController.stopShowroomRotation();
        if (!_isCurrent(generation)) return;

        debugPrint(
          'MUNJA DIGITAL TWIN NATIVE SHOWROOM: STOPPED '
          '(enabled=${widget.showroomSwing}, live=${widget.isLive})',
        );
        return;
      }

      final safeAmplitude = widget.showroomSwingDegrees
          .clamp(2.0, 30.0)
          .toDouble();

      final durationMs = widget.showroomSwingDuration.inMilliseconds.clamp(
        900,
        12000,
      );

      final resumeDelayMs = widget.showroomSwingResumeDelay.inMilliseconds
          .clamp(0, 10000);

      if (!_isCurrent(generation)) return;
      await _nativeController.startShowroomRotation(
        amplitudeDegrees: safeAmplitude,
        cycleDuration: Duration(milliseconds: durationMs),
        resumeDelay: Duration(milliseconds: resumeDelayMs),
      );

      if (!_isCurrent(generation)) return;
      debugPrint(
        'MUNJA DIGITAL TWIN NATIVE SHOWROOM: STARTED | '
        'amplitude=$safeAmplitude° | '
        'duration=${durationMs}ms | '
        'resumeDelay=${resumeDelayMs}ms',
      );
    } catch (error, stackTrace) {
      if (!_isCurrent(generation) ||
          error.toString().contains('not attached to a widget')) {
        debugPrint('MUNJA DIGITAL TWIN NATIVE SHOWROOM CANCELLED: $error');
        return;
      }
      debugPrint('MUNJA DIGITAL TWIN NATIVE SHOWROOM ERROR: $error');
      debugPrint('$stackTrace');
    }
  }

  double _normalizeDegrees(double value) {
    var result = value % 360.0;
    if (result > 180.0) result -= 360.0;
    if (result < -180.0) result += 360.0;
    return result;
  }

  void _handleIosPointerDown(PointerDownEvent event) {
    if (!_useIosTouchFallback ||
        !_ready ||
        _failed ||
        _disposing ||
        _iosPointerActive) {
      return;
    }

    _iosGestureResumeTimer?.cancel();

    _iosPointerActive = true;
    _iosPointerId = event.pointer;
    _iosLastPointerPosition = event.localPosition;
    _iosPointerDownPosition = event.localPosition;
    _iosPointerMoved = false;

    // Pause the native showroom animation before Flutter starts driving the
    // camera. Keeping this Future allows the first camera update to wait for the
    // stop command instead of racing it on older iPhones.
    _iosStopShowroomFuture = _stopNativeShowroomForIosGesture();
  }

  Future<void> _stopNativeShowroomForIosGesture() async {
    if (_disposing || !_ready || _failed) return;

    try {
      await _nativeController.stopShowroomRotation();
    } on StateError catch (error) {
      if (_disposing || error.toString().contains('not attached to a widget')) {
        return;
      }
      debugPrint('MUNJA iOS 3D TOUCH STOP SHOWROOM ERROR: $error');
    } catch (error) {
      debugPrint('MUNJA iOS 3D TOUCH STOP SHOWROOM ERROR: $error');
    }
  }

  void _handleIosPointerMove(PointerMoveEvent event) {
    if (!_useIosTouchFallback ||
        !_iosPointerActive ||
        event.pointer != _iosPointerId ||
        !_ready ||
        _failed ||
        _disposing) {
      return;
    }

    final previous = _iosLastPointerPosition;
    if (previous == null) {
      _iosLastPointerPosition = event.localPosition;
      return;
    }

    final delta = event.localPosition - previous;
    _iosLastPointerPosition = event.localPosition;

    final down = _iosPointerDownPosition;
    if (down != null && (event.localPosition - down).distanceSquared > 36.0) {
      _iosPointerMoved = true;
    }

    // Horizontal drag is the primary 360-degree bike rotation.
    // Vertical drag is deliberately gentler and clamped so the camera cannot
    // flip underneath/over the bike.
    _iosManualHorizontalDegrees = _normalizeDegrees(
      _iosManualHorizontalDegrees - (delta.dx * 0.52),
    );

    _iosManualVerticalDegrees = (_iosManualVerticalDegrees + (delta.dy * 0.20))
        .clamp(-28.0, 28.0)
        .toDouble();

    _iosCameraCommandDirty = true;
    unawaited(_flushIosCameraCommand());
  }

  Future<void> _flushIosCameraCommand() async {
    if (_iosCameraCommandInFlight ||
        !_useIosTouchFallback ||
        !_ready ||
        _failed ||
        _disposing) {
      return;
    }

    _iosCameraCommandInFlight = true;

    try {
      final stopFuture = _iosStopShowroomFuture;
      _iosStopShowroomFuture = null;
      if (stopFuture != null) {
        await stopFuture;
      }

      // Coalesce rapid pointer events. We never queue one platform-channel call
      // per pixel; if newer movement arrives while a call is in flight, only
      // the newest desired camera pose is sent next.
      while (_iosCameraCommandDirty &&
          _useIosTouchFallback &&
          _ready &&
          !_failed &&
          !_disposing) {
        _iosCameraCommandDirty = false;

        final horizontal = _iosManualHorizontalDegrees;
        final vertical = _iosManualVerticalDegrees;

        await _nativeController.setCameraPose(
          horizontalDegrees: horizontal,
          verticalDegrees: vertical,
          targetHeightFactor: _nativeHomeTargetHeightFactor,
          zoom: _nativeHomeZoom,
        );
      }
    } on StateError catch (error) {
      if (!_disposing &&
          !error.toString().contains('not attached to a widget')) {
        debugPrint('MUNJA iOS 3D TOUCH CAMERA ERROR: $error');
      }
    } catch (error, stackTrace) {
      if (!_disposing) {
        debugPrint('MUNJA iOS 3D TOUCH CAMERA ERROR: $error');
        debugPrint('$stackTrace');
      }
    } finally {
      _iosCameraCommandInFlight = false;

      // A move may have arrived after the while-condition was last evaluated.
      if (_iosCameraCommandDirty &&
          _useIosTouchFallback &&
          _ready &&
          !_failed &&
          !_disposing) {
        unawaited(_flushIosCameraCommand());
      }
    }
  }

  void _handleIosPointerUp(PointerUpEvent event) {
    _finishIosPointer(event.pointer, cancelled: false);
  }

  void _handleIosPointerCancel(PointerCancelEvent event) {
    _finishIosPointer(event.pointer, cancelled: true);
  }

  void _finishIosPointer(int pointer, {required bool cancelled}) {
    if (!_useIosTouchFallback ||
        !_iosPointerActive ||
        pointer != _iosPointerId) {
      return;
    }

    final wasTap = !cancelled && !_iosPointerMoved;

    _iosPointerActive = false;
    _iosPointerId = null;
    _iosLastPointerPosition = null;
    _iosPointerDownPosition = null;
    _iosPointerMoved = false;

    // Preserve the existing "tap bike" behavior even though the native iOS view
    // is ignored for pointer handling in fallback mode.
    if (wasTap && widget.onBikeTap != null) {
      widget.onBikeTap!();
    }

    if (!widget.showroomSwing ||
        widget.isLive ||
        !widget.resumeAutoRotateAfterInteraction) {
      return;
    }

    _iosGestureResumeTimer?.cancel();
    _iosGestureResumeTimer = Timer(widget.showroomSwingResumeDelay, () {
      if (!mounted ||
          _disposing ||
          !_ready ||
          _failed ||
          _iosPointerActive ||
          !widget.showroomSwing ||
          widget.isLive) {
        return;
      }

      // Interactive3d's showroom rotation uses the CURRENT camera angle as its
      // centre, so it resumes from the user's chosen view instead of snapping
      // back to the original front pose.
      unawaited(_syncNativeShowroomRotation());
    });
  }

  Widget _buildNativeInteractive3d() {
    return Interactive3d(
      controller: _nativeController,
      modelPath: Munja3DBikeViewer.digitalTwinMasterModelPath,
      solidBackgroundColor: const <double>[0.0, 0.0, 0.0, 0.0],
      backgroundColor: Colors.transparent,
      defaultZoom: _nativeHomeZoom,
      onSelectionChanged: (entities) {
        debugPrint(
          'MUNJA DIGITAL TWIN VIEWER SELECTION: '
          '${entities.map((e) => e.name).toList()}',
        );

        // Android/native path keeps the existing selection behavior.
        // iOS fallback handles a short tap itself in _finishIosPointer().
        if (!_useIosTouchFallback &&
            widget.enableTouch &&
            entities.isNotEmpty &&
            widget.onBikeTap != null) {
          widget.onBikeTap!();
        }
      },
    );
  }

  Widget _buildNativeTouchLayer() {
    if (_useIosTouchFallback) {
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handleIosPointerDown,
        onPointerMove: _handleIosPointerMove,
        onPointerUp: _handleIosPointerUp,
        onPointerCancel: _handleIosPointerCancel,

        // Disable Interactive3d's own iOS pointer recognizer only in fallback
        // mode. The model still renders normally; Flutter owns the drag and
        // drives the same native camera through Interactive3dController.
        child: IgnorePointer(
          ignoring: true,
          child: _buildNativeInteractive3d(),
        ),
      );
    }

    // Existing Android/non-iOS behavior is preserved exactly.
    return IgnorePointer(
      ignoring: !widget.enableTouch,
      child: _buildNativeInteractive3d(),
    );
  }

  Future<void> _applyDigitalTwin({
    bool force = false,
    int? lifecycleGeneration,
  }) async {
    final lifecycle = lifecycleGeneration ?? _lifecycleGeneration;
    if (!_isCurrent(lifecycle) || !_ready) return;

    final signature = _signature;
    if (!force && signature == _lastAppliedSignature) return;

    // Every new material/frame request invalidates an older in-flight request.
    final apply = ++_applyGeneration;
    bool current() =>
        _isCurrent(lifecycle) &&
        apply == _applyGeneration &&
        _ready &&
        !_failed;

    final frameId = _normalizedFrameId;
    final skinId = _normalizedSkinId;
    final entityName = _frameEntityById[frameId] ?? _frameEntities.first;

    try {
      if (!current()) return;
      await _nativeController.resetAllMaterialOverrides();
      if (!current()) return;

      await _nativeController.setExclusiveEntityVisibility(
        entityNames: _frameEntities,
        activeEntityName: entityName,
      );
      if (!current()) return;

      await _nativeController.resetEntityDirectMaterial(entityName: entityName);
      if (!current()) return;

      if (skinId == 'standard') {
        await _nativeController.setEntityBaseColor(
          entityName: entityName,
          rgba: _hexToRgba(widget.frameColor),
        );
        if (!current()) return;

        debugPrint(
          'MUNJA DIGITAL TWIN VIEWER ACTIVE: '
          '$frameId + standard + ${widget.frameColor}',
        );
      } else {
        final materialName = _materialBySkinAndFrame[skinId]?[frameId];
        if (materialName == null || materialName.isEmpty) {
          throw StateError('Missing material mapping for $skinId / $frameId');
        }

        await _nativeController.setEntityMaterialInstance(
          entityName: entityName,
          materialInstanceName: materialName,
        );
        if (!current()) return;

        debugPrint(
          'MUNJA DIGITAL TWIN VIEWER ACTIVE: '
          '$frameId + $skinId + $materialName',
        );
      }

      if (current()) {
        _lastAppliedSignature = signature;
      }
    } on StateError catch (error, stackTrace) {
      // A detach during navigation/dispose is a normal lifecycle cancellation,
      // not a Digital Twin failure.
      if (!_isCurrent(lifecycle) ||
          error.toString().contains('not attached to a widget')) {
        debugPrint('MUNJA DIGITAL TWIN APPLY CANCELLED: $error');
        return;
      }
      debugPrint('MUNJA DIGITAL TWIN VIEWER APPLY ERROR: $signature -> $error');
      debugPrint('$stackTrace');
    } catch (error, stackTrace) {
      if (!_isCurrent(lifecycle)) return;
      debugPrint('MUNJA DIGITAL TWIN VIEWER APPLY ERROR: $signature -> $error');
      debugPrint('$stackTrace');
    }
  }

  List<double> _hexToRgba(String value) {
    var hex = value.trim().replaceFirst('#', '');

    if (hex.length == 6) {
      hex = 'FF$hex';
    }

    if (hex.length != 8) {
      hex = 'FF9AA2A0';
    }

    final argb = int.tryParse(hex, radix: 16) ?? 0xFF9AA2A0;

    final a = ((argb >> 24) & 0xFF) / 255.0;
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;

    return <double>[r, g, b, a];
  }

  @override
  Widget build(BuildContext context) {
    // Keep the Digital Twin showroom deliberately more compact than the
    // surrounding screen slot. This removes the large empty area above/below
    // the bike without changing the caller API.
    final compactHeight = (widget.height * 0.88).clamp(270.0, 330.0);

    return Container(
      height: compactHeight,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0xFF071914),
            Color(0xFF03100D),
            Color(0xFF010806),
          ],
          stops: <double>[0.0, 0.58, 1.0],
        ),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: MunjaColors.mint.withOpacity(widget.isLive ? 0.34 : 0.20),
          width: 1.15,
        ),
        boxShadow: [
          BoxShadow(
            color: MunjaColors.mint.withOpacity(widget.isLive ? 0.20 : 0.10),
            blurRadius: widget.isLive ? 44 : 28,
            spreadRadius: widget.isLive ? 2 : 0,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.46),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(child: _BackgroundGlow(isLive: widget.isLive)),

          // Premium inner showroom frame.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MunjaColors.mint.withOpacity(0.08)),
                ),
              ),
            ),
          ),

          // Subtle floor halo. It visually grounds the model without
          // stealing vertical space from the bike itself.
          Positioned(
            left: 36,
            right: 36,
            bottom: 18,
            child: IgnorePointer(
              child: Container(
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: RadialGradient(
                    radius: 1.0,
                    colors: <Color>[
                      MunjaColors.mint.withOpacity(0.18),
                      MunjaColors.mint.withOpacity(0.06),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: MunjaColors.mint.withOpacity(0.15),
                      blurRadius: 34,
                      spreadRadius: 5,
                    ),
                  ],
                ),
              ),
            ),
          ),

          _buildNativeTouchLayer(),
          if (!_ready && !_failed)
            const Center(
              child: CircularProgressIndicator(
                color: MunjaColors.mint,
                strokeWidth: 2,
              ),
            ),
          if (_failed)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Digital Twin could not be loaded',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  final bool isLive;

  const _BackgroundGlow({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.02),
                radius: 0.88,
                colors: [
                  MunjaColors.mint.withOpacity(isLive ? 0.22 : 0.15),
                  MunjaColors.mint.withOpacity(isLive ? 0.07 : 0.055),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 34,
          right: 34,
          bottom: 60,
          child: Container(
            height: 12,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(isLive ? 0.38 : 0.18),
                  blurRadius: 38,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
        ),
        Positioned.fill(child: CustomPaint(painter: _SubtleGridPainter())),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;

  const _StatusBadge({
    required this.label,
    required this.icon,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: active
            ? MunjaColors.mint.withOpacity(0.14)
            : Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? MunjaColors.mint.withOpacity(0.36)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductHotspot extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback? onTap;

  const _ProductHotspot({
    required this.label,
    required this.icon,
    required this.active,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? MunjaColors.mint : Colors.white38;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.48),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withOpacity(0.45)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.22),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomInfoBar extends StatelessWidget {
  final bool isLive;
  final bool brakeLightMounted;
  final VoidCallback? onOpenGarage;

  const _BottomInfoBar({
    required this.isLive,
    required this.brakeLightMounted,
    this.onOpenGarage,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.28),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onOpenGarage,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  isLive
                      ? Icons.directions_bike_rounded
                      : Icons.view_in_ar_rounded,
                  color: MunjaColors.mint,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  brakeLightMounted
                      ? AppText.t('digitalTwinProductStatus')
                      : AppText.t('scanAndMountProducts'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtleGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 1;

    const spacing = 34.0;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SubtleGridPainter oldDelegate) => false;
}
