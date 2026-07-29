import 'package:flutter/material.dart';

import '../../core/theme/munja_colors.dart';
import 'bike_glow.dart';
import 'bike_painter.dart';
import 'brake_light_widget.dart';

class DigitalTwin extends StatefulWidget {
  final bool isLive;
  final bool brakeLightConnected;
  final bool isBraking;
  final double brakeLightBattery;
  final VoidCallback? onBrakeLightTap;
  final VoidCallback? onBikeTap;

  const DigitalTwin({
    super.key,
    required this.isLive,
    required this.brakeLightConnected,
    this.isBraking = false,
    this.brakeLightBattery = 64,
    this.onBrakeLightTap,
    this.onBikeTap,
  });

  @override
  State<DigitalTwin> createState() => _DigitalTwinState();
}

class _DigitalTwinState extends State<DigitalTwin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wheelController;

  double _rotation = 0;
  double _scale = 1;

  @override
  void initState() {
    super.initState();

    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    if (widget.isLive) {
      _wheelController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant DigitalTwin oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLive && !_wheelController.isAnimating) {
      _wheelController.repeat();
    }

    if (!widget.isLive && _wheelController.isAnimating) {
      _wheelController.stop();
    }
  }

  @override
  void dispose() {
    _wheelController.dispose();
    super.dispose();
  }

  void _handleBikeTap() {
    widget.onBikeTap?.call();
  }

  void _handleBrakeLightTap() {
    widget.onBrakeLightTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleBikeTap,
      onScaleUpdate: (details) {
        setState(() {
          _rotation += details.focalPointDelta.dx * 0.006;
          _scale = (_scale * details.scale).clamp(0.92, 1.16);
        });
      },
      child: Container(
        height: 320,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(38),
          border: Border.all(color: MunjaColors.mint.withOpacity(0.08)),
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 0.86,
            colors: [
              MunjaColors.mint.withOpacity(widget.isLive ? 0.22 : 0.16),
              MunjaColors.panel.withOpacity(0.72),
              MunjaColors.bg,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(widget.isLive ? 0.18 : 0.10),
              blurRadius: widget.isLive ? 44 : 28,
              spreadRadius: widget.isLive ? 2 : 0,
            ),
          ],
        ),
        child: BikeGlow(
          isLive: widget.isLive,
          isBraking: widget.isBraking,
          isConnected: widget.brakeLightConnected,
          child: Transform.scale(
            scale: _scale,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateY(_rotation),
              child: SizedBox(
                width: 348,
                height: 230,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _wheelController,
                      builder: (context, _) {
                        return CustomPaint(
                          size: const Size(348, 230),
                          painter: BikePainter(
                            wheelRotation: widget.isLive
                                ? _wheelController.value
                                : 0,
                            isLive: widget.isLive,
                            brakeLightConnected: widget.brakeLightConnected,
                          ),
                        );
                      },
                    ),

                    Positioned(
                      left: 64,
                      top: 92,
                      child: Transform.rotate(
                        angle: -0.10,
                        child: BrakeLightWidget(
                          connected: widget.brakeLightConnected,
                          braking: widget.isBraking,
                          batteryLevel: widget.brakeLightBattery,
                          onTap: _handleBrakeLightTap,
                        ),
                      ),
                    ),

                    Positioned(
                      left: 18,
                      right: 18,
                      bottom: -10,
                      child: IgnorePointer(
                        child: _DigitalTwinFloorLine(
                          isLive: widget.isLive,
                          isBraking: widget.isBraking,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitalTwinFloorLine extends StatelessWidget {
  final bool isLive;
  final bool isBraking;

  const _DigitalTwinFloorLine({required this.isLive, required this.isBraking});

  @override
  Widget build(BuildContext context) {
    final color = isBraking ? MunjaColors.danger : MunjaColors.mint;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            color.withOpacity(isLive ? 0.75 : 0.38),
            Colors.transparent,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isLive ? 0.45 : 0.20),
            blurRadius: isLive ? 18 : 10,
            spreadRadius: isLive ? 2 : 0,
          ),
        ],
      ),
    );
  }
}
