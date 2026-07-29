import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/munja_colors.dart';

class BikePainter extends CustomPainter {
  final double wheelRotation;
  final bool isLive;
  final bool brakeLightConnected;

  const BikePainter({
    required this.wheelRotation,
    required this.isLive,
    required this.brakeLightConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawShadowPlatform(canvas, size);
    _drawWheels(canvas, size);
    _drawFrame(canvas, size);
    _drawCockpit(canvas, size);
    _drawCrank(canvas, size);
    _drawBrakeLight(canvas, size);
    _drawLiveEffects(canvas, size);
  }

  Offset getRearWheel(Size size) {
    return Offset(size.width * 0.25, size.height * 0.68);
  }

  Offset getFrontWheel(Size size) {
    return Offset(size.width * 0.75, size.height * 0.68);
  }

  double getWheelRadius(Size size) {
    return size.width * 0.125;
  }

  Offset getBrakeLightCenter(Size size) {
    final rear = getRearWheel(size);
    return Offset(rear.dx - 21, rear.dy - 45);
  }

  void _drawShadowPlatform(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.30 : 0.18)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 34);

    final platformRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.83),
      width: size.width * 0.74,
      height: 36,
    );

    canvas.drawOval(platformRect, glowPaint);

    final arcPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.70 : 0.50)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      platformRect,
      math.pi * 0.04,
      math.pi * 0.92,
      false,
      arcPaint,
    );

    final rearSpark = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.65 : 0.32)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.78),
      Offset(size.width * 0.17, size.height * 0.80),
      rearSpark,
    );

    canvas.drawLine(
      Offset(size.width * 0.83, size.height * 0.80),
      Offset(size.width * 0.90, size.height * 0.78),
      rearSpark,
    );
  }

  void _drawWheels(Canvas canvas, Size size) {
    final rear = getRearWheel(size);
    final front = getFrontWheel(size);
    final radius = getWheelRadius(size);

    _drawWheel(canvas, rear, radius);
    _drawWheel(canvas, front, radius);
  }

  void _drawWheel(Canvas canvas, Offset center, double radius) {
    final tyreShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;

    final tyrePaint = Paint()
      ..color = const Color(0xFF121A17)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    final tyreHighlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final rimPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.95 : 0.74)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6;

    final innerRimPaint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final spokePaint = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1.1;

    final hubPaint = Paint()..color = Colors.white.withOpacity(0.58);

    canvas.drawCircle(center, radius, tyreShadowPaint);
    canvas.drawCircle(center, radius, tyrePaint);
    canvas.drawCircle(center, radius - 4, rimPaint);
    canvas.drawCircle(center, radius - 15, innerRimPaint);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi * 0.82,
      math.pi * 0.72,
      false,
      tyreHighlightPaint,
    );

    for (int i = 0; i < 18; i++) {
      final angle = (math.pi * 2 * i / 18) + (wheelRotation * math.pi * 2);
      canvas.drawLine(
        center,
        Offset(
          center.dx + math.cos(angle) * (radius - 8),
          center.dy + math.sin(angle) * (radius - 8),
        ),
        spokePaint,
      );
    }

    canvas.drawCircle(center, 6.2, hubPaint);

    canvas.drawCircle(
      center,
      3.2,
      Paint()..color = Colors.black.withOpacity(0.55),
    );
  }

  void _drawFrame(Canvas canvas, Size size) {
    final rear = getRearWheel(size);
    final front = getFrontWheel(size);

    final seatTubeTop = Offset(size.width * 0.41, size.height * 0.30);
    final headTubeTop = Offset(size.width * 0.67, size.height * 0.35);
    final crank = Offset(size.width * 0.49, size.height * 0.55);

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

    final glowPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.34 : 0.23)
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

    final darkTubePaint = Paint()
      ..color = const Color(0xFF07120F).withOpacity(0.95)
      ..strokeWidth = 9.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final framePaint = Paint()
      ..color = Colors.white.withOpacity(0.92)
      ..strokeWidth = 5.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final highlightPaint = Paint()
      ..color = Colors.white.withOpacity(0.34)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    canvas.drawPath(framePath, glowPaint);
    canvas.drawPath(framePath, darkTubePaint);
    canvas.drawPath(framePath, framePaint);

    final highlightPath = Path()
      ..moveTo(seatTubeTop.dx + 3, seatTubeTop.dy + 2)
      ..lineTo(headTubeTop.dx - 3, headTubeTop.dy + 4)
      ..moveTo(crank.dx + 2, crank.dy - 2)
      ..lineTo(headTubeTop.dx - 5, headTubeTop.dy + 5);

    canvas.drawPath(highlightPath, highlightPaint);
  }

  void _drawCockpit(Canvas canvas, Size size) {
    final seatTubeTop = Offset(size.width * 0.41, size.height * 0.30);
    final headTubeTop = Offset(size.width * 0.67, size.height * 0.35);

    final paint = Paint()
      ..color = Colors.white.withOpacity(0.90)
      ..strokeWidth = 5.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final darkPaint = Paint()
      ..color = const Color(0xFF07120F).withOpacity(0.95)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final seatPostTop = Offset(seatTubeTop.dx - 11, seatTubeTop.dy - 34);

    final saddleLeft = Offset(seatPostTop.dx - 33, seatPostTop.dy - 4);

    final saddleRight = Offset(seatPostTop.dx + 17, seatPostTop.dy - 2);

    canvas.drawLine(seatTubeTop, seatPostTop, darkPaint);
    canvas.drawLine(saddleLeft, saddleRight, darkPaint);

    canvas.drawLine(seatTubeTop, seatPostTop, paint);
    canvas.drawLine(saddleLeft, saddleRight, paint);

    final headTop = Offset(headTubeTop.dx + 12, headTubeTop.dy - 19);

    final barStem = Offset(headTop.dx + 33, headTop.dy + 2);

    final barDrop = Offset(barStem.dx + 20, barStem.dy + 12);

    canvas.drawLine(headTubeTop, headTop, darkPaint);
    canvas.drawLine(headTop, barStem, darkPaint);
    canvas.drawLine(barStem, barDrop, darkPaint);

    canvas.drawLine(headTubeTop, headTop, paint);
    canvas.drawLine(headTop, barStem, paint);
    canvas.drawLine(barStem, barDrop, paint);
  }

  void _drawCrank(Canvas canvas, Size size) {
    final crank = Offset(size.width * 0.49, size.height * 0.55);

    final glowPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(isLive ? 0.46 : 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    final ringPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final armPaint = Paint()
      ..color = MunjaColors.mint.withOpacity(0.86)
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(crank, 12, glowPaint);
    canvas.drawCircle(crank, 10, ringPaint);
    canvas.drawCircle(
      crank,
      4,
      Paint()..color = Colors.white.withOpacity(0.55),
    );

    final crankAngle = wheelRotation * math.pi * 2;

    canvas.drawLine(
      crank,
      Offset(
        crank.dx + math.cos(crankAngle) * 20,
        crank.dy + math.sin(crankAngle) * 20,
      ),
      armPaint,
    );

    canvas.drawLine(
      crank,
      Offset(
        crank.dx + math.cos(crankAngle + math.pi) * 16,
        crank.dy + math.sin(crankAngle + math.pi) * 16,
      ),
      armPaint,
    );
  }

  void _drawBrakeLight(Canvas canvas, Size size) {
    final center = getBrakeLightCenter(size);

    final glowPaint = Paint()
      ..color = (brakeLightConnected ? MunjaColors.danger : Colors.white30)
          .withOpacity(brakeLightConnected ? 0.92 : 0.40)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 13);

    canvas.drawCircle(center, 11, glowPaint);

    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 16, height: 32),
      const Radius.circular(9),
    );

    canvas.drawRRect(body, Paint()..color = const Color(0xFF101917));

    canvas.drawRRect(
      body,
      Paint()
        ..color = brakeLightConnected ? MunjaColors.danger : Colors.white30
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    final ledPaint = Paint()
      ..color = brakeLightConnected
          ? MunjaColors.danger.withOpacity(0.92)
          : Colors.white24
      ..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(center.dx, center.dy - 8 + i * 8),
            width: 6,
            height: 4,
          ),
          const Radius.circular(2),
        ),
        ledPaint,
      );
    }
  }

  void _drawLiveEffects(Canvas canvas, Size size) {
    if (!isLive) return;

    final rear = getRearWheel(size);
    final front = getFrontWheel(size);
    final radius = getWheelRadius(size);

    final livePaint = Paint()
      ..color = MunjaColors.mint.withOpacity(0.27)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

    canvas.drawCircle(rear, radius + 8, livePaint);
    canvas.drawCircle(front, radius + 8, livePaint);

    final speedLine = Paint()
      ..color = MunjaColors.mint.withOpacity(0.22)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.54),
      Offset(size.width * 0.02, size.height * 0.54),
      speedLine,
    );

    canvas.drawLine(
      Offset(size.width * 0.17, size.height * 0.47),
      Offset(size.width * 0.07, size.height * 0.47),
      speedLine,
    );

    canvas.drawLine(
      Offset(size.width * 0.86, size.height * 0.51),
      Offset(size.width * 0.96, size.height * 0.51),
      speedLine,
    );
  }

  @override
  bool shouldRepaint(covariant BikePainter oldDelegate) {
    return oldDelegate.wheelRotation != wheelRotation ||
        oldDelegate.isLive != isLive ||
        oldDelegate.brakeLightConnected != brakeLightConnected;
  }
}
