import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/localization/app_text.dart';
import '../core/theme/munja_colors.dart';

class WheelNavbar extends StatefulWidget {
  final int selectedIndex;
  final bool isRiding;
  final double liveSpeedKmh;
  final Function(int) onChanged;

  const WheelNavbar({
    super.key,
    required this.selectedIndex,
    required this.onChanged,
    this.isRiding = false,
    this.liveSpeedKmh = 0,
  });

  @override
  State<WheelNavbar> createState() => _WheelNavbarState();
}

class _WheelNavbarState extends State<WheelNavbar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wheelCtrl;

  bool menuOpen = false;
  int hoverIndex = 2;

  late final List<_WheelItem> items = [
    _WheelItem(icon: Icons.home_rounded, label: AppText.t('home')),
    _WheelItem(icon: Icons.route_rounded, label: AppText.t('routes')),
    _WheelItem(icon: Icons.shopping_bag_rounded, label: AppText.t('products')),
    _WheelItem(icon: Icons.psychology_rounded, label: AppText.t('coach')),
    _WheelItem(icon: Icons.insights_rounded, label: AppText.t('analytics')),
    _WheelItem(icon: Icons.memory_rounded, label: AppText.t('hardware')),
    _WheelItem(icon: Icons.settings_rounded, label: AppText.t('profile')),
    _WheelItem(icon: Icons.history_rounded, label: AppText.t('recentRides')),
  ];

  @override
  void initState() {
    super.initState();

    _wheelCtrl = AnimationController(
      vsync: this,
      duration: _speedDuration(widget.liveSpeedKmh),
    );

    if (widget.isRiding) {
      _wheelCtrl.repeat();
    }
  }

  Duration _speedDuration(double speedKmh) {
    if (!widget.isRiding || speedKmh <= 1) {
      return const Duration(milliseconds: 950);
    }

    final clampedSpeed = speedKmh.clamp(1, 45);
    final durationMs = 950 - (clampedSpeed * 14);

    return Duration(milliseconds: durationMs.clamp(280, 950).round());
  }

  @override
  void didUpdateWidget(covariant WheelNavbar oldWidget) {
    super.didUpdateWidget(oldWidget);

    _wheelCtrl.duration = _speedDuration(widget.liveSpeedKmh);

    if (widget.isRiding && !_wheelCtrl.isAnimating) {
      _wheelCtrl.repeat();
    }

    if (!widget.isRiding && _wheelCtrl.isAnimating) {
      _wheelCtrl.stop();
    }
  }

  @override
  void dispose() {
    _wheelCtrl.dispose();
    super.dispose();
  }

  void _openMenu() {
    setState(() {
      menuOpen = true;
      hoverIndex = widget.selectedIndex.clamp(0, items.length - 1);
    });
  }

  void _closeMenu({bool select = false}) {
    if (select) {
      widget.onChanged(hoverIndex);
    }

    setState(() {
      menuOpen = false;
    });
  }

  void _updateHover(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;

    final angle = math.atan2(dy, dx);
    final normalized = (angle + math.pi * 2 + math.pi / 2) % (math.pi * 2);

    final section = (normalized / (math.pi * 2 / items.length)).floor();

    setState(() {
      hoverIndex = section.clamp(0, items.length - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: menuOpen ? 320 : 126,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, menuOpen ? 320 : 126);

          return GestureDetector(
            onLongPressStart: (_) => _openMenu(),
            onLongPressMoveUpdate: (details) {
              _updateHover(details.localPosition, size);
            },
            onLongPressEnd: (_) => _closeMenu(select: true),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                if (menuOpen)
                  Positioned(
                    bottom: 10,
                    child: _RadialMenu(items: items, selectedIndex: hoverIndex),
                  ),

                Positioned(
                  bottom: 18,
                  child: _WheelCore(
                    controller: _wheelCtrl,
                    isRiding: widget.isRiding,
                    speed: widget.liveSpeedKmh,
                    menuOpen: menuOpen,
                  ),
                ),

                if (!menuOpen)
                  Positioned(
                    bottom: 0,
                    child: Text(
                      AppText.t('holdWheelMenu'),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WheelCore extends StatelessWidget {
  final AnimationController controller;
  final bool isRiding;
  final double speed;
  final bool menuOpen;

  const _WheelCore({
    required this.controller,
    required this.isRiding,
    required this.speed,
    required this.menuOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: menuOpen ? 138 : 108,
          height: menuOpen ? 138 : 108,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: MunjaColors.mint.withOpacity(
                  isRiding || menuOpen ? 0.50 : 0.22,
                ),
                blurRadius: isRiding || menuOpen ? 42 : 22,
                spreadRadius: isRiding || menuOpen ? 8 : 2,
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              return Transform.rotate(
                angle: controller.value * math.pi * 2,
                child: child,
              );
            },
            child: Image.asset(
              'assets/Bicycle_Tires_1.png',
              fit: BoxFit.contain,
            ),
          ),
        ),

        if (isRiding && !menuOpen)
          Positioned(
            top: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.50),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: MunjaColors.mint.withOpacity(0.35)),
              ),
              child: Text(
                '${speed.toStringAsFixed(1)} km/h',
                style: const TextStyle(
                  color: MunjaColors.mint,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RadialMenu extends StatelessWidget {
  final List<_WheelItem> items;
  final int selectedIndex;

  const _RadialMenu({required this.items, required this.selectedIndex});

  @override
  Widget build(BuildContext context) {
    const radius = 116.0;

    return SizedBox(
      width: 310,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 292,
            height: 252,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MunjaColors.panel.withOpacity(0.72),
              boxShadow: [
                BoxShadow(
                  color: MunjaColors.mint.withOpacity(0.25),
                  blurRadius: 42,
                  spreadRadius: 4,
                ),
              ],
            ),
          ),

          ...List.generate(items.length, (index) {
            final item = items[index];
            final active = index == selectedIndex;

            final angle = -math.pi / 2 + (math.pi * 2 / items.length) * index;

            final x = math.cos(angle) * radius;
            final y = math.sin(angle) * radius;

            return Transform.translate(
              offset: Offset(x, y),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: active ? 92 : 78,
                height: active ? 72 : 64,
                decoration: BoxDecoration(
                  color: active
                      ? MunjaColors.mint.withOpacity(0.18)
                      : Colors.white.withOpacity(0.035),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: active
                        ? MunjaColors.mint.withOpacity(0.55)
                        : Colors.white.withOpacity(0.06),
                  ),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: MunjaColors.mint.withOpacity(0.34),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      item.icon,
                      color: active ? MunjaColors.mint : Colors.white70,
                      size: active ? 26 : 22,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : Colors.white60,
                        fontSize: active ? 11 : 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          Positioned(
            bottom: 16,
            child: Row(
              children: [
                Icon(
                  Icons.touch_app_rounded,
                  color: Colors.white.withOpacity(0.65),
                  size: 17,
                ),
                const SizedBox(width: 6),
                Text(
                  AppText.t('releaseToOpen'),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.65),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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

class _WheelItem {
  final IconData icon;
  final String label;

  const _WheelItem({required this.icon, required this.label});
}
