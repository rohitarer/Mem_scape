// lib/models/media_item.dart
class MediaItem {
  final String type; // "image" | "video"
  final String path; // RTDB path e.g. "images/<id>" or "videos/<id>/chunks"
  final String mime; // e.g. "image/jpeg", "video/mp4"
  final bool chunked; // videos stored as chunks in RTDB
  final int? chunkCount; // if chunked
  final int? durationMs; // optional for videos
  final int? width;
  final int? height;

  MediaItem({
    required this.type,
    required this.path,
    required this.mime,
    this.chunked = false,
    this.chunkCount,
    this.durationMs,
    this.width,
    this.height,
  });

  Map<String, dynamic> toMap() => {
    'type': type,
    'path': path,
    'mime': mime,
    'chunked': chunked,
    'chunkCount': chunkCount,
    'durationMs': durationMs,
    'width': width,
    'height': height,
  };

  factory MediaItem.fromMap(Map<String, dynamic> m) => MediaItem(
    type: m['type'] ?? 'image',
    path: m['path'] ?? '',
    mime: m['mime'] ?? 'application/octet-stream',
    chunked: m['chunked'] ?? false,
    chunkCount: m['chunkCount'],
    durationMs: m['durationMs'],
    width: m['width'],
    height: m['height'],
  );
}
