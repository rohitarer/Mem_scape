import 'dart:convert';
import 'package:flutter/material.dart';

class ProfileHeader extends StatelessWidget {
  final String? profileBase64;
  final String name;
  final String bio;
  final int vibeCount;
  final String mutualsLabel; // show "—" for now or real number later

  const ProfileHeader({
    super.key,
    required this.profileBase64,
    required this.name,
    required this.bio,
    required this.vibeCount,
    this.mutualsLabel = '—',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider =
        (profileBase64 != null)
            ? MemoryImage(base64Decode(profileBase64!))
            : const NetworkImage(
              "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
            );

    return Column(
      children: [
        CircleAvatar(radius: 60, backgroundImage: provider as ImageProvider),
        const SizedBox(height: 12),
        Text(
          name.isEmpty ? "Wanderer" : name,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          bio.isEmpty ? "No bio yet. Just vibes ✨" : bio,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _pillStat(context, "Vibe Count", '$vibeCount'),
            const SizedBox(width: 8),
            _pillStat(context, "Mutuals", mutualsLabel),
          ],
        ),
      ],
    );
  }

  Widget _pillStat(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceVariant,
      ),
      child: Row(
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}
