import 'package:flutter/material.dart';

/// Public filter preset model with a 4x5 color matrix (20 values).
class FilterPreset {
  final String name; // what we show in the UI ("Golden Hour", etc.)
  final List<double> matrix; // 4x5 color matrix
  const FilterPreset(this.name, this.matrix);
}

/// Some helper matrices (contrast/saturation) combined into “Gen‑Z” vibes.
/// These are lightweight—good for realtime preview & baking to photos.
class FilterPresets {
  // Identity
  static const List<double> original = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  // Classic mono
  static const List<double> mono = [
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Sepia
  static const List<double> sepia = [
    0.393,
    0.769,
    0.189,
    0,
    0,
    0.349,
    0.686,
    0.168,
    0,
    0,
    0.272,
    0.534,
    0.131,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Slight filmic contrast
  static const List<double> film = [
    1.20,
    -0.05,
    -0.05,
    0,
    0,
    -0.05,
    1.10,
    -0.05,
    0,
    0,
    -0.05,
    -0.05,
    1.10,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Cool blue shift
  static const List<double> cool = [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1.15, 0, 10, // bump blue & add little offset
    0, 0, 0, 1, 0,
  ];

  // Warm golden shift
  static const List<double> warm = [
    1.15, 0, 0, 0, 10, // bump red & offset
    0, 1.05, 0, 0, 0,
    0, 0, 0.95, 0, -10,
    0, 0, 0, 1, 0,
  ];

  // Punchy neon (higher contrast + saturation-ish feel via matrix skew)
  static const List<double> neonPop = [
    1.3,
    -0.1,
    -0.1,
    0,
    0,
    -0.1,
    1.3,
    -0.1,
    0,
    0,
    -0.1,
    -0.1,
    1.3,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  // Pastel (lower contrast, gentle offsets)
  static const List<double> pastel = [
    0.9,
    0.05,
    0.05,
    0,
    10,
    0.05,
    0.9,
    0.05,
    0,
    10,
    0.05,
    0.05,
    0.9,
    0,
    10,
    0,
    0,
    0,
    1,
    0,
  ];

  // Grunge (muted + greenish shadows)
  static const List<double> grunge = [
    0.9,
    0.0,
    0.0,
    0,
    -10,
    0.05,
    0.85,
    0.05,
    0,
    0,
    0.0,
    0.0,
    0.9,
    0,
    -10,
    0,
    0,
    0,
    1,
    0,
  ];

  // VHS (faded + slight magenta)
  static const List<double> vhs = [
    1.05,
    0.02,
    0.08,
    0,
    10,
    0.0,
    0.95,
    0.02,
    0,
    0,
    0.02,
    0.0,
    0.95,
    0,
    -10,
    0,
    0,
    0,
    1,
    0,
  ];

  // High-contrast B&W (edgy)
  static const List<double> bwPunch = [
    0.6,
    0.6,
    0.6,
    0,
    0,
    0.6,
    0.6,
    0.6,
    0,
    0,
    0.6,
    0.6,
    0.6,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  /// Gen‑Z names mapped to matrices (order = swipe order)
  static const List<FilterPreset> swipeOrder = [
    FilterPreset("No Cap", original), // OG
    FilterPreset("Golden Hour", warm), // cozy warm
    FilterPreset("Icy Drip", cool), // cool blue
    FilterPreset("Retro Vibes", sepia), // vintage
    FilterPreset("VHS Tape", vhs), // 90s cam feel
    FilterPreset("Neon Pop", neonPop), // punchy colors
    FilterPreset("Pastel Dream", pastel), // soft pastel
    FilterPreset("Grunge Glow", grunge), // muted/gritty
    FilterPreset("Film Grain*", film), // subtle film grade (*no grain)
    FilterPreset("Moody AF", bwPunch), // strong B&W
  ];
}

/// Small pill style for filter name HUD
class FilterNamePill extends StatelessWidget {
  final String text;
  const FilterNamePill({super.key, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
