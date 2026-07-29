import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class ChallengeScreen extends StatelessWidget {
  const ChallengeScreen({super.key});

  static const double weeklyGoalKm = 100;
  static const double weeklyCurrentKm = 25;
  static const double monthlyGoalKm = 400;
  static const double monthlyCurrentKm = 148;
  static const double milestoneGoalKm = 500;
  static const double milestoneCurrentKm = 320;

  static const double bottomWheelSafePadding = 360;

  String t(String key) => AppText.t(key);

  @override
  Widget build(BuildContext context) {
    final weeklyProgress = (weeklyCurrentKm / weeklyGoalKm).clamp(0.0, 1.0);
    final monthlyProgress = (monthlyCurrentKm / monthlyGoalKm).clamp(0.0, 1.0);
    final milestoneProgress = (milestoneCurrentKm / milestoneGoalKm).clamp(
      0.0,
      1.0,
    );

    return Scaffold(
      backgroundColor: MunjaColors.bg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            20,
            20,
            20,
            bottomWheelSafePadding,
          ),
          children: [
            _Header(title: t('goals'), subtitle: t('goalsSubtitle')),

            const SizedBox(height: 18),

            _MainGoalCard(
              title: t('thisWeek'),
              focusLabel: t('weeklyFocus'),
              remainingLabel: t('kmLeftThisWeek'),
              current: weeklyCurrentKm,
              goal: weeklyGoalKm,
              progress: weeklyProgress,
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _PremiumStatCard(
                    icon: Icons.local_fire_department_rounded,
                    title: t('streak'),
                    value: '9',
                    subtitle: t('activeDays'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PremiumStatCard(
                    icon: Icons.flag_rounded,
                    title: t('rides'),
                    value: '67',
                    subtitle: t('total'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: t('nextMilestone'),
              subtitle: t('nextMilestoneSubtitle'),
              child: _MilestoneTile(
                icon: Icons.emoji_events_rounded,
                title: '500 km ${t('total')}',
                subtitle:
                    '${milestoneCurrentKm.toStringAsFixed(0)} / ${milestoneGoalKm.toStringAsFixed(0)} km ${t('completed')}',
                progress: milestoneProgress,
              ),
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: t('monthlyGoal'),
              subtitle: t('monthlyGoalSubtitle'),
              child: Column(
                children: [
                  _ProgressTile(
                    icon: Icons.calendar_month_rounded,
                    title: '400 km ${t('thisMonth')}',
                    subtitle:
                        '${monthlyCurrentKm.toStringAsFixed(0)} km ${t('completed')}',
                    progress: monthlyProgress,
                  ),
                  const SizedBox(height: 12),
                  _SmartTipTile(
                    icon: Icons.auto_awesome_rounded,
                    title: t('munjaSuggestion'),
                    subtitle: t('goalAiSuggestion'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: t('personalRecords'),
              subtitle: t('personalRecordsSubtitle'),
              child: Column(
                children: [
                  _RecordTile(
                    icon: Icons.route_rounded,
                    title: t('longestRide'),
                    value: '42.8 km',
                  ),
                  const SizedBox(height: 10),
                  _RecordTile(
                    icon: Icons.speed_rounded,
                    title: t('topSpeed'),
                    value: '38.4 km/t',
                  ),
                  const SizedBox(height: 10),
                  _RecordTile(
                    icon: Icons.timeline_rounded,
                    title: t('bestWeek'),
                    value: '84 km',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            _SectionCard(
              title: t('activeGoals'),
              subtitle: t('activeGoalsSubtitle'),
              child: Column(
                children: [
                  _GoalTile(
                    icon: Icons.work_outline_rounded,
                    title: t('bikeToWork'),
                    subtitle: t('threeTimesThisWeek'),
                    status: '2 / 3',
                  ),
                  const SizedBox(height: 10),
                  _GoalTile(
                    icon: Icons.local_fire_department_rounded,
                    title: t('keepStreak'),
                    subtitle: t('rideOnceToday'),
                    status: 'LIVE',
                  ),
                  const SizedBox(height: 10),
                  _GoalTile(
                    icon: Icons.bolt_rounded,
                    title: t('nextLevel'),
                    subtitle: t('collectMoreXp'),
                    status: '+250 XP',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;

  const _Header({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'MUNJA GOALS',
          style: TextStyle(
            color: MunjaColors.mint,
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 42,
            height: 1,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 9),
        Text(
          subtitle,
          style: const TextStyle(
            color: MunjaColors.textSoft,
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MainGoalCard extends StatelessWidget {
  final String title;
  final String focusLabel;
  final String remainingLabel;
  final double current;
  final double goal;
  final double progress;

  const _MainGoalCard({
    required this.title,
    required this.focusLabel,
    required this.remainingLabel,
    required this.current,
    required this.goal,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).round();
    final remainingKm = (goal - current).clamp(0, goal).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: _premiumDecoration(glow: true),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      focusLabel,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              _RingProgress(progress: progress, label: '$percent%'),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                current.toStringAsFixed(0),
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 54,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  '/ ${goal.toStringAsFixed(0)} km',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(MunjaColors.mint),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                color: MunjaColors.mint,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$remainingKm km $remainingLabel',
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingProgress extends StatelessWidget {
  final double progress;
  final String label;

  const _RingProgress({required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 86,
      child: CustomPaint(
        painter: _RingPainter(progress: progress),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;

  const _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 8.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width - stroke) / 2;

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withOpacity(0.08);

    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = MunjaColors.mint;

    canvas.drawCircle(center, radius, basePaint);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress.clamp(0.0, 1.0),
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _PremiumStatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  const _PremiumStatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 136,
      padding: const EdgeInsets.all(18),
      decoration: _premiumDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MunjaColors.mint, size: 24),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  height: 0.95,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  subtitle,
                  style: const TextStyle(
                    color: MunjaColors.mint,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _premiumDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            style: const TextStyle(
              color: MunjaColors.textSoft,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double progress;

  const _MilestoneTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return _ProgressTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      progress: progress,
      highlighted: true,
    );
  }
}

class _ProgressTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double progress;
  final bool highlighted;

  const _ProgressTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.progress,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlighted
            ? MunjaColors.mint.withOpacity(0.11)
            : Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted
              ? MunjaColors.mint.withOpacity(0.38)
              : Colors.white.withOpacity(0.07),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: MunjaColors.mint.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: MunjaColors.mint),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MunjaColors.textSoft,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(MunjaColors.mint),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmartTipTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SmartTipTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MunjaColors.mint.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MunjaColors.mint.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: MunjaColors.mint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _RecordTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: MunjaColors.mint),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;

  const _GoalTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.15),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.13),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: MunjaColors.mint),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MunjaColors.textSoft,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: MunjaColors.mint.withOpacity(0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: MunjaColors.mint.withOpacity(0.26)),
            ),
            child: Text(
              status,
              style: const TextStyle(
                color: MunjaColors.mint,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _premiumDecoration({bool glow = false}) {
  return BoxDecoration(
    color: MunjaColors.panel.withOpacity(0.86),
    borderRadius: BorderRadius.circular(32),
    border: Border.all(color: Colors.white.withOpacity(0.075)),
    boxShadow: glow
        ? [
            BoxShadow(
              color: MunjaColors.mint.withOpacity(0.16),
              blurRadius: 44,
              spreadRadius: 2,
              offset: const Offset(0, 18),
            ),
          ]
        : null,
  );
}
