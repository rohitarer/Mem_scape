// lib/models/post_model.dart
class PostModel {
  final String id; // Firestore doc id
  final String uid;
  final String caption;
  final String location;
  final String place;
  final DateTime timestamp;
  final double? lat;
  final double? lng;
  final bool isPublic;
  final List<Map<String, dynamic>>
  media; // [{type:'image'|'video', url:'...', storagePath:'...'}]
  final List<String> likes;
  final List<Map<String, dynamic>> comments;

  const PostModel({
    required this.id,
    required this.uid,
    required this.caption,
    required this.location,
    required this.place,
    required this.timestamp,
    required this.isPublic,
    required this.media,
    this.lat,
    this.lng,
    this.likes = const [],
    this.comments = const [],
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'caption': caption,
    'location': location,
    'place': place,
    'timestamp': timestamp.toIso8601String(),
    'lat': lat,
    'lng': lng,
    'isPublic': isPublic,
    'media': media,
    'likes': likes,
    'comments': comments,
  };

  factory PostModel.fromMap(String id, Map<String, dynamic> m) => PostModel(
    id: id,
    uid: m['uid'] ?? '',
    caption: m['caption'] ?? '',
    location: m['location'] ?? '',
    place: m['place'] ?? 'Unknown',
    timestamp: DateTime.parse(m['timestamp']),
    lat: (m['lat'] as num?)?.toDouble(),
    lng: (m['lng'] as num?)?.toDouble(),
    isPublic: m['isPublic'] ?? true,
    media: List<Map<String, dynamic>>.from(m['media'] ?? []),
    likes: List<String>.from(m['likes'] ?? []),
    comments: List<Map<String, dynamic>>.from(m['comments'] ?? []),
  );
}
