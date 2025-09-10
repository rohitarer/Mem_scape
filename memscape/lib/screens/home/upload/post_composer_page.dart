import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:memscape/screens/home/home_screen.dart';
import 'package:memscape/services/firestore_service.dart';


class PostComposerPage extends ConsumerStatefulWidget {
  final List<File>? initialMedia;
  const PostComposerPage({super.key, this.initialMedia});

  @override
  ConsumerState<PostComposerPage> createState() => _PostComposerPageState();
}

class _PostComposerPageState extends ConsumerState<PostComposerPage> {
  final captionCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  TextEditingController? _typeAheadCtrl;

  bool isPublic = true;
  bool isUploading = false;
  double? _lat;
  double? _lng;

  final List<File> _media = [];
  int _carouselIndex = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialMedia != null && widget.initialMedia!.isNotEmpty) {
      _media.addAll(widget.initialMedia!);
    }
    _initLocation();
  }

  @override
  void dispose() {
    captionCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final p = await Geolocator.requestPermission();
      if (p == LocationPermission.denied ||
          p == LocationPermission.deniedForever) {
        locationCtrl.text = 'Unknown';
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lat = pos.latitude;
      _lng = pos.longitude;
    } catch (_) {
      locationCtrl.text = 'Unknown';
    }
  }

  Future<List<String>> _nominatim(String query) async {
    final url = Uri.parse(
      'https://nominatim.openstreetmap.org/search?q=$query&format=json&addressdetails=1&limit=5',
    );
    final res = await http.get(url, headers: {'User-Agent': 'Memscape/1.0'});
    if (res.statusCode != 200) return [];
    final data = json.decode(res.body) as List;
    return data.map((e) => e['display_name'] as String).toList();
  }

  Future<void> _pickMedia() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'mp4', 'mov', 'm4v'],
    );
    if (result == null) return;
    final files = result.paths.whereType<String>().map((p) => File(p)).toList();
    if (files.isEmpty) return;

    const maxItems = 10;
    final limited = files.take(maxItems).toList();

    setState(() {
      _media
        ..clear()
        ..addAll(limited);
      _carouselIndex = 0;
    });
  }

  Future<void> _upload() async {
    if (_media.isEmpty) {
      _snack("Please select images/videos.");
      return;
    }
    final locText = (_typeAheadCtrl?.text ?? locationCtrl.text).trim();
    if (captionCtrl.text.trim().isEmpty || locText.isEmpty) {
      _snack("Add a caption and location.");
      return;
    }

    setState(() => isUploading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Not authenticated.");

      final fs = FirestoreService();
      await fs.uploadMemoryWithMedia(
        files: _media,
        caption: captionCtrl.text.trim(),
        locationInput: locText,
        isPublic: isPublic,
        uid: user.uid,
        fallbackLat: _lat,
        fallbackLng: _lng,
      );

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (_) => false,
      );
    } catch (e) {
      _snack("Upload failed: $e");
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  void _snack(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media picker + carousel preview
            GestureDetector(
              onTap: _pickMedia,
              child: _media.isEmpty
                  ? Container(
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.grey[300],
                      ),
                      child: const Center(
                        child: Text("📷 Tap to select images/videos"),
                      ),
                    )
                  : Column(
                      children: [
                        SizedBox(
                          height: 220,
                          child: PageView.builder(
                            itemCount: _media.length,
                            onPageChanged: (i) =>
                                setState(() => _carouselIndex = i),
                            itemBuilder: (_, i) {
                              final f = _media[i];
                              final isVideo = f.path.toLowerCase().endsWith('.mp4') ||
                                  f.path.toLowerCase().endsWith('.mov') ||
                                  f.path.toLowerCase().endsWith('.m4v');
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    isVideo
                                        ? Container(
                                            color: Colors.black12,
                                            child: const Center(
                                              child: Icon(Icons.play_circle,
                                                  size: 64),
                                            ),
                                          )
                                        : Image.file(f, fit: BoxFit.cover),
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          isVideo ? "VIDEO" : "IMAGE",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        // dots
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _media.length,
                            (i) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: i == _carouselIndex ? 10 : 6,
                              height: i == _carouselIndex ? 10 : 6,
                              decoration: BoxDecoration(
                                color: i == _carouselIndex
                                    ? Colors.black87
                                    : Colors.black26,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _pickMedia,
                          icon: const Icon(Icons.add),
                          label: const Text("Add more"),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: captionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Caption",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TypeAheadField<String>(
              suggestionsCallback: _nominatim,
              itemBuilder: (_, s) =>
                  ListTile(leading: const Icon(Icons.location_on), title: Text(s)),
              onSelected: (s) {
                _typeAheadCtrl?.text = s;
                locationCtrl.text = s;
              },
              builder: (context, controller, focusNode) {
                _typeAheadCtrl = controller;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: "Location",
                    border: OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: isPublic,
              title: const Text("Make this memory public"),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (v) => setState(() => isPublic = v ?? true),
            ),
            const SizedBox(height: 16),
            isUploading
                ? const Center(child: CircularProgressIndicator())
                : SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.cloud_upload),
                      label: const Text("Upload Memory"),
                      onPressed: _upload,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
