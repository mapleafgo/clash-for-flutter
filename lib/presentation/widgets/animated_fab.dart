import 'package:flutter/material.dart';

class AnimatedFab extends StatelessWidget {
  final bool visible;
  final Widget child;

  const AnimatedFab({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: child,
        ),
      ),
    );
  }
}

/// Wraps a child with a cat-head-shake animation.
/// Call [controller.forward(from: 0)] to trigger.
class ShakeBuilder extends StatefulWidget {
  final AnimationController controller;
  final Widget child;

  const ShakeBuilder({
    super.key,
    required this.controller,
    required this.child,
  });

  @override
  State<ShakeBuilder> createState() => _ShakeBuilderState();
}

class _ShakeBuilderState extends State<ShakeBuilder> {
  late final Animation<double> _animation;

  static Animation<double> _createAnimation(AnimationController controller) {
    return TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: 0.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.2, end: -0.18)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1.5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.18, end: 0.12)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1.5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.12, end: -0.07)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1.5,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -0.07, end: 0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
    ]).animate(controller);
  }

  @override
  void initState() {
    super.initState();
    _animation = _createAnimation(widget.controller);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.rotate(angle: _animation.value, child: child);
      },
      child: widget.child,
    );
  }
}

/// Animated icon switch with rotation and scale spring transition.
class AnimatedIconSwitcher extends StatelessWidget {
  final bool value;
  final IconData onIcon;
  final IconData offIcon;

  const AnimatedIconSwitcher({
    super.key,
    required this.value,
    this.onIcon = Icons.flight_land,
    this.offIcon = Icons.flight_takeoff,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.5, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      ),
      child: Icon(
        value ? onIcon : offIcon,
        key: ValueKey(value),
      ),
    );
  }
}
