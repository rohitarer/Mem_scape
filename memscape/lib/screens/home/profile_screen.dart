import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:memscape/screens/home/edit_profile_screen.dart';
import 'package:memscape/screens/home/followers_list_screen.dart';
import 'package:memscape/screens/home/following_feed_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final user = FirebaseAuth.instance.currentUser!;
  String name = '';
  String bio = '';
  String? imagePath;
  String? imageBase64;
  List<String> photoRefs = [];

  final realtimeDB = FirebaseDatabase.instance;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      if (doc.exists) {
        final data = doc.data()!;
        name = data['name'] ?? '';
        bio = data['bio'] ?? '';
        imagePath = data['profileImagePath'];
        photoRefs = List<String>.from(data['photoRefs'] ?? []);

        if (imagePath != null && imagePath!.isNotEmpty) {
          final snapshot = await realtimeDB.ref(imagePath!).get();
          if (snapshot.exists) {
            imageBase64 = snapshot.value as String;
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error loading profile: $e");
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider =
        imageBase64 != null
            ? MemoryImage(base64Decode(imageBase64!))
            : const NetworkImage(
                  "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                )
                as ImageProvider;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen()),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            CircleAvatar(radius: 50, backgroundImage: imageProvider),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(bio, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStat("Photos", photoRefs.length),
                GestureDetector(
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FollowersListScreen(),
                        ),
                      ),
                  child: _buildStat("Followers", 0),
                ),
                GestureDetector(
                  onTap:
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FollowingFeedScreen(),
                        ),
                      ),
                  child: _buildStat("Following", 0),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Posts",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildPhotoGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, int count) {
    return Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildPhotoGrid() {
    if (photoRefs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text("No posts yet."),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: photoRefs.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemBuilder: (context, index) {
          final refPath = "images/${photoRefs[index]}";
          return FutureBuilder<DataSnapshot>(
            future: realtimeDB.ref(refPath).get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 1),
                );
              }

              if (!snapshot.hasData || !snapshot.data!.exists) {
                return const Icon(Icons.broken_image);
              }

              final base64String = snapshot.data!.value as String;
              final image = MemoryImage(base64Decode(base64String));

              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image(image: image, fit: BoxFit.cover),
              );
            },
          );
        },
      ),
    );
  }
}
