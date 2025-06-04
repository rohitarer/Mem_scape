import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:memscape/core/themes.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import '../models/photo_model.dart';
import '../services/firestore_service.dart';

class PhotoCard extends StatefulWidget {
  final PhotoModel photo;
  const PhotoCard({super.key, required this.photo});

  @override
  State<PhotoCard> createState() => _PhotoCardState();
}

class _PhotoCardState extends State<PhotoCard> {
  late Future<String?> _imageFuture;
  late Future<Map<String, dynamic>?> _userFuture;
  final currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController _commentController = TextEditingController();

  // @override
  // void initState() {
  //   super.initState();
  //   _imageFuture = FirestoreService().fetchImageBase64(widget.photo.imagePath!);
  //   _userFuture = FirebaseFirestore.instance
  //       .collection('users')
  //       .doc(widget.photo.uid)
  //       .get()
  //       .then((doc) => doc.data());
  // }

  @override
  void initState() {
    super.initState();

    final imagePath = widget.photo.imagePath;
    final uid = widget.photo.uid;

    _imageFuture =
        (imagePath != null && imagePath.isNotEmpty)
            ? FirestoreService().fetchImageBase64(imagePath)
            : Future.value(null);

    _userFuture =
        (uid.isNotEmpty)
            ? FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .get()
                .then((doc) => doc.data())
            : Future.value(null);
  }

  bool get isLiked => widget.photo.likes.contains(currentUser?.uid);

  Future<bool> requestGalleryPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      return sdkInt >= 33
          ? await Permission.photos.request().isGranted
          : await Permission.storage.request().isGranted;
    } else if (Platform.isIOS) {
      return await Permission.photosAddOnly.request().isGranted;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder(
      future: Future.wait([_imageFuture, _userFuture]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final imageBase64 = snapshot.data![0] as String?;
        final user = snapshot.data![1] as Map<String, dynamic>?;
        if (imageBase64 == null || user == null) {
          return const Center(child: Text("Failed to load image or user."));
        }

        final imageBytes = base64Decode(imageBase64);
        final username = user['username'] ?? 'User';
        final profileImagePath = user['profileImagePath'] ?? '';

        return Container(
          color: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// 🔹 Header
              Padding(
                padding: const EdgeInsets.all(12),
                child:
                // Row(
                //   children: [
                //     FutureBuilder<String?>(
                //       future: FirestoreService().fetchImageBase64(
                //         profileImagePath,
                //       ),
                //       builder: (context, profileSnap) {
                //         if (profileSnap.hasData && profileSnap.data != null) {
                //           return CircleAvatar(
                //             radius: 20,
                //             backgroundImage: MemoryImage(
                //               base64Decode(profileSnap.data!),
                //             ),
                //           );
                //         }
                //         return const CircleAvatar(
                //           radius: 20,
                //           backgroundImage: NetworkImage(
                //             "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                //           ),
                //         );
                //       },
                //     ),
                //     const SizedBox(width: 10),
                //     Column(
                //       crossAxisAlignment: CrossAxisAlignment.start,
                //       children: [
                //         Text(
                //           username,
                //           style: const TextStyle(fontWeight: FontWeight.bold),
                //         ),
                //         if (widget.photo.location.isNotEmpty)
                //           Text(
                //             widget.photo.location,
                //             style: const TextStyle(color: Colors.grey),
                //           ),
                //       ],
                //     ),
                //     const Spacer(),
                //     const Icon(Icons.more_vert),
                //   ],
                // ),
                Row(
                  children: [
                    FutureBuilder<String?>(
                      future: FirestoreService().fetchImageBase64(
                        profileImagePath,
                      ),
                      builder: (context, profileSnap) {
                        if (profileSnap.hasData && profileSnap.data != null) {
                          return CircleAvatar(
                            radius: 20,
                            backgroundImage: MemoryImage(
                              base64Decode(profileSnap.data!),
                            ),
                          );
                        }
                        return const CircleAvatar(
                          radius: 20,
                          backgroundImage: NetworkImage(
                            "https://www.pngall.com/wp-content/uploads/5/Profile-Avatar-PNG.png",
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (widget.photo.location.isNotEmpty)
                            Text(
                              widget.photo.location,
                              style: const TextStyle(color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'download') {
                          try {
                            final imageBase64 = await _imageFuture;
                            if (imageBase64 == null) return;

                            final hasPermission =
                                await requestGalleryPermission();
                            if (!hasPermission) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("❌ Permission denied"),
                                ),
                              );
                              return;
                            }

                            final Uint8List bytes = base64Decode(imageBase64);

                            final result = await SaverGallery.saveImage(
                              bytes,
                              quality: 90,
                              fileName:
                                  "memscape_${widget.photo.id}.jpg", // ✅ correct param name
                              androidRelativePath: "Pictures/Memscape",
                              skipIfExists: false,
                            );

                            debugPrint('✅ Save result: $result');

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("✅ Image saved to gallery"),
                                ),
                              );
                            }
                          } catch (e) {
                            debugPrint("❌ Error: $e");
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text("❌ Error saving image: $e"),
                                ),
                              );
                            }
                          }
                        }
                      },
                      itemBuilder:
                          (context) => [
                            const PopupMenuItem(
                              value: 'download',
                              child: Row(
                                children: [
                                  Icon(Icons.download, size: 18),
                                  SizedBox(width: 8),
                                  Text('Download'),
                                ],
                              ),
                            ),
                          ],
                    ),
                  ],
                ),
              ),

              /// 🔹 Main Image
              Image.memory(
                imageBytes,
                width: double.infinity,
                height: 250,
                fit: BoxFit.cover,
              ),

              /// 🔹 Like & Comment Buttons
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked ? Colors.red : null,
                      ),
                      onPressed:
                          currentUser == null
                              ? null
                              : () async {
                                await FirestoreService().toggleLike(
                                  widget.photo.id!,
                                  currentUser!.uid,
                                );
                                setState(() {
                                  if (widget.photo.likes.contains(
                                    currentUser!.uid,
                                  )) {
                                    widget.photo.likes.remove(currentUser!.uid);
                                  } else {
                                    widget.photo.likes.add(currentUser!.uid);
                                  }
                                });
                              },
                    ),
                    IconButton(
                      icon: const Icon(Icons.comment_outlined),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          builder:
                              (context) => DraggableScrollableSheet(
                                initialChildSize: 0.6,
                                maxChildSize: 0.95,
                                minChildSize: 0.4,
                                expand: false,
                                builder:
                                    (context, scrollController) => Padding(
                                      padding:
                                          MediaQuery.of(context).viewInsets,
                                      child: SingleChildScrollView(
                                        controller: scrollController,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(height: 12),
                                            const Text(
                                              "Comments",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: TextField(
                                                controller: _commentController,
                                                decoration: InputDecoration(
                                                  hintText: "Add a comment...",
                                                  suffixIcon: IconButton(
                                                    icon: const Icon(
                                                      Icons.send,
                                                    ),
                                                    onPressed: () async {
                                                      if (currentUser != null &&
                                                          _commentController
                                                              .text
                                                              .trim()
                                                              .isNotEmpty) {
                                                        await FirestoreService()
                                                            .addComment(
                                                              widget.photo.id!,
                                                              currentUser!.uid,
                                                              _commentController
                                                                  .text
                                                                  .trim(),
                                                            );
                                                        _commentController
                                                            .clear();
                                                        setState(() {});
                                                      }
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              height:
                                                  MediaQuery.of(
                                                    context,
                                                  ).size.height *
                                                  0.4,
                                              child: StreamBuilder<
                                                DocumentSnapshot<
                                                  Map<String, dynamic>
                                                >
                                              >(
                                                stream:
                                                    FirebaseFirestore.instance
                                                        .collection('photos')
                                                        .doc(widget.photo.id)
                                                        .snapshots(),
                                                builder: (context, snapshot) {
                                                  if (!snapshot.hasData ||
                                                      !snapshot.data!
                                                          .data()!
                                                          .containsKey(
                                                            'comments',
                                                          )) {
                                                    return const Center(
                                                      child: Text(
                                                        "No comments yet.",
                                                      ),
                                                    );
                                                  }

                                                  final comments = List<
                                                    Map<String, dynamic>
                                                  >.from(
                                                    snapshot.data!['comments'],
                                                  );

                                                  // ✅ Sort comments by descending timestamp
                                                  comments.sort((a, b) {
                                                    final aTime =
                                                        a['timestamp'];
                                                    final bTime =
                                                        b['timestamp'];

                                                    if (aTime is Timestamp &&
                                                        bTime is Timestamp) {
                                                      return bTime.compareTo(
                                                        aTime,
                                                      ); // latest comment first
                                                    }
                                                    return 0; // fallback if no timestamp
                                                  });

                                                  return ListView.builder(
                                                    controller:
                                                        scrollController,
                                                    itemCount: comments.length,
                                                    itemBuilder: (
                                                      context,
                                                      index,
                                                    ) {
                                                      final comment =
                                                          comments[index];
                                                      return ListTile(
                                                        title: Text(
                                                          comment['text'] ?? '',
                                                        ),
                                                        subtitle: Text(
                                                          comment['username'] ??
                                                              'User',
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                              ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              /// 🔹 Caption & Time
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.photo.caption.isNotEmpty)
                      Text(
                        widget.photo.caption,
                        style: const TextStyle(fontSize: 14),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      widget.photo.timestamp.toLocal().toString().split('.')[0],
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// import 'dart:convert';
// import 'package:flutter/material.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:memscape/screens/home/public_profile_screen.dart';
// import '../models/photo_model.dart';

// class PhotoCard extends StatelessWidget {
//   final PhotoModel photo;

//   const PhotoCard({super.key, required this.photo});

//   Future<String?> fetchBase64Image(String? path) async {
//     if (path == null || path.isEmpty) return null;

//     try {
//       final snapshot = await FirebaseDatabase.instance.ref(path).get();
//       if (snapshot.exists) {
//         return snapshot.value as String;
//       }
//     } catch (e) {
//       debugPrint("❌ Error loading image: $e");
//     }
//     return null;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return FutureBuilder<String?>(
//       future: fetchBase64Image(photo.imagePath),
//       builder: (context, snapshot) {
//         if (snapshot.connectionState == ConnectionState.waiting) {
//           return const Padding(
//             padding: EdgeInsets.all(16),
//             child: Center(child: CircularProgressIndicator()),
//           );
//         }

//         if (!snapshot.hasData || snapshot.data == null) {
//           return const Center(child: Text("❌ Failed to load image"));
//         }

//         final imageBytes = base64Decode(snapshot.data!);

//         return Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             /// 🔹 Header: User avatar + name
//             Padding(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//               child: GestureDetector(
//                 onTap: () {
//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(
//                       builder:
//                           (_) =>
//                               PublicProfileScreen(uid: photo.uid), // <-- fixed
//                     ),
//                   );
//                 },
//                 child: Row(
//                   children: [
//                     const CircleAvatar(
//                       radius: 20,
//                       backgroundImage: AssetImage("assets/default_user.png"),
//                     ),
//                     const SizedBox(width: 10),
//                     Text(
//                       "User: ${photo.uid.substring(0, 6)}", // or displayName if available
//                       style: const TextStyle(
//                         fontWeight: FontWeight.bold,
//                         fontSize: 15,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ),

//             /// 🔹 Image
//             ClipRRect(
//               borderRadius: BorderRadius.circular(0),
//               child: Image.memory(
//                 imageBytes,
//                 width: double.infinity,
//                 height: 250,
//                 fit: BoxFit.cover,
//               ),
//             ),

//             /// 🔹 Caption, Location, Timestamp
//             Padding(
//               padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     photo.caption,
//                     style: const TextStyle(
//                       fontWeight: FontWeight.w600,
//                       fontSize: 16,
//                     ),
//                   ),
//                   if (photo.location.isNotEmpty)
//                     Padding(
//                       padding: const EdgeInsets.only(top: 4),
//                       child: Text(
//                         photo.location,
//                         style: const TextStyle(
//                           color: Colors.grey,
//                           fontSize: 14,
//                         ),
//                       ),
//                     ),
//                   Padding(
//                     padding: const EdgeInsets.only(top: 4),
//                     child: Text(
//                       photo.timestamp.toLocal().toString().split('.')[0],
//                       style: const TextStyle(color: Colors.grey, fontSize: 12),
//                     ),
//                   ),
//                 ],
//               ),
//             ),

//             const Divider(height: 1),
//           ],
//         );
//       },
//     );
//   }
// }
