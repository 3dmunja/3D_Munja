import 'package:flutter/material.dart';

import '../core/theme/munja_colors.dart';
import '../models/user_profile.dart';
import '../main.dart';

class AvatarMiniCard extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback onTap;

  const AvatarMiniCard({super.key, required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final avatar = avatarById(profile.avatarIndex);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MunjaColors.panelSoft,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [MunjaColors.mintStrong, MunjaColors.blueGlow],
                ),
              ),
              child: Text(avatar.emoji, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.firstLine,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${profile.secondLine} · ${avatar.label}',
                    style: const TextStyle(color: MunjaColors.textSoft),
                  ),
                ],
              ),
            ),
            const Icon(Icons.tune_rounded),
          ],
        ),
      ),
    );
  }
}
