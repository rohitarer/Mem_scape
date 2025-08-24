import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:memscape/models/photo_model.dart';

class ProfileGallery extends StatelessWidget {
  final List<PhotoModel> photos;
  const ProfileGallery({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (photos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text("No public memories yet."),
      );
    }
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text("📸 Public Memories", style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 12),
        ...photos.map((photo) => _photoCard(context, photo)),
      ],
    );
  }

  Widget _photoCard(BuildContext context, PhotoModel photo) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photo.imagePath != null)
            FutureBuilder<DatabaseEvent>(
              future: FirebaseDatabase.instance.ref(photo.imagePath!).once(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data!.snapshot.value == null) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: Text("⚠️ Image unavailable")),
                  );
                }
                final base64 = snapshot.data!.snapshot.value as String;
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Image.memory(
                    base64Decode(base64),
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(photo.caption, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text("📍 ${photo.location}", style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  "🗓️ ${photo.timestamp.toLocal().toString().split('.')[0]}",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
