import 'dart:typed_data';

class PhotoModel {
  final String uid;
  final String? imageBase64;
  final String? imagePath;
  final String caption;
  final String location;
  final String place;
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  final bool isPublic;
  final List<String> likes;
  final List<Map<String, dynamic>> comments;
  final String? id;

  /// 🧠 In-memory decoded image cache (not saved to DB)
  Uint8List? decodedImage;

  PhotoModel({
    this.id,
    required this.uid,
    this.imageBase64,
    this.imagePath,
    required this.caption,
    required this.location,
    required this.place,
    required this.timestamp,
    this.lat,
    this.lng,
    required this.isPublic,
    this.likes = const [],
    this.comments = const [],
    this.decodedImage, // ⬅️ added here
  });

  /// 🔄 Converts this model to a Map (used when saving to DB)
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'imageBase64': imageBase64,
      'imagePath': imagePath,
      'caption': caption,
      'location': location,
      'place': place,
      'timestamp': timestamp.toIso8601String(),
      'lat': lat,
      'lng': lng,
      'isPublic': isPublic,
      'likes': likes,
      'comments': comments,
      // ❌ Don't include `decodedImage` in Firestore
    };
  }

  /// 🟢 Alias for toMap (for Firestore/RealtimeDB JSON use)
  Map<String, dynamic> toJson() => toMap();

  /// 🟡 Factory to create PhotoModel from a map
  factory PhotoModel.fromMap(Map<String, dynamic> map, [String? id]) {
    return PhotoModel(
      id: id,
      uid: map['uid'] ?? '',
      imageBase64: map['imageBase64'],
      imagePath: map['imagePath'],
      caption: map['caption'] ?? '',
      location: map['location'] ?? '',
      place: map['place'] ?? 'Unknown',
      timestamp: DateTime.parse(map['timestamp']),
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      isPublic: map['isPublic'] ?? true,
      likes: List<String>.from(map['likes'] ?? []),
      comments: List<Map<String, dynamic>>.from(map['comments'] ?? []),
      // decodedImage is not set here intentionally
    );
  }

  /// 🟢 Alias for fromMap to fix "fromJson not defined" errors
  factory PhotoModel.fromJson(Map<String, dynamic> json, [String? id]) =>
      PhotoModel.fromMap(json, id);

  /// 🔁 Create a copy with overrides
  PhotoModel copyWith({
    String? id,
    String? uid,
    String? imageBase64,
    String? imagePath,
    String? caption,
    String? location,
    String? place,
    DateTime? timestamp,
    double? lat,
    double? lng,
    bool? isPublic,
    List<String>? likes,
    List<Map<String, dynamic>>? comments,
    Uint8List? decodedImage,
  }) {
    return PhotoModel(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      imageBase64: imageBase64 ?? this.imageBase64,
      imagePath: imagePath ?? this.imagePath,
      caption: caption ?? this.caption,
      location: location ?? this.location,
      place: place ?? this.place,
      timestamp: timestamp ?? this.timestamp,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      isPublic: isPublic ?? this.isPublic,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      decodedImage: decodedImage ?? this.decodedImage,
    );
  }
}




// class PhotoModel {
//   final String uid;
//   final String? imageBase64;
//   final String? imagePath;
//   final String caption;
//   final String location;
//   final String place;
//   final DateTime timestamp;
//   final double? lat;
//   final double? lng;
//   final bool isPublic;
//   final List<String> likes;
//   final List<Map<String, dynamic>> comments;
//   final String? id;

//   PhotoModel({
//     this.id,
//     required this.uid,
//     this.imageBase64,
//     this.imagePath,
//     required this.caption,
//     required this.location,
//     required this.place,
//     required this.timestamp,
//     this.lat,
//     this.lng,
//     required this.isPublic,
//     this.likes = const [],
//     this.comments = const [],
//   });

//   /// 🔄 Converts this model to a Map (used when saving to DB)
//   Map<String, dynamic> toMap() {
//     return {
//       'uid': uid,
//       'imageBase64': imageBase64,
//       'imagePath': imagePath,
//       'caption': caption,
//       'location': location,
//       'place': place,
//       'timestamp': timestamp.toIso8601String(),
//       'lat': lat,
//       'lng': lng,
//       'isPublic': isPublic,
//       'likes': likes,
//       'comments': comments,
//     };
//   }

//   /// 🟢 Alias for toMap (for Firestore/RealtimeDB JSON use)
//   Map<String, dynamic> toJson() => toMap();

//   /// 🟡 Factory to create PhotoModel from a map
//   factory PhotoModel.fromMap(Map<String, dynamic> map, [String? id]) {
//     return PhotoModel(
//       id: id,
//       uid: map['uid'] ?? '',
//       imageBase64: map['imageBase64'],
//       imagePath: map['imagePath'],
//       caption: map['caption'] ?? '',
//       location: map['location'] ?? '',
//       place: map['place'] ?? 'Unknown',
//       timestamp: DateTime.parse(map['timestamp']),
//       lat: (map['lat'] as num?)?.toDouble(),
//       lng: (map['lng'] as num?)?.toDouble(),
//       isPublic: map['isPublic'] ?? true,
//       likes: List<String>.from(map['likes'] ?? []),
//       comments: List<Map<String, dynamic>>.from(map['comments'] ?? []),
//     );
//   }

//   /// 🟢 Alias for fromMap to fix "fromJson not defined" errors
//   factory PhotoModel.fromJson(Map<String, dynamic> json, [String? id]) =>
//       PhotoModel.fromMap(json, id);

//   /// 🔁 Create a copy with overrides
//   PhotoModel copyWith({
//     String? id,
//     String? uid,
//     String? imageBase64,
//     String? imagePath,
//     String? caption,
//     String? location,
//     String? place,
//     DateTime? timestamp,
//     double? lat,
//     double? lng,
//     bool? isPublic,
//     List<String>? likes,
//     List<Map<String, dynamic>>? comments,
//   }) {
//     return PhotoModel(
//       id: id ?? this.id,
//       uid: uid ?? this.uid,
//       imageBase64: imageBase64 ?? this.imageBase64,
//       imagePath: imagePath ?? this.imagePath,
//       caption: caption ?? this.caption,
//       location: location ?? this.location,
//       place: place ?? this.place,
//       timestamp: timestamp ?? this.timestamp,
//       lat: lat ?? this.lat,
//       lng: lng ?? this.lng,
//       isPublic: isPublic ?? this.isPublic,
//       likes: likes ?? this.likes,
//       comments: comments ?? this.comments,
//     );
//   }
// }




// class PhotoModel {
//   final String uid;
//   final String? imageBase64; // ⛔ Runtime-only, not saved to Firestore
//   final String?
//   imagePath; // ✅ Path stored in Firestore (e.g., for Firebase Storage)
//   final String caption;
//   final String location;
//   final DateTime timestamp;
//   final double? lat;
//   final double? lng;
//   final bool isPublic;
//   final List<String> likes;
//   final List<Map<String, dynamic>> comments;

//   final String? id; // Firestore doc ID (optional)

//   PhotoModel({
//     this.id,
//     required this.uid,
//     this.imageBase64,
//     this.imagePath,
//     required this.caption,
//     required this.location,
//     required this.timestamp,
//     this.lat,
//     this.lng,
//     required this.isPublic,
//     this.likes = const [],
//     this.comments = const [],
//   });

//   /// ✅ Convert object to Firestore-compatible map (excluding base64)
//   Map<String, dynamic> toMap() {
//     return {
//       'uid': uid,
//       'imagePath': imagePath,
//       'caption': caption,
//       'location': location,
//       'timestamp': timestamp.toIso8601String(),
//       'lat': lat,
//       'lng': lng,
//       'isPublic': isPublic,
//       'likes': likes,
//       'comments': comments,
//     };
//   }

//   /// ✅ Recreate model from Firestore map
//   factory PhotoModel.fromMap(Map<String, dynamic> map, [String? id]) {
//     return PhotoModel(
//       id: id,
//       uid: map['uid'],
//       imagePath: map['imagePath'],
//       caption: map['caption'],
//       location: map['location'],
//       timestamp: DateTime.parse(map['timestamp']),
//       lat: (map['lat'] ?? 0).toDouble(),
//       lng: (map['lng'] ?? 0).toDouble(),
//       isPublic: map['isPublic'] ?? true,
//       likes: List<String>.from(map['likes'] ?? []),
//       comments: List<Map<String, dynamic>>.from(map['comments'] ?? []),
//     );
//   }

//   /// 🔁 Copy object with selective overrides
//   PhotoModel copyWith({
//     String? uid,
//     String? imageBase64,
//     String? imagePath,
//     String? caption,
//     String? location,
//     DateTime? timestamp,
//     double? lat,
//     double? lng,
//     bool? isPublic,
//     List<String>? likes,
//     List<Map<String, dynamic>>? comments,
//   }) {
//     return PhotoModel(
//       uid: uid ?? this.uid,
//       imageBase64: imageBase64 ?? this.imageBase64,
//       imagePath: imagePath ?? this.imagePath,
//       caption: caption ?? this.caption,
//       location: location ?? this.location,
//       timestamp: timestamp ?? this.timestamp,
//       lat: lat ?? this.lat,
//       lng: lng ?? this.lng,
//       isPublic: isPublic ?? this.isPublic,
//       likes: likes ?? this.likes,
//       comments: comments ?? this.comments,
//     );
//   }
// }


