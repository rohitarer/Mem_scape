import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';

import '../models/photo_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _realtime = FirebaseDatabase.instance;

  static const String photosCollection = 'photos';
  static const String usersCollection = 'users';

  // Realtime DB roots
  static const String base64ImagePath = 'images'; // images/<id>
  static const String videosBasePath = 'videos'; // videos/<id>/chunks

  // Chunking config for video base64 in RTDB
  // (Keep videos short; base64 inflates size by ~33%.)
  static const int kChunkSizeBytes = 256 * 1024; // 256 KB per chunk

  // --------------------------
  // Helpers
  // --------------------------
  bool _isVideoPath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.m4v') ||
        p.endsWith('.webm') ||
        p.endsWith('.avi');
  }

  String _guessMimeFromPath(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.mp4')) return 'video/mp4';
    if (p.endsWith('.mov')) return 'video/quicktime';
    if (p.endsWith('.m4v')) return 'video/x-m4v';
    if (p.endsWith('.webm')) return 'video/webm';
    if (p.endsWith('.avi')) return 'video/x-msvideo';
    return 'application/octet-stream';
  }

  Future<Map<String, dynamic>> _uploadOneImageToRTDB({
    required List<int> bytes,
    required String idPrefix,
  }) async {
    final mediaId = "${idPrefix}_${DateTime.now().millisecondsSinceEpoch}";
    final path = "$base64ImagePath/$mediaId";
    final b64 = base64Encode(bytes);
    await _realtime.ref(path).set(b64);

    return {
      'type': 'image',
      'path': path, // RTDB path to full base64 image
      'mime': 'image/*', // best-effort; viewer can infer if needed
      'chunked': false,
    };
  }

  Future<Map<String, dynamic>> _uploadOneVideoToRTDB({
    required List<int> bytes,
    required String idPrefix,
    required String mime,
  }) async {
    final mediaId = "${idPrefix}_${DateTime.now().millisecondsSinceEpoch}";
    final root = "$videosBasePath/$mediaId";
    final chunksPath = "$root/chunks";

    final total = bytes.length;
    final chunkCount = (total / kChunkSizeBytes).ceil();

    for (int i = 0; i < chunkCount; i++) {
      final start = i * kChunkSizeBytes;
      final end = min(start + kChunkSizeBytes, total);
      final chunk = bytes.sublist(start, end);
      final b64 = base64Encode(chunk);
      final key = 'chunk_${(i + 1).toString().padLeft(4, '0')}';
      await _realtime.ref("$chunksPath/$key").set(b64);
    }

    // Optional manifest (useful for reassembly)
    await _realtime.ref("$root/manifest").set({
      'mime': mime,
      'size': total,
      'chunkSize': kChunkSizeBytes,
      'chunkCount': chunkCount,
      'createdAt': ServerValue.timestamp,
    });

    return {
      'type': 'video',
      'path': chunksPath, // RTDB path to chunks
      'mime': mime,
      'chunked': true,
      'chunkCount': chunkCount,
    };
  }

  // --------------------------
  // Single-image legacy upload (kept as-is)
  // --------------------------
  /// Upload base64 to Realtime DB and metadata to Firestore (excluding base64)
  Future<void> uploadPhoto(PhotoModel photo, String base64Image) async {
    try {
      final docRef = _firestore.collection(photosCollection).doc();
      final imagePath = "$base64ImagePath/${docRef.id}";

      await _realtime.ref(imagePath).set(base64Image);
      final updatedPhoto = photo.copyWith(imagePath: imagePath);
      await docRef.set(updatedPhoto.toMap());

      await uploadPhotoReference(photo.uid, docRef.id);
    } catch (e) {
      throw Exception("❌ Firestore uploadPhoto failed: $e");
    }
  }

  // --------------------------
  // Single-image “full memory” legacy (kept)
  // --------------------------
  Future<void> uploadFullMemory({
    required File imageFile,
    required String caption,
    required String locationInput,
    required bool isPublic,
    required String uid,
    double? fallbackLat,
    double? fallbackLng,
  }) async {
    try {
      // 1) Geocode
      double lat, lng;
      String country = "Unknown", state = "Unknown", city = "Unknown";

      try {
        final locationList = await locationFromAddress(locationInput);
        lat = locationList.first.latitude;
        lng = locationList.first.longitude;

        final placemarks = await placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          final mark = placemarks.first;
          country = mark.country ?? "Unknown";
          state = mark.administrativeArea ?? "Unknown";
          city = mark.locality ?? mark.subAdministrativeArea ?? "Unknown";
        }
      } catch (e) {
        if (fallbackLat != null && fallbackLng != null) {
          lat = fallbackLat;
          lng = fallbackLng;
        } else {
          throw Exception("❌ Geocoding failed: $e");
        }
      }

      final readablePlace = [
        city,
        state,
        country,
      ].where((e) => e != "Unknown").join(', ');

      // 2) Prepare model
      final photo = PhotoModel(
        uid: uid,
        caption: caption,
        location: locationInput,
        timestamp: DateTime.now(),
        lat: lat,
        lng: lng,
        isPublic: isPublic,
        place: readablePlace.isNotEmpty ? readablePlace : "Unknown",
      );

      // 3) Encode image and upload
      final base64Image = base64Encode(await imageFile.readAsBytes());
      final docRef = _firestore.collection(photosCollection).doc();
      final imagePath = "$base64ImagePath/${docRef.id}";

      await _realtime.ref(imagePath).set(base64Image);

      final data = photo.copyWith(imagePath: imagePath).toMap();
      await docRef.set(data);
      await uploadPhotoReference(uid, docRef.id);
    } catch (e) {
      throw Exception("❌ uploadFullMemory failed: $e");
    }
  }

  // --------------------------
  // NEW: Multi-media (images + videos) upload
  // Stores media in RTDB (images as a single base64; videos as chunks)
  // Writes Firestore doc with:
  //  - imagePath (first image for backward compatibility)
  //  - media: [ {type, path, mime, chunked, chunkCount?}, ... ]
  // --------------------------
  Future<void> uploadMemoryWithMedia({
    required List<File> files,
    required String caption,
    required String locationInput,
    required bool isPublic,
    required String uid,
    double? fallbackLat,
    double? fallbackLng,
  }) async {
    if (files.isEmpty) {
      throw Exception("No media selected.");
    }

    // 1) Geocode (best-effort; falls back to provided lat/lng if available)
    double lat = fallbackLat ?? 0;
    double lng = fallbackLng ?? 0;
    String country = "Unknown", state = "Unknown", city = "Unknown";
    try {
      final locationList = await locationFromAddress(locationInput);
      lat = locationList.first.latitude;
      lng = locationList.first.longitude;
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final m = placemarks.first;
        country = m.country ?? "Unknown";
        state = m.administrativeArea ?? "Unknown";
        city = m.locality ?? m.subAdministrativeArea ?? "Unknown";
      }
    } catch (_) {
      // ignore; keep fallbacks/zeros
    }
    final place = [
      city,
      state,
      country,
    ].where((e) => e != "Unknown").join(', ');

    // 2) Create Firestore doc id (reuse as prefix for RTDB keys)
    final docRef = _firestore.collection(photosCollection).doc();
    final idPrefix = docRef.id;

    // 3) Upload each media item to RTDB
    final List<Map<String, dynamic>> mediaList = [];
    String? firstImagePathForCompat;

    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (_isVideoPath(file.path)) {
        final mime = _guessMimeFromPath(file.path);
        final meta = await _uploadOneVideoToRTDB(
          bytes: bytes,
          idPrefix: idPrefix,
          mime: mime,
        );
        mediaList.add(meta);
      } else {
        final meta = await _uploadOneImageToRTDB(
          bytes: bytes,
          idPrefix: idPrefix,
        );
        mediaList.add(meta);
        // keep the first IMAGE path as imagePath for older UIs
        firstImagePathForCompat ??= meta['path'] as String?;
      }
    }

    // 4) Build PhotoModel (backward compatible)
    final photo = PhotoModel(
      uid: uid,
      caption: caption,
      location: locationInput,
      place: place.isEmpty ? "Unknown" : place,
      timestamp: DateTime.now(),
      lat: lat,
      lng: lng,
      isPublic: isPublic,
      imagePath: firstImagePathForCompat, // null if no images were selected
    );

    // 5) Write metadata to Firestore (inject media list manually to avoid changing your model right now)
    final data = photo.toMap();
    data['media'] = mediaList;

    await docRef.set(data);

    // 6) Link imageId in user doc
    await uploadPhotoReference(uid, docRef.id);
  }

  // --------------------------
  // Feeds & queries
  // --------------------------
  Future<List<PhotoModel>> fetchPublicPhotos() async {
    try {
      final querySnapshot =
          await _firestore
              .collection(photosCollection)
              .where('isPublic', isEqualTo: true)
              .orderBy('timestamp', descending: true)
              .get();

      return querySnapshot.docs
          .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint("❌ Firestore fetchPublicPhotos failed: $e");
      throw Exception("❌ Firestore fetchPublicPhotos failed: $e");
    }
  }

  Stream<List<PhotoModel>> getPublicPhotoStream() {
    return _firestore
        .collection(photosCollection)
        .where('isPublic', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs
                  .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
                  .toList(),
        );
  }

  Future<List<PhotoModel>> fetchUserPhotos({required String userId}) async {
    try {
      final snapshot =
          await _firestore
              .collection(photosCollection)
              .where('uid', isEqualTo: userId)
              .orderBy('timestamp', descending: true)
              .get();

      return snapshot.docs
          .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception("❌ Firestore fetchUserPhotos failed: $e");
    }
  }

  Future<List<PhotoModel>> fetchUserPhotosForViewer({
    required String ownerUid,
    required String viewerUid,
  }) async {
    try {
      fs.Query<Map<String, dynamic>> q = _firestore
          .collection(photosCollection)
          .where('uid', isEqualTo: ownerUid);

      if (viewerUid != ownerUid) {
        q = q.where('isPublic', isEqualTo: true);
      }

      final snapshot = await q.orderBy('timestamp', descending: true).get();
      return snapshot.docs
          .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      throw Exception("❌ Firestore fetchUserPhotosForViewer failed: $e");
    }
  }

  // --------------------------
  // Social actions
  // --------------------------
  Future<void> toggleLike(String photoId, String userId) async {
    final ref = _firestore.collection(photosCollection).doc(photoId);
    final snap = await ref.get();

    if (!snap.exists) return;

    final likes = (snap.data()?['likes'] as List?) ?? [];
    final isLiked = likes.contains(userId);
    await ref.update({
      'likes':
          isLiked
              ? FieldValue.arrayRemove([userId])
              : FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> addComment(
    String photoId,
    String uid,
    String commentText,
  ) async {
    final userDoc = await _firestore.collection(usersCollection).doc(uid).get();
    final username = userDoc.data()?['username'] ?? 'User';

    final comment = {
      'uid': uid,
      'username': username,
      'text': commentText,
      'timestamp': Timestamp.now(),
    };

    await _firestore.collection(photosCollection).doc(photoId).update({
      'comments': FieldValue.arrayUnion([comment]),
    });
  }

  // --------------------------
  // User refs
  // --------------------------
  Future<void> uploadPhotoReference(String uid, String imageId) async {
    try {
      await _firestore.collection(usersCollection).doc(uid).set({
        'photoRefs': FieldValue.arrayUnion([imageId]),
        'bio': "New memory added 🎉",
      }, SetOptions(merge: true));

      await _firestore
          .collection(usersCollection)
          .doc(uid)
          .collection('photoRefs')
          .doc(imageId)
          .set({
            'imagePath': 'images/$imageId',
            'timestamp': FieldValue.serverTimestamp(),
          });

      debugPrint('✅ photoRefs updated successfully');
    } catch (e) {
      throw Exception("❌ Failed to update user photoRefs: $e");
    }
  }

  Stream<List<String>> getUserPhotoReferences(String uid) {
    return _firestore.collection(usersCollection).doc(uid).snapshots().map((
      doc,
    ) {
      final data = doc.data();
      if (data == null || !data.containsKey('photoRefs')) return [];
      final List<dynamic> rawList = data['photoRefs'];
      return rawList.map((e) => e.toString()).toList();
    });
  }

  // --------------------------
  // RTDB image fetch / save
  // --------------------------
  Future<String?> fetchImageBase64(String imagePath) async {
    try {
      final snapshot = await _realtime.ref(imagePath).get();
      return snapshot.exists ? snapshot.value as String : null;
    } catch (e) {
      throw Exception("❌ Failed to fetch base64 image: $e");
    }
  }

  Future<String?> fetchProfileBase64(String? imagePath) async {
    if (imagePath == null || imagePath.isEmpty) return null;
    return await fetchImageBase64(imagePath);
  }

  // Gallery save helper (kept)
  Future<bool> requestPermissions({required bool skipIfExists}) async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      return sdkInt >= 33
          ? await Permission.photos.request().isGranted
          : await Permission.storage.request().isGranted;
    } else if (Platform.isIOS) {
      return skipIfExists
          ? await Permission.photos.request().isGranted
          : await Permission.photosAddOnly.request().isGranted;
    }
    return false;
  }

  Future<void> saveBase64ImageToGallery(String base64Data) async {
    final hasPermission = await requestPermissions(skipIfExists: false);
    if (!hasPermission) return;

    Uint8List bytes = base64Decode(base64Data);
    final result = await SaverGallery.saveImage(
      bytes,
      quality: 90,
      fileName: "memscape_image_${DateTime.now().millisecondsSinceEpoch}.jpg",
      androidRelativePath: "Pictures/Memscape",
      skipIfExists: false,
    );

    debugPrint("💾 Gallery Save Result: $result");
  }
}




// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:cloud_firestore/cloud_firestore.dart' as fs;
// import 'package:device_info_plus/device_info_plus.dart';
// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/material.dart';
// import 'package:geocoding/geocoding.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:saver_gallery/saver_gallery.dart';
// import '../models/photo_model.dart';

// class FirestoreService {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//   final FirebaseDatabase _realtime = FirebaseDatabase.instance;

//   static const String photosCollection = 'photos';
//   static const String usersCollection = 'users';
//   static const String base64ImagePath = 'images';
  

//   /// Upload base64 to Realtime DB and metadata to Firestore (excluding base64)
//   Future<void> uploadPhoto(PhotoModel photo, String base64Image) async {
//     try {
//       final docRef = _firestore.collection('photos').doc();
//       final imagePath = "$base64ImagePath/${docRef.id}";

//       await _realtime.ref(imagePath).set(base64Image);
//       final updatedPhoto = photo.copyWith(imagePath: imagePath);
//       await docRef.set(updatedPhoto.toMap());

//       await uploadPhotoReference(photo.uid, docRef.id);
//     } catch (e) {
//       throw Exception("❌ Firestore uploadPhoto failed: $e");
//     }
//   }

//   Future<void> uploadFullMemory({
//     required File imageFile,
//     required String caption,
//     required String locationInput,
//     required bool isPublic,
//     required String uid,
//     double? fallbackLat,
//     double? fallbackLng,
//   }) async {
//     try {
//       // 1️⃣ Geocode location
//       double lat, lng;
//       String country = "Unknown", state = "Unknown", city = "Unknown";

//       try {
//         final locationList = await locationFromAddress(locationInput);
//         lat = locationList.first.latitude;
//         lng = locationList.first.longitude;

//         final placemarks = await placemarkFromCoordinates(lat, lng);
//         if (placemarks.isNotEmpty) {
//           final mark = placemarks.first;
//           country = mark.country ?? "Unknown";
//           state = mark.administrativeArea ?? "Unknown";
//           city = mark.locality ?? mark.subAdministrativeArea ?? "Unknown";
//         }
//       } catch (e) {
//         if (fallbackLat != null && fallbackLng != null) {
//           lat = fallbackLat;
//           lng = fallbackLng;
//         } else {
//           throw Exception("❌ Geocoding failed: $e");
//         }
//       }

//       final readablePlace = [
//         city,
//         state,
//         country,
//       ].where((e) => e != "Unknown").join(', ');

//       // 2️⃣ Prepare model
//       final photo = PhotoModel(
//         uid: uid,
//         caption: caption,
//         location: locationInput,
//         timestamp: DateTime.now(),
//         lat: lat,
//         lng: lng,
//         isPublic: isPublic,
//         place: readablePlace.isNotEmpty ? readablePlace : "Unknown",
//       );

//       // 3️⃣ Encode image and upload
//       final base64Image = base64Encode(await imageFile.readAsBytes());
//       final docRef = _firestore.collection('photos').doc();
//       final imagePath = "$base64ImagePath/${docRef.id}";

//       await _realtime.ref(imagePath).set(base64Image);
//       await docRef.set(photo.copyWith(imagePath: imagePath).toMap());

//       await uploadPhotoReference(uid, docRef.id);
//     } catch (e) {
//       throw Exception("❌ uploadFullMemory failed: $e");
//     }
//   }

//   /// Fetch public photos (limit optional)
//   // Future<List<PhotoModel>> fetchPublicPhotos({int limit = 20}) async {
//   //   try {
//   //     final querySnapshot =
//   //         await _firestore
//   //             .collection(photosCollection)
//   //             .where('isPublic', isEqualTo: true)
//   //             .orderBy('timestamp', descending: true)
//   //             .limit(limit)
//   //             .get();

//   //     return querySnapshot.docs
//   //         .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
//   //         .toList();
//   //   } catch (e) {
//   //     throw Exception("❌ Firestore fetchPublicPhotos failed: $e");
//   //   }
//   // }

//   Future<List<PhotoModel>> fetchPublicPhotos() async {
//     try {
//       final querySnapshot =
//           await FirebaseFirestore.instance
//               .collection('photos')
//               .where('isPublic', isEqualTo: true)
//               .orderBy('timestamp', descending: true)
//               .get();

//       return querySnapshot.docs
//           .map((doc) => PhotoModel.fromMap(doc.data()))
//           .toList();
//     } catch (e) {
//       debugPrint("❌ Firestore fetchPublicPhotos failed: $e");
//       throw Exception("❌ Firestore fetchPublicPhotos failed: $e");
//     }
//   }

//   /// Real-time public photo stream
//   Stream<List<PhotoModel>> getPublicPhotoStream() {
//     return _firestore
//         .collection(photosCollection)
//         .where('isPublic', isEqualTo: true)
//         .orderBy('timestamp', descending: true)
//         .snapshots()
//         .map(
//           (snapshot) =>
//               snapshot.docs
//                   .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
//                   .toList(),
//         );
//   }

//   /// Store reference in user's document
//   // Future<void> uploadPhotoReference(String uid, String imageId) async {
//   //   try {
//   //     await _firestore.collection(usersCollection).doc(uid).set({
//   //       'photoRefs': FieldValue.arrayUnion([imageId]),
//   //       'bio': "New memory added 🎉",
//   //     }, SetOptions(merge: true));
//   //   } catch (e) {
//   //     throw Exception("❌ Failed to update user photoRefs: $e");
//   //   }
//   // }
//   Future<void> uploadPhotoReference(String uid, String imageId) async {
//     try {
//       // Update photoRefs array + user bio (optional)
//       await _firestore.collection(usersCollection).doc(uid).set({
//         'photoRefs': FieldValue.arrayUnion([imageId]),
//         'bio': "New memory added 🎉",
//       }, SetOptions(merge: true));

//       // ✅ Also store imageId in a subcollection for advanced querying
//       await _firestore
//           .collection(usersCollection)
//           .doc(uid)
//           .collection('photoRefs')
//           .doc(imageId)
//           .set({
//             'imagePath': 'images/$imageId', // Optional field to help later
//             'timestamp': FieldValue.serverTimestamp(), // Optional
//           });

//       debugPrint('✅ photoRefs updated successfully');
//     } catch (e) {
//       throw Exception("❌ Failed to update user photoRefs: $e");
//     }
//   }

//   /// Stream photo reference IDs from user doc
//   Stream<List<String>> getUserPhotoReferences(String uid) {
//     return _firestore.collection(usersCollection).doc(uid).snapshots().map((
//       doc,
//     ) {
//       final data = doc.data();
//       if (data == null || !data.containsKey('photoRefs')) return [];
//       final List<dynamic> rawList = data['photoRefs'];
//       return rawList.map((e) => e.toString()).toList();
//     });
//   }

//   /// Fetch all photos uploaded by specific user
//   Future<List<PhotoModel>> fetchUserPhotos({required String userId}) async {
//     try {
//       final snapshot =
//           await _firestore
//               .collection(photosCollection)
//               .where('uid', isEqualTo: userId)
//               .orderBy('timestamp', descending: true)
//               .get();

//       return snapshot.docs
//           .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
//           .toList();
//     } catch (e) {
//       throw Exception("❌ Firestore fetchUserPhotos failed: $e");
//     }
//   }

//   /// Toggle like for a photo
//   Future<void> toggleLike(String photoId, String userId) async {
//     final ref = _firestore.collection(photosCollection).doc(photoId);
//     final snap = await ref.get();

//     if (!snap.exists) return;

//     final likes = (snap.data()?['likes'] as List?) ?? [];

//     final isLiked = likes.contains(userId);
//     await ref.update({
//       'likes':
//           isLiked
//               ? FieldValue.arrayRemove([userId])
//               : FieldValue.arrayUnion([userId]),
//     });
//   }

//   /// Add comment to a photo
//   Future<void> addComment(
//     String photoId,
//     String uid,
//     String commentText,
//   ) async {
//     final userDoc =
//         await FirebaseFirestore.instance.collection('users').doc(uid).get();
//     final username = userDoc['username'] ?? 'User';

//     final comment = {
//       'uid': uid,
//       'username': username,
//       'text': commentText,
//       'timestamp':
//           Timestamp.now(), // ✅ use real timestamp instead of serverTimestamp()
//     };

//     await FirebaseFirestore.instance.collection('photos').doc(photoId).update({
//       'comments': FieldValue.arrayUnion([comment]),
//     });
//   }

//   /// Fetch base64 image using imagePath
//   Future<String?> fetchImageBase64(String imagePath) async {
//     try {
//       final snapshot = await _realtime.ref(imagePath).get();
//       return snapshot.exists ? snapshot.value as String : null;
//     } catch (e) {
//       throw Exception("❌ Failed to fetch base64 image: $e");
//     }
//   }

//   /// ✅ Wrapper with a null/empty guard (this is what your screen calls)
//   Future<String?> fetchProfileBase64(String? imagePath) async {
//     if (imagePath == null || imagePath.isEmpty) return null;
//     return await fetchImageBase64(imagePath);
//   }

//   Future<List<PhotoModel>> fetchUserPhotosForViewer({
//     required String ownerUid,
//     required String viewerUid,
//   }) async {
//     try {
//       fs.Query<Map<String, dynamic>> q = _firestore
//           .collection(photosCollection)
//           .where('uid', isEqualTo: ownerUid);

//       if (viewerUid != ownerUid) {
//         q = q.where('isPublic', isEqualTo: true);
//       }

//       final snapshot = await q.orderBy('timestamp', descending: true).get();
//       return snapshot.docs
//           .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
//           .toList();
//     } catch (e) {
//       throw Exception("❌ Firestore fetchUserPhotosForViewer failed: $e");
//     }
//   }

//   /// Follow/unfollow user
//   Future<void> toggleFollow(String currentUserId, String targetUserId) async {
//     final currentUserRef = _firestore
//         .collection(usersCollection)
//         .doc(currentUserId);
//     final targetUserRef = _firestore
//         .collection(usersCollection)
//         .doc(targetUserId);

//     final currentSnap = await currentUserRef.get();
//     final currentData = currentSnap.data() ?? {};
//     final currentFollowing = (currentData['following'] as List?) ?? [];
//     final isFollowing = currentFollowing.contains(targetUserId);

//     await currentUserRef.update({
//       'following':
//           isFollowing
//               ? FieldValue.arrayRemove([targetUserId])
//               : FieldValue.arrayUnion([targetUserId]),
//     });

//     await targetUserRef.update({
//       'followers':
//           isFollowing
//               ? FieldValue.arrayRemove([currentUserId])
//               : FieldValue.arrayUnion([currentUserId]),
//     });
//   }

//   /// Check if current user follows the target user
//   Future<bool> isFollowing(String currentUserId, String targetUserId) async {
//     final currentUserSnap =
//         await _firestore.collection(usersCollection).doc(currentUserId).get();
//     final currentData = currentUserSnap.data() ?? {};
//     final currentFollowing = (currentData['following'] as List?) ?? [];
//     return currentFollowing.contains(targetUserId);
//   }

//   Future<bool> requestPermissions({required bool skipIfExists}) async {
//     if (Platform.isAndroid) {
//       final androidInfo = await DeviceInfoPlugin().androidInfo;
//       final sdkInt = androidInfo.version.sdkInt;
//       return sdkInt >= 33
//           ? await Permission.photos.request().isGranted
//           : await Permission.storage.request().isGranted;
//     } else if (Platform.isIOS) {
//       return skipIfExists
//           ? await Permission.photos.request().isGranted
//           : await Permission.photosAddOnly.request().isGranted;
//     }
//     return false;
//   }

//   Future<void> saveBase64ImageToGallery(String base64Data) async {
//     final hasPermission = await requestPermissions(skipIfExists: false);
//     if (!hasPermission) return;

//     Uint8List bytes = base64Decode(base64Data);
//     final result = await SaverGallery.saveImage(
//       bytes,
//       quality: 90,
//       fileName: "memscape_image_${DateTime.now().millisecondsSinceEpoch}.jpg",
//       androidRelativePath: "Pictures/Memscape",
//       skipIfExists: false,
//     );

//     print("💾 Gallery Save Result: $result");
//   }
// }
