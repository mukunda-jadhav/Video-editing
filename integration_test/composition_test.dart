import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:framelab/features/video_editor/data/ffmpeg_video_renderer.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:image/image.dart' as img;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'every optional composition input terminates',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Composition verification')),
        ),
      );
      await tester.runAsync(() async {
        final temp = await getTemporaryDirectory();
        final fixtures = await temp.createTemp('composition_smoke_');
        final renderer = FfmpegVideoRenderer(preferredEncoder: 'mpeg4');
        try {
          final source = '${fixtures.path}/source.mp4';
          final music = '${fixtures.path}/music.wav';
          for (final args in [
            [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'testsrc2=size=320x180:rate=30',
              '-t',
              '1',
              '-c:v',
              'mpeg4',
              source,
            ],
            [
              '-y',
              '-f',
              'lavfi',
              '-i',
              'sine=sample_rate=48000',
              '-t',
              '0.4',
              music,
            ],
          ]) {
            final session = await FFmpegKit.executeWithArguments(args);
            expect(
              ReturnCode.isSuccess(await session.getReturnCode()),
              true,
              reason: await session.getAllLogsAsString(),
            );
          }
          final picture = img.Image(width: 48, height: 48, numChannels: 4);
          img.fill(picture, color: img.ColorRgba8(200, 10, 30, 160));
          final overlay = '${fixtures.path}/overlay.png';
          await File(overlay).writeAsBytes(img.encodePng(picture));
          final clip = await renderer.probe(source);
          for (final name in [
            'plain',
            'text',
            'overlay',
            'music',
            'musicOffset',
            'combined',
          ]) {
            debugPrint('Composition start: $name');
            final hasMusic = [
              'music',
              'musicOffset',
              'combined',
            ].contains(name);
            final document = VideoDocument(
              clips: [clip],
              texts: name == 'text' || name == 'combined'
                  ? const [VideoText(id: 't', text: 'Hello', start: 0, end: 1)]
                  : [],
              musicPath: hasMusic ? music : null,
              musicStart: name == 'musicOffset' ? 4.25 : 0,
              overlay: name == 'overlay' || name == 'combined'
                  ? VideoOverlay(path: overlay, start: 0, end: 1)
                  : null,
            );
            final result = await renderer
                .render(document, shortEdge: 480, onProgress: (_, _) {})
                .timeout(const Duration(seconds: 25));
            expect(
              (await renderer.probe(result.path)).sourceDuration,
              closeTo(1, .3),
            );
            if (hasMusic) {
              // The source video is silent and the music fixture is only .4s.
              // Audible samples near the 1s end prove actual looping, mixing
              // and offset wrapping, rather than only a valid MP4 container.
              final tail = '${fixtures.path}/$name-tail.pcm';
              final decoded = await FFmpegKit.executeWithArguments([
                '-y',
                '-ss',
                '0.75',
                '-i',
                result.path,
                '-t',
                '0.15',
                '-vn',
                '-ac',
                '1',
                '-ar',
                '48000',
                '-f',
                's16le',
                tail,
              ]);
              expect(
                ReturnCode.isSuccess(await decoded.getReturnCode()),
                true,
                reason: await decoded.getAllLogsAsString(),
              );
              final data = ByteData.sublistView(await File(tail).readAsBytes());
              expect(data.lengthInBytes, greaterThan(1000));
              var absoluteSamples = 0;
              for (var i = 0; i + 1 < data.lengthInBytes; i += 2) {
                absoluteSamples += data.getInt16(i, Endian.little).abs();
              }
              expect(
                absoluteSamples / (data.lengthInBytes / 2),
                greaterThan(100),
              );
            }
            await renderer.release(result.path);
            debugPrint('Composition passed: $name');
          }
        } finally {
          await renderer.dispose();
          await fixtures.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
