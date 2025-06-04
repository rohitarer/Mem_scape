import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:memscape/models/photo_model.dart';

class FollowingFeedScreen extends StatefulWidget {
  const FollowingFeedScreen({super.key});

  @override
  State<FollowingFeedScreen> createState() => _FollowingFeedScreenState();
}

class _FollowingFeedScreenState extends State<FollowingFeedScreen> {
  final user = FirebaseAuth.instance.currentUser!;
  List<PhotoModel> feedPhotos = [];
  Map<String, String> profileImages = {}; // uid → base64 image
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowingFeed();
  }

  Future<void> _loadFollowingFeed() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

      final data = doc.data();
      final List<dynamic> following = data?['following'] ?? [];

      if (following.isEmpty) {
        setState(() {
          feedPhotos = [];
          isLoading = false;
        });
        return;
      }

      final allPhotos =
          await FirebaseFirestore.instance
              .collection('photos')
              .where('uid', whereIn: following)
              .where('isPublic', isEqualTo: true)
              .orderBy('timestamp', descending: true)
              .get();

      List<PhotoModel> photos =
          allPhotos.docs.map((doc) {
            final map = doc.data();
            return PhotoModel.fromMap(map);
          }).toList();

      // Preload profile images from Realtime DB
      for (var uid in following) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final profilePath = userDoc.data()?['profileImagePath'];
        if (profilePath != null) {
          final snapshot =
              await FirebaseDatabase.instance.ref(profilePath).get();
          if (snapshot.exists) {
            profileImages[uid] = snapshot.value as String;
          }
        }
      }

      setState(() {
        feedPhotos = photos;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Error loading feed: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("👥 Following Feed")),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : feedPhotos.isEmpty
              ? const Center(
                child: Text("No recent posts from your followings."),
              )
              : ListView.builder(
                itemCount: feedPhotos.length,
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) {
                  final photo = feedPhotos[index];
                  final profileBase64 = profileImages[photo.uid];

                  return Card(
                    elevation: 3,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundImage:
                                profileBase64 != null
                                    ? MemoryImage(base64Decode(profileBase64))
                                    : const NetworkImage(
                                          'https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png',
                                        )
                                        as ImageProvider,
                          ),
                          title: Text(
                            photo.caption,
                            style: theme.textTheme.titleMedium,
                          ),
                          subtitle: Text(photo.location),
                        ),
                        if (photo.imagePath != null)
                          FutureBuilder<String?>(
                            future: FirebaseDatabase.instance
                                .ref(photo.imagePath!)
                                .get()
                                .then(
                                  (snap) =>
                                      snap.exists ? snap.value as String : null,
                                ),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox(
                                  height: 200,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              } else if (snapshot.hasData) {
                                try {
                                  final bytes = base64Decode(snapshot.data!);
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(
                                      bytes,
                                      width: double.infinity,
                                      height: 200,
                                      fit: BoxFit.cover,
                                    ),
                                  );
                                } catch (_) {
                                  return const Text(
                                    "⚠️ Failed to decode image.",
                                  );
                                }
                              } else {
                                return const Text("⚠️ Image not found.");
                              }
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            "🕒 ${photo.timestamp.toLocal().toString().split('.')[0]}",
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
    );
  }
}
