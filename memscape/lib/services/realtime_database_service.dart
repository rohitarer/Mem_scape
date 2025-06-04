import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../models/photo_model.dart';

class RealtimeDatabaseService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  /// 🔼 Upload base64 image to /images/{imageId}
  // Future<void> uploadBase64Image(String imageId, String base64) async {
  //   try {
  //     await _db.child('images').child(imageId).set(base64);
  //     debugPrint("🖼️ Base64 image uploaded to /images/$imageId");
  //   } catch (e) {
  //     throw Exception("❌ Failed to upload base64 image: $e");
  //   }
  // }

  // /// 🔼 Upload photo metadata (without base64) to /photos/{uid}/{imageId}
  // Future<void> uploadPhotoMetadata(PhotoModel photo, String imageId) async {
  //   try {
  //     await _db
  //         .child('photos')
  //         .child(photo.uid)
  //         .child(imageId)
  //         .set(
  //           photo
  //               .copyWith(imageBase64: null, imagePath: "images/$imageId")
  //               .toMap(),
  //         );

  //     debugPrint("✅ Metadata uploaded for user ${photo.uid} → $imageId");
  //   } catch (e) {
  //     throw Exception("❌ Failed to upload metadata: $e");
  //   }
  // }

  // /// 🚀 High-level function to upload photo + base64 together
  // Future<void> uploadPhoto(PhotoModel photo) async {
  //   final imageId =
  //       "${photo.caption}_${photo.timestamp.millisecondsSinceEpoch}";

  //   await uploadBase64Image(imageId, photo.imageBase64 ?? '');
  //   await uploadPhotoMetadata(photo, imageId);
  // }

  /// ✅ Upload base64 image to Realtime DB under /images/{imageId}
  Future<void> uploadBase64Image(String imageId, String base64) async {
    try {
      await _db.child('images').child(imageId).set(base64);
      debugPrint("🖼️ Base64 image uploaded at images/$imageId");
    } catch (e) {
      throw Exception("❌ Failed to upload base64 image: $e");
    }
  }

  /// 🔼 Upload metadata (excluding base64) to /photos/{uid}/{imageId}
  Future<void> uploadPhotoMetadata(PhotoModel photo, String imageId) async {
    try {
      final metadata =
          photo
              .copyWith(imageBase64: null, imagePath: "images/$imageId")
              .toMap();

      await _db.child('photos').child(photo.uid).child(imageId).set(metadata);

      debugPrint("✅ Metadata uploaded for ${photo.uid} → $imageId");
    } catch (e) {
      throw Exception("❌ Failed to upload metadata: $e");
    }
  }

  /// 🚀 High-level function: Upload photo base64 + metadata
  Future<void> uploadPhoto(PhotoModel photo) async {
    final imageId =
        "${photo.caption}_${photo.timestamp.millisecondsSinceEpoch}";

    await uploadBase64Image(imageId, photo.imageBase64 ?? '');
    await uploadPhotoMetadata(photo, imageId);
  }

  /// 📥 Fetch all photos from all users (for map/explore)
  // Future<List<PhotoModel>> getAllPhotos() async {
  //   try {
  //     final snapshot = await _db.child('photos').get();
  //     if (!snapshot.exists || snapshot.value == null) return [];

  //     final Map data = snapshot.value as Map;
  //     final List<PhotoModel> allPhotos = [];

  //     for (final uidEntry in data.entries) {
  //       if (uidEntry.value is! Map) continue;

  //       final userPhotos = uidEntry.value as Map;
  //       for (final photoEntry in userPhotos.entries) {
  //         try {
  //           final map = Map<String, dynamic>.from(photoEntry.value);
  //           allPhotos.add(PhotoModel.fromMap(map));
  //         } catch (e) {
  //           debugPrint("⚠️ Skipped malformed photo entry: $e");
  //         }
  //       }
  //     }

  //     return allPhotos;
  //   } catch (e) {
  //     throw Exception("❌ Error fetching all photos: $e");
  //   }
  // }

  Future<List<PhotoModel>> getAllPhotos() async {
    try {
      final snapshot = await _db.child('photos').get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final Map<dynamic, dynamic> data =
          snapshot.value as Map<dynamic, dynamic>;
      final List<PhotoModel> allPhotos = [];

      for (final uidEntry in data.entries) {
        if (uidEntry.value is! Map) continue;

        final userPhotos = uidEntry.value as Map<dynamic, dynamic>;
        for (final photoEntry in userPhotos.entries) {
          try {
            final map = Map<String, dynamic>.from(photoEntry.value);
            final id = photoEntry.key.toString(); // Set the photo's ID
            allPhotos.add(PhotoModel.fromMap(map, id));
          } catch (e) {
            debugPrint(
              "⚠️ Skipped malformed photo entry under user ${uidEntry.key}: $e",
            );
          }
        }
      }

      debugPrint("✅ Total photos loaded: ${allPhotos.length}");
      return allPhotos;
    } catch (e) {
      debugPrint("❌ Error fetching all photos: $e");
      throw Exception("Error fetching photos: $e");
    }
  }

  /// 👤 Fetch photos for a specific user
  Future<List<PhotoModel>> fetchPhotosForUser(String uid) async {
    try {
      final snapshot = await _db.child('photos').child(uid).get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final data = snapshot.value as Map;
      return data.entries.map((entry) {
        final map = Map<String, dynamic>.from(entry.value);
        return PhotoModel.fromMap(map);
      }).toList();
    } catch (e) {
      throw Exception("❌ Error fetching user photos: $e");
    }
  }

  /// 🌐 Fetch last 20 public photos sorted by timestamp (desc)
  Future<List<PhotoModel>> fetchPublicPhotos() async {
    try {
      final snapshot = await _db.child('photos').get();
      if (!snapshot.exists || snapshot.value == null) return [];

      final List<PhotoModel> publicPhotos = [];

      for (final userNode in snapshot.children) {
        for (final photoNode in userNode.children) {
          try {
            final photoMap = photoNode.value as Map;
            final photo = PhotoModel.fromMap(
              Map<String, dynamic>.from(photoMap),
            );
            if (photo.isPublic) {
              publicPhotos.add(photo);
            }
          } catch (e) {
            debugPrint("⚠️ Invalid public photo entry: $e");
          }
        }
      }

      publicPhotos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return publicPhotos.take(20).toList();
    } catch (e) {
      throw Exception("❌ Error fetching public photos: $e");
    }
  }

  /// 🧲 Fetch base64 image by imagePath (e.g., "images/imageId")
  Future<String?> fetchBase64Image(String imagePath) async {
    try {
      final snapshot = await _db.child(imagePath).get();
      return snapshot.exists ? snapshot.value as String : null;
    } catch (e) {
      throw Exception("❌ Error fetching base64 image: $e");
    }
  }

  /// ✅ Fetch image URL from Realtime DB (used for Explore Map etc.)
  Future<String> getImageUrl(String imagePath) async {
    try {
      final snapshot = await _db.child(imagePath).get();
      return snapshot.exists ? snapshot.value as String : '';
    } catch (e) {
      debugPrint("❌ Failed to fetch image URL for $imagePath: $e");
      return '';
    }
  }
}

// import 'package:firebase_database/firebase_database.dart';
// import 'package:flutter/foundation.dart';
// import '../models/photo_model.dart';

// class RealtimeDatabaseService {
//   final DatabaseReference _db = FirebaseDatabase.instance.ref();

//   /// Uploads a photo to Realtime Database under: `/photos/{uid}/{imageId}`
//   Future<void> uploadPhoto(PhotoModel photo) async {
//     final imageId =
//         "${photo.caption}_${photo.timestamp.millisecondsSinceEpoch}";

//     try {
//       await _db
//           .child('photos')
//           .child(photo.uid)
//           .child(imageId)
//           .set(photo.toMap());
//       print("✅ Photo uploaded for user ${photo.uid} at ID: $imageId");
//     } catch (e) {
//       throw Exception("❌ Failed to upload to Realtime Database: $e");
//     }
//   }

//   /// Fetches all photos from all users (used for map exploration)
//   Future<List<PhotoModel>> getAllPhotos() async {
//     try {
//       final snapshot = await _db.child('photos').get();
//       if (!snapshot.exists) return [];

//       final List<PhotoModel> allPhotos = [];

//       final data = snapshot.value as Map<dynamic, dynamic>;

//       for (final uidEntry in data.entries) {
//         if (uidEntry.value is! Map) continue; // ✅ skip invalid entries

//         final userPhotos = uidEntry.value as Map<dynamic, dynamic>;
//         for (final photoEntry in userPhotos.entries) {
//           try {
//             final map = Map<String, dynamic>.from(photoEntry.value);
//             allPhotos.add(PhotoModel.fromMap(map));
//           } catch (e) {
//             debugPrint("⚠️ Skipped malformed photo entry: $e");
//           }
//         }
//       }

//       return allPhotos;
//     } catch (e) {
//       throw Exception("❌ Failed to fetch all photos: $e");
//     }
//   }

//   /// Fetches photos for a specific user by UID
//   Future<List<PhotoModel>> fetchPhotosForUser(String uid) async {
//     try {
//       final snapshot = await _db.child('photos').child(uid).get();
//       if (!snapshot.exists) return [];

//       final data = snapshot.value as Map<dynamic, dynamic>;
//       final List<PhotoModel> photos =
//           data.entries.map((entry) {
//             final map = Map<String, dynamic>.from(entry.value);
//             return PhotoModel.fromMap(map);
//           }).toList();

//       print("📸 fetchPhotosForUser: Fetched ${photos.length} for UID: $uid");
//       return photos;
//     } catch (e) {
//       throw Exception("❌ Failed to fetch user photos: $e");
//     }
//   }

//   Future<List<PhotoModel>> fetchPublicPhotos() async {
//     try {
//       final ref = FirebaseDatabase.instance.ref().child('photos');
//       final snapshot = await ref.get();

//       final List<PhotoModel> photos = [];

//       for (final userNode in snapshot.children) {
//         for (final photoNode in userNode.children) {
//           final photoMap = photoNode.value as Map;
//           final photo = PhotoModel.fromMap(Map<String, dynamic>.from(photoMap));
//           if (photo.isPublic) {
//             photos.add(photo);
//           }
//         }
//       }

//       // Sort descending by timestamp and return last 20
//       photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
//       return photos.take(20).toList();
//     } catch (e) {
//       throw Exception("❌ Failed to fetch public photos: $e");
//     }
//   }

//   // Future<List<PhotoModel>> fetchPublicPhotos() async {
//   //   final ref = FirebaseDatabase.instance.ref().child('photos');
//   //   final snapshot = await ref.get();

//   //   final List<PhotoModel> photos = [];
//   //   for (final child in snapshot.children) {
//   //     final photoMap = child.value as Map;
//   //     final photo = PhotoModel.fromMap(Map<String, dynamic>.from(photoMap));
//   //     if (photo.isPublic) {
//   //       photos.add(photo);
//   //     }
//   //   }

//   //   return photos;
//   // }
// }
