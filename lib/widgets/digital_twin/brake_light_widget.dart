import 'package:flutter/material.dart';

class BrakeLightWidget extends StatelessWidget {
  final bool connected;
  final bool braking;
  final double batteryLevel;
  final VoidCallback? onTap;

  const BrakeLightWidget({
    super.key,
    required this.connected,
    required this.braking,
    required this.batteryLevel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glowColor = braking
        ? const Color(0xFFFF3B30)
        : const Color(0xFF42F5B0);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: 26,
        height: 52,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: connected
              ? glowColor.withOpacity(0.22)
              : Colors.grey.withOpacity(0.15),
          border: Border.all(
            color: connected ? glowColor : Colors.grey.shade700,
            width: 2,
          ),
          boxShadow: connected
              ? [
                  BoxShadow(
                    color: glowColor.withOpacity(braking ? 0.9 : 0.45),
                    blurRadius: braking ? 28 : 12,
                    spreadRadius: braking ? 6 : 2,
                  ),
                ]
              : [],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.15,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, glowColor],
                    ),
                  ),
                ),
              ),
            ),

            Icon(
              braking ? Icons.warning_rounded : Icons.light_mode_rounded,
              size: 14,
              color: connected ? glowColor : Colors.grey,
            ),

            Positioned(
              bottom: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${batteryLevel.round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
