import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:memscape/screens/home/upload/widgets/lens_models.dart';

class FaceOverlayPainter extends CustomPainter {
  final List<Face> faces;
  final Size previewSize;
  final LensFilter lens;
  final Map<String, ui.Image> images;
  final bool isFrontCamera;

  FaceOverlayPainter({
    required this.faces,
    required this.previewSize,
    required this.lens,
    required this.images,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Map camera coords → widget coords (camera preview is rotated)
    final scaleX = size.width / previewSize.height;
    final scaleY = size.height / previewSize.width;

    for (final face in faces) {
      final box = face.boundingBox;
      final faceWidth = box.width * scaleX;
      final faceCenter = Offset(box.center.dx * scaleX, box.center.dy * scaleY);

      final leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
      final rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;
      final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
      final mouthBottom = face.landmarks[FaceLandmarkType.bottomMouth]?.position;

      canvas.save();
      if (isFrontCamera) {
        // mirror horizontally
        canvas.translate(size.width, 0);
        canvas.scale(-1, 1);
      }

      for (final layer in lens.overlays) {
        final overlay = images[layer.assetPath]!;
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
              final lx = leftEye.x.toDouble() * scaleX;
              final rx = rightEye.x.toDouble() * scaleX;
              final ly = leftEye.y.toDouble() * scaleY;
              final ry = rightEye.y.toDouble() * scaleY;
              final mid = Offset((lx + rx) / 2, (ly + ry) / 2);

              final w = (rx - lx).abs() * 2.1 * layer.scale;
              final h = w * (overlay.height / overlay.width);
              dst = Rect.fromCenter(center: mid, width: w, height: h);
            } else {
              final w = faceWidth * 0.95 * layer.scale;
              final h = w * (overlay.height / overlay.width);
              dst = Rect.fromCenter(
                center: Offset(faceCenter.dx, faceCenter.dy - h * 0.2),
                width: w,
                height: h,
              );
            }
            break;

          case FaceAnchor.onNose:
            if (noseBase != null) {
              final p = Offset(
                noseBase.x.toDouble() * scaleX,
                noseBase.y.toDouble() * scaleY,
              );
              final w = faceWidth * layer.scale;
              final h = w * (overlay.height / overlay.width);
              dst = Rect.fromCenter(center: p, width: w, height: h);
            } else {
              final w = faceWidth * 0.45 * layer.scale;
              final h = w * (overlay.height / overlay.width);
              dst = Rect.fromCenter(center: faceCenter, width: w, height: h);
            }
            break;

          case FaceAnchor.overMouth:
            if (mouthBottom != null) {
              final p = Offset(
                mouthBottom.x.toDouble() * scaleX,
                mouthBottom.y.toDouble() * scaleY,
              );
              final w = faceWidth * layer.scale;
              final h = w * (overlay.height / overlay.width);
              dst = Rect.fromCenter(center: p, width: w, height: h);
            } else {
              final w = faceWidth * 0.7 * layer.scale;
              final h = w * (overlay.height / overlay.width);
              dst = Rect.fromCenter(
                center: faceCenter.translate(0, faceWidth * 0.15),
                width: w,
                height: h,
              );
            }
            break;

          case FaceAnchor.cheeks:
            // draw twice (left/right)
            if (leftEye != null && rightEye != null) {
              final lx = leftEye.x.toDouble() * scaleX;
              final rx = rightEye.x.toDouble() * scaleX;
              final y = faceCenter.dy + faceWidth * 0.05;
              final d = (rx - lx).abs() * 0.5;

              for (final cx in [lx - d * 0.25, rx + d * 0.25]) {
                final w = faceWidth * layer.scale;
                final h = w * (overlay.height / overlay.width);
                final r = Rect.fromCenter(
                  center: Offset(cx, y),
                  width: w,
                  height: h,
                ).shift(layer.offset);
                _drawImage(canvas, overlay, r, paint);
              }
              continue; // already drawn twice
            } else {
              final w = faceWidth * layer.scale;
              final h = w * (overlay.height / overlay.width);
              final left = Rect.fromCenter(
                center: faceCenter.translate(-faceWidth * 0.28, faceWidth * 0.05),
                width: w,
                height: h,
              ).shift(layer.offset);
              final right = Rect.fromCenter(
                center: faceCenter.translate(faceWidth * 0.28, faceWidth * 0.05),
                width: w,
                height: h,
              ).shift(layer.offset);
              _drawImage(canvas, overlay, left, paint);
              _drawImage(canvas, overlay, right, paint);
              continue;
            }
        }

        dst = dst.shift(layer.offset);
        _drawImage(canvas, overlay, dst, paint);
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
  bool shouldRepaint(covariant FaceOverlayPainter old) {
    return old.faces != faces ||
        old.lens != lens ||
        old.images.length != images.length ||
        old.isFrontCamera != isFrontCamera;
  }
}
