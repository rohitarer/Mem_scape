import 'package:flutter/material.dart';

class LensChipData {
  final String name;
  final ImageProvider? thumb; // optional thumbnail
  const LensChipData({required this.name, this.thumb});
}

class SnapBottomBar extends StatefulWidget {
  final List<LensChipData> items;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;

  // Buttons in the row
  final VoidCallback onCapture; // shutter
  final VoidCallback? onMemories; // left button (optional)
  final VoidCallback? onFlip; // right button (optional)
  final bool isRecording; // draw red ring if recording
  final bool isVideoMode; // change shutter ring color if needed

  // Layout
  final double height;
  final double shutterSize; // diameter of the shutter “hole” in the rail
  final double chipSize; // lens chip diameter
  final double spacing; // spacing between chips

  const SnapBottomBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onCapture,
    this.onMemories,
    this.onFlip,
    this.isRecording = false,
    this.isVideoMode = false,
    this.height = 110,
    this.shutterSize = 84,
    this.chipSize = 56,
    this.spacing = 14,
  });

  @override
  State<SnapBottomBar> createState() => _SnapBottomBarState();
}

class _SnapBottomBarState extends State<SnapBottomBar> {
  late final ScrollController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = ScrollController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  EdgeInsets get _railPadding {
    // leave a “hole” in the center for the shutter
    final halfHole = (widget.shutterSize * 0.5) + 24;
    return EdgeInsets.symmetric(horizontal: 16 + halfHole);
  }

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black.withOpacity(0.28);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Lens rail behind
            Align(
              alignment: Alignment.center,
              child: Container(
                height: widget.chipSize + 20,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: ListView.separated(
                  controller: _ctrl,
                  padding: _railPadding,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
                  itemBuilder: (context, i) {
                    final it = widget.items[i];
                    final selected = i == widget.selectedIndex;
                    return GestureDetector(
                      onTap: () => widget.onIndexChanged(i),
                      child: _LensChip(
                        label: it.name,
                        image: it.thumb,
                        size: widget.chipSize,
                        selected: selected,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Left: Memories
            Positioned(
              left: 16,
              child: _SmallPillButton(
                icon: Icons.photo_library_rounded,
                label: 'Memories',
                onTap: widget.onMemories,
              ),
            ),

            // Right: Flip camera
            Positioned(
              right: 16,
              child: _RoundButton(
                icon: Icons.cameraswitch_rounded,
                onTap: widget.onFlip,
              ),
            ),

            // Center: Shutter (on top, same line)
            GestureDetector(
              onTap: widget.onCapture,
              child: Container(
                width: widget.shutterSize,
                height: widget.shutterSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        widget.isVideoMode
                            ? (widget.isRecording ? Colors.red : Colors.white)
                            : Colors.white,
                    width: 6,
                  ),
                  color: Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  final String label;
  final ImageProvider? image;
  final double size;
  final bool selected;

  const _LensChip({
    required this.label,
    required this.image,
    required this.size,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        selected
            ? Border.all(color: Colors.white, width: 3)
            : Border.all(color: Colors.white24, width: 1.5);

    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        image:
            image != null
                ? DecorationImage(image: image!, fit: BoxFit.cover)
                : null,
        color: image == null ? Colors.white10 : null,
      ),
      alignment: Alignment.center,
      child:
          image == null
              ? Text(
                label.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              )
              : null,
    );

    return inner;
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _SmallPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SmallPillButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
