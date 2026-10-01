import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/photo_document.dart';

Future<ui.Image> decodePhoto(Uint8List bytes, {int? maxEdge}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 32000000) {
      throw const FormatException('Photos up to 32 megapixels are supported.');
    }
    final scale = maxEdge == null
        ? 1.0
        : math.min(
            1.0,
            maxEdge / math.max(descriptor.width, descriptor.height),
          );
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (descriptor.width * scale).round()),
      targetHeight: math.max(1, (descriptor.height * scale).round()),
    );
    return (await codec.getNextFrame()).image;
  } finally {
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Future<ui.Image> _loadPhoto(String path, int maxEdge) async {
  final file = File(path);
  if (await file.length() > 60 * 1024 * 1024) {
    throw const FormatException('Use a photo smaller than 60 MB.');
  }
  return decodePhoto(await file.readAsBytes(), maxEdge: maxEdge);
}

Set<String> _assetPaths(PhotoDocument document) => {
  if (document.backgroundPath != null) document.backgroundPath!,
  ...document.layers
      .where((layer) => layer.kind == 'image' && layer.path != null)
      .map((layer) => layer.path!),
};

int _assetEdge(int maxEdge, int count) => math.min(
  maxEdge,
  math
      .sqrt((maxEdge <= 1200 ? 4000000 : 12000000) / math.max(1, count))
      .floor(),
);

class PhotoComposition {
  PhotoComposition(this.document, this.foreground, this.assets);
  final PhotoDocument document;
  final ui.Image? foreground;
  final Map<String, ui.Image> assets;
  void dispose() {
    foreground?.dispose();
    for (final image in assets.values) {
      image.dispose();
    }
  }
}

/// Source textures are decoded once per media change, never per edit gesture.
/// Clones share the same native texture; composition replacement is cheap.
class PhotoPreviewCache {
  PhotoPreviewCache({this.maxEdge = 1200});
  final int maxEdge;
  final Map<(String, int), ui.Image> _images = {};
  bool _disposed = false;

  String mediaKey(PhotoDocument document) {
    final paths = _assetPaths(document).toList()..sort();
    return jsonEncode([
      document.imagePath,
      paths,
      _assetEdge(maxEdge, paths.length),
    ]);
  }

  Future<PhotoComposition> prepare(PhotoDocument document) async {
    final paths = _assetPaths(document);
    final edge = _assetEdge(maxEdge, paths.length);
    final needed = <(String, int)>{
      if (document.imagePath != null) (document.imagePath!, maxEdge),
      for (final path in paths) (path, edge),
    };
    for (final key in needed) {
      if (_images.containsKey(key)) continue;
      final image = await _loadPhoto(key.$1, key.$2);
      if (_disposed) {
        image.dispose();
        throw StateError('Photo preview was closed.');
      }
      _images[key] = image;
    }
    for (final key in _images.keys.toList()) {
      if (!needed.contains(key)) _images.remove(key)?.dispose();
    }
    return PhotoComposition(
      document.clone(),
      document.imagePath == null
          ? null
          : _images[(document.imagePath!, maxEdge)]!.clone(),
      {for (final path in paths) path: _images[(path, edge)]!.clone()},
    );
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}

/// Export uses exactly the same painter/effect matrices as the live preview,
/// with higher-resolution native textures and bounded overlay memory.
Future<PhotoComposition> preparePhoto(
  PhotoDocument document, {
  int maxEdge = 1200,
}) async {
  ui.Image? foreground;
  final assets = <String, ui.Image>{};
  try {
    if (document.imagePath != null) {
      final cropScale = math
          .min(
            document.cropRight - document.cropLeft,
            document.cropBottom - document.cropTop,
          )
          .clamp(.05, 1.0);
      foreground = await _loadPhoto(
        document.imagePath!,
        math.min(4096, (maxEdge / cropScale).ceil()),
      );
    }
    final paths = _assetPaths(document);
    final edge = _assetEdge(maxEdge, paths.length);
    for (final path in paths) {
      assets[path] = await _loadPhoto(path, edge);
    }
    return PhotoComposition(document.clone(), foreground, assets);
  } catch (_) {
    foreground?.dispose();
    for (final image in assets.values) {
      image.dispose();
    }
    rethrow;
  }
}

Future<Uint8List> exportPhoto(PhotoDocument document) async {
  final (width, height) = document.exportSize();
  final composition = await preparePhoto(
    document,
    maxEdge: math.max(width, height),
  );
  try {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    PhotoPainter(
      composition: composition,
      document: document,
    ).paint(canvas, Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    ui.Image? image;
    try {
      image = await picture.toImage(width, height);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('PNG encoding failed.');
      return bytes.buffer.asUint8List();
    } finally {
      image?.dispose();
      picture.dispose();
    }
  } finally {
    composition.dispose();
  }
}

/// Crop coordinates refer to the rotated/flipped source, as in saved recipes.
class PhotoImageGeometry {
  PhotoImageGeometry(int width, int height, PhotoDocument document) {
    rotatedSize = document.rotation.isOdd
        ? Size(height.toDouble(), width.toDouble())
        : Size(width.toDouble(), height.toDouble());
    final left = (document.cropLeft * rotatedSize.width).round().clamp(
      0,
      rotatedSize.width.toInt() - 1,
    );
    final top = (document.cropTop * rotatedSize.height).round().clamp(
      0,
      rotatedSize.height.toInt() - 1,
    );
    crop = Rect.fromLTWH(
      left.toDouble(),
      top.toDouble(),
      ((document.cropRight - document.cropLeft) * rotatedSize.width)
          .round()
          .clamp(1, rotatedSize.width.toInt() - left)
          .toDouble(),
      ((document.cropBottom - document.cropTop) * rotatedSize.height)
          .round()
          .clamp(1, rotatedSize.height.toInt() - top)
          .toDouble(),
    );
  }
  late final Size rotatedSize;
  late final Rect crop;
}

const _identity = <double>[
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

List<double> _multiply(List<double> after, List<double> before) {
  final result = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 4; col++) {
      for (var i = 0; i < 4; i++) {
        result[row * 5 + col] += after[row * 5 + i] * before[i * 5 + col];
      }
    }
    result[row * 5 + 4] = after[row * 5 + 4];
    for (var i = 0; i < 4; i++) {
      result[row * 5 + 4] += after[row * 5 + i] * before[i * 5 + 4];
    }
  }
  return result;
}

List<double> _adjustMatrix(
  double brightness,
  double contrast,
  double saturation,
) {
  const luma = [.2126, .7152, .0722];
  final matrix = List<double>.from(_identity);
  for (var row = 0; row < 3; row++) {
    for (var col = 0; col < 3; col++) {
      matrix[row * 5 + col] =
          brightness *
          contrast *
          ((1 - saturation) * luma[col] + (row == col ? saturation : 0));
    }
    matrix[row * 5 + 4] = brightness * 127.5 * (1 - contrast);
  }
  return matrix;
}

/// One affine color transform per frame. Alpha is preserved through all looks.
List<double> photoColorMatrix(PhotoDocument document) {
  final base = _adjustMatrix(
    document.brightness * math.pow(2, document.exposure),
    document.contrast,
    document.saturation,
  );
  final List<double> look;
  switch (document.filter) {
    case 'Noir':
      look = _adjustMatrix(1, 1, 0);
    case 'Fade':
      look = _adjustMatrix(1.08, .8, .75);
    case 'Vivid':
      look = _adjustMatrix(1, 1.15, 1.35);
    case 'Warm':
      look = List<double>.from(_identity)
        ..[0] = 1.12
        ..[12] = .88;
    case 'Cool':
      look = List<double>.from(_identity)
        ..[0] = .9
        ..[12] = 1.12;
    case 'Sepia':
      look = [
        .393,
        .769,
        .189,
        0,
        0,
        .349,
        .686,
        .168,
        0,
        0,
        .272,
        .534,
        .131,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ];
    default:
      look = _identity;
  }
  final amount = document.filterIntensity.clamp(0.0, 1.0);
  final blended = List<double>.generate(
    20,
    (i) => _identity[i] + (look[i] - _identity[i]) * amount,
  );
  return _multiply(blended, base);
}

const photoBaseSelectionId = '__base_photo__';

Rect photoLayerRect(PhotoLayer layer, Size size) => Rect.fromLTWH(
  layer.x * size.width,
  layer.y * size.height,
  layer.width * size.width,
  layer.height * size.height,
);

/// The visible fitted image is the same in hit testing, preview and export.
Rect photoImageRect(PhotoDocument document, ui.Image? image, Size size) {
  if (image == null) return Offset.zero & size;
  final geometry = PhotoImageGeometry(image.width, image.height, document);
  final fitted = applyBoxFit(
    document.imageFit == 'contain' ? BoxFit.contain : BoxFit.cover,
    geometry.crop.size,
    size,
  );
  return Alignment.center.inscribe(fitted.destination, Offset.zero & size);
}

Offset photoRotatePoint(Offset point, Offset center, double angle) {
  final delta = point - center;
  return center +
      Offset(
        delta.dx * math.cos(angle) - delta.dy * math.sin(angle),
        delta.dx * math.sin(angle) + delta.dy * math.cos(angle),
      );
}

bool photoLayerContains(
  PhotoLayer layer,
  Size size,
  Offset point, {
  double tolerance = 12,
}) {
  final rect = photoLayerRect(layer, size);
  return rect
      .inflate(tolerance)
      .contains(photoRotatePoint(point, rect.center, -layer.rotation));
}

class PhotoPainter extends CustomPainter {
  PhotoPainter({
    required this.composition,
    required this.document,
    this.selectedId,
    this.showGrid = false,
    this.snapHorizontal = false,
    this.snapVertical = false,
  });
  final PhotoComposition? composition;
  final PhotoDocument document;
  final String? selectedId;
  final bool showGrid;
  final bool snapHorizontal;
  final bool snapVertical;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(document.backgroundColor),
    );
    final background = composition?.assets[document.backgroundPath];
    if (background != null) _drawImage(canvas, background, Offset.zero & size);
    if (composition?.foreground != null) {
      _drawForeground(canvas, composition!.foreground!, size);
    }
    for (final layer in document.layers) {
      final rect = photoLayerRect(layer, size);
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(layer.rotation);
      canvas.translate(-rect.center.dx, -rect.center.dy);
      final baseColor = Color(layer.color);
      final color = baseColor.withValues(alpha: baseColor.a * layer.opacity);
      final paint = Paint()..color = color;
      switch (layer.kind) {
        case 'text':
          final text = TextPainter(
            text: TextSpan(
              text: layer.text,
              style: TextStyle(
                color: color,
                fontSize: layer.fontSize * size.width,
                fontFamily: layer.fontFamily,
                fontWeight: layer.bold ? FontWeight.w700 : FontWeight.w400,
                height: 1.05,
              ),
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.center,
          );
          text.layout(maxWidth: rect.width);
          canvas.save();
          canvas.clipRect(rect);
          text.paint(canvas, Offset(rect.left, rect.top));
          canvas.restore();
          text.dispose();
        case 'circle':
          canvas.drawOval(rect, paint);
        case 'star':
          final path = Path();
          for (var i = 0; i < 10; i++) {
            final a = -math.pi / 2 + i * math.pi / 5;
            final r = i.isEven ? .5 : .22;
            final point = Offset(
              rect.center.dx + math.cos(a) * rect.width * r,
              rect.center.dy + math.sin(a) * rect.height * r,
            );
            if (i == 0) {
              path.moveTo(point.dx, point.dy);
            } else {
              path.lineTo(point.dx, point.dy);
            }
          }
          canvas.drawPath(path..close(), paint);
        case 'heart':
          final path = Path()
            ..moveTo(rect.center.dx, rect.bottom)
            ..cubicTo(
              rect.left - rect.width * .35,
              rect.top + rect.height * .35,
              rect.left + rect.width * .2,
              rect.top - rect.height * .3,
              rect.center.dx,
              rect.top + rect.height * .2,
            )
            ..cubicTo(
              rect.right - rect.width * .2,
              rect.top - rect.height * .3,
              rect.right + rect.width * .35,
              rect.top + rect.height * .35,
              rect.center.dx,
              rect.bottom,
            );
          canvas.drawPath(path, paint);
        case 'image':
          final image = composition?.assets[layer.path];
          if (image != null) {
            _drawImage(canvas, image, rect, opacity: layer.opacity);
          }
        default:
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, Radius.circular(size.width * .015)),
            paint,
          );
      }
      if (selectedId == layer.id) {
        _selection(canvas, rect);
      }
      canvas.restore();
    }
    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: .45)
        ..strokeWidth = 1;
      for (var i = 1; i < 3; i++) {
        canvas.drawLine(
          Offset(size.width * i / 3, 0),
          Offset(size.width * i / 3, size.height),
          grid,
        );
        canvas.drawLine(
          Offset(0, size.height * i / 3),
          Offset(size.width, size.height * i / 3),
          grid,
        );
      }
    }
    if (snapVertical || snapHorizontal) {
      final paint = Paint()
        ..color = const Color(0xff40e0d0)
        ..strokeWidth = 1;
      if (snapVertical) {
        canvas.drawLine(
          Offset(size.width / 2, 0),
          Offset(size.width / 2, size.height),
          paint,
        );
      }
      if (snapHorizontal) {
        canvas.drawLine(
          Offset(0, size.height / 2),
          Offset(size.width, size.height / 2),
          paint,
        );
      }
    }
    canvas.restore();
  }

  void _selection(Canvas canvas, Rect rect) {
    final border = Paint()
      ..color = const Color(0xff40e0d0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(rect, border);
    final handle = Paint()..color = Colors.white;
    for (final point in [rect.topLeft, rect.topRight, rect.bottomLeft]) {
      canvas.drawCircle(point, 3, handle);
    }
    canvas.drawCircle(
      rect.bottomRight,
      9,
      Paint()..color = const Color(0xff40e0d0),
    );
    canvas.drawCircle(
      rect.bottomRight,
      9,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // Geometry and effects are applied to the cached texture in the raster
  // pipeline. Moving a slider never decodes, encodes, or copies source pixels.
  void _drawForeground(Canvas canvas, ui.Image image, Size size) {
    final geometry = PhotoImageGeometry(image.width, image.height, document);
    final fit = document.imageFit == 'contain' ? BoxFit.contain : BoxFit.cover;
    final fitted = applyBoxFit(fit, geometry.crop.size, size);
    final visible = Alignment.center.inscribe(fitted.source, geometry.crop);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.save();
    final center = Offset(size.width / 2, size.height / 2);
    canvas.translate(
      center.dx + document.imageX * size.width,
      center.dy + document.imageY * size.height,
    );
    canvas.rotate(document.imageRotation);
    canvas.scale(document.imageScale);
    canvas.translate(-center.dx, -center.dy);
    canvas.save();
    canvas.clipRect(destination);
    canvas.translate(destination.left, destination.top);
    canvas.scale(
      destination.width / visible.width,
      destination.height / visible.height,
    );
    canvas.translate(-visible.left, -visible.top);
    if (document.flipHorizontal) {
      canvas.translate(geometry.rotatedSize.width, 0);
      canvas.scale(-1, 1);
    }
    switch (document.rotation % 4) {
      case 1:
        canvas.translate(image.height.toDouble(), 0);
        canvas.rotate(math.pi / 2);
      case 2:
        canvas.translate(image.width.toDouble(), image.height.toDouble());
        canvas.rotate(math.pi);
      case 3:
        canvas.translate(0, image.width.toDouble());
        canvas.rotate(-math.pi / 2);
    }
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = ColorFilter.matrix(photoColorMatrix(document));
    if (document.blur > 0) {
      final sigma = document.blur * math.max(image.width, image.height) / 1080;
      canvas.saveLayer(
        null,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      );
    }
    canvas.drawImage(image, Offset.zero, paint);
    if (document.blur > 0) canvas.restore();
    canvas.restore();
    if (selectedId == photoBaseSelectionId) _selection(canvas, destination);
    canvas.restore();
  }

  void _drawImage(
    Canvas canvas,
    ui.Image image,
    Rect rect, {
    double opacity = 1,
    BoxFit fit = BoxFit.cover,
  }) {
    final source = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(fit, source, rect.size);
    final crop = Alignment.center.inscribe(fitted.source, Offset.zero & source);
    final destination = Alignment.center.inscribe(fitted.destination, rect);
    canvas.drawImageRect(
      image,
      crop,
      destination,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withValues(alpha: opacity),
    );
  }

  @override
  bool shouldRepaint(covariant PhotoPainter oldDelegate) => true;
}
