import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:saver_gallery/saver_gallery.dart';
import '../models/photo_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _realtime = FirebaseDatabase.instance;

  static const String photosCollection = 'photos';
  static const String usersCollection = 'users';
  static const String base64ImagePath = 'images';

  /// Upload base64 to Realtime DB and metadata to Firestore (excluding base64)
  Future<void> uploadPhoto(PhotoModel photo, String base64Image) async {
    try {
      final docRef = _firestore.collection('photos').doc();
      final imagePath = "$base64ImagePath/${docRef.id}";

      await _realtime.ref(imagePath).set(base64Image);
      final updatedPhoto = photo.copyWith(imagePath: imagePath);
      await docRef.set(updatedPhoto.toMap());

      await uploadPhotoReference(photo.uid, docRef.id);
    } catch (e) {
      throw Exception("❌ Firestore uploadPhoto failed: $e");
    }
  }

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
      // 1️⃣ Geocode location
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

      // 2️⃣ Prepare model
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

      // 3️⃣ Encode image and upload
      final base64Image = base64Encode(await imageFile.readAsBytes());
      final docRef = _firestore.collection('photos').doc();
      final imagePath = "$base64ImagePath/${docRef.id}";

      await _realtime.ref(imagePath).set(base64Image);
      await docRef.set(photo.copyWith(imagePath: imagePath).toMap());

      await uploadPhotoReference(uid, docRef.id);
    } catch (e) {
      throw Exception("❌ uploadFullMemory failed: $e");
    }
  }

  /// Fetch public photos (limit optional)
  // Future<List<PhotoModel>> fetchPublicPhotos({int limit = 20}) async {
  //   try {
  //     final querySnapshot =
  //         await _firestore
  //             .collection(photosCollection)
  //             .where('isPublic', isEqualTo: true)
  //             .orderBy('timestamp', descending: true)
  //             .limit(limit)
  //             .get();

  //     return querySnapshot.docs
  //         .map((doc) => PhotoModel.fromMap(doc.data(), doc.id))
  //         .toList();
  //   } catch (e) {
  //     throw Exception("❌ Firestore fetchPublicPhotos failed: $e");
  //   }
  // }

  Future<List<PhotoModel>> fetchPublicPhotos() async {
    try {
      final querySnapshot =
          await FirebaseFirestore.instance
              .collection('photos')
              .where('isPublic', isEqualTo: true)
              .orderBy('timestamp', descending: true)
              .get();

      return querySnapshot.docs
          .map((doc) => PhotoModel.fromMap(doc.data()))
          .toList();
    } catch (e) {
      debugPrint("❌ Firestore fetchPublicPhotos failed: $e");
      throw Exception("❌ Firestore fetchPublicPhotos failed: $e");
    }
  }

  /// Real-time public photo stream
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

  /// Store reference in user's document
  Future<void> uploadPhotoReference(String uid, String imageId) async {
    try {
      await _firestore.collection(usersCollection).doc(uid).set({
        'photoRefs': FieldValue.arrayUnion([imageId]),
        'bio': "New memory added 🎉",
      }, SetOptions(merge: true));
    } catch (e) {
      throw Exception("❌ Failed to update user photoRefs: $e");
    }
  }

  /// Stream photo reference IDs from user doc
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

  /// Fetch all photos uploaded by specific user
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

  /// Toggle like for a photo
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

  /// Add comment to a photo
  Future<void> addComment(
    String photoId,
    String uid,
    String commentText,
  ) async {
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final username = userDoc['username'] ?? 'User';

    final comment = {
      'uid': uid,
      'username': username,
      'text': commentText,
      'timestamp':
          Timestamp.now(), // ✅ use real timestamp instead of serverTimestamp()
    };

    await FirebaseFirestore.instance.collection('photos').doc(photoId).update({
      'comments': FieldValue.arrayUnion([comment]),
    });
  }

  /// Fetch base64 image using imagePath
  Future<String?> fetchImageBase64(String imagePath) async {
    try {
      final snapshot = await _realtime.ref(imagePath).get();
      return snapshot.exists ? snapshot.value as String : null;
    } catch (e) {
      throw Exception("❌ Failed to fetch base64 image: $e");
    }
  }

  /// Follow/unfollow user
  Future<void> toggleFollow(String currentUserId, String targetUserId) async {
    final currentUserRef = _firestore
        .collection(usersCollection)
        .doc(currentUserId);
    final targetUserRef = _firestore
        .collection(usersCollection)
        .doc(targetUserId);

    final currentSnap = await currentUserRef.get();
    final currentData = currentSnap.data() ?? {};
    final currentFollowing = (currentData['following'] as List?) ?? [];
    final isFollowing = currentFollowing.contains(targetUserId);

    await currentUserRef.update({
      'following':
          isFollowing
              ? FieldValue.arrayRemove([targetUserId])
              : FieldValue.arrayUnion([targetUserId]),
    });

    await targetUserRef.update({
      'followers':
          isFollowing
              ? FieldValue.arrayRemove([currentUserId])
              : FieldValue.arrayUnion([currentUserId]),
    });
  }

  /// Check if current user follows the target user
  Future<bool> isFollowing(String currentUserId, String targetUserId) async {
    final currentUserSnap =
        await _firestore.collection(usersCollection).doc(currentUserId).get();
    final currentData = currentUserSnap.data() ?? {};
    final currentFollowing = (currentData['following'] as List?) ?? [];
    return currentFollowing.contains(targetUserId);
  }

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

    print("💾 Gallery Save Result: $result");
  }
}

// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_database/firebase_database.dart';
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
//       final docRef = _firestore.collection(photosCollection).doc();
//       final imagePath = "$base64ImagePath/${docRef.id}";

//       // Upload base64 image to Realtime Database
//       await _realtime.ref(imagePath).set(base64Image);

//       // Upload metadata to Firestore (excluding imageBase64)
//       final updatedPhoto = photo.copyWith(
//         imagePath: imagePath,
//         imageBase64: null,
//       );
//       await docRef.set(updatedPhoto.toMap());

//       // Add reference to user's document
//       await uploadPhotoReference(photo.uid, docRef.id);

//       print("✅ Firestore: Metadata saved | Realtime DB imagePath → $imagePath");
//     } catch (e) {
//       throw Exception("❌ Firestore uploadPhoto failed: $e");
//     }
//   }

//   /// Fetch public photos (limit optional)
//   Future<List<PhotoModel>> fetchPublicPhotos({int limit = 20}) async {
//     try {
//       final querySnapshot =
//           await _firestore
//               .collection(photosCollection)
//               .where('isPublic', isEqualTo: true)
//               .orderBy('timestamp', descending: true)
//               .limit(limit)
//               .get();

//       return querySnapshot.docs
//           .map((doc) => PhotoModel.fromMap(doc.data()))
//           .toList();
//     } catch (e) {
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
//                   .map((doc) => PhotoModel.fromMap(doc.data()))
//                   .toList(),
//         );
//   }

//   /// Store reference in user's document
//   Future<void> uploadPhotoReference(String uid, String imageId) async {
//     try {
//       await _firestore.collection(usersCollection).doc(uid).set({
//         'photoRefs': FieldValue.arrayUnion([imageId]),
//         'bio': "New memory added 🎉",
//       }, SetOptions(merge: true));
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
//           .map((doc) => PhotoModel.fromMap(doc.data()))
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
//     String userId,
//     String commentText,
//   ) async {
//     final ref = _firestore.collection(photosCollection).doc(photoId);
//     final snap = await ref.get();

//     if (!snap.exists) return;

//     final newComment = {
//       'uid': userId,
//       'text': commentText,
//       'timestamp': FieldValue.serverTimestamp(),
//     };

//     await ref.update({
//       'comments': FieldValue.arrayUnion([newComment]),
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
// }
