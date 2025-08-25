// lib/screens/home/profile_screen.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'package:memscape/models/photo_model.dart';
import 'package:memscape/screens/home/edit_profile_screen.dart';
import 'package:memscape/screens/home/memories_view_screen.dart';
import 'package:memscape/services/firestore_service.dart';

import 'connections_screen.dart';

/// ─────────────────────────────────────────────────────────────────────────
/// Small in-memory caches to make the profile appear instantly on revisit.
/// Clear on app restart; good enough for UX smoothness.
/// ─────────────────────────────────────────────────────────────────────────
class _MemBytesCache {
  static final Map<String, Uint8List> _bytes = {};
  static Uint8List? get(String key) => _bytes[key];
  static void put(String key, Uint8List value) => _bytes[key] = value;
}

class _ProfileCache {
  static String? username;
  static String? bio;
  static String? profilePath;
  static String? profileBase64;
  static List<PhotoModel>? all;
  static int? connections;
  static DateTime? stamped;

  static const ttl = Duration(seconds: 45);

  static bool get isFresh =>
      stamped != null && DateTime.now().difference(stamped!) < ttl;

  static void set({
    required String username_,
    required String bio_,
    required String? profilePath_,
    required String? profileBase64_,
    required List<PhotoModel> all_,
    required int connections_,
  }) {
    username = username_;
    bio = bio_;
    profilePath = profilePath_;
    profileBase64 = profileBase64_;
    all = List<PhotoModel>.from(all_);
    connections = connections_;
    stamped = DateTime.now();
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  final _rtdb = FirebaseDatabase.instance;

  String username = '';
  String bio = '';
  String? profilePath;
  String? profileBase64;

  bool _loading = true;

  List<PhotoModel> _all = [];
  List<PhotoModel> _pub = [];
  List<PhotoModel> _priv = [];

  int _connectionsCount = 0;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);

    // 1) Try cache for instant paint
    if (_ProfileCache.isFresh && _ProfileCache.all != null) {
      username = _ProfileCache.username ?? '';
      bio = _ProfileCache.bio ?? '';
      profilePath = _ProfileCache.profilePath;
      profileBase64 = _ProfileCache.profileBase64;
      _all = _ProfileCache.all!;
      _all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _pub = _all.where((p) => p.isPublic).toList();
      _priv = _all.where((p) => !p.isPublic).toList();
      _connectionsCount = _ProfileCache.connections ?? 0;
      _loading = false;
      // schedule a refresh but don't block first frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    } else {
      // 2) No cache → load
      _refresh();
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final me = _auth.currentUser!;
    try {
      // profile
      final u = await _db.collection('users').doc(me.uid).get();
      final data = u.data() ?? {};
      final username_ = (data['username'] ?? '').toString();
      final bio_ = (data['bio'] ?? '').toString();
      final profilePath_ = (data['profileImagePath'] ?? '').toString();

      String? profileBase64_;
      if (profilePath_.isNotEmpty) {
        final snap = await _rtdb.ref(profilePath_).get();
        if (snap.exists) profileBase64_ = snap.value as String?;
      }

      // photos
      final all_ = await FirestoreService().fetchUserPhotos(userId: me.uid);
      all_.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      final pub_ = all_.where((p) => p.isPublic).toList();
      final priv_ = all_.where((p) => !p.isPublic).toList();

      // connections count (accepted only)
      final cons =
          await _db
              .collection('connections')
              .where('users', arrayContains: me.uid)
              .where('status', isEqualTo: 'accepted')
              .get();
      final connections_ = cons.size;

      if (!mounted) return;
      setState(() {
        username = username_;
        bio = bio_;
        profilePath = profilePath_;
        profileBase64 = profileBase64_;
        _all = all_;
        _pub = pub_;
        _priv = priv_;
        _connectionsCount = connections_;
        _loading = false;
      });

      // update cache
      _ProfileCache.set(
        username_: username_,
        bio_: bio_,
        profilePath_: profilePath_,
        profileBase64_: profileBase64_,
        all_: all_,
        connections_: connections_,
      );
    } catch (e) {
      debugPrint('❌ load profile error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  ImageProvider get _avatar =>
      (profileBase64 != null && profileBase64!.isNotEmpty)
          ? MemoryImage(base64Decode(profileBase64!))
          : const NetworkImage(
                "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
              )
              as ImageProvider;

  @override
  Widget build(BuildContext context) {
    final photosCount = _all.length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                  onRefresh: _refresh,
                  child: NestedScrollView(
                    headerSliverBuilder: (context, innerScrolled) {
                      return [
                        SliverAppBar(
                          title: const Text("My Profile"),
                          floating: true,
                          snap: true,
                          actions: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EditProfileScreen(),
                                  ),
                                );
                              },
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'logout') {
                                  final ok = await showDialog<bool>(
                                    context: context,
                                    builder:
                                        (_) => AlertDialog(
                                          title: const Text("Confirm Logout"),
                                          content: const Text(
                                            "Are you sure you want to log out?",
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    false,
                                                  ),
                                              child: const Text("Cancel"),
                                            ),
                                            TextButton(
                                              onPressed:
                                                  () => Navigator.pop(
                                                    context,
                                                    true,
                                                  ),
                                              child: const Text("Logout"),
                                            ),
                                          ],
                                        ),
                                  );
                                  if (ok == true) {
                                    await FirebaseAuth.instance.signOut();
                                    if (context.mounted) {
                                      Navigator.of(
                                        context,
                                      ).popUntil((r) => r.isFirst);
                                    }
                                  }
                                }
                              },
                              itemBuilder:
                                  (_) => const [
                                    PopupMenuItem(
                                      value: 'logout',
                                      child: Text('Logout'),
                                    ),
                                  ],
                            ),
                          ],
                        ),
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              const SizedBox(height: 20),
                              CircleAvatar(
                                radius: 50,
                                backgroundImage: _avatar,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                username.isEmpty ? "user" : username,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (bio.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    bio,
                                    style: const TextStyle(color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              const SizedBox(height: 16),

                              // Stats row (Photos then Vibes (linked))
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _StatInline(
                                      label: "Photos",
                                      count: photosCount,
                                      onTap: null,
                                    ),
                                    const SizedBox(width: 18),
                                    _StatInline(
                                      label: "Vibes",
                                      count: _connectionsCount,
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) =>
                                                    const ConnectionsScreen(),
                                          ),
                                        );
                                      },
                                      subtitle: "linked",
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),
                              const Divider(height: 1),

                              // Posts heading
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "Posts",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _TabBarDelegate(
                            const TabBar(
                              tabs: [
                                Tab(text: "Public"),
                                // keep swipable
                                Tab(text: "Private"),
                              ],
                            ),
                          ),
                        ),
                      ];
                    },
                    body: TabBarView(
                      controller: _tabs,
                      children: [
                        _PhotoGridTab(
                          photos: _pub,
                          onOpen: (index, showing) {
                            final paths =
                                showing
                                    .map((p) => p.imagePath)
                                    .whereType<String>()
                                    .where((p) => p.isNotEmpty)
                                    .toList();
                            if (paths.isEmpty) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => MemoriesViewScreen(
                                      items: paths,
                                      initialIndex: index,
                                    ),
                              ),
                            );
                          },
                        ),
                        _PhotoGridTab(
                          photos: _priv,
                          onOpen: (index, showing) {
                            final paths =
                                showing
                                    .map((p) => p.imagePath)
                                    .whereType<String>()
                                    .where((p) => p.isNotEmpty)
                                    .toList();
                            if (paths.isEmpty) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => MemoriesViewScreen(
                                      items: paths,
                                      initialIndex: index,
                                    ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  const _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

class _StatInline extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback? onTap;
  final String? subtitle;

  const _StatInline({
    required this.label,
    required this.count,
    this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(
          '$count',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            if (subtitle != null) ...[
              const SizedBox(width: 6),
              Text(
                '($subtitle)',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
      ],
    );

    return onTap == null
        ? content
        : InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: content,
          ),
        );
  }
}

/// One tab page that displays a grid; keeps state alive for snappy switching.
class _PhotoGridTab extends StatefulWidget {
  final List<PhotoModel> photos;
  final void Function(int index, List<PhotoModel> showing) onOpen;

  const _PhotoGridTab({required this.photos, required this.onOpen});

  @override
  State<_PhotoGridTab> createState() => _PhotoGridTabState();
}

class _PhotoGridTabState extends State<_PhotoGridTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Future<Uint8List?> _loadBytes(String path) async {
    final cached = _MemBytesCache.get(path);
    if (cached != null) return cached;

    // Try FirestoreService helper (RTDB indirection)
    try {
      final base64 = await FirestoreService().fetchImageBase64(path);
      if (base64 != null && base64.isNotEmpty) {
        final bytes = base64Decode(base64);
        _MemBytesCache.put(path, bytes);
        return bytes;
      }
    } catch (_) {}

    try {
      final snap = await FirebaseDatabase.instance.ref(path).get();
      if (snap.exists && snap.value != null) {
        final bytes = base64Decode(snap.value as String);
        _MemBytesCache.put(path, bytes);
        return bytes;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.photos.isEmpty) {
      return const Center(child: Text("Nothing here yet."));
    }

    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: widget.photos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (context, index) {
        final p = widget.photos[index];
        final path = p.imagePath;
        if (path == null || path.isEmpty) {
          return const Icon(Icons.broken_image);
        }

        return FutureBuilder<Uint8List?>(
          future: _loadBytes(path),
          builder: (context, snap) {
            if (!snap.hasData) {
              return Container(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceVariant.withOpacity(0.4),
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1),
                  ),
                ),
              );
            }
            final bytes = snap.data!;
            return GestureDetector(
              onTap: () => widget.onOpen(index, widget.photos),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:memscape/screens/home/edit_profile_screen.dart';
// import 'package:memscape/screens/home/followers_list_screen.dart';
// import 'package:memscape/screens/home/following_feed_screen.dart';
// import 'package:memscape/screens/home/memories_view_screen.dart';

// class ProfileScreen extends StatefulWidget {
//   const ProfileScreen({super.key});

//   @override
//   State<ProfileScreen> createState() => _ProfileScreenState();
// }

// class _ProfileScreenState extends State<ProfileScreen> {
//   final user = FirebaseAuth.instance.currentUser!;
//   String name = '';
//   String bio = '';
//   String? imagePath;
//   String? imageBase64;
//   List<String> photoRefs = [];

//   final realtimeDB = FirebaseDatabase.instance;

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
//               .doc(user.uid)
//               .get();
//       if (doc.exists) {
//         // final data = doc.data()!;
//         // name = data['name'] ?? '';
//         // bio = data['bio'] ?? '';
//         // imagePath = data['profileImagePath'];
//         // photoRefs = List<String>.from(data['photoRefs'] ?? []);

//         // if (imagePath != null && imagePath!.isNotEmpty) {
//         //   final snapshot = await realtimeDB.ref(imagePath!).get();
//         //   if (snapshot.exists) {
//         //     imageBase64 = snapshot.value as String;
//         //   }
//         // }
//         final data = doc.data()!;
//         name = data['name'] ?? '';
//         bio = data['bio'] ?? '';
//         imagePath = data['profileImagePath'];
//         photoRefs = List<String>.from(data['photoRefs'] ?? []);
//         photoRefs = photoRefs.reversed.toList(); // 👈 latest first

//         if (imagePath != null && imagePath!.isNotEmpty) {
//           final snapshot = await realtimeDB.ref(imagePath!).get();
//           if (snapshot.exists) {
//             imageBase64 = snapshot.value as String;
//           }
//         }
//       }
//     } catch (e) {
//       debugPrint("❌ Error loading profile: $e");
//     }
//     if (mounted) setState(() {});
//   }

//   @override
//   Widget build(BuildContext context) {
//     final imageProvider =
//         imageBase64 != null
//             ? MemoryImage(base64Decode(imageBase64!))
//             : const NetworkImage(
//                   "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
//                 )
//                 as ImageProvider;

//     return Scaffold(
//       // appBar: AppBar(
//       //   title: const Text("My Profile"),
//       //   actions: [
//       //     IconButton(
//       //       icon: const Icon(Icons.edit),
//       //       onPressed: () {
//       //         Navigator.push(
//       //           context,
//       //           MaterialPageRoute(builder: (_) => const EditProfileScreen()),
//       //         );
//       //       },
//       //     ),
//       //   ],
//       // ),
//       appBar: AppBar(
//         title: const Text("My Profile"),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.edit),
//             onPressed: () {
//               Navigator.push(
//                 context,
//                 MaterialPageRoute(builder: (_) => const EditProfileScreen()),
//               );
//             },
//           ),
//           PopupMenuButton<String>(
//             onSelected: (value) {
//               if (value == 'logout') {
//                 showDialog(
//                   context: context,
//                   builder:
//                       (context) => AlertDialog(
//                         title: const Text("Confirm Logout"),
//                         content: const Text(
//                           "Are you sure you want to log out?",
//                         ),
//                         actions: [
//                           TextButton(
//                             onPressed: () => Navigator.pop(context),
//                             child: const Text("Cancel"),
//                           ),
//                           TextButton(
//                             onPressed: () {
//                               FirebaseAuth.instance.signOut();
//                               Navigator.of(
//                                 context,
//                               ).popUntil((route) => route.isFirst);
//                             },
//                             child: const Text("Logout"),
//                           ),
//                         ],
//                       ),
//                 );
//               }
//             },
//             itemBuilder:
//                 (context) => [
//                   const PopupMenuItem(value: 'logout', child: Text('Logout')),
//                 ],
//           ),
//         ],
//       ),

//       body: SingleChildScrollView(
//         child: Column(
//           children: [
//             const SizedBox(height: 20),
//             CircleAvatar(radius: 50, backgroundImage: imageProvider),
//             const SizedBox(height: 10),
//             Text(
//               name,
//               style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//             ),
//             Text(bio, style: const TextStyle(color: Colors.grey)),
//             const SizedBox(height: 20),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 _buildStat("Photos", photoRefs.length),
//                 GestureDetector(
//                   onTap:
//                       () => Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (_) => const FollowersListScreen(),
//                         ),
//                       ),
//                   child: _buildStat("Followers", 0),
//                 ),
//                 GestureDetector(
//                   onTap:
//                       () => Navigator.push(
//                         context,
//                         MaterialPageRoute(
//                           builder: (_) => const FollowingFeedScreen(),
//                         ),
//                       ),
//                   child: _buildStat("Following", 0),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 30),
//             const Divider(),
//             const Padding(
//               padding: EdgeInsets.symmetric(horizontal: 16.0),
//               child: Align(
//                 alignment: Alignment.centerLeft,
//                 child: Text(
//                   "Posts",
//                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                 ),
//               ),
//             ),
//             const SizedBox(height: 10),

//             // GestureDetector(
//             //   onTap: () {
//             //     // debugPrint("🟢 Opening MemoriesViewScreen at index $index");

//             //     Navigator.push(
//             //       context,
//             //       MaterialPageRoute(
//             //         builder: (_) => MemoriesViewScreen(photo: photo),
//             //       ),
//             //     );
//             //   },

//             //   child: _buildPhotoGrid(),
//             // ),
//             _buildPhotoGrid(),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildStat(String label, int count) {
//     return Column(
//       children: [
//         Text(
//           '$count',
//           style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//         ),
//         Text(label, style: const TextStyle(color: Colors.grey)),
//       ],
//     );
//   }

//   Widget _buildPhotoGrid() {
//     if (photoRefs.isEmpty) {
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
//         itemCount: photoRefs.length,
//         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//           crossAxisCount: 3,
//           mainAxisSpacing: 6,
//           crossAxisSpacing: 6,
//         ),
//         itemBuilder: (context, index) {
//           final refPath = "images/${photoRefs[index]}";
//           return FutureBuilder<DataSnapshot>(
//             future: realtimeDB.ref(refPath).get(),
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
//               final imageBytes = base64Decode(base64String);

//               // inside _PhotoGrid itemBuilder (where you currently push the screen)
//               return GestureDetector(
//                 onTap: () {
//                   // photoRefs is a List<String> of IDs. Convert to DB paths.
//                   final paths = photoRefs.map((id) => "images/$id").toList();

//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(
//                       builder:
//                           (_) => MemoriesViewScreen(
//                             items: paths, // <-- full "images/<id>" paths
//                             initialIndex: index,
//                           ),
//                     ),
//                   );
//                 },
//                 child: ClipRRect(
//                   borderRadius: BorderRadius.circular(6),
//                   child: Image.memory(imageBytes, fit: BoxFit.cover),
//                 ),
//               );
//               // return GestureDetector(
//               //   onTap: () {
//               //     Navigator.push(
//               //       context,
//               //       MaterialPageRoute(
//               //         builder:
//               //             (_) => MemoriesViewScreen(photoBase64: base64String),
//               //       ),
//               //     );
//               //   },
//               //   child: ClipRRect(
//               //     borderRadius: BorderRadius.circular(6),
//               //     child: Image.memory(imageBytes, fit: BoxFit.cover),
//               //   ),
//               // );
//             },
//           );
//         },
//       ),
//     );
//   }

// }
