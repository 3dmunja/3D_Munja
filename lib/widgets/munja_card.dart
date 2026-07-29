import 'package:flutter/material.dart';
import '../core/theme/munja_colors.dart';

class MunjaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const MunjaCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.045),
            Colors.white.withOpacity(0.015),
          ],
        ),
        color: MunjaColors.panel,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}
