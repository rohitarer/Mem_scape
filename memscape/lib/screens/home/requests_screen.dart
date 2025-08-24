// screens/requests_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:memscape/services/link_up_service.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final db = FirebaseFirestore.instance;
  final link = LinkUpService();
  late final String myUid;

  @override
  void initState() {
    super.initState();
    myUid = FirebaseAuth.instance.currentUser!.uid;
    // 👇 Mark inbox items as read when screen opens
    _markInboxRead(myUid);
  }

  Future<void> _markInboxRead(String myUid) async {
    try {
      final unread =
          await db
              .collection('users')
              .doc(myUid)
              .collection('inbox')
              .where('read', isEqualTo: false)
              .get();

      for (final d in unread.docs) {
        await d.reference.update({'read': true});
      }
    } catch (e) {
      // Optional: show a toast/snackbar in debug or UI
      // debugPrint("Failed to mark inbox read: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    // pending connections where requester != me
    final connQuery =
        db
            .collection('connections')
            .where('users', arrayContains: myUid)
            .where('status', isEqualTo: 'pending')
            .snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('✨ Link‑up Requests')),
      body: RefreshIndicator(
        onRefresh:
            () => _markInboxRead(myUid), // Pull to refresh → mark read again
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: connQuery,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.hasData) {
              return const Center(child: Text('No pending link‑ups.'));
            }

            final docs =
                snap.data!.docs
                    .where((d) => d.data()['requester'] != myUid)
                    .toList();

            if (docs.isEmpty) {
              return const Center(child: Text('No pending link‑ups.'));
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final data = docs[i].data();
                final pairId = docs[i].id;
                final requester = data['requester'] as String? ?? 'Unknown';
                final users = (data['users'] as List).cast<String>();
                final otherUid = users.firstWhere((u) => u != myUid);

                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('Link‑up from $requester'),
                  subtitle: Text('Pair: $pairId'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => link.acceptLinkUp(otherUid),
                        child: const Text('Accept'),
                      ),
                      OutlinedButton(
                        onPressed: () => link.ignoreLinkUp(otherUid),
                        child: const Text('Ignore'),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
