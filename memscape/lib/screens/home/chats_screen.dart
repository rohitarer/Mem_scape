import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:memscape/screens/home/chat_thread_screen.dart';
import 'package:memscape/services/firestore_service.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;

    // Live mutuals (accepted). includeMetadataChanges => instant local updates.
    final connectionsStream = FirebaseFirestore.instance
        .collection('connections')
        .where('users', arrayContains: myUid)
        .where('status', isEqualTo: 'accepted')
        .snapshots(includeMetadataChanges: true);

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: connectionsStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Couldn't load chats.\n${snap.error}",
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const _EmptyChats();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final users = (data['users'] as List).cast<String>();
              final otherUid = users.firstWhere((u) => u != myUid);

              return _UserChatTile(otherUid: otherUid);
            },
          );
        },
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 64),
            const SizedBox(height: 12),
            Text(
              "no chats yet 💬",
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              "accept a link‑up to start a vibe ✨",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the other user's avatar (from Realtime DB base64) and **nickname only** (username).
class _UserChatTile extends StatelessWidget {
  final String otherUid;
  const _UserChatTile({required this.otherUid});

  @override
  Widget build(BuildContext context) {
    final users = FirebaseFirestore.instance.collection('users');

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: users.doc(otherUid).get(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final nickname = (data?['username'] as String?) ?? 'mutual';
        final profilePath = (data?['profileImagePath'] as String?);

        // Load profile base64 if we have a path
        return FutureBuilder<String?>(
          future:
              profilePath == null || profilePath.isEmpty
                  ? Future.value(null)
                  : FirestoreService().fetchProfileBase64(profilePath),
          builder: (context, picSnap) {
            ImageProvider avatarProvider;

            if (picSnap.connectionState == ConnectionState.done &&
                picSnap.hasData &&
                picSnap.data != null &&
                picSnap.data!.isNotEmpty) {
              try {
                avatarProvider = MemoryImage(base64Decode(picSnap.data!));
              } catch (_) {
                avatarProvider = const NetworkImage(
                  "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                );
              }
            } else {
              avatarProvider = const NetworkImage(
                "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
              );
            }

            // You can replace lastMsgPreview/time once you wire messages.
            const lastMsgPreview = "You’re connected — say hi 👋";
            const time = "";

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 8,
              ),
              leading: CircleAvatar(backgroundImage: avatarProvider),
              // 🔥 Show ONLY nickname (username). No real name.
              title: Text(
                nickname,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                lastMsgPreview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                time,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              onTap: () {
                Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ChatThreadScreen(otherUid: otherUid),
  ),
);
              },
            );
          },
        );
      },
    );
  }
}
