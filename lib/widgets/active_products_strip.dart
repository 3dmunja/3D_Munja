import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';

class ActiveProductsStrip extends StatelessWidget {
  final bool hasBrakeLight;
  final bool scanning;
  final int batteryPercent;
  final VoidCallback onRefresh;
  final VoidCallback onOpenProducts;

  const ActiveProductsStrip({
    super.key,
    required this.hasBrakeLight,
    required this.scanning,
    required this.batteryPercent,
    required this.onRefresh,
    required this.onOpenProducts,
  });

  @override
  Widget build(BuildContext context) {
    final battery = batteryPercent.clamp(0, 100);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: hasBrakeLight
                  ? MunjaColors.mint.withOpacity(0.12)
                  : Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              hasBrakeLight
                  ? Icons.bluetooth_connected_rounded
                  : Icons.bluetooth_disabled_rounded,
              color: hasBrakeLight ? MunjaColors.mint : Colors.white54,
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasBrakeLight
                      ? 'Brake Light Connected'
                      : 'No active products',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: hasBrakeLight ? MunjaColors.mint : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),

                    const SizedBox(width: 6),

                    Text(
                      hasBrakeLight
                          ? '$battery% battery'
                          : 'Tap to add product',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          GestureDetector(
            onTap: scanning ? null : onRefresh,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: scanning
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
            ),
          ),

          const SizedBox(width: 8),

          GestureDetector(
            onTap: onOpenProducts,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: MunjaColors.mint.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.memory_rounded,
                color: MunjaColors.mint,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
