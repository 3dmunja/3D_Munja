import 'package:flutter/material.dart';

class BikeGlow extends StatefulWidget {
  final bool isLive;
  final bool isBraking;
  final bool isConnected;
  final Widget child;

  const BikeGlow({
    super.key,
    required this.isLive,
    required this.isBraking,
    required this.isConnected,
    required this.child,
  });

  @override
  State<BikeGlow> createState() => _BikeGlowState();
}

class _BikeGlowState extends State<BikeGlow>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get glowColor {
    if (widget.isBraking) {
      return const Color(0xFFFF3B30);
    }

    if (widget.isConnected) {
      return const Color(0xFF42F5B0);
    }

    return const Color(0xFF2BCF92);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final pulse = widget.isLive
            ? (0.75 + (_controller.value * 0.45))
            : 0.65;

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 420 * pulse,
              height: 220 * pulse,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: glowColor.withOpacity(0.22),
                    blurRadius: 90 * pulse,
                    spreadRadius: 18 * pulse,
                  ),
                ],
              ),
            ),

            widget.child,
          ],
        );
      },
    );
  }
}
