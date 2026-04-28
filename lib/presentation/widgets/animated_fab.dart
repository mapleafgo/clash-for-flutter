import 'package:flutter/material.dart';

class AnimatedFab extends StatelessWidget {
  final bool visible;
  final Widget child;

  const AnimatedFab({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, 2),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: child,
      ),
    );
  }
}
