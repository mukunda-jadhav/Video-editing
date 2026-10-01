import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/media/native_media_service.dart';
import 'package:framelab/features/video_editor/data/ffmpeg_video_renderer.dart';
import 'package:framelab/features/video_editor/data/video_cutout_service.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> ffmpeg(List<String> args) async {
    final s = await FFmpegKit.executeWithArguments(args);
    expect(
      ReturnCode.isSuccess(await s.getReturnCode()),
      true,
      reason: await s.getAllLogsAsString(),
    );
  }

  Future<img.Image> frame(String path, String output) async {
    await ffmpeg(['-y', '-ss', '0.1', '-i', path, '-frames:v', '1', output]);
    return img.decodePng(await File(output).readAsBytes())!;
  }

  testWidgets(
    'manual video cutout preserves audio and maps brush to source frames',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Video cutout verification')),
        ),
      );
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        final dir = await Directory(
          '${support.path}/canvas_cutout_checks',
        ).create(recursive: true);
        final source = '${dir.path}/source.mp4';
        await ffmpeg([
          '-y',
          '-f',
          'lavfi',
          '-i',
          'color=c=red:s=320x180:r=30',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:sample_rate=48000',
          '-t',
          '1.2',
          '-c:v',
          'mpeg4',
          '-q:v',
          '3',
          '-c:a',
          'aac',
          source,
        ]);
        final renderer = FfmpegVideoRenderer(preferredEncoder: 'mpeg4');
        final original = await renderer.probe(source);
        final clip = original.copyWith(start: .15, end: 1.1);
        final sourceBytes = await File(source).readAsBytes();
        final progress = <double>[];
        final service = VideoCutoutService();
        try {
          final output = await service.process(
            clip,
            automatic: false,
            backgroundColor: 0xff0000ff,
            strokes: [
              {
                'mode': 'erase',
                'radius': .18,
                'points': [
                  {'x': .25, 'y': .5},
                ],
              },
            ],
            onProgress: (v, _) => progress.add(v),
          );
          final metadata = await renderer.probe(output);
          expect(metadata.hasAudio, true);
          expect(metadata.sourceDuration, inInclusiveRange(.94, 1.04));
          expect([metadata.width, metadata.height], [320, 180]);
          final image = await frame(output, '${dir.path}/manual-frame.png');
          final erased = image.getPixel(80, 90);
          final retained = image.getPixel(280, 90);
          expect(erased.b, greaterThan(200));
          expect(erased.r, lessThan(40));
          expect(retained.r, greaterThan(200));
          expect(retained.b, lessThan(40));
          expect(progress.first, 0);
          expect(progress.last, 1);
          expect(progress, orderedEquals([...progress]..sort()));
          expect(await File(source).readAsBytes(), sourceBytes);
          final cancelled = VideoCutoutService();
          await cancelled.cancel();
          await expectLater(
            cancelled.process(
              clip,
              automatic: true,
              backgroundColor: 0xff000000,
              onProgress: (_, _) {},
            ),
            throwsA(isA<VideoCutoutCancelled>()),
          );
          await cancelled.dispose();

          // Exercise the real reused ONNX session, manual restoration, and image
          // background in a multi-frame batch. This checks pipeline semantics,
          // rather than assuming segmentation quality on a synthetic fixture.
          final batch = await Directory(
            '${dir.path}/batch',
          ).create(recursive: true);
          final foreground = img.Image(width: 320, height: 180, numChannels: 4);
          img.fill(foreground, color: img.ColorRgba8(255, 0, 0, 255));
          final background = img.Image(width: 320, height: 180, numChannels: 4);
          img.fill(background, color: img.ColorRgba8(0, 255, 0, 255));
          final bgPath = '${dir.path}/background.png';
          await File(bgPath).writeAsBytes(img.encodePng(background));
          for (var i = 1; i <= 2; i++) {
            await File(
              '${batch.path}/${i.toString().padLeft(6, '0')}.png',
            ).writeAsBytes(img.encodePng(foreground));
          }
          const native = NativeMediaService();
          await native.processVideoCutoutFrames(
            batch.path,
            automatic: true,
            backgroundColor: 0xff0000ff,
            backgroundPath: bgPath,
            strokes: [
              {
                'mode': 'erase',
                'radius': .15,
                'points': [
                  {'x': .25, 'y': .5},
                ],
              },
              {
                'mode': 'restore',
                'radius': .1,
                'points': [
                  {'x': .75, 'y': .5},
                ],
              },
            ],
          );
          for (var i = 1; i <= 2; i++) {
            final result = img.decodePng(
              await File(
                '${batch.path}/${i.toString().padLeft(6, '0')}.png',
              ).readAsBytes(),
            )!;
            final removed = result.getPixel(80, 90),
                restored = result.getPixel(240, 90);
            expect(removed.g, greaterThan(245));
            expect(removed.r, lessThan(10));
            expect(restored.r, greaterThan(245));
            expect(restored.g, lessThan(10));
            expect(restored.a, 255);
          }
          debugPrint(
            'Native video cutout: source brush coordinates, audio/trim, ONNX batches, replacement image and cancel passed.',
          );
        } finally {
          await service.dispose();
          await renderer.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'export matches moved video and multiple centered image overlays',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Placement export verification')),
        ),
      );
      await tester.runAsync(() async {
        final support = await getApplicationSupportDirectory();
        final dir = await Directory(
          '${support.path}/placement_checks',
        ).create(recursive: true);
        final source = '${dir.path}/source.mp4';
        await ffmpeg([
          '-y',
          '-f',
          'lavfi',
          '-i',
          'color=c=red:s=320x180:r=30',
          '-t',
          '0.4',
          '-an',
          '-c:v',
          'mpeg4',
          source,
        ]);
        final renderer = FfmpegVideoRenderer(preferredEncoder: 'mpeg4');
        try {
          final clip = (await renderer.probe(source)).copyWith(
            fit: VideoFit.fit,
            zoom: .5,
            positionX: .25,
            positionY: .1,
          );
          final overlays = <VideoOverlay>[];
          for (final entry in [
            ('green', 0xff00ff00, .3, .3),
            ('blue', 0xff0000ff, .7, .25),
          ]) {
            final image = img.Image(width: 40, height: 40, numChannels: 4);
            img.fill(
              image,
              color: img.ColorRgba8(
                (entry.$2 >> 16) & 255,
                (entry.$2 >> 8) & 255,
                entry.$2 & 255,
                255,
              ),
            );
            final path = '${dir.path}/${entry.$1}.png';
            await File(path).writeAsBytes(img.encodePng(image));
            overlays.add(
              VideoOverlay(
                id: entry.$1,
                path: path,
                x: entry.$3,
                y: entry.$4,
                width: .15,
                centered: true,
              ),
            );
          }
          final result = await renderer.render(
            VideoDocument(
              clips: [clip],
              canvas: VideoCanvas.square,
              overlays: overlays,
            ),
            shortEdge: 720,
            onProgress: (value, stage) =>
                debugPrint('Placement export: $value $stage'),
          );
          try {
            final image = await frame(result.path, '${dir.path}/export.png');
            expect([image.width, image.height], [720, 720]);
            expect(image.getPixel(540, 430).r, greaterThan(200));
            expect(image.getPixel(30, 30).r, lessThan(20));
            expect(image.getPixel(216, 216).g, greaterThan(200));
            expect(image.getPixel(504, 180).b, greaterThan(200));
            debugPrint(
              'Placement export: fit, scale, translation and two source-image layers match canvas coordinates.',
            );
          } finally {
            await renderer.release(result.path);
          }
        } finally {
          await renderer.dispose();
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
