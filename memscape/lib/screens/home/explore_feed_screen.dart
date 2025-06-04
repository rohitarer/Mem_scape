import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/services/firestore_service.dart';
import 'package:memscape/widgets/photo_card.dart';

class ExploreFeedScreen extends ConsumerStatefulWidget {
  const ExploreFeedScreen({super.key});

  @override
  ConsumerState<ExploreFeedScreen> createState() => _ExploreFeedScreenState();
}

class _ExploreFeedScreenState extends ConsumerState<ExploreFeedScreen> {
  List<PhotoModel> publicPhotos = [];
  bool isLoading = true;
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    loadPublicPhotos();
  }

  Future<void> loadPublicPhotos() async {
    try {
      final photos = await FirestoreService().fetchPublicPhotos();
      if (mounted) {
        setState(() {
          publicPhotos = photos;
          isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("❌ Failed to load public photos: $e");
    }
  }

  void showCommentsSheet(
    BuildContext context,
    String photoId,
    List<Map<String, dynamic>> comments,
  ) {
    final controller = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (_) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Comments",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ...comments.map(
                  (c) => ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(c['text'] ?? ''),
                    subtitle: Text(
                      '${c['uid']} • ${DateTime.tryParse(c['timestamp'] ?? '')?.toLocal().toString().split('.')[0] ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const Divider(),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: "Add a comment...",
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (controller.text.trim().isNotEmpty) {
                      await FirestoreService().addComment(
                        photoId,
                        currentUserId,
                        controller.text.trim(),
                      );
                      Navigator.pop(context);
                      await loadPublicPhotos();
                    }
                  },
                  child: const Text("Post"),
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🌐 Explore Memories")),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : publicPhotos.isEmpty
              ? const Center(child: Text("No public memories yet."))
              : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: publicPhotos.length,
                itemBuilder: (_, index) {
                  final photo = publicPhotos[index];
                  final isLiked = photo.likes.contains(currentUserId);
                  final photoId =
                      "${photo.caption}_${photo.timestamp.millisecondsSinceEpoch}";

                  return FutureBuilder<DocumentSnapshot>(
                    future:
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(photo.uid)
                            .get(),
                    builder: (context, snapshot) {
                      final userData =
                          snapshot.data?.data() as Map<String, dynamic>?;

                      final username = userData?['username'] ?? photo.uid;
                      final profileImage = userData?['profileImageUrl'];

                      return PhotoCard(photo: publicPhotos[index]);

                      // return Card(
                      //   margin: const EdgeInsets.only(bottom: 16),
                      //   shape: RoundedRectangleBorder(
                      //     borderRadius: BorderRadius.circular(16),
                      //   ),
                      //   elevation: 3,
                      //   child: Column(
                      //     crossAxisAlignment: CrossAxisAlignment.start,
                      //     children: [
                      //       ClipRRect(
                      //         borderRadius: const BorderRadius.vertical(
                      //           top: Radius.circular(16),
                      //         ),
                      //         child: Image.memory(
                      //           base64Decode(photo.imageBase64 ?? ''),
                      //           height: 200,
                      //           width: double.infinity,
                      //           fit: BoxFit.cover,
                      //         ),
                      //       ),
                      //       Padding(
                      //         padding: const EdgeInsets.all(12),
                      //         child: Column(
                      //           crossAxisAlignment: CrossAxisAlignment.start,
                      //           children: [
                      //             Row(
                      //               children: [
                      //                 GestureDetector(
                      //                   onTap:
                      //                       () => Navigator.push(
                      //                         context,
                      //                         MaterialPageRoute(
                      //                           builder:
                      //                               (_) => PublicProfileScreen(
                      //                                 uid: photo.uid,
                      //                               ),
                      //                         ),
                      //                       ),
                      //                   child: CircleAvatar(
                      //                     radius: 16,
                      //                     backgroundImage:
                      //                         profileImage != null &&
                      //                                 profileImage.isNotEmpty
                      //                             ? NetworkImage(profileImage)
                      //                             : const AssetImage(
                      //                                   "assets/default_user.png",
                      //                                 )
                      //                                 as ImageProvider,
                      //                   ),
                      //                 ),
                      //                 const SizedBox(width: 8),
                      //                 Expanded(
                      //                   child: GestureDetector(
                      //                     onTap:
                      //                         () => Navigator.push(
                      //                           context,
                      //                           MaterialPageRoute(
                      //                             builder:
                      //                                 (_) =>
                      //                                     PublicProfileScreen(
                      //                                       uid: photo.uid,
                      //                                     ),
                      //                           ),
                      //                         ),
                      //                     child: Text(
                      //                       username,
                      //                       style:
                      //                           Theme.of(
                      //                             context,
                      //                           ).textTheme.bodyMedium,
                      //                     ),
                      //                   ),
                      //                 ),
                      //                 if (photo.uid != currentUserId)
                      //                   FutureBuilder<bool>(
                      //                     future: FirestoreService()
                      //                         .isFollowing(
                      //                           currentUserId,
                      //                           photo.uid,
                      //                         ),
                      //                     builder: (context, snapshot) {
                      //                       final isFollowing =
                      //                           snapshot.data ?? false;
                      //                       return TextButton(
                      //                         onPressed: () async {
                      //                           await FirestoreService()
                      //                               .toggleFollow(
                      //                                 currentUserId,
                      //                                 photo.uid,
                      //                               );
                      //                           setState(() {});
                      //                         },
                      //                         child: Text(
                      //                           isFollowing
                      //                               ? 'Unfollow'
                      //                               : 'Follow',
                      //                         ),
                      //                       );
                      //                     },
                      //                   ),
                      //               ],
                      //             ),
                      //             const SizedBox(height: 8),
                      //             Text(
                      //               photo.caption,
                      //               style:
                      //                   Theme.of(context).textTheme.titleMedium,
                      //             ),
                      //             const SizedBox(height: 4),
                      //             Text(
                      //               "📍 ${photo.location}",
                      //               style: Theme.of(
                      //                 context,
                      //               ).textTheme.bodySmall?.copyWith(
                      //                 color:
                      //                     Theme.of(context).colorScheme.outline,
                      //               ),
                      //             ),
                      //             const Divider(height: 20),
                      //             Row(
                      //               mainAxisAlignment:
                      //                   MainAxisAlignment.spaceAround,
                      //               children: [
                      //                 IconButton(
                      //                   onPressed: () async {
                      //                     await FirestoreService().toggleLike(
                      //                       photoId,
                      //                       currentUserId,
                      //                     );
                      //                     await loadPublicPhotos();
                      //                   },
                      //                   icon: Icon(
                      //                     isLiked
                      //                         ? Icons.favorite
                      //                         : Icons.favorite_border,
                      //                     color: isLiked ? Colors.red : null,
                      //                   ),
                      //                 ),
                      //                 Text("${photo.likes.length} Likes"),
                      //                 IconButton(
                      //                   onPressed:
                      //                       () => showCommentsSheet(
                      //                         context,
                      //                         photoId,
                      //                         photo.comments,
                      //                       ),
                      //                   icon: const Icon(
                      //                     Icons.comment_outlined,
                      //                   ),
                      //                 ),
                      //                 Text("${photo.comments.length} Comments"),
                      //               ],
                      //             ),
                      //           ],
                      //         ),
                      //       ),
                      //     ],
                      //   ),
                      // );
                    },
                  );
                },
              ),
    );
  }
}

// import 'dart:convert';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:memscape/models/photo_model.dart';
// import 'package:memscape/screens/home/public_profile_screen.dart';
// import 'package:memscape/services/firestore_service.dart';

// class ExploreFeedScreen extends ConsumerStatefulWidget {
//   const ExploreFeedScreen({super.key});

//   @override
//   ConsumerState<ExploreFeedScreen> createState() => _ExploreFeedScreenState();
// }

// class _ExploreFeedScreenState extends ConsumerState<ExploreFeedScreen> {
//   List<PhotoModel> publicPhotos = [];
//   bool isLoading = true;
//   final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

//   @override
//   void initState() {
//     super.initState();
//     loadPublicPhotos();
//   }

//   Future<void> loadPublicPhotos() async {
//     try {
//       final photos = await FirestoreService().fetchPublicPhotos();
//       if (mounted) {
//         setState(() {
//           publicPhotos = photos;
//           isLoading = false;
//         });
//       }
//     } catch (e) {
//       debugPrint("❌ Failed to load public photos: $e");
//     }
//   }

//   void showCommentsSheet(
//     BuildContext context,
//     String photoId,
//     List<Map<String, dynamic>> comments,
//   ) {
//     final controller = TextEditingController();

//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       shape: const RoundedRectangleBorder(
//         borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
//       ),
//       builder:
//           (_) => Padding(
//             padding: EdgeInsets.only(
//               left: 16,
//               right: 16,
//               top: 16,
//               bottom: MediaQuery.of(context).viewInsets.bottom + 16,
//             ),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 const Text(
//                   "Comments",
//                   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                 ),
//                 const SizedBox(height: 12),
//                 ...comments.map(
//                   (c) => ListTile(
//                     leading: const Icon(Icons.person_outline),
//                     title: Text(c['text'] ?? ''),
//                     subtitle: Text(
//                       '${c['uid']} • ${DateTime.tryParse(c['timestamp'] ?? '')?.toLocal().toString().split('.')[0] ?? ''}',
//                       style: const TextStyle(fontSize: 12),
//                     ),
//                   ),
//                 ),
//                 const Divider(),
//                 TextField(
//                   controller: controller,
//                   decoration: const InputDecoration(
//                     hintText: "Add a comment...",
//                   ),
//                 ),
//                 const SizedBox(height: 8),
//                 ElevatedButton(
//                   onPressed: () async {
//                     if (controller.text.trim().isNotEmpty) {
//                       await FirestoreService().addComment(
//                         photoId,
//                         currentUserId,
//                         controller.text.trim(),
//                       );
//                       Navigator.pop(context);
//                       await loadPublicPhotos();
//                     }
//                   },
//                   child: const Text("Post"),
//                 ),
//               ],
//             ),
//           ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("🌐 Explore Memories")),
//       body:
//           isLoading
//               ? const Center(child: CircularProgressIndicator())
//               : publicPhotos.isEmpty
//               ? const Center(child: Text("No public memories yet."))
//               : ListView.builder(
//                 padding: const EdgeInsets.all(16),
//                 itemCount: publicPhotos.length,
//                 itemBuilder: (_, index) {
//                   final photo = publicPhotos[index];
//                   final isLiked = photo.likes.contains(currentUserId);
//                   final photoId =
//                       "${photo.caption}_${photo.timestamp.millisecondsSinceEpoch}";

//                   return Card(
//                     margin: const EdgeInsets.only(bottom: 16),
//                     shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(16),
//                     ),
//                     elevation: 3,
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         ClipRRect(
//                           borderRadius: const BorderRadius.vertical(
//                             top: Radius.circular(16),
//                           ),
//                           child: Image.memory(
//                             base64Decode(photo.imageBase64 ?? ''),
//                             height: 200,
//                             width: double.infinity,
//                             fit: BoxFit.cover,
//                           ),
//                         ),
//                         Padding(
//                           padding: const EdgeInsets.all(12),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               Row(
//                                 children: [
//                                   GestureDetector(
//                                     onTap:
//                                         () => Navigator.push(
//                                           context,
//                                           MaterialPageRoute(
//                                             builder:
//                                                 (_) => PublicProfileScreen(
//                                                   uid: photo.uid,
//                                                 ),
//                                           ),
//                                         ),
//                                     child: FutureBuilder<DocumentSnapshot>(
//                                       future:
//                                           FirebaseFirestore.instance
//                                               .collection('users')
//                                               .doc(photo.uid)
//                                               .get(),
//                                       builder: (context, snapshot) {
//                                         if (snapshot.hasData &&
//                                             snapshot.data?.data() != null) {
//                                           final userData =
//                                               snapshot.data!.data()
//                                                   as Map<String, dynamic>;
//                                           final profileUrl =
//                                               userData['profileImageUrl'];
//                                           return CircleAvatar(
//                                             radius: 16,
//                                             backgroundImage:
//                                                 profileUrl != null &&
//                                                         profileUrl != ''
//                                                     ? NetworkImage(profileUrl)
//                                                     : const AssetImage(
//                                                           "assets/default_user.png",
//                                                         )
//                                                         as ImageProvider,
//                                           );
//                                         }
//                                         return const CircleAvatar(
//                                           radius: 16,
//                                           backgroundImage: AssetImage(
//                                             "assets/default_user.png",
//                                           ),
//                                         );
//                                       },
//                                     ),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   Expanded(
//                                     child: GestureDetector(
//                                       onTap:
//                                           () => Navigator.push(
//                                             context,
//                                             MaterialPageRoute(
//                                               builder:
//                                                   (_) => PublicProfileScreen(
//                                                     uid: photo.uid,
//                                                   ),
//                                             ),
//                                           ),
//                                       child: Text(
//                                         photo.uid,
//                                         style:
//                                             Theme.of(
//                                               context,
//                                             ).textTheme.bodyMedium,
//                                       ),
//                                     ),
//                                   ),
//                                   const SizedBox(width: 8),
//                                   if (photo.uid != currentUserId)
//                                     FutureBuilder<bool>(
//                                       future: FirestoreService().isFollowing(
//                                         currentUserId,
//                                         photo.uid,
//                                       ),
//                                       builder: (context, snapshot) {
//                                         final isFollowing =
//                                             snapshot.data ?? false;
//                                         return TextButton(
//                                           onPressed: () async {
//                                             await FirestoreService()
//                                                 .toggleFollow(
//                                                   currentUserId,
//                                                   photo.uid,
//                                                 );
//                                             setState(() {});
//                                           },
//                                           child: Text(
//                                             isFollowing ? 'Unfollow' : 'Follow',
//                                           ),
//                                         );
//                                       },
//                                     ),
//                                 ],
//                               ),
//                               const SizedBox(height: 8),
//                               Text(
//                                 photo.caption,
//                                 style: Theme.of(context).textTheme.titleMedium,
//                               ),
//                               const SizedBox(height: 4),
//                               Text(
//                                 "📍 ${photo.location}",
//                                 style: Theme.of(
//                                   context,
//                                 ).textTheme.bodySmall?.copyWith(
//                                   color: Theme.of(context).colorScheme.outline,
//                                 ),
//                               ),
//                               const Divider(height: 20),
//                               Row(
//                                 mainAxisAlignment:
//                                     MainAxisAlignment.spaceAround,
//                                 children: [
//                                   IconButton(
//                                     onPressed: () async {
//                                       await FirestoreService().toggleLike(
//                                         photoId,
//                                         currentUserId,
//                                       );
//                                       await loadPublicPhotos();
//                                     },
//                                     icon: Icon(
//                                       isLiked
//                                           ? Icons.favorite
//                                           : Icons.favorite_border,
//                                       color: isLiked ? Colors.red : null,
//                                     ),
//                                   ),
//                                   Text("${photo.likes.length} Likes"),
//                                   IconButton(
//                                     onPressed:
//                                         () => showCommentsSheet(
//                                           context,
//                                           photoId,
//                                           photo.comments,
//                                         ),
//                                     icon: const Icon(Icons.comment_outlined),
//                                   ),
//                                   Text("${photo.comments.length} Comments"),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                       ],
//                     ),
//                   );
//                 },
//               ),
//       bottomNavigationBar: BottomNavigationBar(
//         currentIndex: 1,
//         items: const [
//           BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
//           BottomNavigationBarItem(icon: Icon(Icons.explore), label: "Explore"),
//           BottomNavigationBarItem(icon: Icon(Icons.upload), label: "Upload"),
//         ],
//         onTap: (index) {
//           // Handle navigation
//         },
//       ),
//     );
//   }
// }
