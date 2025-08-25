import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:memscape/screens/home/public_profile_screen.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    final rtdb = FirebaseDatabase.instance;

    // NOTE: Avoid orderBy for now to skip composite index requirement.
    // If you want newest-first, add:
    //   .orderBy('updatedAt', descending: true)
    // and create the composite index when the console link is shown in logs.
    final stream =
        db
            .collection('connections')
            .where('users', arrayContains: me)
            .where('status', isEqualTo: 'accepted')
            .orderBy('updatedAt', descending: true)
            .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Your Vibes')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Couldn't load vibes: ${snap.error}",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return const Center(child: Text('No connections yet.'));
          }

          final docs = snap.data!.docs;

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final users = (data['users'] as List).cast<String>();
              final otherUid = users.firstWhere((u) => u != me);

              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: db.collection('users').doc(otherUid).get(),
                builder: (context, userSnap) {
                  if (userSnap.connectionState == ConnectionState.waiting) {
                    return const ListTile(
                      leading: CircleAvatar(child: Icon(Icons.person)),
                      title: Text('Loading…'),
                    );
                  }
                  final udata = userSnap.data?.data() ?? {};
                  final nickname = (udata['username'] ?? 'mutual').toString();
                  final profilePath =
                      (udata['profileImagePath'] ?? '').toString();

                  // Make this nullable-safe: allow the future to be null
                  Future<DataSnapshot?> avatarFuture =
                      profilePath.isEmpty
                          ? Future.value(null)
                          : rtdb.ref(profilePath).get();

                  return FutureBuilder<DataSnapshot?>(
                    future: avatarFuture,
                    builder: (context, imgSnap) {
                      ImageProvider avatar;
                      final v = imgSnap.data?.value;
                      if (v is String && v.isNotEmpty) {
                        try {
                          avatar = MemoryImage(base64Decode(v));
                        } catch (_) {
                          avatar = const NetworkImage(
                            "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                          );
                        }
                      } else {
                        avatar = const NetworkImage(
                          "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                        );
                      }

                      return ListTile(
                        leading: CircleAvatar(backgroundImage: avatar),
                        title: Text(
                          nickname,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text("Linked • tap to view profile"),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => PublicProfileScreen(uid: otherUid),
                            ),
                          );
                        },
                        trailing: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder:
                                  (_) => AlertDialog(
                                    title: const Text("Unvibe?"),
                                    content: Text(
                                      "Break the link with $nickname?\nYou’ll lose access until you link up again.",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed:
                                            () => Navigator.pop(context, false),
                                        child: const Text("Cancel"),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor:
                                              Theme.of(
                                                context,
                                              ).colorScheme.error,
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed:
                                            () => Navigator.pop(context, true),
                                        child: const Text("Unvibe"),
                                      ),
                                    ],
                                  ),
                            );

                            if (ok == true) {
                              try {
                                await db
                                    .collection('connections')
                                    .doc(doc.id)
                                    .delete();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Unvibed with $nickname"),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Couldn’t unvibe: $e"),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: const Text("Unvibe"),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
