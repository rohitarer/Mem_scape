// lib/screens/home/memories_view_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:memscape/services/firestore_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';

/// 📸 Full-screen pager for memories (swipe left/right to navigate)
/// Accepts a list of Realtime DB image paths (e.g. "images/<photoId>")
class MemoriesViewScreen extends StatefulWidget {
  final List<String> items; // Realtime DB paths like "images/<photoId>"
  final int initialIndex;

  const MemoriesViewScreen({
    super.key,
    required this.items,
    this.initialIndex = 0,
  });

  @override
  State<MemoriesViewScreen> createState() => _MemoriesViewScreenState();
}

class _MemoriesViewScreenState extends State<MemoriesViewScreen> {
  late final PageController _pageController;
  final ValueNotifier<int> _currIndex = ValueNotifier<int>(0);

  // Lightweight in-memory cache (index -> bytes) to avoid re-decoding on download
  final Map<int, Uint8List?> _bytesCache = {};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialIndex);
    _currIndex.value = widget.initialIndex;
  }

  @override
  void dispose() {
    _currIndex.dispose();
    _pageController.dispose();
    super.dispose();
  }

  String _parsePhotoId(String path) {
    final i = path.lastIndexOf('/');
    return (i >= 0 && i < path.length - 1) ? path.substring(i + 1) : path;
  }

  /// Parent-level download handler — no child keys needed.
  Future<void> _downloadCurrentVisible() async {
    final idx = _currIndex.value;
    if (idx < 0 || idx >= widget.items.length) return;

    // Try cache first
    Uint8List? bytes = _bytesCache[idx];
    if (bytes == null) {
      bytes = await _loadBytesForPath(widget.items[idx]);
      if (bytes == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("❌ Image not loaded yet")));
        return;
      }
    }

    final ok = await _requestGalleryPermission();
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("❌ Permission denied")));
      return;
    }

    final photoId = _parsePhotoId(widget.items[idx]);
    await SaverGallery.saveImage(
      bytes,
      quality: 90,
      fileName: "memscape_$photoId.jpg",
      androidRelativePath: "Pictures/Memscape",
      skipIfExists: false,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("✅ Image saved to gallery")));
  }

  Future<Uint8List?> _loadBytesForPath(String imagePath) async {
    // Try your FirestoreService helper first
    try {
      final base64 = await FirestoreService().fetchImageBase64(imagePath);
      if (base64 != null && base64.isNotEmpty) return base64Decode(base64);
    } catch (_) {}
    // Fallback to direct Realtime DB fetch
    try {
      final snap = await FirebaseDatabase.instance.ref(imagePath).get();
      if (snap.exists && snap.value != null) {
        return base64Decode(snap.value as String);
      }
    } catch (_) {}
    return null;
  }

  Future<bool> _requestGalleryPermission() async {
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
    final total = widget.items.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: AnimatedBuilder(
          animation: _pageController,
          builder: (_, __) {
            final curr =
                _pageController.hasClients
                    ? (_pageController.page?.round() ?? widget.initialIndex)
                    : widget.initialIndex;
            return Text("${curr + 1} / $total");
          },
        ),
        actions: [
          PopupMenuButton<String>(
            color: Colors.grey[900],
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) async {
              if (value == 'download') {
                await _downloadCurrentVisible();
              }
            },
            itemBuilder:
                (context) => const [
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.download, size: 18, color: Colors.white70),
                        SizedBox(width: 8),
                        Text(
                          'Download',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (i) => _currIndex.value = i,
        itemCount: total,
        itemBuilder: (context, index) {
          final imagePath = widget.items[index];
          final photoId = _parsePhotoId(imagePath);
          return _PhotoPane(
            index: index,
            imagePath: imagePath,
            photoId: photoId,
            onBytesReady: (bytes) => _bytesCache[index] = bytes,
          );
        },
      ),
    );
  }
}

class _PhotoPane extends StatefulWidget {
  final int index;
  final String imagePath; // "images/<photoId>"
  final String photoId; // "<photoId>"
  final void Function(Uint8List? bytes)? onBytesReady;

  const _PhotoPane({
    required this.index,
    required this.imagePath,
    required this.photoId,
    this.onBytesReady,
  });

  @override
  State<_PhotoPane> createState() => _PhotoPaneState();
}

class _PhotoPaneState extends State<_PhotoPane> {
  final _realtime = FirebaseDatabase.instance;
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Uint8List? _bytes;
  bool _loadingImg = true;
  final _commentCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  @override
  void dispose() {
    _commentCtl.dispose();
    super.dispose();
  }

  // 🔹 Helper to safely convert Firestore/Realtime DB timestamp to DateTime
  DateTime? _coerceToDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {}
    }
    if (v is String) {
      try {
        return DateTime.tryParse(v);
      } catch (_) {}
    }
    return null;
  }

  Future<void> _loadBytes() async {
    try {
      final base64 = await FirestoreService().fetchImageBase64(
        widget.imagePath,
      );
      if (base64 != null && base64.isNotEmpty) {
        _bytes = base64Decode(base64);
        widget.onBytesReady?.call(_bytes);
        if (mounted) setState(() => _loadingImg = false);
        return;
      }
    } catch (_) {}
    try {
      final snap = await _realtime.ref(widget.imagePath).get();
      if (snap.exists && snap.value != null) {
        _bytes = base64Decode(snap.value as String);
        widget.onBytesReady?.call(_bytes);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingImg = false);
  }

  Future<void> _toggleLike(bool isLiked) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await FirestoreService().toggleLike(widget.photoId, uid);
  }

  Future<void> _postComment() async {
    final uid = _auth.currentUser?.uid;
    final text = _commentCtl.text.trim();
    if (uid == null || text.isEmpty) return;

    await FirestoreService().addComment(widget.photoId, uid, text);
    _commentCtl.clear();
  }

  @override
  Widget build(BuildContext context) {
    // live metadata for this photo
    final photoDocStream =
        _db.collection('photos').doc(widget.photoId).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: photoDocStream,
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};

        // final timestampRaw = data['timestamp'];
        // final ts = (timestampRaw is Timestamp) ? timestampRaw.toDate() : null;
        // final timeText =
        //     ts != null ? DateFormat('MMM d, yyyy • h:mm a').format(ts) : '';
        final timestampRaw = data['timestamp'];
        final dt = _coerceToDate(timestampRaw);
        final timeText =
            dt != null ? DateFormat('MMM d, yyyy • h:mm a').format(dt) : '';

        final location = (data['location'] as String?) ?? '';
        final likes =
            (data['likes'] as List?)?.cast<String>() ?? const <String>[];
        final isLiked =
            _auth.currentUser != null && likes.contains(_auth.currentUser!.uid);

        final commentsList =
            (data['comments'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[];

        // latest first
        commentsList.sort((a, b) {
          final at = a['timestamp'];
          final bt = b['timestamp'];
          if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
          return 0;
        });

        return Column(
          children: [
            // ── Square image ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: LayoutBuilder(
                builder: (context, c) {
                  final side = c.maxWidth;
                  return Container(
                    width: side,
                    height: side,
                    color: Colors.black,
                    alignment: Alignment.center,
                    child:
                        _loadingImg
                            ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                            : (_bytes == null
                                ? const Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                  size: 48,
                                )
                                : ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: InteractiveViewer(
                                    minScale: 1,
                                    maxScale: 4,
                                    child: Image.memory(
                                      _bytes!,
                                      width: side,
                                      height: side,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                )),
                  );
                },
              ),
            ),

            // ── Actions row: Heart + location ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.redAccent : Colors.white,
                    ),
                    onPressed: () => _toggleLike(isLiked),
                  ),
                  const SizedBox(width: 8),
                  if (location.isNotEmpty)
                    Flexible(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.place_rounded,
                            size: 16,
                            color: Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // ── Timestamp line (below heart + location) ───────────────────
            if (timeText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      size: 16,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      timeText,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            // ── Comments: first item is the input, then list scrolls ──────
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: commentsList.length + 1, // +1 for composer
                itemBuilder: (context, i) {
                  if (i == 0) {
                    // composer at top of the scroll
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commentCtl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: "Add a comment…",
                                hintStyle: const TextStyle(
                                  color: Colors.white60,
                                ),
                                filled: true,
                                fillColor: Colors.white12,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onSubmitted: (_) => _postComment(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _postComment,
                            icon: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final c = commentsList[i - 1];
                  final text = (c['text'] as String?) ?? '';
                  final user =
                      (c['username'] as String?) ??
                      (c['uid'] as String? ?? 'User');
                  final t = c['timestamp'];
                  String when = '';
                  if (t is Timestamp) {
                    when = DateFormat('MMM d, h:mm a').format(t.toDate());
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.white24,
                          child: Icon(
                            Icons.person,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: "$user  ",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                    TextSpan(
                                      text: text,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (when.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    when,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// // lib/screens/home/memories_view_screen.dart
// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:memscape/services/firestore_service.dart';

// /// 📸 Full-screen pager for memories (swipe left/right to navigate)
// /// Expects a list of Realtime DB image paths (e.g. "images/<id>")
// class MemoriesViewScreen extends StatefulWidget {
//   /// The full sequence to browse (e.g., user’s photos list as DB paths)
//   final List<String> items;

//   /// Start on this index
//   final int initialIndex;

//   const MemoriesViewScreen({
//     super.key,
//     required this.items,
//     this.initialIndex = 0,
//   });

//   @override
//   State<MemoriesViewScreen> createState() => _MemoriesViewScreenState();
// }

// class _MemoriesViewScreenState extends State<MemoriesViewScreen> {
//   late final PageController _pageController;
//   final _realtime = FirebaseDatabase.instance;

//   @override
//   void initState() {
//     super.initState();
//     _pageController = PageController(initialPage: widget.initialIndex);
//   }

//   Future<Uint8List?> _loadBytes(String imagePath) async {
//     try {
//       // Try your FirestoreService helper first
//       final base64 = await FirestoreService().fetchImageBase64(imagePath);
//       if (base64 != null && base64.isNotEmpty) {
//         return base64Decode(base64);
//       }
//     } catch (_) {
//       // fall through to direct DB fetch
//     }

//     try {
//       final snap = await _realtime.ref(imagePath).get();
//       if (!snap.exists || snap.value == null) return null;
//       return base64Decode(snap.value as String);
//     } catch (_) {
//       return null;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final total = widget.items.length;

//     return Scaffold(
//       backgroundColor: Colors.black,
//       appBar: AppBar(
//         backgroundColor: Colors.black,
//         foregroundColor: Colors.white,
//         title: AnimatedBuilder(
//           animation: _pageController,
//           builder: (_, __) {
//             final curr =
//                 _pageController.hasClients
//                     ? (_pageController.page?.round() ?? widget.initialIndex)
//                     : widget.initialIndex;
//             return Text("${curr + 1} / $total");
//           },
//         ),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.more_vert),
//             onPressed: () {
//               // TODO: share/download/report if needed
//             },
//           ),
//         ],
//       ),
//       body: PageView.builder(
//         controller: _pageController,
//         itemCount: total,
//         itemBuilder: (context, index) {
//           final imagePath = widget.items[index];

//           return FutureBuilder<Uint8List?>(
//             future: _loadBytes(imagePath),
//             builder: (context, snap) {
//               if (snap.connectionState == ConnectionState.waiting) {
//                 return const Center(
//                   child: CircularProgressIndicator(color: Colors.white),
//                 );
//               }
//               if (!snap.hasData || snap.data == null) {
//                 return const Center(
//                   child: Icon(
//                     Icons.broken_image,
//                     color: Colors.white54,
//                     size: 48,
//                   ),
//                 );
//               }
//               final bytes = snap.data!;

//               return Column(
//                 children: [
//                   Expanded(
//                     child: InteractiveViewer(
//                       minScale: 1,
//                       maxScale: 4,
//                       child: Image.memory(
//                         bytes,
//                         width: double.infinity,
//                         fit: BoxFit.contain,
//                       ),
//                     ),
//                   ),
//                   // Minimal footer bar; expand later with captions/timestamps if you pass meta
//                   Container(
//                     width: double.infinity,
//                     color: Colors.black.withOpacity(0.35),
//                     padding: const EdgeInsets.symmetric(
//                       horizontal: 16,
//                       vertical: 12,
//                     ),
//                     child: const Text(
//                       "Swipe for more",
//                       style: TextStyle(color: Colors.white70, fontSize: 12),
//                     ),
//                   ),
//                 ],
//               );
//             },
//           );
//         },
//       ),
//     );
//   }
// }

// import 'dart:convert';

// import 'package:flutter/material.dart';

// class MemoriesViewScreen extends StatelessWidget {
//   final String photoBase64;

//   const MemoriesViewScreen({super.key, required this.photoBase64});

//   @override
//   Widget build(BuildContext context) {
//     final imageBytes = base64Decode(photoBase64);

//     return Scaffold(
//       appBar: AppBar(title: const Text("My Memory")),
//       body: Center(child: Image.memory(imageBytes)),
//     );
//   }
// }
