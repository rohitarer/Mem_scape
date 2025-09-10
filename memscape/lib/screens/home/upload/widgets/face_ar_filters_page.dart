// lib/screens/home/upload/widgets/face_ar_filters_page.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// ------------------------------------------------------------
/// Models
/// ------------------------------------------------------------

/// Where on the face to anchor an overlay.
enum FaceAnchor {
  aboveHead, // centered above bounding box
  overEyes, // centered between eyes (glasses, tears)
  onNose, // nose-based
  overMouth, // mustache, lips
  cheeks, // blush (draw twice, left & right)
}

/// One overlay layer (PNG) with how to place it.
class OverlaySpec {
  final String assetPath;
  final FaceAnchor anchor;
  final double scale; // relative to face width (1.0 == face width)
  final Offset offset; // fine-tune in logical px *after* scaling

  const OverlaySpec({
    required this.assetPath,
    required this.anchor,
    this.scale = 1.0,
    this.offset = Offset.zero,
  });
}

/// A filter (a group of overlays + a display name).
class LensFilter {
  final String name;
  final List<OverlaySpec> layers;
  const LensFilter({required this.name, required this.layers});
}

/// ------------------------------------------------------------
/// Page
/// ------------------------------------------------------------
class FaceARFiltersPage extends StatefulWidget {
  const FaceARFiltersPage({super.key});

  @override
  State<FaceARFiltersPage> createState() => _FaceARFiltersPageState();
}

class _FaceARFiltersPageState extends State<FaceARFiltersPage> {
  CameraController? _camera;
  late final FaceDetector _detector;

  bool _busy = false;
  List<Face> _faces = [];

  // Filters (add as many as you want)
  late final List<LensFilter> _filters;
  int _index = 0;

  // Cache for decoded PNGs
  final Map<String, ui.Image> _imageCache = {};

  // UI: show name for 1s on change
  String _nameFlash = '';
  Timer? _nameTimer;

  @override
  void initState() {
    super.initState();

    _filters = [
      const LensFilter(name: 'No Cap', layers: []),

      const LensFilter(
        name: 'Doggo',
        layers: [
          OverlaySpec(
            assetPath: 'assets/lenses/dog_ears.png',
            anchor: FaceAnchor.aboveHead,
            scale: 1.15,
            offset: Offset(0, -20),
          ),
          OverlaySpec(
            assetPath: 'assets/lenses/dog_nose.png',
            anchor: FaceAnchor.onNose,
            scale: 0.45,
            offset: Offset(0, 18),
          ),
        ],
      ),

      const LensFilter(
        name: 'Nerd Mode',
        layers: [
          OverlaySpec(
            assetPath: 'assets/lenses/glasses.png',
            anchor: FaceAnchor.overEyes,
            scale: 1.05,
            offset: Offset(0, 12),
          ),
        ],
      ),

      const LensFilter(
        name: '’Stache',
        layers: [
          OverlaySpec(
            assetPath: 'assets/lenses/mustache.png',
            anchor: FaceAnchor.overMouth,
            scale: 0.7,
            offset: Offset(0, 6),
          ),
        ],
      ),

      const LensFilter(
        name: 'Blush',
        layers: [
          OverlaySpec(
            assetPath: 'assets/lenses/blush.png',
            anchor: FaceAnchor.cheeks,
            scale: 0.35,
            offset: Offset(0, 14),
          ),
        ],
      ),

      const LensFilter(
        name: 'Crybaby',
        layers: [
          OverlaySpec(
            assetPath: 'assets/lenses/tears.png',
            anchor: FaceAnchor.overEyes,
            scale: 0.95,
            offset: Offset(0, 32),
          ),
        ],
      ),
    ];

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableLandmarks: true,
        enableContours: false,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    _initCamera();
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    _camera?.dispose();
    _detector.close();
    super.dispose();
  }

  /// ---------------- Camera / ML Kit wiring (new API) ----------------

  // Map Android camera sensor orientation -> ML Kit enum
  InputImageRotation _rotationFor(CameraDescription camera) {
    switch (camera.sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  InputImage _buildInputImage(CameraImage image, CameraDescription camDesc) {
    // Concatenate YUV planes into a single byte array
    final bytes = _concatPlanes(image.planes);

    // Build metadata — no planeData on InputImageMetadata
    final metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _rotationFor(camDesc),
      format: InputImageFormat.yuv420, // typical for Android camera
      bytesPerRow: image.planes.isNotEmpty ? image.planes.first.bytesPerRow : 0,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List _concatPlanes(List<Plane> planes) {
    final total = planes.fold<int>(0, (s, p) => s + p.bytes.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final p in planes) {
      out.setRange(offset, offset + p.bytes.length, p.bytes);
      offset += p.bytes.length;
    }
    return out;
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    final front = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cams.first,
    );

    _camera = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _camera!.initialize();
    await _camera!.startImageStream(_onFrame);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _camera == null) return;
    _busy = true;
    try {
      final input = _buildInputImage(image, _camera!.description);
      final faces = await _detector.processImage(input);
      if (mounted) setState(() => _faces = faces);
    } catch (_) {
      // swallow frame errors
    } finally {
      _busy = false;
    }
  }

  // Swipe navigation
  void _nudge(int dir) {
    if (_filters.isEmpty) return;
    var next = (_index + dir) % _filters.length;
    if (next < 0) next = _filters.length - 1;
    setState(() => _index = next);

    _nameTimer?.cancel();
    setState(() => _nameFlash = _filters[_index].name);
    _nameTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _nameFlash = '');
    });
  }

  // Cache PNGs once
  Future<ui.Image> _loadImage(String assetPath) async {
    final cached = _imageCache[assetPath];
    if (cached != null) return cached;
    final data = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _imageCache[assetPath] = frame.image;
    return frame.image;
  }

  Future<Map<String, ui.Image>> _preload(LensFilter lens) async {
    final Map<String, ui.Image> map = {};
    for (final layer in lens.layers) {
      map[layer.assetPath] = await _loadImage(layer.assetPath);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final active = _filters[_index];

    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 120) return;
          _nudge(v > 0 ? -1 : 1);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPreview(cam),

            // Overlays
            FutureBuilder<Map<String, ui.Image>>(
              future: _preload(active),
              builder: (context, snap) {
                if (!snap.hasData) return const SizedBox.shrink();
                return CustomPaint(
                  painter: _FaceOverlayPainter(
                    faces: _faces,
                    previewSize: cam.value.previewSize!,
                    lens: active,
                    images: snap.data!,
                    isFrontCamera:
                        cam.description.lensDirection ==
                        CameraLensDirection.front,
                  ),
                );
              },
            ),

            // Filter name flash (center)
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _nameFlash.isEmpty ? 0 : 1,
                duration: const Duration(milliseconds: 120),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _nameFlash,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ------------------------------------------------------------
/// Painter
/// ------------------------------------------------------------
class _FaceOverlayPainter extends CustomPainter {
  final List<Face> faces;
  final Size previewSize;
  final LensFilter lens;
  final Map<String, ui.Image> images;
  final bool isFrontCamera;

  _FaceOverlayPainter({
    required this.faces,
    required this.previewSize,
    required this.lens,
    required this.images,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Map camera coords → widget coords (CameraPreview rotated)
    final scaleX = size.width / previewSize.height;
    final scaleY = size.height / previewSize.width;

    for (final face in faces) {
      final box = face.boundingBox;
      final faceWidth = box.width * scaleX;
      final faceCenter = Offset(box.center.dx * scaleX, box.center.dy * scaleY);

      // Landmarks if available
      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final mouthBottom =
          face.landmarks[FaceLandmarkType.bottomMouth]?.position;

      // Mirror front camera horizontally
      canvas.save();
      if (isFrontCamera) {
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }

      for (final layer in lens.layers) {
        final image = images[layer.assetPath]!;
        final paint = Paint();

        Rect dst;
        switch (layer.anchor) {
          case FaceAnchor.aboveHead:
            final w = faceWidth * layer.scale;
            final h = w;
            dst = Rect.fromCenter(
              center: Offset(faceCenter.dx, box.top * scaleY - h * 0.35),
              width: w,
              height: h,
            );
            break;

          case FaceAnchor.overEyes:
            if (leftEye != null && rightEye != null) {
              final lx = leftEye.x * scaleX;
              final rx = rightEye.x * scaleX;
              final ly = leftEye.y * scaleY;
              final ry = rightEye.y * scaleY;
              final mid = Offset((lx + rx) / 2, (ly + ry) / 2);

              final w = (rx - lx).abs() * 2.1 * layer.scale;
              final h = w * (image.height / image.width);
              dst = Rect.fromCenter(center: mid, width: w, height: h);
            } else {
              final w = faceWidth * 0.95 * layer.scale;
              final h = w * (image.height / image.width);
              dst = Rect.fromCenter(
                center: Offset(faceCenter.dx, faceCenter.dy - h * 0.2),
                width: w,
                height: h,
              );
            }
            break;

          case FaceAnchor.onNose:
            if (noseBase != null) {
              final p = Offset(noseBase.x * scaleX, noseBase.y * scaleY);
              final w = faceWidth * layer.scale;
              final h = w * (image.height / image.width);
              dst = Rect.fromCenter(center: p, width: w, height: h);
            } else {
              final w = faceWidth * 0.45 * layer.scale;
              final h = w * (image.height / image.width);
              dst = Rect.fromCenter(center: faceCenter, width: w, height: h);
            }
            break;

          case FaceAnchor.overMouth:
            if (mouthBottom != null) {
              final p = Offset(mouthBottom.x * scaleX, mouthBottom.y * scaleY);
              final w = faceWidth * layer.scale;
              final h = w * (image.height / image.width);
              dst = Rect.fromCenter(center: p, width: w, height: h);
            } else {
              final w = faceWidth * 0.7 * layer.scale;
              final h = w * (image.height / image.width);
              dst = Rect.fromCenter(
                center: faceCenter.translate(0, faceWidth * 0.15),
                width: w,
                height: h,
              );
            }
            break;

          case FaceAnchor.cheeks:
            // Draw twice (left/right)
            if (leftEye != null && rightEye != null) {
              final lx = leftEye.x * scaleX;
              final rx = rightEye.x * scaleX;
              final y = faceCenter.dy + faceWidth * 0.05;
              final d = (rx - lx).abs() * 0.5;

              for (final cx in [lx - d * 0.25, rx + d * 0.25]) {
                final w = faceWidth * layer.scale;
                final h = w * (image.height / image.width);
                final r = Rect.fromCenter(
                  center: Offset(cx, y),
                  width: w,
                  height: h,
                ).shift(layer.offset);
                _drawImage(canvas, image, r, paint);
              }
              continue;
            } else {
              final w = faceWidth * layer.scale;
              final h = w * (image.height / image.width);
              final left = Rect.fromCenter(
                center: faceCenter.translate(
                  -faceWidth * 0.28,
                  faceWidth * 0.05,
                ),
                width: w,
                height: h,
              ).shift(layer.offset);
              final right = Rect.fromCenter(
                center: faceCenter.translate(
                  faceWidth * 0.28,
                  faceWidth * 0.05,
                ),
                width: w,
                height: h,
              ).shift(layer.offset);
              _drawImage(canvas, image, left, paint);
              _drawImage(canvas, image, right, paint);
              continue;
            }
        }

        // Common tweak
        dst = dst.shift(layer.offset);
        _drawImage(canvas, image, dst, paint);
      }

      canvas.restore();
    }
  }

  void _drawImage(Canvas canvas, ui.Image image, Rect dst, Paint paint) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _FaceOverlayPainter old) {
    return old.faces != faces ||
        old.lens != lens ||
        old.images.length != images.length ||
        old.isFrontCamera != isFrontCamera;
  }
}
