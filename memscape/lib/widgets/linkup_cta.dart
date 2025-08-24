import 'package:flutter/material.dart';

class LinkUpCta extends StatelessWidget {
  final bool isPending;
  final bool iRequested;
  final bool theyRequested;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const LinkUpCta({
    super.key,
    required this.isPending,
    required this.iRequested,
    required this.theyRequested,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget primary;
    Widget? secondary;

    if (!isPending && !theyRequested) {
      primary = FilledButton.icon(
        icon: const Icon(Icons.all_inclusive),
        onPressed: onSend,
        label: const Text("Link Up to Unveil"),
      );
      secondary = Text(
        "Profile is blurred until they link up with you.",
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall,
      );
    } else if (iRequested) {
      primary = FilledButton.icon(
        icon: const Icon(Icons.hourglass_top),
        onPressed: null,
        label: const Text("Pending link‑up…"),
      );
      secondary = TextButton(onPressed: onCancel, child: const Text("Cancel"));
    } else if (theyRequested) {
      primary = FilledButton.icon(
        icon: const Icon(Icons.handshake),
        onPressed: onAccept,
        label: const Text("Accept & Unveil"),
      );
      secondary = TextButton(onPressed: onIgnore, child: const Text("Ignore"));
    } else {
      primary = FilledButton.icon(
        icon: const Icon(Icons.hourglass_top),
        onPressed: null,
        label: const Text("Pending link‑up…"),
      );
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Unveil full profile",
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            primary,
            if (secondary != null) ...[
              const SizedBox(height: 6),
              Center(child: secondary),
            ],
          ],
        ),
      ),
    );
  }
}
