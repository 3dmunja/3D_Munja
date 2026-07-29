import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../models/home_ai_state.dart';

class HomeAIHero extends StatelessWidget {
  final HomeAIState state;
  final VoidCallback onPrimaryAction;
  final VoidCallback onSecondaryAction;
  final VoidCallback onOpenCoach;

  const HomeAIHero({
    super.key,
    required this.state,
    required this.onPrimaryAction,
    required this.onSecondaryAction,
    required this.onOpenCoach,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MunjaColors.panel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                state.mood.emoji,
                style: const TextStyle(fontSize: 26),
              ),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  state.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    _MiniChip(
                      icon: Icons.bolt_rounded,
                      label: '${state.readinessScore}%',
                    ),

                    const SizedBox(width: 8),

                    _MiniChip(
                      icon: Icons.battery_3_bar_rounded,
                      label: '${state.fatigueScore}%',
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          IconButton(
            onPressed: onOpenCoach,
            style: IconButton.styleFrom(
              backgroundColor: MunjaColors.mint.withOpacity(0.10),
            ),
            icon: const Icon(
              Icons.auto_awesome_rounded,
              color: MunjaColors.mint,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MunjaColors.mint),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
