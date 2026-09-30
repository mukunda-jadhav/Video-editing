import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../domain/photo_document.dart';

/// CPU filters and codecs run in a worker. Preview jobs are serialized by the UI.
Future<Uint8List> renderPhotoRaster(Map<String, dynamic> request) async {
  final document = PhotoDocument.fromJson(
    Map<String, dynamic>.from(request['document'] as Map),
  );
  final edge = (request['maxEdge'] as int? ?? 1200).clamp(1, 4096);
  final suppliedBytes = request['bytes'] as Uint8List?;
  final bytes = suppliedBytes ?? await _readPhoto(document.imagePath!);
  if (bytes.length > 60 * 1024 * 1024) {
    throw const FormatException(
      'This photo is larger than 60 MB. Resize it before importing.',
    );
  }
  img.Decoder? decoder;
  try {
    decoder = img.findDecoderForData(bytes);
  } on Object {
    throw const FormatException('Use a JPEG, PNG, WebP, GIF or BMP photo.');
  }
  final info = decoder?.startDecode(bytes);
  if (info == null) {
    throw const FormatException('Use a JPEG, PNG, WebP, GIF or BMP photo.');
  }
  if (info.width * info.height > 32000000) {
    throw const FormatException(
      'Photos up to 32 megapixels are supported on this device.',
    );
  }
  var result = decoder!.decodeFrame(0);
  if (result == null) {
    throw const FormatException('The selected photo could not be decoded.');
  }
  result = img.bakeOrientation(result);
  if (document.rotation != 0) {
    result = img.copyRotate(result, angle: document.rotation * 90);
  }
  if (document.flipHorizontal) result = img.flipHorizontal(result);
  final left = (document.cropLeft * result.width).round().clamp(
    0,
    result.width - 1,
  );
  final top = (document.cropTop * result.height).round().clamp(
    0,
    result.height - 1,
  );
  result = img.copyCrop(
    result,
    x: left,
    y: top,
    width: ((document.cropRight - document.cropLeft) * result.width)
        .round()
        .clamp(1, result.width - left),
    height: ((document.cropBottom - document.cropTop) * result.height)
        .round()
        .clamp(1, result.height - top),
  );
  final ratio = math.min(1.0, edge / math.max(result.width, result.height));
  if (ratio < 1) {
    result = img.copyResize(
      result,
      width: math.max(1, (result.width * ratio).round()),
      height: math.max(1, (result.height * ratio).round()),
      interpolation: img.Interpolation.linear,
    );
  }
  result = img.adjustColor(
    result,
    brightness: document.brightness * math.pow(2, document.exposure),
    contrast: document.contrast,
    saturation: document.saturation,
  );
  switch (document.filter) {
    case 'Noir':
      result = img.grayscale(result);
    case 'Fade':
      result = img.adjustColor(
        result,
        contrast: .8,
        saturation: .75,
        brightness: 1.08,
      );
    case 'Vivid':
      result = img.adjustColor(result, contrast: 1.15, saturation: 1.35);
    case 'Warm':
      for (final pixel in result) {
        pixel.r = math.min(255, pixel.r * 1.12);
        pixel.b *= .88;
      }
    case 'Cool':
      for (final pixel in result) {
        pixel.b = math.min(255, pixel.b * 1.12);
        pixel.r *= .9;
      }
    case 'Sepia':
      result = img.sepia(result);
  }
  if (document.blur > 0) {
    result = img.gaussianBlur(
      result,
      radius: math.max(1, (document.blur * edge / 1080).round()),
    );
  }
  return Uint8List.fromList(img.encodePng(result));
}

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

Future<Uint8List> _readPhoto(String path) async {
  final file = File(path);
  if (await file.length() > 60 * 1024 * 1024) {
    throw const FormatException('Use a photo smaller than 60 MB.');
  }
  return file.readAsBytes();
}

/// Native codec downsamples before the worker allocates its editable pixel map.
Future<Uint8List> _boundedSource(PhotoDocument document, int maxEdge) async {
  final cropScale = math
      .min(
        document.cropRight - document.cropLeft,
        document.cropBottom - document.cropTop,
      )
      .clamp(.05, 1.0);
  final edge = math.min(4096, (maxEdge / cropScale).ceil());
  final image = await decodePhoto(
    await _readPhoto(document.imagePath!),
    maxEdge: edge,
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Photo decoding failed.');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

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

Future<PhotoComposition> preparePhoto(
  PhotoDocument document, {
  int maxEdge = 1200,
}) async {
  ui.Image? foreground;
  final assets = <String, ui.Image>{};
  try {
    if (document.imagePath != null) {
      final bytes = await compute(renderPhotoRaster, {
        'document': document.toJson(),
        'maxEdge': maxEdge,
        'bytes': await _boundedSource(document, maxEdge),
      });
      foreground = await decodePhoto(bytes);
    }
    final paths = {
      if (document.backgroundPath != null) document.backgroundPath!,
      ...document.layers
          .where((layer) => layer.kind == 'image' && layer.path != null)
          .map((layer) => layer.path!),
    };
    // Total decoded overlays stay below twelve million pixels during export.
    final assetEdge = math.min(
      maxEdge,
      math
          .sqrt(
            (maxEdge <= 1200 ? 4000000 : 12000000) / math.max(1, paths.length),
          )
          .floor(),
    );
    for (final path in paths) {
      assets[path] = await decodePhoto(
        await _readPhoto(path),
        maxEdge: assetEdge,
      );
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

Future<Uint8List> exportPhoto(
  PhotoDocument document, {
  required bool premium,
}) async {
  final (width, height) = document.exportSize(premium: premium);
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

class PhotoPainter extends CustomPainter {
  PhotoPainter({
    required this.composition,
    required this.document,
    this.selectedId,
    this.showGrid = false,
  });
  final PhotoComposition? composition;
  final PhotoDocument document;
  final String? selectedId;
  final bool showGrid;

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
      _drawImage(
        canvas,
        composition!.foreground!,
        Offset.zero & size,
        fit: document.imageFit == 'contain' ? BoxFit.contain : BoxFit.cover,
      );
    }
    for (final layer in document.layers) {
      final rect = Rect.fromLTWH(
        layer.x * size.width,
        layer.y * size.height,
        layer.width * size.width,
        layer.height * size.height,
      );
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
        canvas.drawRect(
          rect.inflate(3),
          Paint()
            ..color = const Color(0xffb4a0ff)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
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
