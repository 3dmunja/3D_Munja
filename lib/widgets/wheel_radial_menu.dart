import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class WheelRadialMenuItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const WheelRadialMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class WheelRadialMenu extends StatefulWidget {
  final bool isRiding;
  final double liveSpeedKmh;
  final List<WheelRadialMenuItem> items;
  final VoidCallback onWheelTap;
  final double size;

  /// Beholdes for kompatibilitet.
  /// Assettet bruges som synligt cykelhjul.
  final String wheelAsset;

  const WheelRadialMenu({
    super.key,
    required this.items,
    required this.onWheelTap,
    this.isRiding = false,
    this.liveSpeedKmh = 0,
    this.size = 124,
    this.wheelAsset = 'assets/Bicycle_Tires_1.png',
  });

  @override
  State<WheelRadialMenu> createState() => _WheelRadialMenuState();
}

class _WheelRadialMenuState extends State<WheelRadialMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Timer? _holdTimer;

  bool _holding = false;
  bool _menuOpen = false;
  bool _startTriggered = false;

  double _holdProgress = 0;
  Offset _dragOffset = Offset.zero;
  int? _hoverIndex;

  static const double _dragOpenDistance = 24;
  static const Duration _holdToStartDuration = Duration(milliseconds: 1250);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _durationFromSpeed(widget.liveSpeedKmh),
    );

    if (widget.isRiding) {
      _controller.repeat();
    } else {
      _controller.repeat(period: const Duration(milliseconds: 3600));
    }
  }

  @override
  void didUpdateWidget(covariant WheelRadialMenu oldWidget) {
    super.didUpdateWidget(oldWidget);

    _controller.duration = _durationFromSpeed(widget.liveSpeedKmh);

    if (!_controller.isAnimating) {
      if (widget.isRiding) {
        _controller.repeat();
      } else {
        _controller.repeat(period: const Duration(milliseconds: 3600));
      }
    }
  }

  Duration _durationFromSpeed(double speed) {
    if (!widget.isRiding || speed <= 1) {
      return const Duration(milliseconds: 2600);
    }

    final clamped = speed.clamp(1, 45);
    final ms = 1200 - (clamped * 18);

    return Duration(milliseconds: ms.clamp(320, 1200).round());
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    HapticFeedback.lightImpact();

    _holdTimer?.cancel();

    setState(() {
      _holding = true;
      _menuOpen = false;
      _startTriggered = false;
      _holdProgress = 0;
      _dragOffset = Offset.zero;
      _hoverIndex = null;
    });

    _runHoldProgress();

    _holdTimer = Timer(_holdToStartDuration, () {
      if (!_holding || _menuOpen || _startTriggered) return;

      _startTriggered = true;

      setState(() {
        _holdProgress = 0;
      });

      HapticFeedback.heavyImpact();
      widget.onWheelTap();
    });
  }

  Future<void> _runHoldProgress() async {
    const steps = 25;
    final delayMs = (_holdToStartDuration.inMilliseconds / steps).round();

    for (int i = 0; i <= steps; i++) {
      if (!_holding || _menuOpen || _startTriggered) return;

      setState(() {
        _holdProgress = i / steps;
      });

      await Future.delayed(Duration(milliseconds: delayMs));
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_holding) return;

    final nextOffset = _dragOffset + details.delta;
    final shouldOpen = nextOffset.distance >= _dragOpenDistance;

    setState(() {
      _dragOffset = nextOffset;

      if (shouldOpen && !_menuOpen) {
        _menuOpen = true;
        _holdProgress = 0;
        _holdTimer?.cancel();
        HapticFeedback.mediumImpact();
      }

      if (_menuOpen) {
        _hoverIndex = _closestItemIndex(nextOffset);
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _finishGesture();
  }

  void _onPanCancel() {
    _finishGesture();
  }

  void _finishGesture() {
    _holdTimer?.cancel();

    final items = widget.items.take(5).toList();

    if (_menuOpen && _hoverIndex != null && _hoverIndex! < items.length) {
      HapticFeedback.selectionClick();
      items[_hoverIndex!].onTap();
    }

    setState(() {
      _holding = false;
      _menuOpen = false;
      _startTriggered = false;
      _holdProgress = 0;
      _dragOffset = Offset.zero;
      _hoverIndex = null;
    });
  }

  int? _closestItemIndex(Offset dragOffset) {
    final items = widget.items.take(5).toList();

    if (items.isEmpty) return null;
    if (dragOffset.distance < _dragOpenDistance) return null;

    double bestDistance = double.infinity;
    int? bestIndex;

    for (int i = 0; i < items.length; i++) {
      final pos = _RadialNavTile.offsetForIndex(index: i, count: items.length);

      final distance = (dragOffset - pos).distance;

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    return bestIndex;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items.take(5).toList();

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          height: 214,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  onPanCancel: _onPanCancel,
                  child: SizedBox(
                    width: 210,
                    height: 188,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) {
                                final pulse =
                                    (math.sin(_controller.value * math.pi * 2) +
                                        1) /
                                    2;

                                return Container(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment.center,
                                      radius: _menuOpen ? 0.92 : 0.62,
                                      colors: [
                                        MunjaColors.mint.withOpacity(
                                          widget.isRiding
                                              ? 0.22 + pulse * 0.10
                                              : _menuOpen
                                              ? 0.18
                                              : 0.12,
                                        ),
                                        MunjaColors.mint.withOpacity(
                                          _menuOpen ? 0.07 : 0.035,
                                        ),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        _WheelVisualCore(
                          controller: _controller,
                          size: widget.size + 8,
                          asset: widget.wheelAsset,
                          isRiding: widget.isRiding,
                          progress: _holdProgress,
                          menuOpen: _menuOpen,
                        ),

                        _WheelCenterStatus(
                          isRiding: widget.isRiding,
                          speed: widget.liveSpeedKmh,
                          progress: _holdProgress,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_menuOpen)
                Positioned(
                  bottom: 14,
                  child: IgnorePointer(
                    child: Container(
                      width: 292,
                      height: 292,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: MunjaColors.mint.withOpacity(0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: MunjaColors.mint.withOpacity(
                              widget.isRiding ? 0.30 : 0.18,
                            ),
                            blurRadius: widget.isRiding ? 54 : 38,
                            spreadRadius: widget.isRiding ? 5 : 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              ...List.generate(items.length, (index) {
                final active = _menuOpen && _hoverIndex == index;

                return Positioned(
                  bottom: 76,
                  child: _RadialNavTile(
                    item: items[index],
                    index: index,
                    count: items.length,
                    visible: _menuOpen,
                    active: active,
                  ),
                );
              }),

              if (_menuOpen && _hoverIndex != null)
                Positioned(
                  bottom: 76,
                  child: _DragIndicator(dragOffset: _dragOffset),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WheelVisualCore extends StatelessWidget {
  final AnimationController controller;
  final double size;
  final String asset;
  final bool isRiding;
  final double progress;
  final bool menuOpen;

  const _WheelVisualCore({
    required this.controller,
    required this.size,
    required this.asset,
    required this.isRiding,
    required this.progress,
    required this.menuOpen,
  });

  @override
  Widget build(BuildContext context) {
    final wheelOpacity = isRiding ? 0.98 : 0.90;

    return IgnorePointer(
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: menuOpen ? 1.05 : 1,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size + 62,
              height: size + 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    MunjaColors.mint.withOpacity(isRiding ? 0.26 : 0.16),
                    MunjaColors.mint.withOpacity(0.05),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: MunjaColors.mint.withOpacity(isRiding ? 0.40 : 0.22),
                    blurRadius: isRiding ? 48 : 30,
                    spreadRadius: isRiding ? 8 : 2,
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: controller.value * math.pi * 2,
                  child: child,
                );
              },
              child: Opacity(
                opacity: wheelOpacity,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Image.asset(asset, fit: BoxFit.contain),
                ),
              ),
            ),
            Container(
              width: size * 0.22,
              height: size * 0.22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0A1713).withOpacity(0.92),
                border: Border.all(
                  color: MunjaColors.mint.withOpacity(0.38),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: MunjaColors.mint.withOpacity(isRiding ? 0.28 : 0.12),
                    blurRadius: isRiding ? 20 : 12,
                    spreadRadius: isRiding ? 2 : 0,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: size * 0.08,
                  height: size * 0.08,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRiding ? MunjaColors.mint : Colors.white30,
                  ),
                ),
              ),
            ),
            if (progress > 0)
              SizedBox(
                width: size + 18,
                height: size + 18,
                child: CustomPaint(
                  painter: _WheelProgressPainter(progress: progress),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RadialNavTile extends StatelessWidget {
  final WheelRadialMenuItem item;
  final int index;
  final int count;
  final bool visible;
  final bool active;

  const _RadialNavTile({
    required this.item,
    required this.index,
    required this.count,
    required this.visible,
    required this.active,
  });

  static Offset offsetForIndex({required int index, required int count}) {
    const positions = <Offset>[
      Offset(0, -112),
      Offset(118, -18),
      Offset(76, 104),
      Offset(-76, 104),
      Offset(-118, -18),
    ];

    if (count == 5 && index < positions.length) {
      return positions[index];
    }

    final angle = -math.pi / 2 + (math.pi * 2 / count) * index;
    const radius = 118.0;

    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  @override
  Widget build(BuildContext context) {
    final offset = offsetForIndex(index: index, count: count);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: visible ? 1 : 0,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: visible ? 1 : 0.76,
        child: Transform.translate(
          offset: visible ? offset : Offset.zero,
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              width: active ? 90 : 74,
              height: active ? 82 : 68,
              decoration: BoxDecoration(
                color: active
                    ? MunjaColors.mint.withOpacity(0.24)
                    : Colors.black.withOpacity(0.22),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: active
                      ? MunjaColors.mint.withOpacity(0.72)
                      : Colors.white.withOpacity(0.07),
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: MunjaColors.mint.withOpacity(0.38),
                          blurRadius: 30,
                          spreadRadius: 3,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.24),
                          blurRadius: 18,
                        ),
                      ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    color: active ? MunjaColors.mint : Colors.white70,
                    size: active ? 27 : 22,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? Colors.white : Colors.white54,
                      fontSize: active ? 11 : 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.2,
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

class _DragIndicator extends StatelessWidget {
  final Offset dragOffset;

  const _DragIndicator({required this.dragOffset});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Transform.translate(
        offset: dragOffset,
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MunjaColors.mint,
            boxShadow: [
              BoxShadow(
                color: MunjaColors.mint.withOpacity(0.65),
                blurRadius: 18,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WheelCenterStatus extends StatelessWidget {
  final bool isRiding;
  final double speed;
  final double progress;

  const _WheelCenterStatus({
    required this.isRiding,
    required this.speed,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();

    String text;
    if (isRiding) {
      text = '${speed.toStringAsFixed(1)} km/h';
    } else if (percent > 0) {
      text = '$percent%';
    } else {
      text = AppText.t('hold_to_start');
    }

    return IgnorePointer(
      child: Transform.translate(
        offset: const Offset(0, 78),
        child: Text(
          text,
          style: TextStyle(
            color: (percent > 0 || isRiding)
                ? MunjaColors.mint
                : MunjaColors.textSoft,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            shadows: [
              Shadow(color: Colors.black.withOpacity(0.9), blurRadius: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _WheelProgressPainter extends CustomPainter {
  final double progress;

  const _WheelProgressPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final progressPaint = Paint()
      ..color = MunjaColors.mint
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
