import 'dart:math' as math;

import 'package:flutter/material.dart';

class SkinUnlockCelebration extends StatefulWidget {
  const SkinUnlockCelebration({
    super.key,
    required this.skinName,
    required this.accentColor,
    this.headline = 'NEW SKIN UNLOCKED',
    this.subtitle = 'Equipped on your Digital Twin',
    this.duration = const Duration(milliseconds: 2600),
    this.onCompleted,
  });

  final String skinName;
  final Color accentColor;
  final String headline;
  final String subtitle;
  final Duration duration;
  final VoidCallback? onCompleted;

  @override
  State<SkinUnlockCelebration> createState() =>
      _SkinUnlockCelebrationState();
}

class _SkinUnlockCelebrationState extends State<SkinUnlockCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _flashOpacity;
  late final Animation<double> _contentOpacity;
  late final Animation<double> _contentScale;
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  final List<_CelebrationParticle> _particles = List.generate(
    34,
    (index) => _CelebrationParticle.fromIndex(index),
  );

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.82).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 18,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.82, end: 0.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(0.0),
        weight: 60,
      ),
    ]).animate(_controller);

    _contentOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(
        0.12,
        0.90,
        curve: Curves.easeOut,
      ),
      reverseCurve: Curves.easeIn,
    );

    _contentScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.78, end: 1.10).chain(
          CurveTween(curve: Curves.easeOutBack),
        ),
        weight: 48,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.10, end: 1.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 52,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.08, 0.72),
      ),
    );

    _ringScale = Tween<double>(
      begin: 0.55,
      end: 1.55,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(
          0.08,
          0.78,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _ringOpacity = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.95),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.95, end: 0.0),
        weight: 80,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.08, 0.82),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onCompleted?.call();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildBackgroundFlash(),
                _buildParticleLayer(),
                _buildCenterGlow(),
                _buildUnlockContent(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackgroundFlash() {
    return Opacity(
      opacity: _flashOpacity.value,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.02),
            radius: 0.92,
            colors: [
              widget.accentColor.withValues(alpha: 0.36),
              widget.accentColor.withValues(alpha: 0.12),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticleLayer() {
    return CustomPaint(
      painter: _CelebrationParticlePainter(
        progress: _controller.value,
        particles: _particles,
        accentColor: widget.accentColor,
      ),
    );
  }

  Widget _buildCenterGlow() {
    return Center(
      child: Opacity(
        opacity: _ringOpacity.value,
        child: Transform.scale(
          scale: _ringScale.value,
          child: Container(
            width: 178,
            height: 178,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.accentColor.withValues(alpha: 0.44),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accentColor.withValues(alpha: 0.24),
                  blurRadius: 38,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnlockContent() {
    final t = _controller.value;

    final verticalShift = Tween<double>(
      begin: 16,
      end: 0,
    ).transform(
      Curves.easeOutCubic.transform(
        ((t - 0.08) / 0.42).clamp(0.0, 1.0),
      ),
    );

    return Center(
      child: Transform.translate(
        offset: Offset(0, verticalShift),
        child: FadeTransition(
          opacity: _contentOpacity,
          child: ScaleTransition(
            scale: _contentScale,
            child: Container(
              width: 272,
              padding: const EdgeInsets.fromLTRB(
                22,
                24,
                22,
                22,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF081812)
                        .withValues(alpha: 0.96),
                    const Color(0xFF03100D)
                        .withValues(alpha: 0.98),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: widget.accentColor.withValues(alpha: 0.34),
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.18),
                    blurRadius: 30,
                    spreadRadius: -4,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 26,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildUnlockedIcon(),
                  const SizedBox(height: 15),
                  Text(
                    widget.headline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.accentColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.55,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    widget.skinName.toUpperCase(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.46),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
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

  Widget _buildUnlockedIcon() {
    final glowProgress = Curves.easeOutBack.transform(
      ((_controller.value - 0.06) / 0.45).clamp(0.0, 1.0),
    );

    return Transform.scale(
      scale: 0.82 + (0.18 * glowProgress),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              widget.accentColor.withValues(alpha: 0.26),
              widget.accentColor.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(
            color: widget.accentColor.withValues(alpha: 0.36),
          ),
          boxShadow: [
            BoxShadow(
              color: widget.accentColor.withValues(alpha: 0.30),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Icon(
          Icons.auto_awesome_rounded,
          color: widget.accentColor,
          size: 31,
        ),
      ),
    );
  }
}

class _CelebrationParticle {
  const _CelebrationParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
    required this.sparkLength,
    required this.twinkle,
  });

  factory _CelebrationParticle.fromIndex(int index) {
    final seeded = math.Random(index * 7919 + 17);

    return _CelebrationParticle(
      angle: seeded.nextDouble() * math.pi * 2,
      distance: 82 + seeded.nextDouble() * 170,
      size: 2.5 + seeded.nextDouble() * 5.0,
      delay: seeded.nextDouble() * 0.18,
      sparkLength: 5 + seeded.nextDouble() * 12,
      twinkle: seeded.nextBool(),
    );
  }

  final double angle;
  final double distance;
  final double size;
  final double delay;
  final double sparkLength;
  final bool twinkle;
}

class _CelebrationParticlePainter extends CustomPainter {
  const _CelebrationParticlePainter({
    required this.progress,
    required this.particles,
    required this.accentColor,
  });

  final double progress;
  final List<_CelebrationParticle> particles;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      size.width / 2,
      size.height / 2 - 12,
    );

    for (var i = 0; i < particles.length; i++) {
      final particle = particles[i];

      final localProgress = (
        (progress - particle.delay) /
        (1.0 - particle.delay)
      ).clamp(0.0, 1.0);

      if (localProgress <= 0) {
        continue;
      }

      final motion = Curves.easeOutCubic.transform(
        localProgress.clamp(0.0, 1.0),
      );

      final fade = 1.0 -
          Curves.easeIn.transform(
            ((localProgress - 0.54) / 0.46)
                .clamp(0.0, 1.0),
          );

      if (fade <= 0.0) {
        continue;
      }

      final travel = particle.distance * motion;
      final x = math.cos(particle.angle) * travel;
      final y = math.sin(particle.angle) * travel;

      final gravity = 26 * localProgress * localProgress;
      final position = center + Offset(x, y + gravity);

      final accentMix = i % 3 == 0
          ? accentColor
          : i % 3 == 1
              ? Colors.white
              : Color.lerp(
                  accentColor,
                  Colors.white,
                  0.48,
                )!;

      final opacity = fade *
          (particle.twinkle
              ? (0.62 + 0.38 * math.sin(localProgress * 18).abs())
              : 0.92);

      final paint = Paint()
        ..color = accentMix.withValues(
          alpha: opacity.clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.fill;

      if (i % 4 == 0) {
        _drawSpark(
          canvas,
          position,
          particle.angle,
          particle.sparkLength,
          paint,
        );
      } else if (i % 5 == 0) {
        _drawStar(
          canvas,
          position,
          particle.size + 2.0,
          paint,
        );
      } else {
        canvas.drawCircle(
          position,
          particle.size * (0.7 + 0.3 * fade),
          paint,
        );
      }
    }
  }

  void _drawSpark(
    Canvas canvas,
    Offset center,
    double angle,
    double length,
    Paint paint,
  ) {
    final direction = Offset(
      math.cos(angle),
      math.sin(angle),
    );

    final start = center - direction * (length * 0.35);
    final end = center + direction * (length * 0.65);

    final linePaint = Paint()
      ..color = paint.color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(start, end, linePaint);
  }

  void _drawStar(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint,
  ) {
    final path = Path();

    for (var i = 0; i < 8; i++) {
      final angle = (math.pi / 4) * i - math.pi / 2;
      final currentRadius = i.isEven ? radius : radius * 0.34;

      final point = Offset(
        center.dx + math.cos(angle) * currentRadius,
        center.dy + math.sin(angle) * currentRadius,
      );

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
    covariant _CelebrationParticlePainter oldDelegate,
  ) {
    return oldDelegate.progress != progress ||
        oldDelegate.accentColor != accentColor;
  }
}
