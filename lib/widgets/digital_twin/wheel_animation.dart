import 'package:flutter/material.dart';

class WheelAnimation extends StatefulWidget {
  final bool isLive;
  final Widget child;

  const WheelAnimation({super.key, required this.isLive, required this.child});

  @override
  State<WheelAnimation> createState() => _WheelAnimationState();
}

class _WheelAnimationState extends State<WheelAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    if (widget.isLive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WheelAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isLive && !_controller.isAnimating) {
      _controller.repeat();
    }

    if (!widget.isLive && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get rotation => _controller.value;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return widget.child;
      },
    );
  }
}
