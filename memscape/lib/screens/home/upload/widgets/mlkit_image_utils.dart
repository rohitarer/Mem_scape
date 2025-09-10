import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show WriteBuffer, Uint8List;
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

Uint8List concatPlanes(List<Plane> planes) {
  final WriteBuffer wb = WriteBuffer();
  for (final p in planes) {
    wb.putUint8List(p.bytes);
  }
  return wb.done().buffer.asUint8List();
}

InputImageRotation rotationFor(CameraDescription camera) {
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

InputImage buildInputImage(CameraImage image, CameraDescription camDesc) {
  final bytes = concatPlanes(image.planes);
  final metadata = InputImageMetadata(
    size: Size(image.width.toDouble(), image.height.toDouble()),
    rotation: rotationFor(camDesc),
    format: InputImageFormat.yuv420,
    bytesPerRow: image.planes.isNotEmpty ? image.planes.first.bytesPerRow : 0,
  );
  return InputImage.fromBytes(bytes: bytes, metadata: metadata);
}
