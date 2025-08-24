import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:memscape/services/link_up_service.dart';

class PingsScreen extends StatelessWidget {
  const PingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    final link = LinkUpService();

    // 🔴 Live link-ups that involve me
    final connStream =
        db
            .collection('connections')
            .where('users', arrayContains: myUid)
            .snapshots();

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: connStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData) {
            return const _EmptyState();
          }

          final docs =
              snap.data!.docs
                  .where(
                    (d) =>
                        (d.data()['requester'] as String?) != myUid &&
                        (d.data()['status'] == 'pending' ||
                            d.data()['status'] == 'accepted'),
                  )
                  .toList();

          if (docs.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final data = docs[i].data();
              final users = (data['users'] as List).cast<String>();
              final otherUid = users.firstWhere((u) => u != myUid);
              final status = data['status'] as String? ?? 'pending';

              return _PingRequestCard(
                otherUid: otherUid,
                status: status,
                onAccept: () => link.acceptLinkUp(otherUid),
                onIgnore: () => link.ignoreLinkUp(otherUid),
              );
            },
          );
        },
      ),
    );
  }
}

// ===== Widgets =====

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none_rounded, size: 64),
            const SizedBox(height: 12),
            Text(
              "no pings rn 👀",
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              "your vibe radar’s chill — check back later ✨",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _PingRequestCard extends StatelessWidget {
  final String otherUid;
  final String status; // "pending" or "accepted"
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const _PingRequestCard({
    required this.otherUid,
    required this.status,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    final isAccepted = status == 'accepted';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const CircleAvatar(child: Icon(Icons.person_rounded)),
            const SizedBox(width: 12),
            Expanded(
              child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future:
                    FirebaseFirestore.instance
                        .collection('users')
                        .doc(otherUid)
                        .get(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data();
                  final name = data?['name'] ?? data?['username'] ?? otherUid;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "$name wants to Link Up",
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAccepted
                            ? "you’re now connected 🎉"
                            : "tap accept to unveil each other’s profile",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  icon: Icon(isAccepted ? Icons.check_circle : Icons.handshake),
                  label: Text(isAccepted ? "Accepted" : "Accept"),
                  onPressed: isAccepted ? null : onAccept,
                ),
                if (!isAccepted) ...[
                  const SizedBox(height: 6),
                  TextButton(onPressed: onIgnore, child: const Text("Ignore")),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:memscape/services/link_up_service.dart';

// class PingsScreen extends StatelessWidget {
//   const PingsScreen({super.key});

//   @override
//   Widget build(BuildContext context) {
//     final myUid = FirebaseAuth.instance.currentUser!.uid;
//     final db = FirebaseFirestore.instance;
//     final link = LinkUpService();

//     // 🔴 Live pending link‑ups sent TO me
//     final connStream =
//         db
//             .collection('connections')
//             .where('users', arrayContains: myUid)
//             .where('status', isEqualTo: 'pending')
//             .snapshots();

//     return Scaffold(
//       appBar: AppBar(title: const Text("⚡ Pings")),
//       body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
//         stream: connStream,
//         builder: (context, snap) {
//           if (snap.connectionState == ConnectionState.waiting) {
//             return const Center(child: CircularProgressIndicator());
//           }
//           if (!snap.hasData) {
//             return const _EmptyState();
//           }

//           // Only show pings where **they** requested me
//           final docs =
//               snap.data!.docs
//                   .where((d) => (d.data()['requester'] as String?) != myUid)
//                   .toList();

//           if (docs.isEmpty) {
//             return const _EmptyState();
//           }

//           return ListView.separated(
//             padding: const EdgeInsets.all(16),
//             itemCount: docs.length,
//             separatorBuilder: (_, __) => const SizedBox(height: 12),
//             itemBuilder: (context, i) {
//               final data = docs[i].data();
//               final users = (data['users'] as List).cast<String>();
//               final otherUid = users.firstWhere((u) => u != myUid);

//               return _PingRequestCard(
//                 otherUid: otherUid,
//                 onAccept: () => link.acceptLinkUp(otherUid),
//                 onIgnore: () => link.ignoreLinkUp(otherUid),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

// // ===== Widgets =====

// class _EmptyState extends StatelessWidget {
//   const _EmptyState();

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(32),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Icon(Icons.notifications_none_rounded, size: 64),
//             const SizedBox(height: 12),
//             Text(
//               "no pings rn 👀",
//               style: Theme.of(
//                 context,
//               ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
//             ),
//             const SizedBox(height: 6),
//             Text(
//               "your vibe radar’s chill — check back later ✨",
//               textAlign: TextAlign.center,
//               style: Theme.of(context).textTheme.bodyMedium,
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// class _PingRequestCard extends StatelessWidget {
//   final String otherUid;
//   final VoidCallback onAccept;
//   final VoidCallback onIgnore;

//   const _PingRequestCard({
//     required this.otherUid,
//     required this.onAccept,
//     required this.onIgnore,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Card(
//       elevation: 3,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
//       child: Padding(
//         padding: const EdgeInsets.all(12),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: [
//             const CircleAvatar(child: Icon(Icons.person_rounded)),
//             const SizedBox(width: 12),
//             Expanded(
//               child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
//                 future:
//                     FirebaseFirestore.instance
//                         .collection('users')
//                         .doc(otherUid)
//                         .get(),
//                 builder: (context, snapshot) {
//                   final data = snapshot.data?.data();
//                   final name = data?['name'] ?? data?['username'] ?? otherUid;
//                   return Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         "$name wants to Link Up",
//                         style: Theme.of(context).textTheme.titleMedium
//                             ?.copyWith(fontWeight: FontWeight.w700),
//                       ),
//                       const SizedBox(height: 2),
//                       Text(
//                         "tap accept to unveil each other’s profile",
//                         style: Theme.of(context).textTheme.bodySmall,
//                       ),
//                     ],
//                   );
//                 },
//               ),
//             ),
//             const SizedBox(width: 8),
//             Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 FilledButton.icon(
//                   icon: const Icon(Icons.handshake_rounded),
//                   label: const Text("Accept"),
//                   onPressed: onAccept,
//                 ),
//                 const SizedBox(height: 6),
//                 TextButton(onPressed: onIgnore, child: const Text("Ignore")),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
