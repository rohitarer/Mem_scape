import 'dart:ui';
import 'package:flutter/material.dart';

class BlurGuard extends StatelessWidget {
  final bool enabled;
  final Widget child;
  final double sigma;

  const BlurGuard({
    super.key,
    required this.enabled,
    required this.child,
    this.sigma = 6,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            ignoring: true,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: Container(color: Colors.black12),
            ),
          ),
        ),
      ],
    );
  }
}
