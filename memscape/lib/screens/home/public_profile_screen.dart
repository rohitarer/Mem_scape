import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/services/firestore_service.dart';

class PublicProfileScreen extends StatefulWidget {
  final String uid;
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  String name = '';
  String bio = '';
  String? profileBase64;
  List<PhotoModel> userPhotos = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfileAndPhotos();
  }

  Future<void> _loadProfileAndPhotos() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.uid)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        name = data['name'] ?? '';
        bio = data['bio'] ?? '';
        final profilePath = data['profileImagePath'];
        if (profilePath != null) {
          final snap = await FirebaseDatabase.instance.ref(profilePath).get();
          if (snap.exists) {
            profileBase64 = snap.value as String;
          }
        }
      }

      userPhotos = await FirestoreService().fetchUserPhotos(userId: widget.uid);

      // Filter only public photos
      userPhotos = userPhotos.where((p) => p.isPublic).toList();
    } catch (e) {
      debugPrint("❌ Failed to load profile: $e");
    }

    if (mounted) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text("👤 Public Profile")),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundImage:
                          profileBase64 != null
                              ? MemoryImage(base64Decode(profileBase64!))
                              : const NetworkImage(
                                    "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                                  )
                                  as ImageProvider,
                    ),
                    const SizedBox(height: 12),
                    Text(name, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const Divider(height: 32),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "📸 Public Memories",
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (userPhotos.isEmpty)
                      const Text("No public photos available.")
                    else
                      ...userPhotos.map(
                        (photo) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (photo.imagePath != null)
                                FutureBuilder<DatabaseEvent>(
                                  future:
                                      FirebaseDatabase.instance
                                          .ref(photo.imagePath!)
                                          .once(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox(
                                        height: 200,
                                        child: Center(
                                          child: CircularProgressIndicator(),
                                        ),
                                      );
                                    }

                                    if (snapshot.hasError ||
                                        !snapshot.hasData ||
                                        snapshot.data!.snapshot.value == null) {
                                      return const SizedBox(
                                        height: 200,
                                        child: Center(
                                          child: Text("⚠️ Image unavailable"),
                                        ),
                                      );
                                    }

                                    final base64 =
                                        snapshot.data!.snapshot.value as String;

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
                                    Text(
                                      photo.caption,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "📍 ${photo.location}",
                                      style: theme.textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "🗓️ ${photo.timestamp.toLocal().toString().split('.')[0]}",
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.outline,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
    );
  }

  // @override
  // Widget build(BuildContext context) {
  //   final theme = Theme.of(context);

  //   return Scaffold(
  //     appBar: AppBar(title: const Text("👤 Public Profile")),
  //     body:
  //         isLoading
  //             ? const Center(child: CircularProgressIndicator())
  //             : SingleChildScrollView(
  //               padding: const EdgeInsets.all(16),
  //               child: Column(
  //                 children: [
  //                   CircleAvatar(
  //                     radius: 60,
  //                     backgroundImage:
  //                         profileBase64 != null
  //                             ? MemoryImage(base64Decode(profileBase64!))
  //                             : const NetworkImage(
  //                                   "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
  //                                 )
  //                                 as ImageProvider,
  //                   ),
  //                   const SizedBox(height: 12),
  //                   Text(name, style: theme.textTheme.titleLarge),
  //                   const SizedBox(height: 4),
  //                   Text(
  //                     bio,
  //                     style: theme.textTheme.bodyMedium,
  //                     textAlign: TextAlign.center,
  //                   ),
  //                   const Divider(height: 32),
  //                   Align(
  //                     alignment: Alignment.centerLeft,
  //                     child: Text(
  //                       "📸 Public Memories",
  //                       style: theme.textTheme.titleMedium,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 12),
  //                   if (userPhotos.isEmpty)
  //                     const Text("No public photos available.")
  //                   else
  //                     ...userPhotos.map(
  //                       (photo) => Card(
  //                         margin: const EdgeInsets.symmetric(vertical: 8),
  //                         shape: RoundedRectangleBorder(
  //                           borderRadius: BorderRadius.circular(12),
  //                         ),
  //                         elevation: 3,
  //                         child: Column(
  //                           crossAxisAlignment: CrossAxisAlignment.start,
  //                           children: [
  //                             if (photo.imageBase64 != null)
  //                               ClipRRect(
  //                                 borderRadius: const BorderRadius.vertical(
  //                                   top: Radius.circular(12),
  //                                 ),
  //                                 child: Image.memory(
  //                                   base64Decode(photo.imageBase64!),
  //                                   height: 200,
  //                                   width: double.infinity,
  //                                   fit: BoxFit.cover,
  //                                 ),
  //                               ),
  //                             Padding(
  //                               padding: const EdgeInsets.all(12),
  //                               child: Column(
  //                                 crossAxisAlignment: CrossAxisAlignment.start,
  //                                 children: [
  //                                   Text(
  //                                     photo.caption,
  //                                     style: theme.textTheme.titleMedium,
  //                                   ),
  //                                   const SizedBox(height: 4),
  //                                   Text(
  //                                     "📍 ${photo.location}",
  //                                     style: theme.textTheme.bodySmall,
  //                                   ),
  //                                   const SizedBox(height: 4),
  //                                   Text(
  //                                     "🗓️ ${photo.timestamp.toLocal().toString().split('.')[0]}",
  //                                     style: theme.textTheme.bodySmall
  //                                         ?.copyWith(
  //                                           color: theme.colorScheme.outline,
  //                                         ),
  //                                   ),
  //                                 ],
  //                               ),
  //                             ),
  //                           ],
  //                         ),
  //                       ),
  //                     ),
  //                 ],
  //               ),
  //             ),
  //   );
  // }
}
