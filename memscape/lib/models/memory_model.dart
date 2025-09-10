import 'package:cloud_firestore/cloud_firestore.dart';
import 'media_item.dart';

class MemoryModel {
  final String id;
  final String uid;
  final String caption;
  final String locationInput; // full text user typed/selected
  final String place; // parsed City, State, Country
  final double? lat;
  final double? lng;
  final bool isPublic;
  final DateTime createdAt;
  final List<MediaItem> media; // images/videos (download URLs after upload)
  final List<String> likes;
  final List<Map<String, dynamic>> comments;

  const MemoryModel({
    required this.id,
    required this.uid,
    required this.caption,
    required this.locationInput,
    required this.place,
    required this.isPublic,
    required this.createdAt,
    required this.media,
    this.lat,
    this.lng,
    this.likes = const [],
    this.comments = const [],
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'caption': caption,
    'locationInput': locationInput,
    'place': place,
    'lat': lat,
    'lng': lng,
    'isPublic': isPublic,
    'createdAt': createdAt.toIso8601String(),
    'media': media.map((m) => m.toMap()).toList(),
    'likes': likes,
    'comments': comments,
  };

  factory MemoryModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MemoryModel(
      id: doc.id,
      uid: d['uid'] ?? '',
      caption: d['caption'] ?? '',
      locationInput: d['locationInput'] ?? '',
      place: d['place'] ?? 'Unknown',
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      isPublic: d['isPublic'] ?? true,
      createdAt: DateTime.tryParse(d['createdAt'] ?? '') ?? DateTime.now(),
      media:
          (d['media'] as List? ?? [])
              .map((e) => MediaItem.fromMap(Map<String, dynamic>.from(e)))
              .toList(),
      likes: List<String>.from(d['likes'] ?? []),
      comments: List<Map<String, dynamic>>.from(d['comments'] ?? []),
    );
  }
}
