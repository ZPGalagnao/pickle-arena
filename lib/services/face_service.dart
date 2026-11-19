// Player face capture: camera/gallery -> ML Kit face detection -> square crop.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class FacePick {
  final Uint8List bytes; // upright JPEG
  final int width, height;
  final Rect crop; // suggested square crop in image pixels
  final int facesFound;
  const FacePick(this.bytes, this.width, this.height, this.crop, this.facesFound);
}

class FaceService {
  static final _picker = ImagePicker();

  static Future<FacePick?> pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 92,
      preferredCameraDevice: CameraDevice.front,
    );
    if (x == null) return null;
    final raw = await x.readAsBytes();
    final norm = await compute(_normalize, raw);
    if (norm == null) return null;
    final (bytes, w, h) = norm;

    Rect? box;
    var count = 0;
    try {
      final tmp = File('${File(x.path).parent.path}${Platform.pathSeparator}pickle_face_norm.jpg');
      await tmp.writeAsBytes(bytes, flush: true);
      final detector = FaceDetector(
        options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate, minFaceSize: 0.08),
      );
      final faces = await detector.processImage(InputImage.fromFilePath(tmp.path));
      await detector.close();
      count = faces.length;
      if (faces.isNotEmpty) {
        faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
            .compareTo(a.boundingBox.width * a.boundingBox.height));
        box = faces.first.boundingBox;
      }
      try {
        await tmp.delete();
      } catch (_) {}
    } catch (_) {
      // ML Kit unavailable (e.g. emulator without Play services) - manual crop
    }
    return FacePick(bytes, w, h, suggestCrop(box, w, h), count);
  }

  /// Square around the detected face, enlarged to include hair and chin.
  static Rect suggestCrop(Rect? face, int w, int h) {
    double cx, cy, size;
    if (face != null) {
      cx = face.center.dx;
      cy = face.center.dy - face.height * 0.08;
      size = math.max(face.width, face.height) * 1.55;
    } else {
      cx = w / 2;
      cy = h * 0.42;
      size = math.min(w, h) * 0.75;
    }
    return clampCrop(cx, cy, size, w, h);
  }

  static Rect clampCrop(double cx, double cy, double size, int w, int h) {
    size = size.clamp(48.0, math.min(w, h).toDouble());
    final half = size / 2;
    cx = cx.clamp(half, w - half);
    cy = cy.clamp(half, h - half);
    return Rect.fromCenter(center: Offset(cx, cy), width: size, height: size);
  }

  /// Final 256x256 JPEG of the face (~15 KB, small enough to send over Wi-Fi).
  static Future<Uint8List> cropToFace(Uint8List bytes, Rect crop) =>
      compute(_crop, (bytes, crop.left, crop.top, crop.width));
}

(Uint8List, int, int)? _normalize(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null;
  var im = img.bakeOrientation(decoded);
  final m = math.max(im.width, im.height);
  if (m > 1000) {
    im = im.width >= im.height ? img.copyResize(im, width: 1000) : img.copyResize(im, height: 1000);
  }
  return (Uint8List.fromList(img.encodeJpg(im, quality: 90)), im.width, im.height);
}

Uint8List _crop((Uint8List, double, double, double) a) {
  final (bytes, left, top, size) = a;
  final im = img.decodeImage(bytes)!;
  final int s = size.round().clamp(1, math.min(im.width, im.height)).toInt();
  final int x = left.round().clamp(0, im.width - s).toInt();
  final int y = top.round().clamp(0, im.height - s).toInt();
  final c = img.copyCrop(im, x: x, y: y, width: s, height: s);
  final r = img.copyResize(c, width: 256, height: 256, interpolation: img.Interpolation.cubic);
  return Uint8List.fromList(img.encodeJpg(r, quality: 85));
}
