// import 'dart:io';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:geocoding/geocoding.dart';
// import '../models/media_item.dart';
// import '../models/memory_model.dart';
// import 'storage_service.dart';

// class MemoryService {
//   final _fs = FirebaseFirestore.instance;
//   final _storage = StorageService();

//   Future<String> createMemory({
//     required String uid,
//     required String caption,
//     required String locationInput,
//     required bool isPublic,
//     required List<MediaItem> pickedMedia,
//     double? lat, double? lng,
//   }) async {
//     // Geocode (best effort)
//     String place = 'Unknown';
//     double? finalLat = lat;
//     double? finalLng = lng;
//     try {
//       if ((lat == null || lng == null) && locationInput.isNotEmpty) {
//         final locs = await locationFromAddress(locationInput);
//         finalLat = locs.first.latitude;
//         finalLng = locs.first.longitude;
//       }
//       if (finalLat != null && finalLng != null) {
//         final marks = await placemarkFromCoordinates(finalLat, finalLng);
//         if (marks.isNotEmpty) {
//           final m = marks.first;
//           final city = m.locality ?? m.subAdministrativeArea ?? '';
//           final state = m.administrativeArea ?? '';
//           final country = m.country ?? '';
//           place = [city, state, country].where((e) => e.isNotEmpty).join(', ');
//         }
//       }
//     } catch (_) {/* ignore geocode errors */}

//     final doc = _fs.collection('memories').doc(); // NEW collection
//     final uploads = <MediaItem>[];

//     // upload each picked media to Storage
//     for (int i = 0; i < pickedMedia.length; i++) {
//       final item = pickedMedia[i];
//       final file = File(item.localPath);
//       final ext = item.type == MediaType.image ? 'jpg' : 'mp4';
//       final contentType = item.type == MediaType.image ? 'image/jpeg' : 'video/mp4';
//       final path = 'memories/$uid/${doc.id}/${i}.$ext';
//       final (url, storagePath) = await _storage.uploadFile(
//         file: file,
//         destPath: path,
//         contentType: contentType,
//       );
//       uploads.add(item.copyWith(storageUrl: url, storagePath: storagePath));
//     }

//     final memory = MemoryModel(
//       id: doc.id,
//       uid: uid,
//       caption: caption.trim(),
//       locationInput: locationInput.trim(),
//       place: place,
//       lat: finalLat,
//       lng: finalLng,
//       isPublic: isPublic,
//       createdAt: DateTime.now(),
//       media: uploads,
//     );

//     await doc.set(memory.toMap());

//     // Also maintain a user reference list (like your photoRefs)
//     await _fs.collection('users').doc(uid).set({
//       'memoryRefs': FieldValue.arrayUnion([doc.id]),
//     }, SetOptions(merge: true));

//     return doc.id;
//   }
// }
