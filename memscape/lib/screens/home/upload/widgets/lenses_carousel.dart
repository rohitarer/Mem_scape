// lib/screens/home/upload/widgets/lenses_carousel.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Minimal lens model the carousel needs.
/// If you already have a LensFilter type elsewhere, you can:
///  - keep this class and map your LensFilter -> LensChipData, or
///  - replace LensChipData with your existing LensFilter.
class LensChipData {
  final String name;     // shown under the chip
  final ImageProvider? thumb; // optional thumbnail
  const LensChipData({required this.name, this.thumb});
}

/// Snapchat-like bottom lens carousel:
/// - horizontally scrollable
/// - center snapping
/// - the centered item is "selected" (scaled up, label bold)
/// - emits onIndexChanged when the center lens changes
class LensesCarousel extends StatefulWidget {
  final List<LensChipData> items;
  final int initialIndex;
  final ValueChanged<int> onIndexChanged;

  /// Distance from the bottom (to sit above the shutter).
  final double bottomPadding;

  /// Visual sizes
  final double itemSize;        // diameter of chip
  final double itemScale;       // max scale for centered item (e.g. 1.2)
  final double spacing;         // space between chips

  const LensesCarousel({
    super.key,
    required this.items,
    required this.onIndexChanged,
    this.initialIndex = 0,
    this.bottomPadding = 128,
    this.itemSize = 56,
    this.itemScale = 1.22,
    this.spacing = 14,
  });

  @override
  State<LensesCarousel> createState() => _LensesCarouselState();
}

class _LensesCarouselState extends State<LensesCarousel> {
  late final PageController _pc;
  double _page = 0.0;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pc = PageController(
      viewportFraction: _viewportFractionFor(widget.itemSize, widget.spacing),
      initialPage: widget.initialIndex,
    )..addListener(_onScroll);
    _current = widget.initialIndex;
    _page = widget.initialIndex.toDouble();
  }

  @override
  void dispose() {
    _pc.removeListener(_onScroll);
    _pc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted) return;
    setState(() => _page = _pc.page ?? _page);

    // Snap the selected index
    final idx = (_pc.page ?? _current.toDouble()).round().clamp(0, widget.items.length - 1);
    if (idx != _current) {
      _current = idx;
      widget.onIndexChanged(idx);
      // subtle haptic
      Feedback.forTap(context);
    }
  }

  // Viewport fraction so a chip sits centered nicely with spacing on both sides.
  double _viewportFractionFor(double itemSize, double spacing) {
    // viewportFraction is ratio of page to viewport.
    // We'll approximate: item takes itemSize, we leave spacing as negative itemBuilder padding.
    // 0.25..0.45 feels good visually; we compute later with layout width.
    return 0.28; // good default
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: widget.bottomPadding,
      child: IgnorePointer(
        ignoring: false,
        child: SizedBox(
          height: widget.itemSize + 36, // chip + label
          child: PageView.builder(
            controller: _pc,
            itemCount: widget.items.length,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, i) {
              final t = (i - _page).abs().clamp(0.0, 1.0);
              final scale = lerpDouble(widget.itemScale, 1.0, t)!;
              final opacity = lerpDouble(1.0, 0.6, t)!;

              final item = widget.items[i];

              return Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: opacity,
                  child: Transform.scale(
                    scale: scale,
                    child: _LensChip(
                      label: item.name,
                      thumb: item.thumb,
                      size: widget.itemSize,
                      selected: i == _current,
                      onTap: () => _pc.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  final String label;
  final ImageProvider? thumb;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  const _LensChip({
    required this.label,
    required this.thumb,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? Colors.white : Colors.white.withOpacity(0.85);
    final fg = selected ? Colors.black : Colors.black87;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(selected ? 0.20 : 0.08),
                  blurRadius: selected ? 12 : 6,
                  offset: const Offset(0, 4),
                ),
              ],
              image: thumb != null
                  ? DecorationImage(image: thumb!, fit: BoxFit.cover)
                  : null,
            ),
            child: thumb == null
                ? Center(
                    child: Icon(
                      Icons.auto_awesome, // fallback glyph
                      size: size * 0.42,
                      color: fg,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: math.max(size, 68),
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12,
              height: 1.0,
              color: Colors.white.withOpacity(selected ? 1 : 0.85),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
              shadows: const [
                Shadow(blurRadius: 3, color: Colors.black54, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Simple linear interpolate for doubles.
double? lerpDouble(double a, double b, double t) => a + (b - a) * t;
