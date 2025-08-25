import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:memscape/models/connection_model.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/screens/home/chat_thread_screen.dart';
import 'package:memscape/screens/home/memories_view_screen.dart';
import 'package:memscape/services/firestore_service.dart';
import 'package:memscape/services/link_up_service.dart';

class PublicProfileScreen extends StatefulWidget {
  final String uid; // profile being viewed
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _link = LinkUpService();
  final _realtime = FirebaseDatabase.instance;

  String nickname = ''; // use “nice name” (username) instead of real name
  String bio = '';
  String? profileBase64;
  List<PhotoModel> userPhotos = [];
  bool isLoading = true;

  // Optimistic UI for pending state
  bool _optimisticPending = false;
  String? _optimisticRequester;

  String get _myUid => _auth.currentUser!.uid;

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
              .doc(widget.uid)
              .get();

      if (doc.exists) {
        final data = doc.data()!;
        // Prefer “username” as the nice/handle name; fallback to name
        nickname =
            (data['username'] as String?)?.trim().isNotEmpty == true
                ? data['username']
                : (data['name'] ?? '');
        bio = data['bio'] ?? '';
        profileBase64 = await FirestoreService().fetchProfileBase64(
          data['profileImagePath'],
        );
      }
    } catch (e) {
      debugPrint("❌ Failed to load profile: $e");
    }

    if (mounted) setState(() => isLoading = false);
  }

  Future<void> _loadPhotosIfNeeded() async {
    if (userPhotos.isNotEmpty) return;
    try {
      final myUid = _auth.currentUser!.uid;
      userPhotos = await FirestoreService().fetchUserPhotosForViewer(
        ownerUid: widget.uid,
        viewerUid: myUid,
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("❌ Failed to load photos: $e");
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _unvibe() async {
    final pairId = ConnectionModel.makePairId(_myUid, widget.uid);
    final db = FirebaseFirestore.instance;

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
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Unvibe"),
              ),
            ],
          ),
    );

    if (ok != true) return;

    try {
      await db.collection('connections').doc(pairId).delete();
      if (!mounted) return;
      _toast("Unvibed with $nickname");
      setState(() => userPhotos = []);
    } catch (e) {
      if (!mounted) return;
      _toast("Couldn’t unvibe: $e");
    }
  }

  void _goToDM() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatThreadScreen(otherUid: widget.uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = _myUid == widget.uid;

    // Self-view (no gate, no Unvibe/Message)
    if (isMe) {
      final imageProvider =
          profileBase64 != null
              ? MemoryImage(base64Decode(profileBase64!))
              : const NetworkImage(
                    "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                  )
                  as ImageProvider;

      return Scaffold(
        appBar: AppBar(title: const Text("👤 Your Public Profile")),
        body:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : _AcceptedProfileBody(
                  imageProvider: imageProvider,
                  nickname: nickname, // show nice name
                  bio: bio,
                  userPhotos: userPhotos,
                  realtime: _realtime,
                  // controls row
                  showMessage: false,
                  showUnvibe: false,
                  onMessage: null,
                  onUnvibe: null,
                ),
      );
    }

    // Other user — lock until accepted
    return StreamBuilder<ConnectionModel?>(
      stream: _link.watchConnection(widget.uid),
      builder: (context, snapshot) {
        final conn = snapshot.data;
        var status = conn?.status;
        var requester = conn?.requester;

        var isAccepted = status == LinkUpStatus.accepted;
        var isPending = status == LinkUpStatus.pending;
        var iRequested = isPending && requester == _myUid;
        var theyRequested = isPending && requester == widget.uid;

        if (_optimisticPending && !isAccepted) {
          isPending = true;
          iRequested = _optimisticRequester == _myUid;
          theyRequested = _optimisticRequester == widget.uid;
        }

        if (isAccepted && userPhotos.isEmpty) {
          _loadPhotosIfNeeded();
        }

        final imageProvider =
            profileBase64 != null
                ? MemoryImage(base64Decode(profileBase64!))
                : const NetworkImage(
                      "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                    )
                    as ImageProvider;

        return Scaffold(
          appBar: AppBar(
            title: Text(isAccepted ? "👥 Mutual Vibes" : "🔒 Profile Locked"),
          ),
          body:
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : isAccepted
                  ? _AcceptedProfileBody(
                    imageProvider: imageProvider,
                    nickname: nickname, // show nice name
                    bio: bio,
                    userPhotos: userPhotos,
                    realtime: _realtime,
                    // centered, compact row: Vibes | Message | Unvibe
                    showMessage: true,
                    showUnvibe: true,
                    onMessage: _goToDM,
                    onUnvibe: _unvibe,
                  )
                  : _LockedGate(
                    isPending: isPending,
                    iRequested: iRequested,
                    theyRequested: theyRequested,
                    onSend: () async {
                      setState(() {
                        _optimisticPending = true;
                        _optimisticRequester = _myUid;
                      });
                      await _link.sendLinkUp(widget.uid);
                      _toast("✨ Link‑up sent");
                    },
                    onCancel: () async {
                      setState(() {
                        _optimisticPending = false;
                        _optimisticRequester = null;
                      });
                      await _link.cancelLinkUp(widget.uid);
                      _toast("Link‑up canceled");
                    },
                    onAccept: () async {
                      setState(() {
                        _optimisticPending = false;
                        _optimisticRequester = null;
                      });
                      await _link.acceptLinkUp(widget.uid);
                      _toast("You’re mutuals now 🫶");
                    },
                    onIgnore: () async {
                      setState(() {
                        _optimisticPending = false;
                        _optimisticRequester = null;
                      });
                      await _link.ignoreLinkUp(widget.uid);
                      _toast("Request ignored");
                    },
                  ),
        );
      },
    );
  }
}

class _AcceptedProfileBody extends StatelessWidget {
  final ImageProvider imageProvider;
  final String nickname;
  final String bio;
  final List<PhotoModel> userPhotos;
  final FirebaseDatabase realtime;

  // Optional visibility + actions
  final bool showMessage;
  final bool showUnvibe;
  final VoidCallback? onMessage;
  final VoidCallback? onUnvibe;

  const _AcceptedProfileBody({
    required this.imageProvider,
    required this.nickname,
    required this.bio,
    required this.userPhotos,
    required this.realtime,
    this.showMessage = true,
    this.showUnvibe = true,
    this.onMessage,
    this.onUnvibe,
  });

  @override
  Widget build(BuildContext context) {
    final photosCount = userPhotos.length;
    // TODO: replace with your real vibes count if you store it separately
    final vibesCount = userPhotos.length;

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),

          // ───────────────── Top block: avatar + text + stats (centered) ─────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 360;

                if (narrow) {
                  // Stack vertically on small widths
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      CircleAvatar(radius: 50, backgroundImage: imageProvider),
                      const SizedBox(height: 10),
                      if (nickname.trim().isNotEmpty)
                        Text(
                          nickname,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      if (bio.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            bio,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _StatPill(label: "Photos", count: photosCount),
                          const SizedBox(width: 14),
                          _StatPill(label: "Vibes", count: vibesCount),
                        ],
                      ),
                    ],
                  );
                }

                // Side‑by‑side for normal/wide widths
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left: avatar + nickname + bio (center-aligned)
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundImage: imageProvider,
                          ),
                          const SizedBox(height: 10),
                          if (nickname.trim().isNotEmpty)
                            Text(
                              nickname,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          if (bio.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                bio,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Right: stats column (centered vertically)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StatPill(label: "Photos", count: photosCount),
                        const SizedBox(height: 10),
                        _StatPill(label: "Vibes", count: vibesCount),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // ───────────────── Actions row ─────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (showMessage) ...[
                FilledButton.tonal(
                  onPressed: onMessage, // null => disabled
                  child: const Text("Message"),
                ),
                const SizedBox(width: 12),
              ],
              if (showUnvibe)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onUnvibe, // null => disabled
                  child: const Text("Unvibe"),
                ),
            ],
          ),

          const SizedBox(height: 24),
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

          _PhotoGrid(userPhotos: userPhotos, realtime: realtime),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final int count;
  const _StatPill({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            '$count',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

// class _StatPill extends StatelessWidget {
//   final String label;
//   final int count;
//   const _StatPill({required this.label, required this.count});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//       decoration: BoxDecoration(
//         color: Theme.of(context).colorScheme.surfaceVariant,
//         borderRadius: BorderRadius.circular(16),
//       ),
//       child: Row(
//         children: [
//           Text(
//             '$count',
//             style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//           ),
//           const SizedBox(width: 6),
//           Text(label, style: const TextStyle(color: Colors.grey)),
//         ],
//       ),
//     );
//   }
// }

class _PhotoGrid extends StatelessWidget {
  final List<PhotoModel> userPhotos;
  final FirebaseDatabase realtime;

  const _PhotoGrid({required this.userPhotos, required this.realtime});

  @override
  Widget build(BuildContext context) {
    final imagePaths =
        userPhotos
            .map((p) => p.imagePath)
            .whereType<String>()
            .where((p) => p.isNotEmpty)
            .toList();

    if (imagePaths.isEmpty) {
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
        itemCount: imagePaths.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
        ),
        itemBuilder: (context, index) {
          final imagePath = imagePaths[index];
          return FutureBuilder<DataSnapshot>(
            future: realtime.ref(imagePath).get(),
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
              final bytes = base64Decode(base64String);

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (_) => MemoriesViewScreen(
                            items: imagePaths,
                            initialIndex: index,
                          ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _LockedGate extends StatelessWidget {
  final bool isPending;
  final bool iRequested;
  final bool theyRequested;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onAccept;
  final VoidCallback onIgnore;

  const _LockedGate({
    required this.isPending,
    required this.iRequested,
    required this.theyRequested,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.onIgnore,
  });

  @override
  Widget build(BuildContext context) {
    Widget primary;
    Widget? secondary;

    if (!isPending && !theyRequested) {
      primary = FilledButton.icon(
        icon: const Icon(Icons.all_inclusive),
        onPressed: onSend,
        label: const Text("Link Up to Unveil"),
      );
      secondary = const Text(
        "Nothing is visible until your link‑up is accepted.",
        textAlign: TextAlign.center,
      );
    } else if (iRequested) {
      primary = FilledButton.icon(
        icon: Icon(Icons.hourglass_top),
        onPressed: null,
        label: Text("Pending link‑up…"),
      );
      secondary = TextButton(onPressed: onCancel, child: const Text("Cancel"));
    } else if (theyRequested) {
      primary = FilledButton.icon(
        icon: const Icon(Icons.handshake),
        onPressed: onAccept,
        label: const Text("Accept & Unveil"),
      );
      secondary = TextButton(onPressed: onIgnore, child: const Text("Ignore"));
    } else {
      primary = FilledButton.icon(
        icon: Icon(Icons.hourglass_top),
        onPressed: null,
        label: Text("Pending link‑up…"),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 42),
                const SizedBox(height: 12),
                const Text(
                  "Profile Locked",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  "Link up to unveil their world.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                primary,
                if (secondary != null) ...[
                  const SizedBox(height: 8),
                  secondary!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}




// import 'dart:convert';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:memscape/models/connection_model.dart';
// import 'package:memscape/models/photo_model.dart';
// import 'package:memscape/screens/home/memories_view_screen.dart';
// import 'package:memscape/services/firestore_service.dart';
// import 'package:memscape/services/link_up_service.dart';

// class PublicProfileScreen extends StatefulWidget {
//   final String uid; // profile being viewed
//   const PublicProfileScreen({super.key, required this.uid});

//   @override
//   State<PublicProfileScreen> createState() => _PublicProfileScreenState();
// }

// class _PublicProfileScreenState extends State<PublicProfileScreen> {
//   final _auth = FirebaseAuth.instance;
//   final _link = LinkUpService();
//   final _realtime = FirebaseDatabase.instance;

//   String name = '';
//   String bio = '';
//   String? profileBase64;
//   List<PhotoModel> userPhotos = [];
//   bool isLoading = true;

//   // Optimistic UI flags so the CTA flips immediately
//   bool _optimisticPending = false;
//   String? _optimisticRequester; // set to my uid when I send

//   String get _myUid => _auth.currentUser!.uid;

//   @override
//   void initState() {
//     super.initState();
//     _loadProfile();
//   }

//   Future<void> _loadProfile() async {
//     try {
//       final doc =
//           await FirebaseFirestore.instance
//               .collection('users')
//               .doc(widget.uid)
//               .get();

//       if (doc.exists) {
//         final data = doc.data()!;
//         name = data['name'] ?? '';
//         bio = data['bio'] ?? '';
//         profileBase64 = await FirestoreService().fetchProfileBase64(
//           data['profileImagePath'],
//         );
//       }
//     } catch (e) {
//       debugPrint("❌ Failed to load profile: $e");
//     }

//     if (mounted) setState(() => isLoading = false);
//   }

//   Future<void> _loadPhotosIfNeeded() async {
//     // Only load once when accepted
//     if (userPhotos.isNotEmpty) return;
//     try {
//       final myUid = _auth.currentUser!.uid;
//       userPhotos = await FirestoreService().fetchUserPhotosForViewer(
//         ownerUid: widget.uid,
//         viewerUid: myUid,
//       );
//       if (mounted) setState(() {});
//     } catch (e) {
//       debugPrint("❌ Failed to load photos: $e");
//     }
//   }

//   void _toast(String msg) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isMe = _myUid == widget.uid;

//     // You viewing your own public profile (no gate)
//     if (isMe) {
//       final imageProvider =
//           profileBase64 != null
//               ? MemoryImage(base64Decode(profileBase64!))
//               : const NetworkImage(
//                     "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//                   )
//                   as ImageProvider;

//       return Scaffold(
//         appBar: AppBar(title: const Text("👤 Your Public Profile")),
//         body:
//             isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : _AcceptedProfileBody(
//                   imageProvider: imageProvider,
//                   name: name,
//                   bio: bio,
//                   userPhotos: userPhotos,
//                   realtime: _realtime,
//                 ),
//       );
//     }

//     // Viewing someone else → gate until accepted
//     return StreamBuilder<ConnectionModel?>(
//       stream: _link.watchConnection(widget.uid),
//       builder: (context, snapshot) {
//         final conn = snapshot.data;
//         var status = conn?.status;
//         var requester = conn?.requester;

//         var isAccepted = status == LinkUpStatus.accepted;
//         var isPending = status == LinkUpStatus.pending;
//         var iRequested = isPending && requester == _myUid;
//         var theyRequested = isPending && requester == widget.uid;

//         // Apply optimistic overrides (instant button state change)
//         if (_optimisticPending && !isAccepted) {
//           isPending = true;
//           iRequested = _optimisticRequester == _myUid;
//           theyRequested = _optimisticRequester == widget.uid;
//         }

//         // Load photos only after acceptance
//         if (isAccepted && userPhotos.isEmpty) {
//           _loadPhotosIfNeeded();
//         }

//         final imageProvider =
//             profileBase64 != null
//                 ? MemoryImage(base64Decode(profileBase64!))
//                 : const NetworkImage(
//                       "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//                     )
//                     as ImageProvider;

//         return Scaffold(
//           appBar: AppBar(
//             title: Text(isAccepted ? "👥 Mutual Vibes" : "🔒 Profile Locked"),
//           ),
//           body:
//               isLoading
//                   ? const Center(child: CircularProgressIndicator())
//                   : isAccepted
//                   // ✅ ACCEPTED → use the same visual structure as ProfileScreen
//                   ? _AcceptedProfileBody(
//                     imageProvider: imageProvider,
//                     name: name,
//                     bio: bio,
//                     userPhotos: userPhotos,
//                     realtime: _realtime,
//                   )
//                   // 🔒 LOCKED → hard gate
//                   : _LockedGate(
//                     isPending: isPending,
//                     iRequested: iRequested,
//                     theyRequested: theyRequested,
//                     onSend: () async {
//                       setState(() {
//                         _optimisticPending = true;
//                         _optimisticRequester = _myUid;
//                       });
//                       await _link.sendLinkUp(widget.uid);
//                       _toast("✨ Link‑up sent");
//                     },
//                     onCancel: () async {
//                       setState(() {
//                         _optimisticPending = false;
//                         _optimisticRequester = null;
//                       });
//                       await _link.cancelLinkUp(widget.uid);
//                       _toast("Link‑up canceled");
//                     },
//                     onAccept: () async {
//                       setState(() {
//                         _optimisticPending = false;
//                         _optimisticRequester = null;
//                       });
//                       await _link.acceptLinkUp(widget.uid);
//                       _toast("You’re mutuals now 🫶");
//                     },
//                     onIgnore: () async {
//                       setState(() {
//                         _optimisticPending = false;
//                         _optimisticRequester = null;
//                       });
//                       await _link.ignoreLinkUp(widget.uid);
//                       _toast("Request ignored");
//                     },
//                   ),
//         );
//       },
//     );
//   }
// }

// class _AcceptedProfileBody extends StatelessWidget {
//   final ImageProvider imageProvider;
//   final String name;
//   final String bio;
//   final List<PhotoModel> userPhotos;
//   final FirebaseDatabase realtime;

//   const _AcceptedProfileBody({
//     required this.imageProvider,
//     required this.name,
//     required this.bio,
//     required this.userPhotos,
//     required this.realtime,
//   });

//   @override
//   Widget build(BuildContext context) {
//     // Vibe count == total public memories available after acceptance
//     final vibes = userPhotos.length;

//     return SingleChildScrollView(
//       child: Column(
//         children: [
//           const SizedBox(height: 20),
//           CircleAvatar(radius: 50, backgroundImage: imageProvider),
//           const SizedBox(height: 10),
//           Text(
//             name,
//             style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//           ),
//           Text(bio, style: const TextStyle(color: Colors.grey)),
//           const SizedBox(height: 20),

//           // 🔢 Stats row — "Vibes" instead of "Photos"
//           Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [_StatPill(label: "Vibes", count: vibes)],
//           ),

//           const SizedBox(height: 30),
//           const Divider(),
//           const Padding(
//             padding: EdgeInsets.symmetric(horizontal: 16.0),
//             child: Align(
//               alignment: Alignment.centerLeft,
//               child: Text(
//                 "Posts",
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//               ),
//             ),
//           ),
//           const SizedBox(height: 10),

//           _PhotoGrid(userPhotos: userPhotos, realtime: realtime),
//         ],
//       ),
//     );
//   }
// }

// class _StatPill extends StatelessWidget {
//   final String label;
//   final int count;
//   const _StatPill({required this.label, required this.count});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
//       decoration: BoxDecoration(
//         color: Theme.of(context).colorScheme.surfaceVariant,
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Column(
//         children: [
//           Text(
//             '$count',
//             style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//           ),
//           Text(label, style: const TextStyle(color: Colors.grey)),
//         ],
//       ),
//     );
//   }
// }

// class _PhotoGrid extends StatelessWidget {
//   final List<PhotoModel> userPhotos;
//   final FirebaseDatabase realtime;

//   const _PhotoGrid({required this.userPhotos, required this.realtime});

//   @override
//   Widget build(BuildContext context) {
//     // Build a clean list of non‑empty image paths in the same order
//     final imagePaths =
//         userPhotos
//             .map((p) => p.imagePath)
//             .whereType<String>()
//             .where((p) => p.isNotEmpty)
//             .toList();

//     if (imagePaths.isEmpty) {
//       return const Padding(
//         padding: EdgeInsets.all(20),
//         child: Text("No posts yet."),
//       );
//     }

//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: GridView.builder(
//         shrinkWrap: true,
//         physics: const NeverScrollableScrollPhysics(),
//         itemCount: imagePaths.length,
//         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//           crossAxisCount: 3,
//           mainAxisSpacing: 6,
//           crossAxisSpacing: 6,
//         ),
//         itemBuilder: (context, index) {
//           final imagePath = imagePaths[index]; // e.g., "images/<photoId>"

//           return FutureBuilder<DataSnapshot>(
//             future: realtime.ref(imagePath).get(),
//             builder: (context, snapshot) {
//               if (snapshot.connectionState == ConnectionState.waiting) {
//                 return const Center(
//                   child: CircularProgressIndicator(strokeWidth: 1),
//                 );
//               }

//               if (!snapshot.hasData || !snapshot.data!.exists) {
//                 return const Icon(Icons.broken_image);
//               }

//               final base64String = snapshot.data!.value as String;
//               final bytes = base64Decode(base64String);

//               return GestureDetector(
//                 onTap: () {
//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(
//                       builder:
//                           (_) => MemoriesViewScreen(
//                             items: imagePaths, // whole sequence to swipe
//                             initialIndex: index, // start on tapped image
//                           ),
//                     ),
//                   );
//                 },
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(6),
//                   child: Image.memory(bytes, fit: BoxFit.cover),
//                 ),
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

// class _LockedGate extends StatelessWidget {
//   final bool isPending;
//   final bool iRequested;
//   final bool theyRequested;
//   final VoidCallback onSend;
//   final VoidCallback onCancel;
//   final VoidCallback onAccept;
//   final VoidCallback onIgnore;

//   const _LockedGate({
//     required this.isPending,
//     required this.iRequested,
//     required this.theyRequested,
//     required this.onSend,
//     required this.onCancel,
//     required this.onAccept,
//     required this.onIgnore,
//   });

//   @override
//   Widget build(BuildContext context) {
//     Widget primary;
//     Widget? secondary;

//     if (!isPending && !theyRequested) {
//       primary = FilledButton.icon(
//         icon: const Icon(Icons.all_inclusive),
//         onPressed: onSend,
//         label: const Text("Link Up to Unveil"),
//       );
//       secondary = const Text(
//         "Nothing is visible until your link‑up is accepted.",
//         textAlign: TextAlign.center,
//       );
//     } else if (iRequested) {
//       primary = FilledButton.icon(
//         icon: Icon(Icons.hourglass_top),
//         onPressed: null,
//         label: Text("Pending link‑up…"),
//       );
//       secondary = TextButton(onPressed: onCancel, child: const Text("Cancel"));
//     } else if (theyRequested) {
//       primary = FilledButton.icon(
//         icon: const Icon(Icons.handshake),
//         onPressed: onAccept,
//         label: const Text("Accept & Unveil"),
//       );
//       secondary = TextButton(onPressed: onIgnore, child: const Text("Ignore"));
//     } else {
//       primary = FilledButton.icon(
//         icon: Icon(Icons.hourglass_top),
//         onPressed: null,
//         label: Text("Pending link‑up…"),
//       );
//     }

//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(24),
//         child: Card(
//           elevation: 6,
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(16),
//           ),
//           child: Padding(
//             padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 const Icon(Icons.lock_outline, size: 42),
//                 const SizedBox(height: 12),
//                 const Text(
//                   "Profile Locked",
//                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
//                 ),
//                 const SizedBox(height: 6),
//                 const Text(
//                   "Link up to unveil their world.",
//                   textAlign: TextAlign.center,
//                 ),
//                 const SizedBox(height: 16),
//                 primary,
//                 if (secondary != null) ...[
//                   const SizedBox(height: 8),
//                   secondary!,
//                 ],
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

