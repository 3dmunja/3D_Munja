import 'package:flutter/material.dart';
import '../core/theme/munja_colors.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),

              if (subtitle != null) ...[
                const SizedBox(height: 6),

                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),

        if (trailing != null) trailing!,
      ],
    );
  }
}
