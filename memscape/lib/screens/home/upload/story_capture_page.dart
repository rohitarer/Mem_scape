import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// Your widgets & helpers
import 'widgets/filters_presets.dart'; // color matrices
import 'widgets/lens_models.dart'; // FaceAnchor, OverlaySpec, LensFilter
import 'widgets/face_overlay_painter.dart'; // preview painter for AR overlays
import 'widgets/mlkit_image_utils.dart'; // buildInputImage()
// NOTE: removed lenses_carousel import – we now render the Snapchat rail inline.

class StoryCapturePage extends StatefulWidget {
  final ValueChanged<File> onCaptured;
  const StoryCapturePage({super.key, required this.onCaptured});

  @override
  State<StoryCapturePage> createState() => _StoryCapturePageState();
}

class _StoryCapturePageState extends State<StoryCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _ready = false;
  bool _usingFront = true;
  bool _isTaking = false;
  FlashMode _flash = FlashMode.off;

  // Video mode
  bool _isVideoMode = false;
  bool _isRecording = false;

  // Lenses (first color filters, then AR overlays)
  late final List<LensFilter> _lenses;
  int _index = 0;

  // Center name flash
  bool _showName = false;
  String _nameText = '';
  Timer? _nameTimer;

  // Face detection (live) for AR overlays
  late final FaceDetector _detector;
  bool _detecting = false;
  List<Face> _faces = [];

  // ui.Image cache for preview overlays
  final Map<String, ui.Image> _overlayCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Build the carousel content
    _lenses = [
      // Color filters (matrix only)
      LensFilter(
        name: FilterPresets.swipeOrder[0].name,
        matrix: FilterPresets.swipeOrder[0].matrix,
      ),
      LensFilter(
        name: FilterPresets.swipeOrder[1].name,
        matrix: FilterPresets.swipeOrder[1].matrix,
      ),
      LensFilter(
        name: FilterPresets.swipeOrder[2].name,
        matrix: FilterPresets.swipeOrder[2].matrix,
      ),
      LensFilter(
        name: FilterPresets.swipeOrder[3].name,
        matrix: FilterPresets.swipeOrder[3].matrix,
      ),
      LensFilter(
        name: FilterPresets.swipeOrder[4].name,
        matrix: FilterPresets.swipeOrder[4].matrix,
      ),
      LensFilter(
        name: FilterPresets.swipeOrder[5].name,
        matrix: FilterPresets.swipeOrder[5].matrix,
      ),

      // AR overlays (preview + baked on photo)
      const LensFilter(
        name: 'Doggo',
        overlays: [
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
        overlays: [
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
        overlays: [
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
        overlays: [
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
        overlays: [
          OverlaySpec(
            assetPath: 'assets/lenses/tears.png',
            anchor: FaceAnchor.overEyes,
            scale: 0.95,
            offset: Offset(0, 32),
          ),
        ],
      ),
    ];

    _nameText = _lenses[_index].name;

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
    WidgetsBinding.instance.removeObserver(this);
    _nameTimer?.cancel();
    _stopImageStream();
    _controller?.dispose();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      await _stopImageStream();
      await _controller?.dispose();
      _controller = null;
      if (mounted) setState(() => _ready = false);
    } else if (state == AppLifecycleState.resumed) {
      await _initCamera();
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _initCamera() async {
    try {
      if (!(await Permission.camera.request()).isGranted) {
        _snack("Camera permission denied. Enable it in Settings.");
        if (mounted) setState(() => _ready = false);
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _ready = false);
        _snack("No camera found on this device.");
        return;
      }
      _cameras = cameras;

      final description =
          _usingFront
              ? _cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.front,
                orElse: () => _cameras.first,
              )
              : _cameras.firstWhere(
                (c) => c.lensDirection == CameraLensDirection.back,
                orElse: () => _cameras.first,
              );

      final controller = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: _isVideoMode,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      _controller?.dispose();
      _controller = controller;
      await controller.initialize();
      await controller.setFlashMode(_flash);

      await _updateImageStream(); // start/stop face stream based on lens

      if (!mounted) return;
      setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _ready = false);
      _snack("Camera init failed: $e");
    }
  }

  Future<void> _toggleCamera() async {
    _usingFront = !_usingFront;
    await _initCamera();
  }

  Future<void> _toggleFlash() async {
    if (_controller == null) return;
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      FlashMode.always => FlashMode.torch,
      FlashMode.torch => FlashMode.off,
      _ => FlashMode.off,
    };
    _flash = next;
    await _controller!.setFlashMode(_flash);
    setState(() {});
  }

  Future<void> _toggleVideoMode() async {
    if (_isRecording) return;
    setState(() => _isVideoMode = !_isVideoMode);
    await _initCamera();
  }

  // Face stream only when AR overlays active
  bool get _arActive => _lenses[_index].overlays.isNotEmpty;

  Future<void> _updateImageStream() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_arActive) {
      await _startImageStream();
    } else {
      await _stopImageStream();
      if (mounted) setState(() => _faces = []);
    }
  }

  Future<void> _startImageStream() async {
    if (_controller == null) return;
    if (_controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(_onFrame);
  }

  Future<void> _stopImageStream() async {
    final cam = _controller;
    if (cam == null) return;
    if (cam.value.isStreamingImages) {
      try {
        await cam.stopImageStream();
      } catch (_) {}
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_detecting) return;
    _detecting = true;
    try {
      final input = buildInputImage(image, _controller!.description);
      final faces = await _detector.processImage(input);
      if (mounted && _arActive) {
        setState(() => _faces = faces);
      }
    } catch (_) {
      // ignore
    } finally {
      _detecting = false;
    }
  }

  // ===== Capture (video) =====
  Future<void> _startStopRecording() async {
    final cam = _controller;
    if (!_ready || cam == null) return;

    try {
      if (_isRecording) {
        final file = await cam.stopVideoRecording();
        setState(() => _isRecording = false);
        // AR overlays are preview-only for video.
        widget.onCaptured(File(file.path));
        return;
      }

      await cam.startVideoRecording();
      setState(() => _isRecording = true);
    } catch (e) {
      _snack("Video error: $e");
      if (cam.value.isRecordingVideo == true) {
        try {
          await cam.stopVideoRecording();
        } catch (_) {}
      }
      setState(() => _isRecording = false);
    }
  }

  // ===== Capture (photo) =====
  Future<void> _capturePhoto() async {
    final cam = _controller;
    if (cam?.value.isTakingPicture == true) return;
    if (!_ready || cam == null || _isTaking) return;

    try {
      setState(() => _isTaking = true);
      final xfile = await cam.takePicture();
      File outFile = File(xfile.path);

      final lens = _lenses[_index];

      // 1) Bake color matrix (if any)
      if (lens.matrix != null) {
        try {
          final bytes = await outFile.readAsBytes();
          final decoded = img.decodeImage(bytes);
          if (decoded != null) {
            final filtered = _applyMatrix(decoded, lens.matrix!);
            final jpg = img.encodeJpg(filtered, quality: 92);
            final tmpDir = await getTemporaryDirectory();
            outFile = await File(
              '${tmpDir.path}/memscape_${DateTime.now().millisecondsSinceEpoch}.jpg',
            ).writeAsBytes(jpg, flush: true);
          }
        } catch (e) {
          _snack("Color filter failed (using original): $e");
        }
      }

      // 2) Bake AR overlays (if any)
      if (lens.overlays.isNotEmpty) {
        try {
          final baked = await _bakeOverlaysOnFile(outFile, lens);
          if (baked != null) outFile = baked;
        } catch (e) {
          _snack("AR overlay bake failed (using filtered image): $e");
        }
      }

      if (!mounted) return;
      widget.onCaptured(outFile);
    } catch (e) {
      _snack("Capture failed: $e");
    } finally {
      if (mounted) setState(() => _isTaking = false);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final lens = _lenses[_index];
    final preview =
        lens.matrix == null
            ? CameraPreview(_controller!)
            : ColorFiltered(
              colorFilter: ColorFilter.matrix(lens.matrix!),
              child: CameraPreview(_controller!),
            );

    return Stack(
      children: [
        // Full preview (NO swipe handler anymore)
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final value = _controller!.value;
              final ps = value.isInitialized ? value.previewSize : null;

              final previewLayer = Stack(
                fit: StackFit.expand,
                children: [
                  preview,
                  if (_arActive && ps != null)
                    FutureBuilder<Map<String, ui.Image>>(
                      future: _preload(lens),
                      builder: (context, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        return CustomPaint(
                          painter: FaceOverlayPainter(
                            faces: _faces,
                            previewSize: ps,
                            lens: lens,
                            images: snap.data!,
                            isFrontCamera:
                                _controller!.description.lensDirection ==
                                CameraLensDirection.front,
                          ),
                        );
                      },
                    ),
                ],
              );

              if (ps == null) return previewLayer;

              return OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: value.previewSize!.height,
                    height: value.previewSize!.width,
                    child: previewLayer,
                  ),
                ),
              );
            },
          ),
        ),

        // Top-right controls
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0, right: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _RoundIconButton(
                    icon: switch (_flash) {
                      FlashMode.off => Icons.flash_off,
                      FlashMode.auto => Icons.flash_auto,
                      FlashMode.always => Icons.flash_on,
                      FlashMode.torch => Icons.bolt,
                      _ => Icons.flash_off,
                    },
                    tooltip: 'Flash',
                    onTap: _toggleFlash,
                  ),
                  const SizedBox(height: 10),
                  _RoundIconButton(
                    icon: Icons.cameraswitch,
                    tooltip: 'Flip camera',
                    onTap: _toggleCamera,
                  ),
                  const SizedBox(height: 10),
                  _RoundIconButton(
                    icon:
                        _isVideoMode ? Icons.videocam : Icons.videocam_outlined,
                    tooltip: 'Toggle video mode',
                    active: _isVideoMode,
                    onTap: _toggleVideoMode,
                  ),
                ],
              ),
            ),
          ),
        ),

        // Center name flash
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _showName ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 180),
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
                  _nameText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ===== Snapchat-style bottom rail: carousel + shutter in one line =====
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _SnapBottomBar(
            items:
                _lenses
                    .map((l) => _LensChipData(name: l.name, thumb: null))
                    .toList(),
            selectedIndex: _index,
            onIndexChanged: (i) async {
              setState(() {
                _index = i;
                _nameText = _lenses[_index].name;
                _showName = true;
              });
              _nameTimer?.cancel();
              _nameTimer = Timer(const Duration(seconds: 1), () {
                if (mounted) setState(() => _showName = false);
              });
              await _updateImageStream();
            },
            onCapture: _isVideoMode ? _startStopRecording : _capturePhoto,
            onMemories: () {
              // TODO: open gallery/memories
            },
            onFlip: _toggleCamera,
            isRecording: _isRecording,
            isVideoMode: _isVideoMode,
            height: 118,
            shutterSize: 84,
            chipSize: 56,
            spacing: 14,
          ),
        ),
      ],
    );
  }

  // ===== ui.Image cache for preview overlays =====
  Future<Map<String, ui.Image>> _preload(LensFilter lens) async {
    final map = <String, ui.Image>{};
    for (final l in lens.overlays) {
      map[l.assetPath] = await _loadUiImage(l.assetPath);
    }
    return map;
  }

  Future<ui.Image> _loadUiImage(String asset) async {
    if (_overlayCache.containsKey(asset)) return _overlayCache[asset]!;
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    _overlayCache[asset] = frame.image;
    return frame.image;
  }

  // ===== Baking AR overlays onto a captured photo =====
  Future<File?> _bakeOverlaysOnFile(File file, LensFilter lens) async {
    final bytes = await file.readAsBytes();
    final base = img.decodeImage(bytes);
    if (base == null) return null;

    // Detect faces on full-res image
    final input = InputImage.fromFilePath(file.path);
    final faces = await _detector.processImage(input);

    // Load overlay PNGs
    final Map<String, img.Image> overlayImgs = {};
    for (final spec in lens.overlays) {
      final data = await rootBundle.load(spec.assetPath);
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded != null) overlayImgs[spec.assetPath] = decoded;
    }

    final out = img.Image.from(base);

    void drawOverlay(img.Image target, img.Image sticker, Rect dst) {
      final w = dst.width.round().clamp(1, 4096);
      final h = dst.height.round().clamp(1, 4096);
      final resized = img.copyResize(
        sticker,
        width: w,
        height: h,
        interpolation: img.Interpolation.cubic,
      );
      final x = dst.left.round();
      final y = dst.top.round();
      img.compositeImage(
        target,
        resized,
        dstX: x,
        dstY: y,
        blend: img.BlendMode.alpha, // proper alpha blending
      );
    }

    for (final face in faces) {
      final box = face.boundingBox;
      final faceWidth = box.width.toDouble();
      final faceCenter = Offset(
        box.center.dx.toDouble(),
        box.center.dy.toDouble(),
      );

      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final mouthBottom =
          face.landmarks[FaceLandmarkType.bottomMouth]?.position;

      for (final spec in lens.overlays) {
        final sticker = overlayImgs[spec.assetPath];
        if (sticker == null) continue;

        Rect dst;
        switch (spec.anchor) {
          case FaceAnchor.aboveHead:
            final w = faceWidth * spec.scale;
            final h = w;
            dst = Rect.fromCenter(
              center: Offset(faceCenter.dx, box.top.toDouble() - h * 0.35),
              width: w,
              height: h,
            );
            break;

          case FaceAnchor.overEyes:
            if (leftEye != null && rightEye != null) {
              final lx = leftEye.x.toDouble();
              final rx = rightEye.x.toDouble();
              final ly = leftEye.y.toDouble();
              final ry = rightEye.y.toDouble();
              final mid = Offset((lx + rx) / 2, (ly + ry) / 2);
              final w = (rx - lx).abs() * 2.1 * spec.scale;
              final h = w * (sticker.height / sticker.width);
              dst = Rect.fromCenter(center: mid, width: w, height: h);
            } else {
              final w = faceWidth * 0.95 * spec.scale;
              final h = w * (sticker.height / sticker.width);
              dst = Rect.fromCenter(
                center: Offset(faceCenter.dx, faceCenter.dy - h * 0.2),
                width: w,
                height: h,
              );
            }
            break;

          case FaceAnchor.onNose:
            if (noseBase != null) {
              final p = Offset(noseBase.x.toDouble(), noseBase.y.toDouble());
              final w = faceWidth * spec.scale;
              final h = w * (sticker.height / sticker.width);
              dst = Rect.fromCenter(center: p, width: w, height: h);
            } else {
              final w = faceWidth * 0.45 * spec.scale;
              final h = w * (sticker.height / sticker.width);
              dst = Rect.fromCenter(center: faceCenter, width: w, height: h);
            }
            break;

          case FaceAnchor.overMouth:
            if (mouthBottom != null) {
              final p = Offset(
                mouthBottom.x.toDouble(),
                mouthBottom.y.toDouble(),
              );
              final w = faceWidth * spec.scale;
              final h = w * (sticker.height / sticker.width);
              dst = Rect.fromCenter(center: p, width: w, height: h);
            } else {
              final w = faceWidth * 0.7 * spec.scale;
              final h = w * (sticker.height / sticker.width);
              dst = Rect.fromCenter(
                center: faceCenter.translate(0, faceWidth * 0.15),
                width: w,
                height: h,
              );
            }
            break;

          case FaceAnchor.cheeks:
            if (leftEye != null && rightEye != null) {
              final lx = leftEye.x.toDouble();
              final rx = rightEye.x.toDouble();
              final y = faceCenter.dy + faceWidth * 0.05;
              final d = (rx - lx).abs() * 0.5;

              for (final cx in [lx - d * 0.25, rx + d * 0.25]) {
                final w = faceWidth * spec.scale;
                final h = w * (sticker.height / sticker.width);
                final r = Rect.fromCenter(
                  center: Offset(cx, y),
                  width: w,
                  height: h,
                ).shift(spec.offset);
                drawOverlay(out, sticker, r);
              }
              continue;
            } else {
              final w = faceWidth * spec.scale;
              final h = w * (sticker.height / sticker.width);
              final left = Rect.fromCenter(
                center: faceCenter.translate(
                  -faceWidth * 0.28,
                  faceWidth * 0.05,
                ),
                width: w,
                height: h,
              ).shift(spec.offset);
              final right = Rect.fromCenter(
                center: faceCenter.translate(
                  faceWidth * 0.28,
                  faceWidth * 0.05,
                ),
                width: w,
                height: h,
              ).shift(spec.offset);
              drawOverlay(out, sticker, left);
              drawOverlay(out, sticker, right);
              continue;
            }
        }

        dst = dst.shift(spec.offset);
        drawOverlay(out, sticker, dst);
      }
    }

    final jpg = img.encodeJpg(out, quality: 92);
    final tmpDir = await getTemporaryDirectory();
    final baked = await File(
      '${tmpDir.path}/memscape_${DateTime.now().millisecondsSinceEpoch}_ar.jpg',
    ).writeAsBytes(jpg, flush: true);
    return baked;
  }

  // ===== Color matrix (image v4) =====
  img.Image _applyMatrix(img.Image input, List<double> m) {
    final out = img.Image.from(input);
    for (int y = 0; y < input.height; y++) {
      for (int x = 0; x < input.width; x++) {
        final p = input.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final a = p.a.toDouble();
        final nr =
            (r * m[0] + g * m[1] + b * m[2] + a * m[3] + m[4])
                .clamp(0, 255)
                .toInt();
        final ng =
            (r * m[5] + g * m[6] + b * m[7] + a * m[8] + m[9])
                .clamp(0, 255)
                .toInt();
        final nb =
            (r * m[10] + g * m[11] + b * m[12] + a * m[13] + m[14])
                .clamp(0, 255)
                .toInt();
        final na =
            (r * m[15] + g * m[16] + b * m[17] + a * m[18] + m[19])
                .clamp(0, 255)
                .toInt();
        out.setPixelRgba(x, y, nr, ng, nb, na);
      }
    }
    return out;
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.black54,
          shape: BoxShape.circle,
          border:
              active
                  ? Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  )
                  : null,
        ),
        child: Icon(
          icon,
          color: active ? Colors.black : Colors.white,
          size: 22,
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/* =====================  SNAPCHAT-LIKE BOTTOM BAR  ===================== */

class _LensChipData {
  final String name;
  final ImageProvider? thumb;
  const _LensChipData({required this.name, this.thumb});
}

class _SnapBottomBar extends StatefulWidget {
  final List<_LensChipData> items;
  final int selectedIndex;
  final ValueChanged<int> onIndexChanged;

  final VoidCallback onCapture; // shutter
  final VoidCallback? onMemories; // left pill
  final VoidCallback? onFlip; // right circle
  final bool isRecording;
  final bool isVideoMode;

  final double height;
  final double shutterSize;
  final double chipSize;
  final double spacing;

  const _SnapBottomBar({
    required this.items,
    required this.selectedIndex,
    required this.onIndexChanged,
    required this.onCapture,
    this.onMemories,
    this.onFlip,
    this.isRecording = false,
    this.isVideoMode = false,
    this.height = 118,
    this.shutterSize = 84,
    this.chipSize = 56,
    this.spacing = 14,
  });

  @override
  State<_SnapBottomBar> createState() => _SnapBottomBarState();
}

class _SnapBottomBarState extends State<_SnapBottomBar> {
  final _ctrl = ScrollController();

  EdgeInsets get _railPadding {
    final halfHole = (widget.shutterSize * 0.5) + 24;
    return EdgeInsets.symmetric(horizontal: 16 + halfHole);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = Colors.black.withOpacity(0.28);

    return SafeArea(
      top: false,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Lens rail
            Align(
              alignment: Alignment.center,
              child: Container(
                height: widget.chipSize + 20,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: ListView.separated(
                  controller: _ctrl,
                  padding: _railPadding,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.items.length,
                  separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
                  itemBuilder: (context, i) {
                    final it = widget.items[i];
                    final selected = i == widget.selectedIndex;
                    return GestureDetector(
                      onTap: () => widget.onIndexChanged(i),
                      child: _LensChip(
                        label: it.name,
                        image: it.thumb,
                        size: widget.chipSize,
                        selected: selected,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Left pill: Memories
            Positioned(
              left: 16,
              child: _SmallPillButton(
                icon: Icons.photo_library_rounded,
                label: 'Memories',
                onTap: widget.onMemories,
              ),
            ),

            // Right circle: Flip camera
            Positioned(
              right: 16,
              child: _RoundButton(
                icon: Icons.cameraswitch_rounded,
                onTap: widget.onFlip,
              ),
            ),

            // Center shutter
            GestureDetector(
              onTap: widget.onCapture,
              child: Container(
                width: widget.shutterSize,
                height: widget.shutterSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        widget.isVideoMode
                            ? (widget.isRecording ? Colors.red : Colors.white)
                            : Colors.white,
                    width: 6,
                  ),
                  color: Colors.transparent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  final String label;
  final ImageProvider? image;
  final double size;
  final bool selected;

  const _LensChip({
    required this.label,
    required this.image,
    required this.size,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final border =
        selected
            ? Border.all(color: Colors.white, width: 3)
            : Border.all(color: Colors.white24, width: 1.5);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: border,
        image:
            image != null
                ? DecorationImage(image: image!, fit: BoxFit.cover)
                : null,
        color: image == null ? Colors.white10 : null,
      ),
      alignment: Alignment.center,
      child:
          image == null
              ? Text(
                label.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              )
              : null,
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _SmallPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  const _SmallPillButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}




// lib/screens/home/upload/story_capture_page.dart
// import 'dart:async';
// import 'dart:io';
// import 'dart:ui' as ui;

// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart' show rootBundle;
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:image/image.dart' as img;
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';

// // Your widgets & helpers
// import 'widgets/filters_presets.dart'; // color matrices
// import 'widgets/lens_models.dart'; // FaceAnchor, OverlaySpec, LensFilter
// import 'widgets/face_overlay_painter.dart'; // preview painter for AR overlays
// import 'widgets/mlkit_image_utils.dart'; // buildInputImage()
// import 'widgets/lenses_carousel.dart'; // bottom Snapchat-like carousel

// class StoryCapturePage extends StatefulWidget {
//   final ValueChanged<File> onCaptured;
//   const StoryCapturePage({super.key, required this.onCaptured});

//   @override
//   State<StoryCapturePage> createState() => _StoryCapturePageState();
// }

// class _StoryCapturePageState extends State<StoryCapturePage>
//     with WidgetsBindingObserver {
//   CameraController? _controller;
//   List<CameraDescription> _cameras = [];
//   bool _ready = false;
//   bool _usingFront = true;
//   bool _isTaking = false;
//   FlashMode _flash = FlashMode.off;

//   // Video mode
//   bool _isVideoMode = false;
//   bool _isRecording = false;

//   // Lenses (first color filters, then AR overlays)
//   late final List<LensFilter> _lenses;
//   int _index = 0;

//   // Center name flash
//   bool _showName = false;
//   String _nameText = '';
//   Timer? _nameTimer;

//   // Face detection (live) for AR overlays
//   late final FaceDetector _detector;
//   bool _detecting = false;
//   List<Face> _faces = [];

//   // ui.Image cache for preview overlays
//   final Map<String, ui.Image> _overlayCache = {};

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);

//     // Build the carousel content
//     _lenses = [
//       // Color filters (matrix only)
//       LensFilter(
//         name: FilterPresets.swipeOrder[0].name,
//         matrix: FilterPresets.swipeOrder[0].matrix,
//       ),
//       LensFilter(
//         name: FilterPresets.swipeOrder[1].name,
//         matrix: FilterPresets.swipeOrder[1].matrix,
//       ),
//       LensFilter(
//         name: FilterPresets.swipeOrder[2].name,
//         matrix: FilterPresets.swipeOrder[2].matrix,
//       ),
//       LensFilter(
//         name: FilterPresets.swipeOrder[3].name,
//         matrix: FilterPresets.swipeOrder[3].matrix,
//       ),
//       LensFilter(
//         name: FilterPresets.swipeOrder[4].name,
//         matrix: FilterPresets.swipeOrder[4].matrix,
//       ),
//       LensFilter(
//         name: FilterPresets.swipeOrder[5].name,
//         matrix: FilterPresets.swipeOrder[5].matrix,
//       ),

//       // AR overlays (preview + baked on photo)
//       const LensFilter(
//         name: 'Doggo',
//         overlays: [
//           OverlaySpec(
//             assetPath: 'assets/lenses/dog_ears.png',
//             anchor: FaceAnchor.aboveHead,
//             scale: 1.15,
//             offset: Offset(0, -20),
//           ),
//           OverlaySpec(
//             assetPath: 'assets/lenses/dog_nose.png',
//             anchor: FaceAnchor.onNose,
//             scale: 0.45,
//             offset: Offset(0, 18),
//           ),
//         ],
//       ),
//       const LensFilter(
//         name: 'Nerd Mode',
//         overlays: [
//           OverlaySpec(
//             assetPath: 'assets/lenses/glasses.png',
//             anchor: FaceAnchor.overEyes,
//             scale: 1.05,
//             offset: Offset(0, 12),
//           ),
//         ],
//       ),
//       const LensFilter(
//         name: '’Stache',
//         overlays: [
//           OverlaySpec(
//             assetPath: 'assets/lenses/mustache.png',
//             anchor: FaceAnchor.overMouth,
//             scale: 0.7,
//             offset: Offset(0, 6),
//           ),
//         ],
//       ),
//       const LensFilter(
//         name: 'Blush',
//         overlays: [
//           OverlaySpec(
//             assetPath: 'assets/lenses/blush.png',
//             anchor: FaceAnchor.cheeks,
//             scale: 0.35,
//             offset: Offset(0, 14),
//           ),
//         ],
//       ),
//       const LensFilter(
//         name: 'Crybaby',
//         overlays: [
//           OverlaySpec(
//             assetPath: 'assets/lenses/tears.png',
//             anchor: FaceAnchor.overEyes,
//             scale: 0.95,
//             offset: Offset(0, 32),
//           ),
//         ],
//       ),
//     ];

//     _nameText = _lenses[_index].name;

//     _detector = FaceDetector(
//       options: FaceDetectorOptions(
//         enableLandmarks: true,
//         enableContours: false,
//         performanceMode: FaceDetectorMode.accurate,
//       ),
//     );

//     _initCamera();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _nameTimer?.cancel();
//     _stopImageStream();
//     _controller?.dispose();
//     _detector.close();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) async {
//     final cam = _controller;
//     if (cam == null || !cam.value.isInitialized) return;

//     if (state == AppLifecycleState.inactive ||
//         state == AppLifecycleState.paused) {
//       await _stopImageStream();
//       await _controller?.dispose();
//       _controller = null;
//       if (mounted) setState(() => _ready = false);
//     } else if (state == AppLifecycleState.resumed) {
//       await _initCamera();
//     }
//   }

//   void _snack(String m) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
//   }

//   Future<void> _initCamera() async {
//     try {
//       if (!(await Permission.camera.request()).isGranted) {
//         _snack("Camera permission denied. Enable it in Settings.");
//         if (mounted) setState(() => _ready = false);
//         return;
//       }

//       final cameras = await availableCameras();
//       if (cameras.isEmpty) {
//         if (mounted) setState(() => _ready = false);
//         _snack("No camera found on this device.");
//         return;
//       }
//       _cameras = cameras;

//       final description =
//           _usingFront
//               ? _cameras.firstWhere(
//                 (c) => c.lensDirection == CameraLensDirection.front,
//                 orElse: () => _cameras.first,
//               )
//               : _cameras.firstWhere(
//                 (c) => c.lensDirection == CameraLensDirection.back,
//                 orElse: () => _cameras.first,
//               );

//       final controller = CameraController(
//         description,
//         ResolutionPreset.medium,
//         enableAudio: _isVideoMode,
//         imageFormatGroup: ImageFormatGroup.yuv420,
//       );

//       _controller?.dispose();
//       _controller = controller;
//       await controller.initialize();
//       await controller.setFlashMode(_flash);

//       await _updateImageStream(); // start/stop face stream based on lens

//       if (!mounted) return;
//       setState(() => _ready = true);
//     } catch (e) {
//       if (mounted) setState(() => _ready = false);
//       _snack("Camera init failed: $e");
//     }
//   }

//   Future<void> _toggleCamera() async {
//     _usingFront = !_usingFront;
//     await _initCamera();
//   }

//   Future<void> _toggleFlash() async {
//     if (_controller == null) return;
//     final next = switch (_flash) {
//       FlashMode.off => FlashMode.auto,
//       FlashMode.auto => FlashMode.always,
//       FlashMode.always => FlashMode.torch,
//       FlashMode.torch => FlashMode.off,
//       _ => FlashMode.off,
//     };
//     _flash = next;
//     await _controller!.setFlashMode(_flash);
//     setState(() {});
//   }

//   Future<void> _toggleVideoMode() async {
//     if (_isRecording) return;
//     setState(() => _isVideoMode = !_isVideoMode);
//     await _initCamera();
//   }

//   // Face stream only when AR overlays active
//   bool get _arActive => _lenses[_index].overlays.isNotEmpty;

//   Future<void> _updateImageStream() async {
//     if (_controller == null || !_controller!.value.isInitialized) return;
//     if (_arActive) {
//       await _startImageStream();
//     } else {
//       await _stopImageStream();
//       if (mounted) setState(() => _faces = []);
//     }
//   }

//   Future<void> _startImageStream() async {
//     if (_controller == null) return;
//     if (_controller!.value.isStreamingImages) return;
//     await _controller!.startImageStream(_onFrame);
//   }

//   Future<void> _stopImageStream() async {
//     final cam = _controller;
//     if (cam == null) return;
//     if (cam.value.isStreamingImages) {
//       try {
//         await cam.stopImageStream();
//       } catch (_) {}
//     }
//   }

//   Future<void> _onFrame(CameraImage image) async {
//     if (_detecting) return;
//     _detecting = true;
//     try {
//       final input = buildInputImage(image, _controller!.description);
//       final faces = await _detector.processImage(input);
//       if (mounted && _arActive) {
//         setState(() => _faces = faces);
//       }
//     } catch (_) {
//       // ignore
//     } finally {
//       _detecting = false;
//     }
//   }

//   // ===== Capture (video) =====
//   Future<void> _startStopRecording() async {
//     final cam = _controller;
//     if (!_ready || cam == null) return;

//     try {
//       if (_isRecording) {
//         final file = await cam.stopVideoRecording();
//         setState(() => _isRecording = false);
//         // AR overlays are preview-only for video.
//         widget.onCaptured(File(file.path));
//         return;
//       }

//       await cam.startVideoRecording();
//       setState(() => _isRecording = true);
//     } catch (e) {
//       _snack("Video error: $e");
//       if (cam?.value.isRecordingVideo == true) {
//         try {
//           await cam!.stopVideoRecording();
//         } catch (_) {}
//       }
//       setState(() => _isRecording = false);
//     }
//   }

//   // ===== Capture (photo) =====
//   Future<void> _capturePhoto() async {
//     final cam = _controller;
//     if (cam?.value.isTakingPicture == true) return;
//     if (!_ready || cam == null || _isTaking) return;

//     try {
//       setState(() => _isTaking = true);
//       final xfile = await cam.takePicture();
//       File outFile = File(xfile.path);

//       final lens = _lenses[_index];

//       // 1) Bake color matrix (if any)
//       if (lens.matrix != null) {
//         try {
//           final bytes = await outFile.readAsBytes();
//           final decoded = img.decodeImage(bytes);
//           if (decoded != null) {
//             final filtered = _applyMatrix(decoded, lens.matrix!);
//             final jpg = img.encodeJpg(filtered, quality: 92);
//             final tmpDir = await getTemporaryDirectory();
//             outFile = await File(
//               '${tmpDir.path}/memscape_${DateTime.now().millisecondsSinceEpoch}.jpg',
//             ).writeAsBytes(jpg, flush: true);
//           }
//         } catch (e) {
//           _snack("Color filter failed (using original): $e");
//         }
//       }

//       // 2) Bake AR overlays (if any)
//       if (lens.overlays.isNotEmpty) {
//         try {
//           final baked = await _bakeOverlaysOnFile(outFile, lens);
//           if (baked != null) outFile = baked;
//         } catch (e) {
//           _snack("AR overlay bake failed (using filtered image): $e");
//         }
//       }

//       if (!mounted) return;
//       widget.onCaptured(outFile);
//     } catch (e) {
//       _snack("Capture failed: $e");
//     } finally {
//       if (mounted) setState(() => _isTaking = false);
//     }
//   }

//   // ===== UI =====
//   @override
//   Widget build(BuildContext context) {
//     if (!_ready || _controller == null) {
//       return const Center(child: CircularProgressIndicator());
//     }

//     final lens = _lenses[_index];
//     final preview =
//         lens.matrix == null
//             ? CameraPreview(_controller!)
//             : ColorFiltered(
//               colorFilter: ColorFilter.matrix(lens.matrix!),
//               child: CameraPreview(_controller!),
//             );

//     return Stack(
//       children: [
//         // Full preview (NO swipe handler anymore)
//         Positioned.fill(
//           child: LayoutBuilder(
//             builder: (context, constraints) {
//               final value = _controller!.value;
//               final ps = value.isInitialized ? value.previewSize : null;

//               final previewLayer = Stack(
//                 fit: StackFit.expand,
//                 children: [
//                   preview,
//                   if (_arActive && ps != null)
//                     FutureBuilder<Map<String, ui.Image>>(
//                       future: _preload(lens),
//                       builder: (context, snap) {
//                         if (!snap.hasData) return const SizedBox.shrink();
//                         return CustomPaint(
//                           painter: FaceOverlayPainter(
//                             faces: _faces,
//                             previewSize: ps!,
//                             lens: lens,
//                             images: snap.data!,
//                             isFrontCamera:
//                                 _controller!.description.lensDirection ==
//                                 CameraLensDirection.front,
//                           ),
//                         );
//                       },
//                     ),
//                 ],
//               );

//               if (ps == null) return previewLayer;

//               return OverflowBox(
//                 alignment: Alignment.center,
//                 child: FittedBox(
//                   fit: BoxFit.cover,
//                   child: SizedBox(
//                     width: value.previewSize!.height,
//                     height: value.previewSize!.width,
//                     child: previewLayer,
//                   ),
//                 ),
//               );
//             },
//           ),
//         ),

//         // Top-right controls
//         SafeArea(
//           child: Align(
//             alignment: Alignment.topRight,
//             child: Padding(
//               padding: const EdgeInsets.only(top: 8.0, right: 8.0),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   _RoundIconButton(
//                     icon: switch (_flash) {
//                       FlashMode.off => Icons.flash_off,
//                       FlashMode.auto => Icons.flash_auto,
//                       FlashMode.always => Icons.flash_on,
//                       FlashMode.torch => Icons.bolt,
//                       _ => Icons.flash_off,
//                     },
//                     tooltip: 'Flash',
//                     onTap: _toggleFlash,
//                   ),
//                   const SizedBox(height: 10),
//                   _RoundIconButton(
//                     icon: Icons.cameraswitch,
//                     tooltip: 'Flip camera',
//                     onTap: _toggleCamera,
//                   ),
//                   const SizedBox(height: 10),
//                   _RoundIconButton(
//                     icon:
//                         _isVideoMode ? Icons.videocam : Icons.videocam_outlined,
//                     tooltip: 'Toggle video mode',
//                     active: _isVideoMode,
//                     onTap: _toggleVideoMode,
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),

//         // Center name flash
//         IgnorePointer(
//           child: AnimatedOpacity(
//             opacity: _showName ? 1.0 : 0.0,
//             duration: const Duration(milliseconds: 180),
//             child: Center(
//               child: Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 14,
//                   vertical: 8,
//                 ),
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(0.55),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Text(
//                   _nameText,
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 16,
//                     letterSpacing: 0.3,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),

//         // Shutter button (center bottom)
//         Align(
//           alignment: Alignment.bottomCenter,
//           child: Padding(
//             padding: const EdgeInsets.only(bottom: 28.0),
//             child: GestureDetector(
//               onTap: _isVideoMode ? _startStopRecording : _capturePhoto,
//               child: Container(
//                 width: 84,
//                 height: 84,
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   border: Border.all(
//                     color:
//                         _isVideoMode
//                             ? (_isRecording ? Colors.red : Colors.white)
//                             : Colors.white,
//                     width: 6,
//                   ),
//                 ),
//                 child:
//                     (_isTaking || _isRecording)
//                         ? const Center(
//                           child: SizedBox(
//                             width: 26,
//                             height: 26,
//                             child: CircularProgressIndicator(strokeWidth: 2.4),
//                           ),
//                         )
//                         : null,
//               ),
//             ),
//           ),
//         ),

//         // Snapchat-like lens carousel (just above the shutter)
//         LensesCarousel(
//           items:
//               _lenses
//                   .map(
//                     (l) => LensChipData(
//                       name: l.name,
//                       // Optional: AssetImage('assets/lenses/thumbs/${l.name}.png')
//                       thumb: null,
//                     ),
//                   )
//                   .toList(),
//           initialIndex: _index,
//           bottomPadding: 128, // sits above shutter
//           itemSize: 56,
//           itemScale: 1.22,
//           spacing: 14,
//           onIndexChanged: (i) async {
//             setState(() {
//               _index = i;
//               _nameText = _lenses[_index].name;
//               _showName = true;
//             });
//             _nameTimer?.cancel();
//             _nameTimer = Timer(const Duration(seconds: 1), () {
//               if (mounted) setState(() => _showName = false);
//             });
//             await _updateImageStream();
//           },
//         ),
//       ],
//     );
//   }

//   // ===== ui.Image cache for preview overlays =====
//   Future<Map<String, ui.Image>> _preload(LensFilter lens) async {
//     final map = <String, ui.Image>{};
//     for (final l in lens.overlays) {
//       map[l.assetPath] = await _loadUiImage(l.assetPath);
//     }
//     return map;
//   }

//   Future<ui.Image> _loadUiImage(String asset) async {
//     if (_overlayCache.containsKey(asset)) return _overlayCache[asset]!;
//     final data = await rootBundle.load(asset);
//     final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
//     final frame = await codec.getNextFrame();
//     _overlayCache[asset] = frame.image;
//     return frame.image;
//   }

//   // ===== Baking AR overlays onto a captured photo =====
//   Future<File?> _bakeOverlaysOnFile(File file, LensFilter lens) async {
//     final bytes = await file.readAsBytes();
//     final base = img.decodeImage(bytes);
//     if (base == null) return null;

//     // Detect faces on full-res image
//     final input = InputImage.fromFilePath(file.path);
//     final faces = await _detector.processImage(input);

//     // Load overlay PNGs
//     final Map<String, img.Image> overlayImgs = {};
//     for (final spec in lens.overlays) {
//       final data = await rootBundle.load(spec.assetPath);
//       final decoded = img.decodeImage(data.buffer.asUint8List());
//       if (decoded != null) overlayImgs[spec.assetPath] = decoded;
//     }

//     final out = img.Image.from(base);

//     void drawOverlay(img.Image target, img.Image sticker, Rect dst) {
//       final w = dst.width.round().clamp(1, 4096);
//       final h = dst.height.round().clamp(1, 4096);
//       final resized = img.copyResize(
//         sticker,
//         width: w,
//         height: h,
//         interpolation: img.Interpolation.cubic,
//       );
//       final x = dst.left.round();
//       final y = dst.top.round();
//       img.compositeImage(
//         target,
//         resized,
//         dstX: x,
//         dstY: y,
//         blend: img.BlendMode.alpha, // proper alpha blending
//       );
//     }

//     for (final face in faces) {
//       final box = face.boundingBox;
//       final faceWidth = box.width.toDouble();
//       final faceCenter = Offset(
//         box.center.dx.toDouble(),
//         box.center.dy.toDouble(),
//       );

//       final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
//       final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
//       final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
//       final mouthBottom =
//           face.landmarks[FaceLandmarkType.bottomMouth]?.position;

//       for (final spec in lens.overlays) {
//         final sticker = overlayImgs[spec.assetPath];
//         if (sticker == null) continue;

//         Rect dst;
//         switch (spec.anchor) {
//           case FaceAnchor.aboveHead:
//             final w = faceWidth * spec.scale;
//             final h = w;
//             dst = Rect.fromCenter(
//               center: Offset(faceCenter.dx, box.top.toDouble() - h * 0.35),
//               width: w,
//               height: h,
//             );
//             break;

//           case FaceAnchor.overEyes:
//             if (leftEye != null && rightEye != null) {
//               final lx = leftEye.x.toDouble();
//               final rx = rightEye.x.toDouble();
//               final ly = leftEye.y.toDouble();
//               final ry = rightEye.y.toDouble();
//               final mid = Offset((lx + rx) / 2, (ly + ry) / 2);

//               final w = (rx - lx).abs() * 2.1 * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               dst = Rect.fromCenter(center: mid, width: w, height: h);
//             } else {
//               final w = faceWidth * 0.95 * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               dst = Rect.fromCenter(
//                 center: Offset(faceCenter.dx, faceCenter.dy - h * 0.2),
//                 width: w,
//                 height: h,
//               );
//             }
//             break;

//           case FaceAnchor.onNose:
//             if (noseBase != null) {
//               final p = Offset(noseBase.x.toDouble(), noseBase.y.toDouble());
//               final w = faceWidth * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               dst = Rect.fromCenter(center: p, width: w, height: h);
//             } else {
//               final w = faceWidth * 0.45 * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               dst = Rect.fromCenter(center: faceCenter, width: w, height: h);
//             }
//             break;

//           case FaceAnchor.overMouth:
//             if (mouthBottom != null) {
//               final p = Offset(
//                 mouthBottom.x.toDouble(),
//                 mouthBottom.y.toDouble(),
//               );
//               final w = faceWidth * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               dst = Rect.fromCenter(center: p, width: w, height: h);
//             } else {
//               final w = faceWidth * 0.7 * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               dst = Rect.fromCenter(
//                 center: faceCenter.translate(0, faceWidth * 0.15),
//                 width: w,
//                 height: h,
//               );
//             }
//             break;

//           case FaceAnchor.cheeks:
//             if (leftEye != null && rightEye != null) {
//               final lx = leftEye.x.toDouble();
//               final rx = rightEye.x.toDouble();
//               final y = faceCenter.dy + faceWidth * 0.05;
//               final d = (rx - lx).abs() * 0.5;

//               for (final cx in [lx - d * 0.25, rx + d * 0.25]) {
//                 final w = faceWidth * spec.scale;
//                 final h = w * (sticker.height / sticker.width);
//                 final r = Rect.fromCenter(
//                   center: Offset(cx, y),
//                   width: w,
//                   height: h,
//                 ).shift(spec.offset);
//                 drawOverlay(out, sticker, r);
//               }
//               continue;
//             } else {
//               final w = faceWidth * spec.scale;
//               final h = w * (sticker.height / sticker.width);
//               final left = Rect.fromCenter(
//                 center: faceCenter.translate(
//                   -faceWidth * 0.28,
//                   faceWidth * 0.05,
//                 ),
//                 width: w,
//                 height: h,
//               ).shift(spec.offset);
//               final right = Rect.fromCenter(
//                 center: faceCenter.translate(
//                   faceWidth * 0.28,
//                   faceWidth * 0.05,
//                 ),
//                 width: w,
//                 height: h,
//               ).shift(spec.offset);
//               drawOverlay(out, sticker, left);
//               drawOverlay(out, sticker, right);
//               continue;
//             }
//         }

//         dst = dst.shift(spec.offset);
//         drawOverlay(out, sticker, dst);
//       }
//     }

//     final jpg = img.encodeJpg(out, quality: 92);
//     final tmpDir = await getTemporaryDirectory();
//     final baked = await File(
//       '${tmpDir.path}/memscape_${DateTime.now().millisecondsSinceEpoch}_ar.jpg',
//     ).writeAsBytes(jpg, flush: true);
//     return baked;
//   }

//   // ===== Color matrix (image v4) =====
//   img.Image _applyMatrix(img.Image input, List<double> m) {
//     final out = img.Image.from(input);
//     for (int y = 0; y < input.height; y++) {
//       for (int x = 0; x < input.width; x++) {
//         final p = input.getPixel(x, y);
//         final r = p.r.toDouble();
//         final g = p.g.toDouble();
//         final b = p.b.toDouble();
//         final a = p.a.toDouble();
//         final nr =
//             (r * m[0] + g * m[1] + b * m[2] + a * m[3] + m[4])
//                 .clamp(0, 255)
//                 .toInt();
//         final ng =
//             (r * m[5] + g * m[6] + b * m[7] + a * m[8] + m[9])
//                 .clamp(0, 255)
//                 .toInt();
//         final nb =
//             (r * m[10] + g * m[11] + b * m[12] + a * m[13] + m[14])
//                 .clamp(0, 255)
//                 .toInt();
//         final na =
//             (r * m[15] + g * m[16] + b * m[17] + a * m[18] + m[19])
//                 .clamp(0, 255)
//                 .toInt();
//         out.setPixelRgba(x, y, nr, ng, nb, na);
//       }
//     }
//     return out;
//   }
// }

// class _RoundIconButton extends StatelessWidget {
//   final IconData icon;
//   final VoidCallback onTap;
//   final String? tooltip;
//   final bool active;
//   const _RoundIconButton({
//     required this.icon,
//     required this.onTap,
//     this.tooltip,
//     this.active = false,
//     super.key,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final child = InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(999),
//       child: Container(
//         width: 44,
//         height: 44,
//         decoration: BoxDecoration(
//           color: active ? Colors.white : Colors.black54,
//           shape: BoxShape.circle,
//           border:
//               active
//                   ? Border.all(
//                     color: Theme.of(context).colorScheme.primary,
//                     width: 2,
//                   )
//                   : null,
//         ),
//         child: Icon(
//           icon,
//           color: active ? Colors.black : Colors.white,
//           size: 22,
//         ),
//       ),
//     );
//     return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
//   }
// }





// // lib/screens/home/upload/story_capture_page.dart
// import 'dart:async';
// import 'dart:io';
// import 'package:camera/camera.dart';
// import 'package:flutter/material.dart';
// import 'package:image/image.dart' as img;
// import 'package:path_provider/path_provider.dart';
// import 'package:permission_handler/permission_handler.dart';

// import 'widgets/filters_presets.dart';

// class StoryCapturePage extends StatefulWidget {
//   final ValueChanged<File> onCaptured;
//   const StoryCapturePage({super.key, required this.onCaptured});

//   @override
//   State<StoryCapturePage> createState() => _StoryCapturePageState();
// }

// class _StoryCapturePageState extends State<StoryCapturePage>
//     with WidgetsBindingObserver {
//   CameraController? _controller;
//   List<CameraDescription> _cameras = [];
//   bool _ready = false;
//   bool _usingFront = false;
//   bool _isTaking = false;
//   FlashMode _flash = FlashMode.off;

//   // Video mode
//   bool _isVideoMode = false;
//   bool _isRecording = false;

//   // Filters: index (0 == "No Cap")
//   final List<FilterPreset> _filters = FilterPresets.swipeOrder;
//   int _filterIndex = 0;

//   // Center filter name flash
//   bool _showFilterName = false;
//   String _currentFilterName = '';
//   Timer? _nameHideTimer;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _initCamera();
//     _currentFilterName = _filters[_filterIndex].name;
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _nameHideTimer?.cancel();
//     _disposeCamera();
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) async {
//     final cam = _controller;
//     if (cam == null || !cam.value.isInitialized) return;

//     if (state == AppLifecycleState.inactive ||
//         state == AppLifecycleState.paused) {
//       await _disposeCamera();
//     } else if (state == AppLifecycleState.resumed) {
//       await _initCamera();
//     }
//   }

//   void _snack(String m) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
//   }

//   Future<void> _disposeCamera() async {
//     try {
//       if (_controller != null) {
//         final c = _controller!;
//         _controller = null;
//         if (c.value.isStreamingImages) await c.stopImageStream();
//         if (c.value.isRecordingVideo) await c.stopVideoRecording();
//         await c.dispose();
//       }
//     } catch (_) {
//       // ignore
//     } finally {
//       if (mounted) setState(() => _ready = false);
//     }
//   }

//   Future<void> _initCamera() async {
//     try {
//       final camStatus = await Permission.camera.request();
//       if (!camStatus.isGranted) {
//         _snack("Camera permission denied. Enable it in Settings.");
//         if (mounted) setState(() => _ready = false);
//         return;
//       }

//       await _disposeCamera();

//       final cams = await availableCameras();
//       if (cams.isEmpty) {
//         if (mounted) setState(() => _ready = false);
//         _snack("No camera found on this device.");
//         return;
//       }
//       _cameras = cams;

//       final camera =
//           _usingFront
//               ? _cameras.firstWhere(
//                 (c) => c.lensDirection == CameraLensDirection.front,
//                 orElse: () => _cameras.first,
//               )
//               : _cameras.firstWhere(
//                 (c) => c.lensDirection == CameraLensDirection.back,
//                 orElse: () => _cameras.first,
//               );

//       final controller = CameraController(
//         camera,
//         ResolutionPreset.medium, // avoids buffer pressure
//         enableAudio: _isVideoMode, // audio only in video mode
//         imageFormatGroup: ImageFormatGroup.yuv420,
//       );

//       _controller = controller;
//       await controller.initialize();
//       await controller.setFlashMode(_flash);

//       if (!mounted) return;
//       setState(() => _ready = true);
//     } catch (e) {
//       if (mounted) setState(() => _ready = false);
//       _snack("Camera init failed: $e");
//     }
//   }

//   Future<void> _toggleCamera() async {
//     _usingFront = !_usingFront;
//     await _initCamera();
//   }

//   Future<void> _toggleFlash() async {
//     if (_controller == null) return;
//     final next = switch (_flash) {
//       FlashMode.off => FlashMode.auto,
//       FlashMode.auto => FlashMode.always,
//       FlashMode.always => FlashMode.torch,
//       FlashMode.torch => FlashMode.off,
//       _ => FlashMode.off,
//     };
//     _flash = next;
//     await _controller!.setFlashMode(_flash);
//     setState(() {});
//   }

//   Future<void> _toggleVideoMode() async {
//     if (_isRecording) return;
//     setState(() => _isVideoMode = !_isVideoMode);
//     await _initCamera();
//   }

//   Future<void> _startStopRecording() async {
//     final cam = _controller;
//     if (!_ready || cam == null) return;

//     try {
//       if (_isRecording) {
//         final file = await cam.stopVideoRecording();
//         setState(() => _isRecording = false);
//         // Filter overlay is preview-only for video without post processing.
//         widget.onCaptured(File(file.path));
//         return;
//       }

//       await cam.startVideoRecording();
//       setState(() => _isRecording = true);
//     } catch (e) {
//       _snack("Video error: $e");
//       if (cam?.value.isRecordingVideo == true) {
//         try {
//           await cam!.stopVideoRecording();
//         } catch (_) {}
//       }
//       setState(() => _isRecording = false);
//     }
//   }

//   Future<void> _capturePhoto() async {
//     final cam = _controller;
//     if (cam?.value.isTakingPicture == true) return;
//     if (!_ready || cam == null || _isTaking) return;

//     try {
//       setState(() => _isTaking = true);
//       final xfile = await cam.takePicture();
//       File outFile = File(xfile.path);

//       // Bake filter if not original
//       if (_filterIndex != 0) {
//         try {
//           final preset = _filters[_filterIndex];
//           final bytes = await outFile.readAsBytes();
//           final decoded = img.decodeImage(bytes);
//           if (decoded != null) {
//             final filtered = _applyMatrixFilter(decoded, preset.matrix);
//             final jpg = img.encodeJpg(filtered, quality: 92);
//             final tmpDir = await getTemporaryDirectory();
//             final f = File(
//               '${tmpDir.path}/memscape_${DateTime.now().millisecondsSinceEpoch}.jpg',
//             );
//             await f.writeAsBytes(jpg, flush: true);
//             outFile = f;
//           }
//         } catch (e) {
//           _snack("Filter apply failed, using original: $e");
//         }
//       }

//       if (!mounted) return;
//       widget.onCaptured(outFile);
//     } catch (e) {
//       _snack("Capture failed: $e");
//     } finally {
//       if (mounted) setState(() => _isTaking = false);
//     }
//   }

//   // Swipe left/right to change filter + show name
//   void _nudgeFilter(int dir) {
//     final next = (_filterIndex + dir) % _filters.length;
//     final fixed = next < 0 ? _filters.length - 1 : next;
//     setState(() {
//       _filterIndex = fixed;
//       _currentFilterName = _filters[_filterIndex].name;
//       _showFilterName = true;
//     });

//     _nameHideTimer?.cancel();
//     _nameHideTimer = Timer(const Duration(seconds: 1), () {
//       if (mounted) setState(() => _showFilterName = false);
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (!_ready || _controller == null) {
//       return const Center(child: CircularProgressIndicator());
//     }

//     final current = _filters[_filterIndex];

//     final previewWithFilter = ColorFiltered(
//       colorFilter: ColorFilter.matrix(current.matrix),
//       child: CameraPreview(_controller!),
//     );

//     return Stack(
//       children: [
//         // Full-bleed preview with swipe to change filter
//         Positioned.fill(
//           child: LayoutBuilder(
//             builder: (context, constraints) {
//               final value = _controller!.value;
//               final ps = value.isInitialized ? value.previewSize : null;

//               final previewChild = GestureDetector(
//                 behavior: HitTestBehavior.opaque,
//                 onHorizontalDragEnd: (details) {
//                   final v = details.primaryVelocity ?? 0;
//                   if (v.abs() < 100) return;
//                   // right swipe (positive) -> previous; left swipe (negative) -> next
//                   _nudgeFilter(v > 0 ? -1 : 1);
//                 },
//                 child: previewWithFilter,
//               );

//               if (ps == null) return previewChild;

//               return OverflowBox(
//                 alignment: Alignment.center,
//                 child: FittedBox(
//                   fit: BoxFit.cover,
//                   child: SizedBox(
//                     width: value.previewSize!.height,
//                     height: value.previewSize!.width,
//                     child: previewChild,
//                   ),
//                 ),
//               );
//             },
//           ),
//         ),

//         // Right-top vertical controls
//         SafeArea(
//           child: Align(
//             alignment: Alignment.topRight,
//             child: Padding(
//               padding: const EdgeInsets.only(top: 8.0, right: 8.0),
//               child: Column(
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   _RoundIconButton(
//                     icon: switch (_flash) {
//                       FlashMode.off => Icons.flash_off,
//                       FlashMode.auto => Icons.flash_auto,
//                       FlashMode.always => Icons.flash_on,
//                       FlashMode.torch => Icons.bolt,
//                       _ => Icons.flash_off,
//                     },
//                     tooltip: 'Flash',
//                     onTap: _toggleFlash,
//                   ),
//                   const SizedBox(height: 10),
//                   _RoundIconButton(
//                     icon: Icons.cameraswitch,
//                     tooltip: 'Flip camera',
//                     onTap: _toggleCamera,
//                   ),
//                   const SizedBox(height: 10),
//                   _RoundIconButton(
//                     icon:
//                         _isVideoMode ? Icons.videocam : Icons.videocam_outlined,
//                     tooltip: 'Toggle video mode',
//                     active: _isVideoMode,
//                     onTap: _toggleVideoMode,
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ),

//         // Centered filter name (fade for 1s)
//         IgnorePointer(
//           child: AnimatedOpacity(
//             opacity: _showFilterName ? 1.0 : 0.0,
//             duration: const Duration(milliseconds: 180),
//             child: Center(
//               child: Container(
//                 padding: const EdgeInsets.symmetric(
//                   horizontal: 14,
//                   vertical: 8,
//                 ),
//                 decoration: BoxDecoration(
//                   color: Colors.black.withOpacity(0.55),
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 child: Text(
//                   _currentFilterName,
//                   style: const TextStyle(
//                     color: Colors.white,
//                     fontSize: 16,
//                     letterSpacing: 0.3,
//                     fontWeight: FontWeight.w700,
//                   ),
//                 ),
//               ),
//             ),
//           ),
//         ),

//         // Bottom capture/record only (strip removed)
//         Align(
//           alignment: Alignment.bottomCenter,
//           child: Padding(
//             padding: const EdgeInsets.only(bottom: 20.0),
//             child: GestureDetector(
//               onTap: _isVideoMode ? _startStopRecording : _capturePhoto,
//               child: Container(
//                 width: 84,
//                 height: 84,
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   border: Border.all(
//                     color:
//                         _isVideoMode
//                             ? (_isRecording ? Colors.red : Colors.white)
//                             : Colors.white,
//                     width: 6,
//                   ),
//                 ),
//                 child:
//                     (_isTaking || _isRecording)
//                         ? const Center(
//                           child: SizedBox(
//                             width: 26,
//                             height: 26,
//                             child: CircularProgressIndicator(strokeWidth: 2.4),
//                           ),
//                         )
//                         : null,
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   /// v4‑compatible: apply a 4x5 color matrix to an `image` package Image.
//   img.Image _applyMatrixFilter(img.Image input, List<double> m) {
//     final out = img.Image.from(input);
//     for (int y = 0; y < input.height; y++) {
//       for (int x = 0; x < input.width; x++) {
//         final p = input.getPixel(x, y); // Pixel with r,g,b,a
//         final r = p.r.toDouble();
//         final g = p.g.toDouble();
//         final b = p.b.toDouble();
//         final a = p.a.toDouble();

//         final nr =
//             (r * m[0] + g * m[1] + b * m[2] + a * m[3] + m[4])
//                 .clamp(0, 255)
//                 .toInt();
//         final ng =
//             (r * m[5] + g * m[6] + b * m[7] + a * m[8] + m[9])
//                 .clamp(0, 255)
//                 .toInt();
//         final nb =
//             (r * m[10] + g * m[11] + b * m[12] + a * m[13] + m[14])
//                 .clamp(0, 255)
//                 .toInt();
//         final na =
//             (r * m[15] + g * m[16] + b * m[17] + a * m[18] + m[19])
//                 .clamp(0, 255)
//                 .toInt();

//         out.setPixelRgba(x, y, nr, ng, nb, na);
//       }
//     }
//     return out;
//   }
// }

// class _RoundIconButton extends StatelessWidget {
//   final IconData icon;
//   final VoidCallback onTap;
//   final String? tooltip;
//   final bool active;
//   const _RoundIconButton({
//     required this.icon,
//     required this.onTap,
//     this.tooltip,
//     this.active = false,
//     super.key,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final child = InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(999),
//       child: Container(
//         width: 44,
//         height: 44,
//         decoration: BoxDecoration(
//           color: active ? Colors.white : Colors.black54,
//           shape: BoxShape.circle,
//           border:
//               active
//                   ? Border.all(
//                     color: Theme.of(context).colorScheme.primary,
//                     width: 2,
//                   )
//                   : null,
//         ),
//         child: Icon(
//           icon,
//           color: active ? Colors.black : Colors.white,
//           size: 22,
//         ),
//       ),
//     );
//     return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
//   }
// }




