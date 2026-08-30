import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';

class MunjaBackground extends StatelessWidget {
  final Widget child;
  final double logoOpacity;
  final double logoWidthFactor;
  final Alignment logoAlignment;
  final bool showGlow;

  const MunjaBackground({
    super.key,
    required this.child,
    this.logoOpacity = 0.07,
    this.logoWidthFactor = 0.72,
    this.logoAlignment = Alignment.center,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final logoWidth = screenWidth * logoWidthFactor;

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF071C18),
            Color(0xFF04110F),
            Color(0xFF020A09),
          ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (showGlow)
            IgnorePointer(
              child: Align(
                alignment: const Alignment(0, -0.15),
                child: Container(
                  width: screenWidth * 0.90,
                  height: screenWidth * 0.90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        MunjaColors.mint.withOpacity(0.10),
                        MunjaColors.mint.withOpacity(0.025),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.48, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          IgnorePointer(
            child: Align(
              alignment: logoAlignment,
              child: Opacity(
                opacity: logoOpacity.clamp(0.0, 1.0),
                child: Image.asset(
                  'assets/munja-logo-icon.png',
                  width: logoWidth,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
