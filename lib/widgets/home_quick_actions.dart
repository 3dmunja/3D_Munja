import 'package:flutter/material.dart';

class HomeQuickActions extends StatelessWidget {
  const HomeQuickActions({
    super.key,
    required this.onSmartRoutes,
    required this.onAiCoach,
    required this.onAnalytics,
    required this.onProducts,
  });

  final VoidCallback onSmartRoutes;
  final VoidCallback onAiCoach;
  final VoidCallback onAnalytics;
  final VoidCallback onProducts;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.85,
      children: [
        _QuickActionTile(
          icon: Icons.route_rounded,
          title: 'Smart Routes',
          onTap: onSmartRoutes,
        ),
        _QuickActionTile(
          icon: Icons.psychology_rounded,
          title: 'AI Coach',
          onTap: onAiCoach,
        ),
        _QuickActionTile(
          icon: Icons.insights_rounded,
          title: 'Analytics',
          onTap: onAnalytics,
        ),
        _QuickActionTile(
          icon: Icons.inventory_2_rounded,
          title: 'Products',
          onTap: onProducts,
        ),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.white.withOpacity(0.045),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 23, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
