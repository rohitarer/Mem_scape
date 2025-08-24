import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:memscape/models/connection_model.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/services/firestore_service.dart';
import 'package:memscape/services/link_up_service.dart';
import 'package:memscape/widgets/profile_gallery.dart';
import 'package:memscape/widgets/profile_header.dart';

class PublicProfileScreen extends StatefulWidget {
  final String uid; // profile being viewed
  const PublicProfileScreen({super.key, required this.uid});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  final _auth = FirebaseAuth.instance;
  final _link = LinkUpService();

  String name = '';
  String bio = '';
  String? profileBase64;
  List<PhotoModel> userPhotos = [];
  bool isLoading = true;

  // Optimistic UI flags so the CTA flips immediately
  bool _optimisticPending = false;
  String? _optimisticRequester; // set to my uid when I send

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
        name = data['name'] ?? '';
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
    // Only load once when accepted
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

  @override
  Widget build(BuildContext context) {
    final isMe = _myUid == widget.uid;

    if (isMe) {
      return Scaffold(
        appBar: AppBar(title: const Text("👤 Your Public Profile")),
        body:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      ProfileHeader(
                        profileBase64: profileBase64,
                        name: name,
                        bio: bio,
                        vibeCount: userPhotos.length,
                      ),
                      const Divider(height: 32),
                      ProfileGallery(photos: userPhotos),
                    ],
                  ),
                ),
      );
    }

    return StreamBuilder(
      // If you update LinkUpService.watchConnection to use includeMetadataChanges: true
      // the UI will reflect local writes even faster.
      stream: _link.watchConnection(widget.uid),
      builder: (context, snapshot) {
        final conn = snapshot.data;
        var status = conn?.status;
        var requester = conn?.requester;

        var isAccepted = status == LinkUpStatus.accepted;
        var isPending = status == LinkUpStatus.pending;
        var iRequested = isPending && requester == _myUid;
        var theyRequested = isPending && requester == widget.uid;

        // Apply optimistic overrides (instant button state change)
        if (_optimisticPending && !isAccepted) {
          isPending = true;
          iRequested = _optimisticRequester == _myUid;
          theyRequested = _optimisticRequester == widget.uid;
        }

        // Only load photos AFTER acceptance
        if (isAccepted && userPhotos.isEmpty) {
          _loadPhotosIfNeeded();
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(isAccepted ? "👥 Mutual Vibes" : "🔒 Profile Locked"),
          ),
          body:
              isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (isAccepted
                      // ✅ Accepted → render full profile
                      ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            ProfileHeader(
                              profileBase64: profileBase64,
                              name: name,
                              bio: bio,
                              vibeCount: userPhotos.length,
                            ),
                            const Divider(height: 32),
                            ProfileGallery(photos: userPhotos),
                          ],
                        ),
                      )
                      // 🔒 Not accepted → show hard gate only
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
                      )),
        );
      },
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




// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:memscape/models/connection_model.dart';
// import 'package:memscape/models/photo_model.dart';
// import 'package:memscape/services/firestore_service.dart';
// import 'package:memscape/services/link_up_service.dart';
// import 'package:memscape/widgets/blur_guard.dart';
// import 'package:memscape/widgets/linkup_cta.dart';
// import 'package:memscape/widgets/profile_gallery.dart';
// import 'package:memscape/widgets/profile_header.dart';

// class PublicProfileScreen extends StatefulWidget {
//   final String uid; // profile being viewed
//   const PublicProfileScreen({super.key, required this.uid});

//   @override
//   State<PublicProfileScreen> createState() => _PublicProfileScreenState();
// }

// class _PublicProfileScreenState extends State<PublicProfileScreen> {
//   final _auth = FirebaseAuth.instance;
//   final _link = LinkUpService();

//   String name = '';
//   String bio = '';
//   String? profileBase64;
//   List<PhotoModel> userPhotos = [];
//   bool isLoading = true;

//   bool _optimisticPending = false;
//   String? _optimisticRequester; // set to my uid when I send, null otherwise

//   String get _myUid => _auth.currentUser!.uid;

//   @override
//   void initState() {
//     super.initState();
//     _loadProfileAndPhotos();
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
//       // swallow or show a toast
//     }
//   }

//   Future<void> _loadProfileAndPhotos() async {
//     try {
//       // Load profile doc (name, bio, avatar path -> base64 fetch moved into service or kept in FirestoreService if you want)
//       final doc =
//           await FirebaseFirestore.instance
//               .collection('users')
//               .doc(widget.uid)
//               .get();

//       if (doc.exists) {
//         final data = doc.data()!;
//         name = data['name'] ?? '';
//         bio = data['bio'] ?? '';
//         // Optional: if you keep base64 in Realtime DB, you can expose a helper in FirestoreService
//         profileBase64 = await FirestoreService().fetchProfileBase64(
//           data['profileImagePath'],
//         );
//       }

//       final myUid = FirebaseAuth.instance.currentUser!.uid;
//       userPhotos = await FirestoreService().fetchUserPhotosForViewer(
//         ownerUid: widget.uid,
//         viewerUid: myUid,
//       );
//       // No need to filter on client now
//     } catch (e) {
//       debugPrint("❌ Failed to load profile: $e");
//     }

//     if (mounted) setState(() => isLoading = false);
//   }

//   void _toast(String msg) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
//   }

//   @override
//   @override
//   Widget build(BuildContext context) {
//     final isMe = _myUid == widget.uid;

//     if (isMe) {
//       return Scaffold(
//         appBar: AppBar(title: const Text("👤 Your Public Profile")),
//         body:
//             isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : SingleChildScrollView(
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     children: [
//                       ProfileHeader(
//                         profileBase64: profileBase64,
//                         name: name,
//                         bio: bio,
//                         vibeCount: userPhotos.length,
//                       ),
//                       const Divider(height: 32),
//                       ProfileGallery(photos: userPhotos),
//                     ],
//                   ),
//                 ),
//       );
//     }

//     return StreamBuilder(
//       stream: _link.watchConnection(widget.uid),
//       builder: (context, snapshot) {
//         final conn = snapshot.data;
//         final status = conn?.status;
//         final requester = conn?.requester;

//         final isAccepted = status == LinkUpStatus.accepted;
//         final isPending = status == LinkUpStatus.pending;
//         final iRequested = isPending && requester == _myUid;
//         final theyRequested = isPending && requester == widget.uid;

//         // ✅ Only load photos AFTER acceptance
//         if (isAccepted && userPhotos.isEmpty) {
//           _loadPhotosIfNeeded();
//         }

//         return Scaffold(
//           appBar: AppBar(
//             title: Text(isAccepted ? "👥 Mutual Vibes" : "🔒 Profile Locked"),
//           ),
//           body:
//               isLoading
//                   ? const Center(child: CircularProgressIndicator())
//                   : Stack(
//                     children: [
//                       // ✅ If not accepted, show a hard gate — NO profile details at all
//                       if (!isAccepted)
//                         _LockedGate(
//                           isPending: isPending,
//                           iRequested: iRequested,
//                           theyRequested: theyRequested,
//                           onSend: () async {
//                             await _link.sendLinkUp(widget.uid);
//                             _toast("✨ Link‑up sent");
//                           },
//                           onCancel: () async {
//                             await _link.cancelLinkUp(widget.uid);
//                             _toast("Link‑up canceled");
//                           },
//                           onAccept: () async {
//                             await _link.acceptLinkUp(widget.uid);
//                             _toast("You’re mutuals now 🫶");
//                           },
//                           onIgnore: () async {
//                             await _link.ignoreLinkUp(widget.uid);
//                             _toast("Request ignored");
//                           },
//                         ),

//                       // ✅ Accepted → render full profile
//                       if (isAccepted)
//                         SingleChildScrollView(
//                           padding: const EdgeInsets.all(16),
//                           child: Column(
//                             children: [
//                               ProfileHeader(
//                                 profileBase64: profileBase64,
//                                 name: name,
//                                 bio: bio,
//                                 vibeCount: userPhotos.length,
//                               ),
//                               const Divider(height: 32),
//                               ProfileGallery(photos: userPhotos),
//                             ],
//                           ),
//                         ),
//                     ],
//                   ),
//         );
//       },
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





// ------------------------------------




// import 'dart:convert';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:memscape/models/photo_model.dart';
// import 'package:memscape/services/firestore_service.dart';

// class PublicProfileScreen extends StatefulWidget {
//   final String uid;
//   const PublicProfileScreen({super.key, required this.uid});

//   @override
//   State<PublicProfileScreen> createState() => _PublicProfileScreenState();
// }

// class _PublicProfileScreenState extends State<PublicProfileScreen> {
//   String name = '';
//   String bio = '';
//   String? profileBase64;
//   List<PhotoModel> userPhotos = [];
//   bool isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadProfileAndPhotos();
//   }

//   Future<void> _loadProfileAndPhotos() async {
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
//         final profilePath = data['profileImagePath'];
//         if (profilePath != null) {
//           final snap = await FirebaseDatabase.instance.ref(profilePath).get();
//           if (snap.exists) {
//             profileBase64 = snap.value as String;
//           }
//         }
//       }

//       userPhotos = await FirestoreService().fetchUserPhotos(userId: widget.uid);

//       // Filter only public photos
//       userPhotos = userPhotos.where((p) => p.isPublic).toList();
//     } catch (e) {
//       debugPrint("❌ Failed to load profile: $e");
//     }

//     if (mounted) {
//       setState(() => isLoading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);

//     return Scaffold(
//       appBar: AppBar(title: const Text("👤 Public Profile")),
//       body:
//           isLoading
//               ? const Center(child: CircularProgressIndicator())
//               : SingleChildScrollView(
//                 padding: const EdgeInsets.all(16),
//                 child: Column(
//                   children: [
//                     CircleAvatar(
//                       radius: 60,
//                       backgroundImage:
//                           profileBase64 != null
//                               ? MemoryImage(base64Decode(profileBase64!))
//                               : const NetworkImage(
//                                     "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//                                   )
//                                   as ImageProvider,
//                     ),
//                     const SizedBox(height: 12),
//                     Text(name, style: theme.textTheme.titleLarge),
//                     const SizedBox(height: 4),
//                     Text(
//                       bio,
//                       style: theme.textTheme.bodyMedium,
//                       textAlign: TextAlign.center,
//                     ),
//                     const Divider(height: 32),
//                     Align(
//                       alignment: Alignment.centerLeft,
//                       child: Text(
//                         "📸 Public Memories",
//                         style: theme.textTheme.titleMedium,
//                       ),
//                     ),
//                     const SizedBox(height: 12),
//                     if (userPhotos.isEmpty)
//                       const Text("No public photos available.")
//                     else
//                       ...userPhotos.map(
//                         (photo) => Card(
//                           margin: const EdgeInsets.symmetric(vertical: 8),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           elevation: 3,
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               if (photo.imagePath != null)
//                                 FutureBuilder<DatabaseEvent>(
//                                   future:
//                                       FirebaseDatabase.instance
//                                           .ref(photo.imagePath!)
//                                           .once(),
//                                   builder: (context, snapshot) {
//                                     if (snapshot.connectionState ==
//                                         ConnectionState.waiting) {
//                                       return const SizedBox(
//                                         height: 200,
//                                         child: Center(
//                                           child: CircularProgressIndicator(),
//                                         ),
//                                       );
//                                     }

//                                     if (snapshot.hasError ||
//                                         !snapshot.hasData ||
//                                         snapshot.data!.snapshot.value == null) {
//                                       return const SizedBox(
//                                         height: 200,
//                                         child: Center(
//                                           child: Text("⚠️ Image unavailable"),
//                                         ),
//                                       );
//                                     }

//                                     final base64 =
//                                         snapshot.data!.snapshot.value as String;

//                                     return ClipRRect(
//                                       borderRadius: const BorderRadius.vertical(
//                                         top: Radius.circular(12),
//                                       ),
//                                       child: Image.memory(
//                                         base64Decode(base64),
//                                         height: 200,
//                                         width: double.infinity,
//                                         fit: BoxFit.cover,
//                                       ),
//                                     );
//                                   },
//                                 ),
//                               Padding(
//                                 padding: const EdgeInsets.all(12),
//                                 child: Column(
//                                   crossAxisAlignment: CrossAxisAlignment.start,
//                                   children: [
//                                     Text(
//                                       photo.caption,
//                                       style: theme.textTheme.titleMedium,
//                                     ),
//                                     const SizedBox(height: 4),
//                                     Text(
//                                       "📍 ${photo.location}",
//                                       style: theme.textTheme.bodySmall,
//                                     ),
//                                     const SizedBox(height: 4),
//                                     Text(
//                                       "🗓️ ${photo.timestamp.toLocal().toString().split('.')[0]}",
//                                       style: theme.textTheme.bodySmall
//                                           ?.copyWith(
//                                             color: theme.colorScheme.outline,
//                                           ),
//                                     ),
//                                   ],
//                                 ),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                   ],
//                 ),
//               ),
//     );
//   }
// }
