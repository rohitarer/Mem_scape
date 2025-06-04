import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

class FollowersListScreen extends StatefulWidget {
  const FollowersListScreen({super.key});

  @override
  State<FollowersListScreen> createState() => _FollowersListScreenState();
}

class _FollowersListScreenState extends State<FollowersListScreen> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  List<Map<String, dynamic>> followers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFollowers();
  }

  Future<void> _loadFollowers() async {
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(currentUser.uid)
              .get();

      final data = doc.data();
      final List<dynamic> followerIds = data?['followers'] ?? [];

      List<Map<String, dynamic>> tempList = [];

      for (var uid in followerIds) {
        final userDoc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();

        if (!userDoc.exists) continue;

        final userData = userDoc.data()!;
        String? base64Image;

        if (userData['profileImagePath'] != null) {
          final snap =
              await FirebaseDatabase.instance
                  .ref(userData['profileImagePath'])
                  .get();

          if (snap.exists) {
            base64Image = snap.value as String;
          }
        }

        tempList.add({
          'uid': uid,
          'name': userData['name'] ?? 'Unnamed User',
          'bio': userData['bio'] ?? '',
          'profileImage': base64Image,
        });
      }

      setState(() {
        followers = tempList;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("❌ Error loading followers: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text("👥 Followers")),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : followers.isEmpty
              ? const Center(child: Text("You have no followers yet."))
              : ListView.builder(
                itemCount: followers.length,
                itemBuilder: (context, index) {
                  final user = followers[index];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage:
                          user['profileImage'] != null
                              ? MemoryImage(base64Decode(user['profileImage']))
                              : const NetworkImage(
                                    'https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png',
                                  )
                                  as ImageProvider,
                    ),
                    title: Text(user['name']),
                    subtitle: Text(user['bio']),
                    trailing: const Icon(Icons.person),
                  );
                },
              ),
    );
  }
}
