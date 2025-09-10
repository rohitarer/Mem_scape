import 'dart:io';
import 'package:flutter/material.dart';
import 'package:memscape/screens/home/upload/live_stub_page.dart';
import 'package:memscape/screens/home/upload/post_composer_page.dart';
import 'package:memscape/screens/home/upload/story_capture_page.dart';

enum ComposeMode { story, post, live }

class UploadMemoryScreen extends StatefulWidget {
  const UploadMemoryScreen({super.key});

  @override
  State<UploadMemoryScreen> createState() => _UploadMemoryScreenState();
}

class _UploadMemoryScreenState extends State<UploadMemoryScreen> {
  ComposeMode _mode = ComposeMode.story;

  // When Story captures a photo, we pass it to Post
  List<File> _pendingMedia = const [];

  void _switchMode(ComposeMode mode) {
    setState(() => _mode = mode);
  }

  void _handleStoryCaptured(File file) {
    setState(() {
      _pendingMedia = [file];
      _mode = ComposeMode.post;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (_mode) {
      case ComposeMode.story:
        body = StoryCapturePage(onCaptured: _handleStoryCaptured);
        break;
      case ComposeMode.post:
        body = PostComposerPage(initialMedia: _pendingMedia);
        break;
      case ComposeMode.live:
        body = const LiveStubPage();
        break;
    }

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: body),
          // Top-left menu
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _ModeMenu(current: _mode, onSelect: _switchMode),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeMenu extends StatelessWidget {
  final ComposeMode current;
  final ValueChanged<ComposeMode> onSelect;
  const _ModeMenu({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<ComposeMode>(
      tooltip: "Menu",
      position: PopupMenuPosition.under,
      onSelected: onSelect,
      itemBuilder:
          (ctx) => [
            PopupMenuItem(
              value: ComposeMode.story,
              child: Row(
                children: [
                  Icon(
                    Icons.camera,
                    color:
                        current == ComposeMode.story
                            ? Theme.of(context).colorScheme.primary
                            : null,
                  ),
                  const SizedBox(width: 8),
                  const Text("Story"),
                ],
              ),
            ),
            PopupMenuItem(
              value: ComposeMode.post,
              child: Row(
                children: [
                  Icon(
                    Icons.photo_library,
                    color:
                        current == ComposeMode.post
                            ? Theme.of(context).colorScheme.primary
                            : null,
                  ),
                  const SizedBox(width: 8),
                  const Text("Post"),
                ],
              ),
            ),
            PopupMenuItem(
              value: ComposeMode.live,
              child: Row(
                children: [
                  Icon(
                    Icons.podcasts,
                    color:
                        current == ComposeMode.live
                            ? Theme.of(context).colorScheme.primary
                            : null,
                  ),
                  const SizedBox(width: 8),
                  const Text("Live Stream"),
                ],
              ),
            ),
          ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.menu, color: Colors.white),
      ),
    );
  }
}

// // lib/screens/upload/upload_memory_screen.dart
// import 'dart:convert';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:flutter_typeahead/flutter_typeahead.dart';
// import 'package:http/http.dart' as http;
// import 'package:permission_handler/permission_handler.dart';

// import '../../services/firestore_service.dart';
// import '../home/home_screen.dart';

// enum ComposeMode { story, post, live }

// class UploadMemoryScreen extends ConsumerStatefulWidget {
//   const UploadMemoryScreen({super.key});
//   @override
//   ConsumerState<UploadMemoryScreen> createState() => _UploadMemoryScreenState();
// }

// class _UploadMemoryScreenState extends ConsumerState<UploadMemoryScreen>
//     with WidgetsBindingObserver {
//   // MODE
//   ComposeMode _mode = ComposeMode.story;

//   // Post form
//   final captionCtrl = TextEditingController();
//   final locationCtrl = TextEditingController();
//   TextEditingController? _typeAheadCtrl;
//   bool isPublic = true;
//   bool isUploading = false;
//   double? _lat;
//   double? _lng;
//   final List<File> _media = [];
//   int _carouselIndex = 0;

//   // Camera
//   CameraController? _cameraController;
//   List<CameraDescription> _cameras = [];
//   bool _camReady = false;
//   bool _usingFront = false;
//   bool _isTaking = false;
//   FlashMode _flash = FlashMode.off;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this); // 👈
//     _boot();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this); // 👈
//     _disposeCamera(); // 👈 make sure we free it
//     captionCtrl.dispose();
//     locationCtrl.dispose();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) async {
//     final cam = _cameraController;
//     if (cam == null || !cam.value.isInitialized) return;

//     if (state == AppLifecycleState.inactive ||
//         state == AppLifecycleState.paused) {
//       // App not in foreground → release camera
//       await _disposeCamera();
//     } else if (state == AppLifecycleState.resumed) {
//       // Foreground again → re-init ONLY if we're in Story mode
//       if (_mode == ComposeMode.story) {
//         await _initCamera();
//       }
//     }
//   }

//   Future<void> _boot() async {
//     await _initLocation();
//     await _initCamera(); // default to story → open camera
//   }

//   // ---------------- Location ----------------
//   Future<void> _initLocation() async {
//     try {
//       final p = await Geolocator.requestPermission();
//       if (p == LocationPermission.denied ||
//           p == LocationPermission.deniedForever) {
//         locationCtrl.text = 'Unknown';
//         return;
//       }
//       final pos = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );
//       _lat = pos.latitude;
//       _lng = pos.longitude;
//     } catch (_) {
//       locationCtrl.text = 'Unknown';
//     }
//   }

//   Future<List<String>> _nominatim(String query) async {
//     final url = Uri.parse(
//       'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
//     );
//     final res = await http.get(url, headers: {'User-Agent': 'Memscape/1.0'});
//     if (res.statusCode != 200) return [];
//     final data = json.decode(res.body) as List;
//     return data.map((e) => e['display_name'] as String).toList();
//   }

//   Future<void> _disposeCamera() async {
//     try {
//       if (_cameraController != null) {
//         final c = _cameraController!;
//         _cameraController = null; // prevent re-entry
//         if (c.value.isStreamingImages) await c.stopImageStream();
//         await c.dispose();
//       }
//     } catch (_) {
//       // swallow — disposing during lifecycle can race
//     } finally {
//       if (mounted) setState(() => _camReady = false);
//     }
//   }

//   Future<void> _initCamera() async {
//     try {
//       // ask for permission explicitly
//       final camStatus = await Permission.camera.request();
//       if (!camStatus.isGranted) {
//         _snack("Camera permission denied. Enable it in Settings.");
//         if (mounted) setState(() => _camReady = false);
//         return;
//       }

//       // ensure old controller is gone before creating a new one
//       await _disposeCamera();

//       final cameras = await availableCameras();
//       if (cameras.isEmpty) {
//         if (mounted) setState(() => _camReady = false);
//         _snack("No camera found on this device.");
//         return;
//       }
//       _cameras = cameras;

//       final camera =
//           _usingFront
//               ? _cameras.firstWhere(
//                 (c) => c.lensDirection == CameraLensDirection.front,
//                 orElse: () => _cameras.first,
//               )
//               : _cameras.firstWhere(
//                 (c) => c.lensDirection == CameraLensDirection.back,
//                 orElse: () => _cameras.first,
//               );

//       // Use a lower preset to reduce memory/backpressure; bump later if stable
//       final controller = CameraController(
//         camera,
//         ResolutionPreset.medium, // 👈 was high
//         enableAudio: false,
//         imageFormatGroup: ImageFormatGroup.yuv420, // stable default
//       );

//       _cameraController = controller;
//       await controller.initialize();
//       await controller.setFlashMode(_flash);

//       if (!mounted) return;
//       setState(() => _camReady = true);
//     } catch (e) {
//       if (mounted) setState(() => _camReady = false);
//       _snack("Camera init failed: $e");
//     }
//   }

//   Future<void> _toggleCamera() async {
//     _usingFront = !_usingFront;
//     await _initCamera();
//   }

//   Future<void> _toggleFlash() async {
//     if (_cameraController == null) return;
//     final next = switch (_flash) {
//       FlashMode.off => FlashMode.auto,
//       FlashMode.auto => FlashMode.always,
//       FlashMode.always => FlashMode.torch,
//       FlashMode.torch => FlashMode.off,
//       _ => FlashMode.off,
//     };
//     _flash = next;
//     await _cameraController!.setFlashMode(_flash);
//     setState(() {});
//   }

//   Future<void> _captureStoryPhoto() async {
//     if (_cameraController?.value.isTakingPicture == true) return;
//     if (!_camReady || _cameraController == null || _isTaking) return;
//     try {
//       setState(() => _isTaking = true);
//       final file = await _cameraController!.takePicture();
//       if (!mounted) return;
//       // For now: after capture, switch to Post mode with this image preselected
//       setState(() {
//         _mode = ComposeMode.post;
//         _media
//           ..clear()
//           ..add(File(file.path));
//         _carouselIndex = 0;
//       });
//     } catch (e) {
//       _snack("Capture failed: $e");
//     } finally {
//       if (mounted) setState(() => _isTaking = false);
//     }
//   }

//   // ---------------- Post: pick & upload ----------------
//   Future<void> _pickMedia() async {
//     final result = await FilePicker.platform.pickFiles(
//       allowMultiple: true,
//       type: FileType.custom,
//       allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'm4v'],
//     );
//     if (result == null) return;
//     final files = result.paths.whereType<String>().map((p) => File(p)).toList();
//     if (files.isEmpty) return;

//     // guard to avoid extreme RTDB payloads
//     const maxItems = 10;
//     final limited = files.take(maxItems).toList();

//     setState(() {
//       _media
//         ..clear()
//         ..addAll(limited);
//       _carouselIndex = 0;
//     });
//   }

//   Future<void> _upload() async {
//     if (_media.isEmpty) {
//       _snack("Please select images/videos.");
//       return;
//     }
//     final locText = (_typeAheadCtrl?.text ?? locationCtrl.text).trim();
//     if (captionCtrl.text.trim().isEmpty || locText.isEmpty) {
//       _snack("Add a caption and location.");
//       return;
//     }

//     setState(() => isUploading = true);
//     try {
//       final user = FirebaseAuth.instance.currentUser;
//       if (user == null) throw Exception("Not authenticated.");

//       final fs = FirestoreService();
//       await fs.uploadMemoryWithMedia(
//         files: _media,
//         caption: captionCtrl.text.trim(),
//         locationInput: locText,
//         isPublic: isPublic,
//         uid: user.uid,
//         fallbackLat: _lat,
//         fallbackLng: _lng,
//       );

//       if (!mounted) return;
//       Navigator.of(context).pushAndRemoveUntil(
//         MaterialPageRoute(builder: (_) => const HomeScreen()),
//         (_) => false,
//       );
//     } catch (e) {
//       _snack("Upload failed: $e");
//     } finally {
//       if (mounted) setState(() => isUploading = false);
//     }
//   }

//   // ---------------- UI ----------------
//   void _snack(String m) {
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           // Main body changes with mode
//           Positioned.fill(child: _buildBodyByMode()),

//           // Top-left menu button
//           SafeArea(
//             child: Align(
//               alignment: Alignment.topLeft,
//               child: Padding(
//                 padding: const EdgeInsets.all(8.0),
//                 child: _ModeMenu(
//                   current: _mode,
//                   onSelect: (m) async {
//                     setState(() => _mode = m);
//                     if (m == ComposeMode.story) {
//                       await _initCamera();
//                     }
//                   },
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildBodyByMode() {
//     switch (_mode) {
//       case ComposeMode.story:
//         return _buildStoryCamera();
//       case ComposeMode.post:
//         return _buildPostTab();
//       case ComposeMode.live:
//         return _buildLiveStub();
//     }
//   }

//   // =============== STORY (Camera-first) ===============
//   Widget _buildStoryCamera() {
//     if (!_camReady || _cameraController == null) {
//       return const Center(child: CircularProgressIndicator());
//     }
//     return Stack(
//       children: [
//         // Full preview (stable layout)
//         Positioned.fill(
//           child:
//               _cameraController == null
//                   ? const SizedBox.shrink()
//                   : LayoutBuilder(
//                     builder: (context, constraints) {
//                       final value = _cameraController!.value;
//                       final previewSize =
//                           value.isInitialized ? value.previewSize : null;

//                       // If we don't know yet, just show raw preview
//                       if (previewSize == null) {
//                         return CameraPreview(_cameraController!);
//                       }

//                       final previewAspect =
//                           previewSize.height / previewSize.width;
//                       final screenAspect =
//                           constraints.maxWidth / constraints.maxHeight;

//                       return OverflowBox(
//                         alignment: Alignment.center,
//                         child: FittedBox(
//                           fit: BoxFit.cover,
//                           child: SizedBox(
//                             width: value.previewSize!.height,
//                             height: value.previewSize!.width,
//                             child: CameraPreview(_cameraController!),
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//         ),

//         // Top-right flash
//         SafeArea(
//           child: Align(
//             alignment: Alignment.topRight,
//             child: IconButton(
//               icon: Icon(switch (_flash) {
//                 FlashMode.off => Icons.flash_off,
//                 FlashMode.auto => Icons.flash_auto,
//                 FlashMode.always => Icons.flash_on,
//                 FlashMode.torch => Icons.bolt,
//                 _ => Icons.flash_off,
//               }, color: Colors.white),
//               onPressed: _toggleFlash,
//             ),
//           ),
//         ),

//         // Bottom controls
//         Align(
//           alignment: Alignment.bottomCenter,
//           child: Padding(
//             padding: const EdgeInsets.only(bottom: 28.0),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 // Library → switch to Post picker
//                 ElevatedButton.icon(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.black54,
//                     foregroundColor: Colors.white,
//                   ),
//                   icon: const Icon(Icons.photo_library),
//                   label: const Text("Library"),
//                   onPressed: () => setState(() => _mode = ComposeMode.post),
//                 ),

//                 // Capture
//                 GestureDetector(
//                   onTap: _captureStoryPhoto,
//                   child: Container(
//                     width: 78,
//                     height: 78,
//                     decoration: BoxDecoration(
//                       shape: BoxShape.circle,
//                       border: Border.all(color: Colors.white, width: 5),
//                     ),
//                     child:
//                         _isTaking
//                             ? const Center(
//                               child: SizedBox(
//                                 width: 24,
//                                 height: 24,
//                                 child: CircularProgressIndicator(
//                                   strokeWidth: 2,
//                                 ),
//                               ),
//                             )
//                             : null,
//                   ),
//                 ),

//                 // Switch camera
//                 ElevatedButton.icon(
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Colors.black54,
//                     foregroundColor: Colors.white,
//                   ),
//                   icon: const Icon(Icons.cameraswitch),
//                   label: const Text("Flip"),
//                   onPressed: _toggleCamera,
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   // =============== POST (multi media + form) ===============
//   Widget _buildPostTab() {
//     return Scaffold(
//       backgroundColor: Theme.of(context).scaffoldBackgroundColor,
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Media picker + carousel preview
//               GestureDetector(
//                 onTap: _pickMedia,
//                 child:
//                     _media.isEmpty
//                         ? Container(
//                           height: 220,
//                           decoration: BoxDecoration(
//                             borderRadius: BorderRadius.circular(16),
//                             color: Colors.grey[300],
//                           ),
//                           child: const Center(
//                             child: Text("📷 Tap to select images/videos"),
//                           ),
//                         )
//                         : Column(
//                           children: [
//                             SizedBox(
//                               height: 220,
//                               child: PageView.builder(
//                                 itemCount: _media.length,
//                                 onPageChanged:
//                                     (i) => setState(() => _carouselIndex = i),
//                                 itemBuilder: (_, i) {
//                                   final f = _media[i];
//                                   final isVideo =
//                                       f.path.toLowerCase().endsWith('.mp4') ||
//                                       f.path.toLowerCase().endsWith('.mov') ||
//                                       f.path.toLowerCase().endsWith('.m4v');
//                                   return ClipRRect(
//                                     borderRadius: BorderRadius.circular(16),
//                                     child: Stack(
//                                       fit: StackFit.expand,
//                                       children: [
//                                         isVideo
//                                             ? Container(
//                                               color: Colors.black12,
//                                               child: const Center(
//                                                 child: Icon(
//                                                   Icons.play_circle,
//                                                   size: 64,
//                                                 ),
//                                               ),
//                                             )
//                                             : Image.file(f, fit: BoxFit.cover),
//                                         Positioned(
//                                           right: 8,
//                                           top: 8,
//                                           child: Container(
//                                             padding: const EdgeInsets.symmetric(
//                                               horizontal: 8,
//                                               vertical: 4,
//                                             ),
//                                             decoration: BoxDecoration(
//                                               color: Colors.black54,
//                                               borderRadius:
//                                                   BorderRadius.circular(999),
//                                             ),
//                                             child: Text(
//                                               isVideo ? "VIDEO" : "IMAGE",
//                                               style: const TextStyle(
//                                                 color: Colors.white,
//                                                 fontSize: 12,
//                                               ),
//                                             ),
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   );
//                                 },
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             // dots
//                             Row(
//                               mainAxisAlignment: MainAxisAlignment.center,
//                               children: List.generate(
//                                 _media.length,
//                                 (i) => Container(
//                                   margin: const EdgeInsets.symmetric(
//                                     horizontal: 3,
//                                   ),
//                                   width: i == _carouselIndex ? 10 : 6,
//                                   height: i == _carouselIndex ? 10 : 6,
//                                   decoration: BoxDecoration(
//                                     color:
//                                         i == _carouselIndex
//                                             ? Colors.black87
//                                             : Colors.black26,
//                                     shape: BoxShape.circle,
//                                   ),
//                                 ),
//                               ),
//                             ),
//                             const SizedBox(height: 8),
//                             TextButton.icon(
//                               onPressed: _pickMedia,
//                               icon: const Icon(Icons.add),
//                               label: const Text("Add more"),
//                             ),
//                           ],
//                         ),
//               ),
//               const SizedBox(height: 16),
//               TextField(
//                 controller: captionCtrl,
//                 maxLines: 3,
//                 decoration: const InputDecoration(
//                   labelText: "Caption",
//                   border: OutlineInputBorder(),
//                 ),
//               ),
//               const SizedBox(height: 12),
//               TypeAheadField<String>(
//                 suggestionsCallback: _nominatim,
//                 itemBuilder:
//                     (_, s) => ListTile(
//                       leading: const Icon(Icons.location_on),
//                       title: Text(s),
//                     ),
//                 onSelected: (s) {
//                   _typeAheadCtrl?.text = s;
//                   locationCtrl.text = s;
//                 },
//                 builder: (context, controller, focusNode) {
//                   _typeAheadCtrl = controller;
//                   return TextField(
//                     controller: controller,
//                     focusNode: focusNode,
//                     decoration: const InputDecoration(
//                       labelText: "Location",
//                       border: OutlineInputBorder(),
//                     ),
//                   );
//                 },
//               ),
//               const SizedBox(height: 12),
//               CheckboxListTile(
//                 contentPadding: EdgeInsets.zero,
//                 value: isPublic,
//                 title: const Text("Make this memory public"),
//                 controlAffinity: ListTileControlAffinity.leading,
//                 onChanged: (v) => setState(() => isPublic = v ?? true),
//               ),
//               const SizedBox(height: 16),
//               isUploading
//                   ? const Center(child: CircularProgressIndicator())
//                   : SizedBox(
//                     width: double.infinity,
//                     child: ElevatedButton.icon(
//                       icon: const Icon(Icons.cloud_upload),
//                       label: const Text("Upload Memory"),
//                       onPressed: _upload,
//                     ),
//                   ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // =============== LIVE (stub) ===============
//   Widget _buildLiveStub() {
//     return Scaffold(
//       body: SafeArea(
//         child: Center(
//           child: ElevatedButton.icon(
//             icon: const Icon(Icons.videocam),
//             label: const Text("Start Live (coming soon)"),
//             onPressed: () {
//               _snack(
//                 "Integrate WebRTC/Agora here. We'll wire auth/room later.",
//               );
//             },
//           ),
//         ),
//       ),
//     );
//   }
// }

// // Top-left menu widget
// class _ModeMenu extends StatelessWidget {
//   final ComposeMode current;
//   final ValueChanged<ComposeMode> onSelect;
//   const _ModeMenu({required this.current, required this.onSelect});

//   @override
//   Widget build(BuildContext context) {
//     return PopupMenuButton<ComposeMode>(
//       tooltip: "Menu",
//       position: PopupMenuPosition.under,
//       onSelected: onSelect,
//       itemBuilder:
//           (ctx) => [
//             PopupMenuItem(
//               value: ComposeMode.story,
//               child: Row(
//                 children: [
//                   Icon(
//                     Icons.camera,
//                     color:
//                         current == ComposeMode.story
//                             ? Theme.of(context).colorScheme.primary
//                             : null,
//                   ),
//                   const SizedBox(width: 8),
//                   const Text("Story"),
//                 ],
//               ),
//             ),
//             PopupMenuItem(
//               value: ComposeMode.post,
//               child: Row(
//                 children: [
//                   Icon(
//                     Icons.photo_library,
//                     color:
//                         current == ComposeMode.post
//                             ? Theme.of(context).colorScheme.primary
//                             : null,
//                   ),
//                   const SizedBox(width: 8),
//                   const Text("Post"),
//                 ],
//               ),
//             ),
//             PopupMenuItem(
//               value: ComposeMode.live,
//               child: Row(
//                 children: [
//                   Icon(
//                     Icons.podcasts,
//                     color:
//                         current == ComposeMode.live
//                             ? Theme.of(context).colorScheme.primary
//                             : null,
//                   ),
//                   const SizedBox(width: 8),
//                   const Text("Live Stream"),
//                 ],
//               ),
//             ),
//           ],
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
//         decoration: BoxDecoration(
//           color: Colors.black54,
//           borderRadius: BorderRadius.circular(12),
//         ),
//         child: const Icon(Icons.menu, color: Colors.white),
//       ),
//     );
//   }
// }
// ---------------------
// import 'dart:convert';
// import 'dart:io';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:flutter_typeahead/flutter_typeahead.dart';
// import 'package:http/http.dart' as http;
// import 'package:image_picker/image_picker.dart';
// import 'package:geolocator/geolocator.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:memscape/screens/home/home_screen.dart';

// import '../../models/photo_model.dart';
// import '../../widgets/custom_textfield.dart';
// import '../../widgets/primary_button.dart';

// class UploadPhotoScreen extends ConsumerStatefulWidget {
//   const UploadPhotoScreen({super.key});

//   @override
//   ConsumerState<UploadPhotoScreen> createState() => _UploadPhotoScreenState();
// }

// class _UploadPhotoScreenState extends ConsumerState<UploadPhotoScreen> {
//   File? _selectedImage;
//   final captionController = TextEditingController();
//   final locationController = TextEditingController();
//   TextEditingController? fieldTextEditingController;
//   bool isLoading = false;
//   final picker = ImagePicker();
//   double? _lat;
//   double? _lng;
//   bool isPublic = true;

//   @override
//   void initState() {
//     super.initState();
//     getCurrentLocation();
//   }

//   Future<void> pickImage() async {
//     try {
//       final picked = await picker.pickImage(source: ImageSource.gallery);
//       if (picked != null) {
//         final file = File(picked.path);
//         final sizeInMB = await file.length() / (1024 * 1024);
//         if (sizeInMB > 5) {
//           _showSnackBar("❌ Image too large. Please pick one under 5MB.");
//           return;
//         }
//         setState(() => _selectedImage = file);
//       } else {
//         _showSnackBar("⚠️ No image selected.");
//       }
//     } catch (e) {
//       _showSnackBar("❌ Image selection failed: $e");
//     }
//   }

//   Future<void> getCurrentLocation() async {
//     try {
//       final permission = await Geolocator.requestPermission();
//       if (permission == LocationPermission.denied ||
//           permission == LocationPermission.deniedForever) {
//         throw Exception("❌ Location permission denied");
//       }

//       final position = await Geolocator.getCurrentPosition(
//         desiredAccuracy: LocationAccuracy.high,
//       );
//       final placemarks = await placemarkFromCoordinates(
//         position.latitude,
//         position.longitude,
//       );
//       final city =
//           placemarks.isNotEmpty
//               ? placemarks.first.locality ?? 'Unknown'
//               : 'Unknown';

//       setState(() {
//         locationController.text = city;
//         _lat = position.latitude;
//         _lng = position.longitude;
//       });
//     } catch (e) {
//       debugPrint("❌ Failed to get location: $e");
//       locationController.text = 'Unknown';
//     }
//   }

//   Future<String> encodeImageToBase64(File imageFile) async {
//     final bytes = await imageFile.readAsBytes();
//     return base64Encode(bytes);
//   }

//   // Future<void> uploadMemory() async {
//   //   if (_selectedImage == null) {
//   //     _showSnackBar("❗ Please select an image.");
//   //     return;
//   //   }

//   //   if (captionController.text.trim().isEmpty ||
//   //       locationController.text.trim().isEmpty) {
//   //     _showSnackBar("⚠️ Please enter a caption and location.");
//   //     return;
//   //   }

//   //   setState(() => isLoading = true);

//   //   try {
//   //     final user = FirebaseAuth.instance.currentUser;
//   //     if (user == null) throw Exception("User not authenticated");

//   //     final base64Image = await encodeImageToBase64(_selectedImage!);
//   //     final photoId = FirebaseFirestore.instance.collection('photos').doc().id;
//   //     final imagePath = "images/$photoId";

//   //     await FirebaseDatabase.instance.ref(imagePath).set(base64Image);

//   //     final photo = PhotoModel(
//   //       uid: user.uid,
//   //       caption: captionController.text.trim(),
//   //       location: locationController.text.trim(),
//   //       timestamp: DateTime.now(),
//   //       lat: _lat ?? 0,
//   //       lng: _lng ?? 0,
//   //       isPublic: isPublic,
//   //       place: locationController.text.split(',').first.trim(),
//   //     ).copyWith(imagePath: imagePath);

//   //     await FirebaseFirestore.instance
//   //         .collection("photos")
//   //         .doc(photoId)
//   //         .set(photo.toMap());

//   //     if (mounted) {
//   //       Navigator.of(context).pushAndRemoveUntil(
//   //         MaterialPageRoute(builder: (_) => const HomeScreen()),
//   //         (route) => false,
//   //       );
//   //     }
//   //   } catch (e) {
//   //     _showSnackBar("❌ Upload failed: $e");
//   //   } finally {
//   //     if (mounted) setState(() => isLoading = false);
//   //   }
//   // }

//   Future<void> uploadMemory() async {
//     if (_selectedImage == null) {
//       _showSnackBar("❗ Please select an image.");
//       return;
//     }

//     if (captionController.text.trim().isEmpty ||
//         locationController.text.trim().isEmpty) {
//       _showSnackBar("⚠️ Please enter a caption and location.");
//       return;
//     }

//     setState(() => isLoading = true);

//     try {
//       final user = FirebaseAuth.instance.currentUser;
//       if (user == null) throw Exception("User not authenticated");

//       final base64Image = await encodeImageToBase64(_selectedImage!);
//       final photoId = FirebaseFirestore.instance.collection('photos').doc().id;
//       final imagePath = "images/$photoId";

//       // Upload image to Realtime Database
//       await FirebaseDatabase.instance.ref(imagePath).set(base64Image);

//       final photo = PhotoModel(
//         uid: user.uid,
//         caption: captionController.text.trim(),
//         location: locationController.text.trim(),
//         timestamp: DateTime.now(),
//         lat: _lat ?? 0,
//         lng: _lng ?? 0,
//         isPublic: isPublic,
//         place: locationController.text.split(',').first.trim(),
//       ).copyWith(imagePath: imagePath);

//       // Save to global 'photos' collection
//       // Upload metadata to Firestore
//       await FirebaseFirestore.instance
//           .collection("photos")
//           .doc(photoId)
//           .set(photo.toMap());

//       // ✅ Store image path in user's photoRefs
//       await FirebaseFirestore.instance.collection("users").doc(user.uid).set({
//         "photoRefs": FieldValue.arrayUnion([photoId]),
//       }, SetOptions(merge: true));

//       if (mounted) {
//         Navigator.of(context).pushAndRemoveUntil(
//           MaterialPageRoute(builder: (_) => const HomeScreen()),
//           (route) => false,
//         );
//       }
//     } catch (e) {
//       _showSnackBar("❌ Upload failed: $e");
//     } finally {
//       if (mounted) setState(() => isLoading = false);
//     }
//   }

//   void _showSnackBar(String message) {
//     ScaffoldMessenger.of(
//       context,
//     ).showSnackBar(SnackBar(content: Text(message)));
//   }

//   Future<List<String>> fetchNominatimSuggestions(String query) async {
//     final url = Uri.parse(
//       'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
//     );

//     final response = await http.get(
//       url,
//       headers: {'User-Agent': 'FlutterApp/1.0 (yourname@example.com)'},
//     );

//     if (response.statusCode == 200) {
//       final data = json.decode(response.body) as List;
//       return data.map((item) => item['display_name'] as String).toList();
//     } else {
//       throw Exception('Failed to load suggestions');
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: const Text("Upload Memory")),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(24),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             GestureDetector(
//               onTap: pickImage,
//               child:
//                   _selectedImage != null
//                       ? ClipRRect(
//                         borderRadius: BorderRadius.circular(16),
//                         child: Image.file(
//                           _selectedImage!,
//                           height: 220,
//                           width: double.infinity,
//                           fit: BoxFit.cover,
//                         ),
//                       )
//                       : Container(
//                         height: 220,
//                         width: double.infinity,
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(16),
//                           color: Colors.grey[300],
//                         ),
//                         child: const Center(
//                           child: Text("📷 Tap to select image"),
//                         ),
//                       ),
//             ),
//             const SizedBox(height: 20),
//             CustomTextField(
//               controller: captionController,
//               label: "Caption",
//               maxLines: 2,
//             ),
//             const SizedBox(height: 12),
//             TypeAheadField<String>(
//               suggestionsCallback: fetchNominatimSuggestions,
//               itemBuilder: (context, String suggestion) {
//                 return ListTile(
//                   leading: const Icon(Icons.location_on),
//                   title: Text(suggestion),
//                 );
//               },
//               onSelected: (String suggestion) {
//                 debugPrint("📍 Suggestion selected: $suggestion");
//                 locationController.text = suggestion;
//                 fieldTextEditingController?.text = suggestion;
//                 debugPrint(
//                   "📝 locationController updated to: ${locationController.text}",
//                 );
//               },
//               builder: (context, controller, focusNode) {
//                 fieldTextEditingController = controller;
//                 return TextField(
//                   controller: controller,
//                   focusNode: focusNode,
//                   decoration: const InputDecoration(
//                     labelText: 'Location',
//                     border: OutlineInputBorder(),
//                   ),
//                 );
//               },
//             ),
//             const SizedBox(height: 12),
//             CheckboxListTile(
//               contentPadding: EdgeInsets.zero,
//               value: isPublic,
//               title: const Text("Make this memory public"),
//               controlAffinity: ListTileControlAffinity.leading,
//               onChanged: (val) => setState(() => isPublic = val ?? true),
//             ),
//             const SizedBox(height: 24),
//             isLoading
//                 ? const Center(child: CircularProgressIndicator())
//                 : PrimaryButton(text: "Upload Memory", onPressed: uploadMemory),
//           ],
//         ),
//       ),
//     );
//   }
// }
