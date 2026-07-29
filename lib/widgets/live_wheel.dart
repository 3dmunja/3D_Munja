import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';

class LiveWheel extends StatefulWidget {
  final double size;
  final double speedKmh;
  final bool active;
  final bool braking;
  final bool glowing;
  final String assetPath;

  const LiveWheel({
    super.key,
    this.size = 96,
    this.speedKmh = 0,
    this.active = false,
    this.braking = false,
    this.glowing = true,
    this.assetPath = 'assets/Bicycle_Tires_1.png',
  });

  @override
  State<LiveWheel> createState() => _LiveWheelState();
}

class _LiveWheelState extends State<LiveWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _durationFromSpeed(widget.speedKmh)),
    );

    if (widget.active) {
      _ctrl.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant LiveWheel oldWidget) {
    super.didUpdateWidget(oldWidget);

    final speedChanged = widget.speedKmh != oldWidget.speedKmh;
    final activeChanged = widget.active != oldWidget.active;
    final brakeChanged = widget.braking != oldWidget.braking;

    if (speedChanged || brakeChanged) {
      _ctrl.duration = Duration(
        milliseconds: _durationFromSpeed(widget.speedKmh),
      );

      if (widget.active && !_ctrl.isAnimating) {
        _ctrl.repeat();
      }
    }

    if (activeChanged) {
      if (widget.active) {
        _ctrl.duration = Duration(
          milliseconds: _durationFromSpeed(widget.speedKmh),
        );
        _ctrl.repeat();
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.stop();
    _ctrl.dispose();
    super.dispose();
  }

  int _durationFromSpeed(double speedKmh) {
    if (widget.braking) return 1400;

    final speed = speedKmh.clamp(0, 55);

    if (speed <= 1) return 3200;
    if (speed <= 5) return 2400;
    if (speed <= 12) return 1700;
    if (speed <= 25) return 1100;
    if (speed <= 40) return 760;

    return 520;
  }

  @override
  Widget build(BuildContext context) {
    final activeGlow = widget.glowing && (widget.active || widget.braking);

    final angle = widget.braking
        ? -_ctrl.value * math.pi * 0.35
        : _ctrl.value * math.pi * 2;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: widget.braking
                      ? Colors.redAccent.withOpacity(0.45)
                      : activeGlow
                      ? MunjaColors.mint.withOpacity(0.35)
                      : Colors.black.withOpacity(0.25),
                  blurRadius: widget.braking
                      ? 34
                      : activeGlow
                      ? 28
                      : 14,
                  spreadRadius: widget.braking
                      ? 8
                      : activeGlow
                      ? 4
                      : 1,
                ),
              ],
            ),
          ),
          if (widget.glowing)
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: widget.size * 0.92,
              height: widget.size * 0.92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.braking
                      ? Colors.redAccent.withOpacity(0.65)
                      : widget.active
                      ? MunjaColors.mint.withOpacity(0.45)
                      : Colors.white.withOpacity(0.12),
                  width: widget.braking ? 3 : 2,
                ),
              ),
            ),
          Transform.rotate(
            angle: angle,
            child: Image.asset(
              widget.assetPath,
              width: widget.size * 0.86,
              height: widget.size * 0.86,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) {
                return Icon(
                  Icons.donut_large_rounded,
                  size: widget.size * 0.7,
                  color: widget.active
                      ? MunjaColors.mint
                      : Colors.white.withOpacity(0.65),
                );
              },
            ),
          ),
          if (widget.braking)
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: widget.braking ? 1 : 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent.withOpacity(0.08),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
