import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/photo_editor/data/photo_renderer.dart';
import 'package:framelab/features/photo_editor/domain/photo_document.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  img.Image source() {
    final image = img.Image(width: 80, height: 40, numChannels: 4);
    for (final pixel in image) {
      pixel.setRgba(pixel.x < 40 ? 180 : 20, 80, 30, 200);
    }
    return image;
  }

  Future<img.Image> raster(PhotoDocument document, {int maxEdge = 1080}) async {
    final texture = await decodePhoto(
      Uint8List.fromList(img.encodePng(source())),
      maxEdge: maxEdge,
    );
    final geometry = PhotoImageGeometry(
      texture.width,
      texture.height,
      document,
    );
    final width = geometry.crop.width.toInt();
    final height = geometry.crop.height.toInt();
    document.backgroundColor = 0;
    final composition = PhotoComposition(document, texture, {});
    final recorder = ui.PictureRecorder();
    PhotoPainter(
      composition: composition,
      document: document,
    ).paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return img.decodePng(data!.buffer.asUint8List())!;
    } finally {
      image.dispose();
      picture.dispose();
      composition.dispose();
    }
  }

  test(
    'crop removes the selected source edge and rotate swaps dimensions',
    () async {
      final result = await raster(PhotoDocument(cropLeft: .5));
      expect((result.width, result.height), (40, 40));
      expect(result.getPixel(10, 10).r, 20);
      final rotated = await raster(PhotoDocument(rotation: 1));
      expect((rotated.width, rotated.height), (40, 80));
    },
  );

  test('flip changes the source composition without changing alpha', () async {
    final result = await raster(PhotoDocument(flipHorizontal: true));
    expect(result.getPixel(0, 0).r, 20);
    expect(result.getPixel(79, 0).r, 180);
    expect(result.getPixel(0, 0).a, 200);
  });

  test(
    'preview decoder keeps the requested pixel bound and aspect ratio',
    () async {
      final result = await raster(PhotoDocument(), maxEdge: 20);
      expect((result.width, result.height), (20, 10));
    },
  );

  test(
    'brightness exposure saturation and contrast change actual pixels',
    () async {
      final original = await raster(PhotoDocument());
      final bright = await raster(PhotoDocument(brightness: 1.2));
      final exposure = await raster(PhotoDocument(exposure: 1));
      final gray = await raster(PhotoDocument(saturation: 0));
      final contrast = await raster(PhotoDocument(contrast: 1.5));
      expect(bright.getPixel(0, 0).r, greaterThan(original.getPixel(0, 0).r));
      expect(exposure.getPixel(0, 0).r, greaterThan(original.getPixel(0, 0).r));
      expect(gray.getPixel(0, 0).r, gray.getPixel(0, 0).g);
      expect(contrast.getPixel(0, 0).r, isNot(original.getPixel(0, 0).r));
    },
  );

  test(
    'all filter looks produce different pixels while preserving alpha',
    () async {
      final original = (await raster(PhotoDocument())).getPixel(0, 0);
      for (final filter in ['Noir', 'Fade', 'Vivid', 'Warm', 'Cool', 'Sepia']) {
        final pixel = (await raster(
          PhotoDocument(filter: filter),
        )).getPixel(0, 0);
        expect(
          [pixel.r, pixel.g, pixel.b],
          isNot([original.r, original.g, original.b]),
          reason: filter,
        );
        expect(pixel.a, 200, reason: filter);
      }
    },
  );

  test('blur softens a real edge', () async {
    final sharp = await raster(PhotoDocument());
    final blurred = await raster(PhotoDocument(blur: 30));
    expect(blurred.getPixel(39, 20).r, lessThan(sharp.getPixel(39, 20).r));
    expect(blurred.getPixel(40, 20).r, greaterThan(sharp.getPixel(40, 20).r));
  });

  test('invalid source fails with a useful photo error', () async {
    await expectLater(
      decodePhoto(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'PNG export uses canvas dimensions and retains layer transparency',
    () async {
      final doc = PhotoDocument(
        width: 64,
        height: 80,
        backgroundColor: 0,
        layers: [
          PhotoLayer(
            id: 'shape',
            kind: 'rect',
            x: .25,
            y: .25,
            width: .5,
            height: .5,
            color: 0x80ff0000,
            opacity: .5,
          ),
        ],
      );
      final result = img.decodePng(await exportPhoto(doc))!;
      expect((result.width, result.height), (64, 80));
      expect(result.getPixel(0, 0).a, 0);
      expect(result.getPixel(32, 40).a, closeTo(64, 1));
    },
  );

  test('a transparent layer stays transparent over the background', () async {
    final doc = PhotoDocument(
      width: 64,
      height: 64,
      backgroundColor: 0xff224488,
      layers: [
        PhotoLayer(
          id: 'clear',
          kind: 'rect',
          x: 0,
          y: 0,
          width: 1,
          height: 1,
          color: 0,
          opacity: 1,
        ),
      ],
    );
    final result = img.decodePng(await exportPhoto(doc))!;
    final pixel = result.getPixel(32, 32);
    expect([pixel.r, pixel.g, pixel.b, pixel.a], [34, 68, 136, 255]);
  });
  test('cached source survives rapid edits without reopening media', () async {
    final directory = await Directory.systemTemp.createTemp('photo-live-test-');
    final file = File('${directory.path}/source.png');
    await file.writeAsBytes(img.encodePng(source()));
    final document = PhotoDocument(imagePath: file.path);
    final cache = PhotoPreviewCache();
    final history = PhotoHistory(document);
    final initial = await cache.prepare(document);
    final key = cache.mediaKey(document);
    await file.delete(); // A second decode would now fail.
    try {
      for (var i = 1; i <= 30; i++) {
        document.brightness = 1 + i / 30;
        document.cropLeft = i / 100;
        document.width = 1920;
        document.height = 1080;
        expect(cache.mediaKey(document), key);
        final next = await cache.prepare(document);
        expect(next.foreground!.isCloneOf(initial.foreground!), isTrue);
        next.dispose();
      }
      history.commit(document);
      final restored = history.undo();
      expect(restored.brightness, 1);
      expect(restored.cropLeft, 0);
      final undone = await cache.prepare(restored);
      expect(undone.foreground!.isCloneOf(initial.foreground!), isTrue);
      undone.dispose();
    } finally {
      initial.dispose();
      cache.dispose();
      await directory.delete(recursive: true);
    }
  });

  test(
    'live preview and PNG export use identical color and geometry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photo-parity-test-',
      );
      final file = File('${directory.path}/source.png');
      await file.writeAsBytes(img.encodePng(source()));
      final document = PhotoDocument(
        imagePath: file.path,
        width: 40,
        height: 80,
        rotation: 1,
        flipHorizontal: true,
        brightness: 1.18,
        contrast: 1.12,
        saturation: .8,
        exposure: .25,
        filter: 'Warm',
        cropLeft: .2,
        cropRight: .9,
        cropTop: .1,
        cropBottom: .85,
        backgroundColor: 0,
      );
      final cache = PhotoPreviewCache();
      final composition = await cache.prepare(document);
      final recorder = ui.PictureRecorder();
      PhotoPainter(
        composition: composition,
        document: document,
      ).paint(Canvas(recorder), const Size(40, 80));
      final picture = recorder.endRecording();
      final image = await picture.toImage(40, 80);
      try {
        final preview = img.decodePng(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        )!;
        final exported = img.decodePng(await exportPhoto(document))!;
        for (var y = 0; y < preview.height; y++) {
          for (var x = 0; x < preview.width; x++) {
            final before = preview.getPixel(x, y);
            final after = exported.getPixel(x, y);
            expect(
              [after.r, after.g, after.b, after.a],
              [before.r, before.g, before.b, before.a],
            );
          }
        }
      } finally {
        image.dispose();
        picture.dispose();
        composition.dispose();
        cache.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
