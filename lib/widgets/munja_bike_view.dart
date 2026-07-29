import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';

class MunjaBikeView extends StatefulWidget {
  final bool isLive;
  final bool brakeLightConnected;
  final VoidCallback onBikeTap;

  const MunjaBikeView({
    super.key,
    required this.isLive,
    required this.brakeLightConnected,
    required this.onBikeTap,
  });

  @override
  State<MunjaBikeView> createState() => _MunjaBikeViewState();
}

class _MunjaBikeViewState extends State<MunjaBikeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double _rotation = 0;
  double _scale = 1;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    if (widget.isLive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MunjaBikeView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLive && !_controller.isAnimating) {
      _controller.repeat();
    }

    if (!widget.isLive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleUpdate: (details) {
        setState(() {
          _rotation += details.focalPointDelta.dx * 0.006;
          _scale = (_scale * details.scale).clamp(0.92, 1.16);
        });
      },
      onTap: widget.onBikeTap,
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
              MunjaColors.surface.withOpacity(0.72),
              MunjaColors.background,
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
        child: Transform.scale(
          scale: _scale,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(_rotation),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  size: const Size(348, 230),
                  painter: MunjaPremiumBikePainter(
                    wheelRotation: widget.isLive ? _controller.value : 0,
                    isLive: widget.isLive,
                    brakeLightConnected: widget.brakeLightConnected,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class MunjaPremiumBikePainter extends CustomPainter {
  final double wheelRotation;
  final bool isLive;
  final bool brakeLightConnected;

  const MunjaPremiumBikePainter({
    required this.wheelRotation,
    required this.isLive,
    required this.brakeLightConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final platformGlow = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.30 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.83),
        width: size.width * 0.72,
        height: 34,
      ),
      platformGlow,
    );

    final platformLine = Paint()
      ..color = MunjaColors.mint.withOpacity(0.55)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.83),
        width: size.width * 0.72,
        height: 34,
      ),
      math.pi * 0.05,
      math.pi * 0.9,
      false,
      platformLine,
    );

    final rear = Offset(size.width * 0.25, size.height * 0.68);
    final front = Offset(size.width * 0.75, size.height * 0.68);
    final wheelRadius = size.width * 0.125;

    final tyreShadow = Paint()
      ..color = Colors.black.withOpacity(0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14;

    final tyre = Paint()
      ..color = Colors.white.withOpacity(0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    final rim = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.92 : 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4;

    final spoke = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1.1;

    void drawWheel(Offset c) {
      canvas.drawCircle(c, wheelRadius, tyreShadow);
      canvas.drawCircle(c, wheelRadius, tyre);
      canvas.drawCircle(c, wheelRadius - 4, rim);

      for (int i = 0; i < 14; i++) {
        final angle = (math.pi * 2 * i / 14) + (wheelRotation * math.pi * 2);
        canvas.drawLine(
          c,
          Offset(
            c.dx + math.cos(angle) * (wheelRadius - 8),
            c.dy + math.sin(angle) * (wheelRadius - 8),
          ),
          spoke,
        );
      }

      canvas.drawCircle(c, 5, Paint()..color = Colors.white.withOpacity(0.55));
    }

    drawWheel(rear);
    drawWheel(front);

    final seatTubeTop = Offset(size.width * 0.41, size.height * 0.30);
    final headTubeTop = Offset(size.width * 0.67, size.height * 0.35);
    final crank = Offset(size.width * 0.49, size.height * 0.55);

    final frameGlow = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.32 : 0.22)
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    final frameDark = Paint()
      ..color = const Color(0xFF0A1411).withOpacity(0.88)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final frame = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..strokeWidth = 5.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final framePath = Path()
      ..moveTo(rear.dx, rear.dy)
      ..lineTo(seatTubeTop.dx, seatTubeTop.dy)
      ..lineTo(headTubeTop.dx, headTubeTop.dy)
      ..lineTo(front.dx, front.dy)
      ..lineTo(crank.dx, crank.dy)
      ..lineTo(rear.dx, rear.dy)
      ..moveTo(seatTubeTop.dx, seatTubeTop.dy)
      ..lineTo(crank.dx, crank.dy)
      ..moveTo(crank.dx, crank.dy)
      ..lineTo(headTubeTop.dx, headTubeTop.dy);

    canvas.drawPath(framePath, frameGlow);
    canvas.drawPath(framePath, frameDark);
    canvas.drawPath(framePath, frame);

    final cockpitPaint = Paint()
      ..color = Colors.white.withOpacity(0.90)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final seatPostTop = Offset(seatTubeTop.dx - 11, seatTubeTop.dy - 34);
    final saddleLeft = Offset(seatPostTop.dx - 31, seatPostTop.dy - 4);
    final saddleRight = Offset(seatPostTop.dx + 16, seatPostTop.dy - 2);

    canvas.drawLine(seatTubeTop, seatPostTop, cockpitPaint);
    canvas.drawLine(saddleLeft, saddleRight, cockpitPaint);

    final headTop = Offset(headTubeTop.dx + 12, headTubeTop.dy - 19);
    final barStem = Offset(headTop.dx + 31, headTop.dy + 2);
    final barDrop = Offset(barStem.dx + 18, barStem.dy + 12);

    canvas.drawLine(headTubeTop, headTop, cockpitPaint);
    canvas.drawLine(headTop, barStem, cockpitPaint);
    canvas.drawLine(barStem, barDrop, cockpitPaint);

    final crankPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(0.82)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(crank, 9, crankPaint);
    canvas.drawLine(
      crank,
      Offset(
        crank.dx + math.cos(wheelRotation * math.pi * 2) * 18,
        crank.dy + math.sin(wheelRotation * math.pi * 2) * 18,
      ),
      crankPaint,
    );

    final brakeLightCenter = Offset(rear.dx - 21, rear.dy - 45);

    final brakeGlow = Paint()
      ..color = (brakeLightConnected ? MunjaColors.danger : Colors.white30)
          .withOpacity(brakeLightConnected ? 0.9 : 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    canvas.drawCircle(brakeLightCenter, 9, brakeGlow);

    final brakeBody = RRect.fromRectAndRadius(
      Rect.fromCenter(center: brakeLightCenter, width: 14, height: 28),
      const Radius.circular(8),
    );

    canvas.drawRRect(brakeBody, Paint()..color = const Color(0xFF101917));

    canvas.drawRRect(
      brakeBody,
      Paint()
        ..color = brakeLightConnected ? MunjaColors.danger : Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    if (isLive) {
      final livePaint = Paint()
        ..color = MunjaColors.mint.withOpacity(0.26)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      canvas.drawCircle(rear, wheelRadius + 7, livePaint);
      canvas.drawCircle(front, wheelRadius + 7, livePaint);
    }
  }

  @override
  bool shouldRepaint(covariant MunjaPremiumBikePainter oldDelegate) {
    return oldDelegate.wheelRotation != wheelRotation ||
        oldDelegate.isLive != isLive ||
        oldDelegate.brakeLightConnected != brakeLightConnected;
  }
}
