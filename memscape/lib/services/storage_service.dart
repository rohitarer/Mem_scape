// import 'dart:io';
// import 'package:firebase_storage/firebase_storage.dart';

// class StorageService {
//   final FirebaseStorage _storage = FirebaseStorage.instance;

//   Future<(String url, String path)> uploadFile({
//     required File file,
//     required String destPath, // e.g. "memories/{uid}/{docId}/{filename}"
//     required String contentType, // "image/jpeg" | "video/mp4"
//   }) async {
//     final ref = _storage.ref(destPath);
//     final metadata = SettableMetadata(contentType: contentType);
//     await ref.putFile(file, metadata);
//     final url = await ref.getDownloadURL();
//     return (url, ref.fullPath);
//   }
// }
