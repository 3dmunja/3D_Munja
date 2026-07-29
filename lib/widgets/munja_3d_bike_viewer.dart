import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class Munja3DBikeViewer extends StatefulWidget {
  final bool isLive;
  final bool brakeLightMounted;
  final bool showControls;
  final double height;
  final String modelPath;
  final VoidCallback? onOpenGarage;
  final VoidCallback? onBikeTap;

  const Munja3DBikeViewer({
    super.key,
    this.isLive = false,
    this.brakeLightMounted = false,
    this.showControls = true,
    this.height = 360,
    this.modelPath = defaultModelPath,
    this.onOpenGarage,
    this.onBikeTap,
  });

  static const String defaultModelPath = 'assets/models/munja_bike.glb';

  @override
  State<Munja3DBikeViewer> createState() => _Munja3DBikeViewerState();
}

class _Munja3DBikeViewerState extends State<Munja3DBikeViewer> {
  final Flutter3DController _controller = Flutter3DController();

  Timer? _loadingFallbackTimer;

  bool _modelLoaded = false;
  bool _modelFailed = false;
  double _loadingProgress = 0;

  @override
  void initState() {
    super.initState();

    _controller.onModelLoaded.addListener(_onModelLoadedChanged);
    _startLoadingFallbackTimer();
  }

  @override
  void dispose() {
    _loadingFallbackTimer?.cancel();
    _controller.onModelLoaded.removeListener(_onModelLoadedChanged);
    super.dispose();
  }

  void _startLoadingFallbackTimer() {
    _loadingFallbackTimer?.cancel();

    _loadingFallbackTimer = Timer(const Duration(seconds: 7), () {
      if (!mounted || _modelLoaded || _modelFailed) return;

      debugPrint(
        'MUNJA 3D LOADING FALLBACK: hiding loader after timeout for ${widget.modelPath}',
      );

      setState(() {
        _modelLoaded = true;
      });

      _applyInitialCamera();
      _stopAutoRotation();
    });
  }

  void _onModelLoadedChanged() {
    if (!mounted) return;

    final loaded = _controller.onModelLoaded.value;

    if (!loaded) return;

    _loadingFallbackTimer?.cancel();

    setState(() {
      _modelLoaded = true;
      _modelFailed = false;
      _loadingProgress = 1;
    });

    _applyInitialCamera();
    _stopAutoRotation();
  }

  void _markModelLoadedFromProgress(double progressValue) {
    if (!mounted || _modelLoaded || _modelFailed) return;

    final normalizedProgress = _normalizeProgress(progressValue);

    setState(() {
      _loadingProgress = normalizedProgress;
    });

    if (normalizedProgress >= 0.99) {
      _loadingFallbackTimer?.cancel();

      setState(() {
        _modelLoaded = true;
      });

      _applyInitialCamera();
      _stopAutoRotation();
    }
  }

  double _normalizeProgress(double progressValue) {
    if (progressValue <= 0) return 0;

    if (progressValue > 1) {
      return (progressValue / 100).clamp(0.0, 1.0);
    }

    return progressValue.clamp(0.0, 1.0);
  }

  void _applyInitialCamera() {
    try {
      _controller.setCameraOrbit(0, 72, 2.85);
    } catch (e) {
      debugPrint('MUNJA 3D CAMERA ERROR: $e');
    }
  }

  void _stopAutoRotation() {
    try {
      _controller.stopRotation();
    } catch (e) {
      debugPrint('MUNJA 3D STOP ROTATION ERROR: $e');
    }
  }

  void _retryLoad() {
    if (!mounted) return;

    setState(() {
      _modelLoaded = false;
      _modelFailed = false;
      _loadingProgress = 0;
    });

    _startLoadingFallbackTimer();
  }

  @override
  Widget build(BuildContext context) {
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
              child: Flutter3DViewer(
                controller: _controller,
                src: widget.modelPath,
                activeGestureInterceptor: true,
                enableTouch: true,
                progressBarColor: Colors.transparent,
                onProgress: (double progressValue) {
                  debugPrint('MUNJA 3D PROGRESS: $progressValue');
                  _markModelLoadedFromProgress(progressValue);
                },
                onLoad: (String modelAddress) {
                  debugPrint('MUNJA 3D MODEL LOADED: $modelAddress');

                  if (!mounted) return;

                  _loadingFallbackTimer?.cancel();

                  setState(() {
                    _modelLoaded = true;
                    _modelFailed = false;
                    _loadingProgress = 1;
                  });

                  _applyInitialCamera();
                  _stopAutoRotation();
                },
                onError: (String error) {
                  debugPrint('MUNJA 3D MODEL ERROR: $error');

                  if (!mounted) return;

                  _loadingFallbackTimer?.cancel();

                  setState(() {
                    _modelLoaded = false;
                    _modelFailed = true;
                  });
                },
              ),
            ),
            if (!_modelLoaded && !_modelFailed)
              Positioned.fill(
                child: _LoadingOverlay(progress: _loadingProgress),
              ),
            if (_modelFailed)
              Positioned.fill(child: _ErrorOverlay(onRetry: _retryLoad)),
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
            if (widget.brakeLightMounted)
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
                bottom: 86,
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
                center: const Alignment(0, -0.08),
                radius: 0.82,
                colors: [
                  MunjaColors.mint.withOpacity(isLive ? 0.22 : 0.13),
                  MunjaColors.mint.withOpacity(isLive ? 0.07 : 0.04),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 72,
          child: Container(
            height: 16,
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
