import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../domain/background_brush.dart';
import 'photo_renderer.dart';

const backgroundRefineMaxEdge = 4096;
const backgroundRefineMaxPixels = 8000000;

Size backgroundRefineOutputSize(int width, int height) {
  final scale = math.min(
    1.0,
    math.min(
      backgroundRefineMaxEdge / math.max(width, height),
      math.sqrt(backgroundRefineMaxPixels / (width * height)),
    ),
  );
  return Size(
    math.max(1, (width * scale).floor()).toDouble(),
    math.max(1, (height * scale).floor()).toDouble(),
  );
}

Rect backgroundRefineImageRect(Size viewport, Size image) {
  final inner = Rect.fromLTWH(
    12,
    12,
    math.max(1, viewport.width - 24),
    math.max(1, viewport.height - 24),
  );
  final fitted = applyBoxFit(BoxFit.contain, image, inner.size).destination;
  return Alignment.center.inscribe(fitted, inner);
}

Offset? backgroundRefinePoint(Offset localPoint, Rect imageRect) {
  if (!imageRect.contains(localPoint)) return null;
  return Offset(
    (localPoint.dx - imageRect.left) / imageRect.width,
    (localPoint.dy - imageRect.top) / imageRect.height,
  );
}

class BackgroundRefineSource {
  BackgroundRefineSource({
    required this.original,
    this.initial,
    required this.sourceWidth,
    required this.sourceHeight,
  });
  final ui.Image original;
  final ui.Image? initial;
  final int sourceWidth;
  final int sourceHeight;
  Size get outputSize => backgroundRefineOutputSize(sourceWidth, sourceHeight);
  bool get downsampled =>
      outputSize.width < sourceWidth || outputSize.height < sourceHeight;

  static Future<BackgroundRefineSource> load(
    String originalPath, {
    String? initialMaskPath,
  }) async {
    final bytes = await _read(originalPath);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    int width;
    int height;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      width = descriptor.width;
      height = descriptor.height;
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
    final original = await decodePhoto(bytes, maxEdge: 1400);
    ui.Image? initial;
    try {
      if (initialMaskPath != null && initialMaskPath != originalPath) {
        initial = await decodePhoto(
          await _read(initialMaskPath),
          maxEdge: 1400,
        );
        if ((initial.width / initial.height - width / height).abs() > .02) {
          throw const FormatException(
            'The cutout must match the original photo.',
          );
        }
      }
      return BackgroundRefineSource(
        original: original,
        initial: initial,
        sourceWidth: width,
        sourceHeight: height,
      );
    } catch (_) {
      original.dispose();
      initial?.dispose();
      rethrow;
    }
  }

  void dispose() {
    original.dispose();
    initial?.dispose();
  }
}

Future<Uint8List> _read(String path) async {
  final file = File(path);
  if (await file.length() > 60 * 1024 * 1024) {
    throw const FormatException('Use a photo smaller than 60 MB.');
  }
  return file.readAsBytes();
}

/// Painting and preview share the same GPU operations. Neither a pointer move
/// nor an undo encodes media or sends work to an isolate.
class BackgroundRefinePainter extends CustomPainter {
  BackgroundRefinePainter({
    required this.original,
    this.initial,
    required this.strokes,
    this.imageRect,
    this.checkerboard = true,
    this.cursor,
    this.cursorRadius = 0,
  });
  final ui.Image original;
  final ui.Image? initial;
  final List<BackgroundBrushStroke> strokes;
  final Rect? imageRect;
  final bool checkerboard;
  final Offset? cursor;
  final double cursorRadius;

  @override
  void paint(Canvas canvas, Size size) {
    if (checkerboard) {
      const step = 16.0;
      for (double y = 0; y < size.height; y += step) {
        for (double x = 0; x < size.width; x += step) {
          canvas.drawRect(
            Rect.fromLTWH(x, y, step, step),
            Paint()
              ..color = ((x / step).floor() + (y / step).floor()).isEven
                  ? const Color(0xff242429)
                  : const Color(0xff303037),
          );
        }
      }
    }
    final target = imageRect ?? Offset.zero & size;
    canvas.save();
    canvas.clipRect(target);
    canvas.saveLayer(target, Paint());
    _drawImage(canvas, initial ?? original, target, Paint());
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final radius = stroke.radius * math.min(target.width, target.height);
      final points = stroke.points
          .map(
            (point) => Offset(
              target.left + point.dx * target.width,
              target.top + point.dy * target.height,
            ),
          )
          .toList();
      if (stroke.mode == BackgroundBrushMode.erase) {
        final paint = Paint()
          ..blendMode = BlendMode.clear
          ..style = PaintingStyle.stroke
          ..strokeWidth = radius * 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (points.length == 1) {
          canvas.drawCircle(
            points.single,
            radius,
            Paint()..blendMode = BlendMode.clear,
          );
        } else {
          final path = Path()..moveTo(points.first.dx, points.first.dy);
          for (final point in points.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
          canvas.drawPath(path, paint);
        }
      } else {
        // Replace the clipped region with the original, rather than compositing
        // on top, preserving the original alpha even on semi-transparent edges.
        canvas.save();
        canvas.clipPath(_brushRegion(points, radius));
        _drawImage(
          canvas,
          original,
          target,
          Paint()..blendMode = BlendMode.src,
        );
        canvas.restore();
      }
    }
    canvas.restore();
    canvas.restore();
    if (cursor != null && cursorRadius > 0) {
      canvas.drawCircle(
        cursor!,
        cursorRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
      canvas.drawCircle(
        cursor!,
        cursorRadius + 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.black54,
      );
    }
  }

  static void _drawImage(
    Canvas canvas,
    ui.Image image,
    Rect target,
    Paint paint,
  ) {
    paint.filterQuality = FilterQuality.low;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      target,
      paint,
    );
  }

  static Path _brushRegion(List<Offset> points, double radius) {
    final path = Path();
    for (final point in points) {
      path.addOval(Rect.fromCircle(center: point, radius: radius));
    }
    for (var i = 1; i < points.length; i++) {
      final delta = points[i] - points[i - 1];
      if (delta.distance == 0) continue;
      final normal = Offset(-delta.dy, delta.dx) * (radius / delta.distance);
      path.addPolygon([
        points[i - 1] - normal,
        points[i] - normal,
        points[i] + normal,
        points[i - 1] + normal,
      ], true);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant BackgroundRefinePainter oldDelegate) => true;
}

Future<Uint8List> renderRefinedBackground({
  required ui.Image original,
  ui.Image? initial,
  required List<BackgroundBrushStroke> strokes,
  required int width,
  required int height,
}) async {
  final recorder = ui.PictureRecorder();
  BackgroundRefinePainter(
    original: original,
    initial: initial,
    strokes: strokes,
    checkerboard: false,
  ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  ui.Image? output;
  try {
    output = await picture.toImage(width, height);
    final data = await output.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) throw StateError('Unable to read the refined photo.');
    return await compute(_encodeRgba, (
      width,
      height,
      data.buffer.asUint8List(),
    ));
  } finally {
    output?.dispose();
    picture.dispose();
  }
}

Uint8List _encodeRgba((int, int, Uint8List) payload) {
  final image = img.Image.fromBytes(
    width: payload.$1,
    height: payload.$2,
    bytes: payload.$3.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodePng(image));
}

Future<String> saveRefinedBackground({
  required String originalPath,
  String? initialMaskPath,
  required Size outputSize,
  required List<BackgroundBrushStroke> strokes,
}) async {
  // Native codec scales before returning a decoded frame; large images are
  // never expanded into a full-size Dart pixel buffer.
  final original = await decodePhoto(
    await _read(originalPath),
    maxEdge: math.max(outputSize.width, outputSize.height).round(),
  );
  ui.Image? initial;
  try {
    if (initialMaskPath != null && initialMaskPath != originalPath) {
      initial = await decodePhoto(
        await _read(initialMaskPath),
        maxEdge: math.max(outputSize.width, outputSize.height).round(),
      );
    }
    final png = await renderRefinedBackground(
      original: original,
      initial: initial,
      strokes: strokes,
      width: outputSize.width.toInt(),
      height: outputSize.height.toInt(),
    );
    final path = p.join(
      File(originalPath).parent.path,
      'refined_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await File(path).writeAsBytes(png, flush: true);
    return path;
  } finally {
    original.dispose();
    initial?.dispose();
  }
}
