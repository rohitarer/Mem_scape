import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:memscape/models/photo_model.dart';
import 'package:memscape/screens/home/full_screen_image_viewer.dart';
import 'package:memscape/services/firestore_service.dart';

class LocationPhotosScreen extends StatefulWidget {
  final String location;
  const LocationPhotosScreen({super.key, required this.location});

  @override
  State<LocationPhotosScreen> createState() => _LocationPhotosScreenState();
}

class _LocationPhotosScreenState extends State<LocationPhotosScreen> {
  final FirestoreService firestoreService = FirestoreService();
  List<PhotoModel> _locationPhotos = [];
  bool _loading = true;
  DateTime? _selectedDate;
  bool _isFilterEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPhotosForLocation();
  }

  Future<void> _loadPhotosForLocation({DateTime? dateFilter}) async {
    setState(() {
      _loading = true;
    });

    print("🔍 Location filter: ${widget.location}");

    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('photos')
              .where('isPublic', isEqualTo: true)
              .where('location', isEqualTo: widget.location)
              .get();

      print("📸 Total documents fetched: ${snapshot.docs.length}");

      final allPhotos =
          snapshot.docs.where((doc) => doc['timestamp'] != null).map((doc) {
            final data = doc.data();
            return PhotoModel.fromMap(data, doc.id);
          }).toList();

      if (_isFilterEnabled && dateFilter != null) {
        print("📅 Date filter ON: ${dateFilter.toIso8601String()}");

        final startDate = DateTime(
          dateFilter.year,
          dateFilter.month,
          dateFilter.day,
        );
        final endDate = startDate.add(const Duration(days: 1));

        final filteredPhotos =
            allPhotos.where((photo) {
                final ts =
                    (photo.timestamp is Timestamp)
                        ? (photo.timestamp as Timestamp).toDate()
                        : DateTime.tryParse(photo.timestamp.toString());

                return ts != null &&
                    ts.isAfter(startDate) &&
                    ts.isBefore(endDate);
              }).toList()
              ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        print("✅ Final matched photos: ${filteredPhotos.length}");
        for (var p in filteredPhotos) {
          print("🖼️ Matched: ${p.caption} at ${p.timestamp}");
        }

        setState(() {
          _locationPhotos = filteredPhotos;
          _loading = false;
        });
      } else {
        print("📅 Date filter OFF");
        allPhotos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        setState(() {
          _locationPhotos = allPhotos;
          _loading = false;
        });
      }
    } catch (e) {
      print("❌ Error fetching photos: $e");
      setState(() {
        _locationPhotos = [];
        _loading = false;
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _isFilterEnabled = true;
      });
      await _loadPhotosForLocation(dateFilter: picked);
    }
  }

  void _toggleFilter() async {
    setState(() {
      _isFilterEnabled = !_isFilterEnabled;
    });
    await _loadPhotosForLocation(dateFilter: _selectedDate);
  }

  Future<Uint8List?> _decodeImage(PhotoModel photo) async {
    print("🖼️ Decoding image for: ${photo.caption}");

    if (photo.imageBase64 != null && photo.imageBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(photo.imageBase64!);
        print("✅ Decoded imageBase64 successfully for: ${photo.caption}");
        return bytes;
      } catch (e) {
        print("❌ Base64 decode failed for ${photo.caption}: $e");
      }
    } else if (photo.imagePath != null && photo.imagePath!.isNotEmpty) {
      print("🌐 Fetching imageBase64 from Firestore for: ${photo.caption}");
      final base64 = await firestoreService.fetchImageBase64(photo.imagePath!);
      if (base64 != null && base64.isNotEmpty) {
        try {
          final bytes = base64Decode(base64);
          print("✅ Fetched + decoded from Firestore: ${photo.caption}");
          return bytes;
        } catch (e) {
          print("❌ Firestore base64 decode failed for ${photo.caption}: $e");
        }
      } else {
        print("⚠️ No base64 found in Firestore for: ${photo.caption}");
      }
    } else {
      print("⚠️ No image data found for: ${photo.caption}");
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "📍 Memories",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_isFilterEnabled && _selectedDate != null)
              Text(
                "📅 ${DateFormat('dd MMM yyyy').format(_selectedDate!)} at ${widget.location}",
                style: const TextStyle(fontSize: 12),
              )
            else
              Text(widget.location, style: const TextStyle(fontSize: 12)),
          ],
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        actions: [
          if (_isFilterEnabled)
            IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: "Pick Date",
              onPressed: _pickDate,
            ),
          IconButton(
            icon: Icon(
              _isFilterEnabled ? Icons.filter_alt : Icons.filter_alt_off,
            ),
            tooltip: _isFilterEnabled ? "Remove Filter" : "Apply Filter",
            onPressed: _toggleFilter,
          ),
        ],
      ),

      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _locationPhotos.isEmpty
              ? const Center(child: Text("No memories found."))
              : GridView.count(
                crossAxisCount: 2,
                padding: const EdgeInsets.all(8),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children:
                    _locationPhotos.map((photo) {
                      return FutureBuilder<Uint8List?>(
                        future: _decodeImage(photo),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (!snapshot.hasData || snapshot.data == null) {
                            return const Center(child: Text("Image error"));
                          }

                          return GestureDetector(
                            // onTap: () {
                            //   Navigator.push(
                            //     context,
                            //     MaterialPageRoute(
                            //       builder:
                            //           (_) =>
                            //               FullscreenImageViewer(photo: photo),
                            //     ),
                            //   );
                            // },
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => FullscreenImageViewer(
                                        photos: _locationPhotos,
                                        initialIndex: _locationPhotos.indexOf(
                                          photo,
                                        ),
                                      ),
                                ),
                              );
                            },

                            child: Hero(
                              tag: "photo_${photo.id}",
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
              ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:memscape/models/photo_model.dart';
// import 'package:memscape/services/firestore_service.dart';
// import 'package:memscape/widgets/photo_card.dart'; // ✅ Import your PhotoCard widget

// class LocationPhotosScreen extends StatefulWidget {
//   final String location;

//   const LocationPhotosScreen({super.key, required this.location});

//   @override
//   State<LocationPhotosScreen> createState() => _LocationPhotosScreenState();
// }

// class _LocationPhotosScreenState extends State<LocationPhotosScreen> {
//   final FirestoreService firestoreService = FirestoreService();
//   List<PhotoModel> _locationPhotos = [];
//   bool _loading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadPhotosForLocation();
//   }

//   Future<void> _loadPhotosForLocation() async {
//     final snapshot =
//         await FirebaseFirestore.instance
//             .collection('photos')
//             .where('isPublic', isEqualTo: true)
//             .where('location', isEqualTo: widget.location)
//             .get();

//     final photos =
//         snapshot.docs
//             .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
//             .toList();

//     setState(() {
//       _locationPhotos = photos;
//       _loading = false;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);

//     return Scaffold(
//       appBar: AppBar(
//         title: Text("📍 Memories at ${widget.location}"),
//         backgroundColor: theme.colorScheme.primary,
//         foregroundColor: theme.colorScheme.onPrimary,
//       ),
//       body:
//           _loading
//               ? const Center(child: CircularProgressIndicator())
//               : _locationPhotos.isEmpty
//               ? const Center(child: Text("No memories found."))
//               : ListView.builder(
//                 padding: const EdgeInsets.only(bottom: 16),
//                 itemCount: _locationPhotos.length,
//                 itemBuilder: (context, index) {
//                   final photo = _locationPhotos[index];
//                   return PhotoCard(photo: photo); // ✅ Using your custom widget
//                 },
//               ),
//     );
//   }
// }
