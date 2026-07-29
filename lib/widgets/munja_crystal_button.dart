import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class MunjaCrystalButton extends StatefulWidget {
  final bool isLive;
  final Future<void> Function() onCompleted;

  const MunjaCrystalButton({
    super.key,
    required this.isLive,
    required this.onCompleted,
  });

  @override
  State<MunjaCrystalButton> createState() => _MunjaCrystalButtonState();
}

class _MunjaCrystalButtonState extends State<MunjaCrystalButton> {
  double progress = 0;
  bool holding = false;

  Future<void> _startHold() async {
    if (holding) return;

    holding = true;

    for (int i = 0; i <= 100; i += 25) {
      if (!holding) return;

      setState(() => progress = i / 100);
      await Future.delayed(const Duration(milliseconds: 230));
    }

    holding = false;
    setState(() => progress = 0);

    await widget.onCompleted();
  }

  void _cancelHold() {
    if (!holding) return;

    holding = false;
    setState(() => progress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();

    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _cancelHold(),
      child: Column(
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(
                    widget.isLive ? 0.46 : 0.27,
                  ),
                  blurRadius: widget.isLive ? 52 : 38,
                  spreadRadius: widget.isLive ? 10 : 4,
                ),
              ],
            ),
            child: CustomPaint(
              painter: MunjaCrystalPainter(
                progress: progress,
                active: widget.isLive,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            percent > 0
                ? '$percent%'
                : widget.isLive
                ? AppText.t('hold_to_stop')
                : AppText.t('hold_to_start'),
            style: const TextStyle(
              color: MunjaColors.mint,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class MunjaCrystalPainter extends CustomPainter {
  final double progress;
  final bool active;

  const MunjaCrystalPainter({required this.progress, required this.active});

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..color = MunjaColors.mint.withOpacity(
        active ? 0.30 : 0.18 + progress * 0.20,
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

    final path = Path()
      ..moveTo(size.width / 2, 5)
      ..lineTo(size.width - 10, size.height * 0.34)
      ..lineTo(size.width * 0.72, size.height - 10)
      ..lineTo(size.width * 0.28, size.height - 10)
      ..lineTo(10, size.height * 0.34)
      ..close();

    canvas.drawPath(path, glow);

    final fill = Paint()
      ..color = MunjaColors.mint.withOpacity(
        active ? 0.28 : 0.14 + progress * 0.3,
      )
      ..style = PaintingStyle.fill;

    final outline = Paint()
      ..color = MunjaColors.mint.withOpacity(active ? 1 : 0.82)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);

    canvas.drawLine(
      Offset(size.width / 2, 5),
      Offset(size.width / 2, size.height - 10),
      outline,
    );

    canvas.drawLine(
      Offset(10, size.height * 0.34),
      Offset(size.width * 0.72, size.height - 10),
      outline,
    );

    canvas.drawLine(
      Offset(size.width - 10, size.height * 0.34),
      Offset(size.width * 0.28, size.height - 10),
      outline,
    );

    if (progress > 0) {
      final progressPaint = Paint()
        ..color = MunjaColors.mint
        ..strokeWidth = 4.5
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
  }

  @override
  bool shouldRepaint(covariant MunjaCrystalPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.active != active;
  }
}

class MunjaMiniCrystal extends StatelessWidget {
  const MunjaMiniCrystal({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(28, 28),
      painter: const MunjaCrystalPainter(progress: 0, active: false),
    );
  }
}
