import 'package:flutter/material.dart';

/// Where on the face to anchor an overlay.
enum FaceAnchor { aboveHead, overEyes, onNose, overMouth, cheeks }

/// One overlay layer (PNG) with how to place it.
class OverlaySpec {
  final String assetPath;
  final FaceAnchor anchor;
  final double scale; // relative to face width (1.0 == face width)
  final Offset offset; // fine‑tune in logical px after scaling
  const OverlaySpec({
    required this.assetPath,
    required this.anchor,
    this.scale = 1.0,
    this.offset = Offset.zero,
  });
}

/// A lens: optional color matrix + zero or more AR overlays.
class LensFilter {
  final String name;
  final List<double>? matrix; // null = no color filter
  final List<OverlaySpec> overlays; // empty = no AR overlays
  const LensFilter({required this.name, this.matrix, this.overlays = const []});
}
