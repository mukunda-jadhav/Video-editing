import 'dart:typed_data';

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

  Future<img.Image> raster(
    PhotoDocument document, {
    int maxEdge = 1080,
  }) async => img.decodePng(
    await renderPhotoRaster({
      'document': document.toJson(),
      'bytes': Uint8List.fromList(img.encodePng(source())),
      'maxEdge': maxEdge,
    }),
  )!;

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
    final blurred = await raster(PhotoDocument(blur: 4));
    expect(blurred.getPixel(39, 20).r, lessThan(sharp.getPixel(39, 20).r));
    expect(blurred.getPixel(40, 20).r, greaterThan(sharp.getPixel(40, 20).r));
  });

  test('invalid source fails with a useful photo error', () async {
    await expectLater(
      renderPhotoRaster({
        'document': PhotoDocument().toJson(),
        'bytes': Uint8List.fromList([1, 2, 3]),
      }),
      throwsFormatException,
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
      final result = img.decodePng(await exportPhoto(doc, premium: false))!;
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
    final result = img.decodePng(await exportPhoto(doc, premium: true))!;
    final pixel = result.getPixel(32, 32);
    expect([pixel.r, pixel.g, pixel.b, pixel.a], [34, 68, 136, 255]);
  });
}
