import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/media/native_media_service.dart';
import 'package:framelab/features/video_editor/data/ffmpeg_video_renderer.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_renderer.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

// Runs against the real Android plugins and bundled ONNX model. Every media
// fixture is generated locally; no network or external account is required.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native offline media pipeline', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Native media verification')),
      ),
    );
    await tester.runAsync(() async {
      final support = await getApplicationSupportDirectory();
      final fixtures = await Directory(
        '${support.path}/native_smoke',
      ).create(recursive: true);
      final renderer = FfmpegVideoRenderer(preferredEncoder: 'mpeg4');
      const native = NativeMediaService();
      final diagnostics = await native.diagnostics();
      debugPrint('FFmpeg version: ${await FFmpegKitConfig.getFFmpegVersion()}');
      debugPrint('Device at start: $diagnostics');
      expect(diagnostics['modelBundled'], true);
      expect(await native.availableBytes(), greaterThan(32 * 1024 * 1024));

      Future<void> ffmpeg(List<String> arguments) async {
        final session = await FFmpegKit.executeWithArguments(arguments);
        expect(
          ReturnCode.isSuccess(await session.getReturnCode()),
          true,
          reason: await session.getAllLogsAsString(),
        );
      }

      final watchdog = Timer.periodic(const Duration(seconds: 20), (_) async {
        final sessions = await FFmpegKit.listSessions();
        if (sessions.isEmpty) return;
        final last = sessions.last;
        debugPrint(
          'Native session ${last.getSessionId()} state ${await last.getState()}',
        );
        final logs = await last.getAllLogsAsString();
        if (logs != null) {
          debugPrint(logs.substring(logs.length > 600 ? logs.length - 600 : 0));
        }
      });
      try {
        final source = '${fixtures.path}/source.mp4';
        final silent = '${fixtures.path}/silent.mp4';
        final music = '${fixtures.path}/music.wav';
        await ffmpeg([
          '-y',
          '-f',
          'lavfi',
          '-i',
          'testsrc2=size=320x180:rate=30',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:sample_rate=48000',
          '-t',
          '1.5',
          '-c:v',
          'mpeg4',
          '-q:v',
          '3',
          '-c:a',
          'aac',
          source,
        ]);
        await ffmpeg([
          '-y',
          '-f',
          'lavfi',
          '-i',
          'color=c=blue:s=180x320:r=30',
          '-t',
          '1',
          '-c:v',
          'mpeg4',
          '-q:v',
          '3',
          silent,
        ]);
        await ffmpeg([
          '-y',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=220:sample_rate=48000',
          '-t',
          '1',
          music,
        ]);

        final photo = img.Image(width: 320, height: 240, numChannels: 4);
        img.fill(photo, color: img.ColorRgba8(220, 225, 230, 255));
        img.fillCircle(
          photo,
          x: 160,
          y: 100,
          radius: 60,
          color: img.ColorRgba8(230, 90, 30, 255),
        );
        img.fillRect(
          photo,
          x1: 100,
          y1: 150,
          x2: 220,
          y2: 230,
          color: img.ColorRgba8(30, 70, 200, 255),
        );
        final photoPath = '${fixtures.path}/portrait.jpg';
        final overlayPath = '${fixtures.path}/overlay.png';
        await File(photoPath).writeAsBytes(img.encodeJpg(photo));
        await File(overlayPath).writeAsBytes(img.encodePng(photo));

        final cutoutPath = await native.removeBackground(photoPath);
        final cutout = img.decodePng(await File(cutoutPath).readAsBytes())!;
        expect([cutout.width, cutout.height], [320, 240]);
        expect(cutout.numChannels, 4);
        expect(cutout.any((pixel) => pixel.a < 200), true);
        expect(cutout.any((pixel) => pixel.a > 200), true);
        final publishedPhoto = await native.publish(
          cutoutPath,
          'FrameLab_smoke_cutout.png',
          video: false,
        );
        expect(publishedPhoto, startsWith('content://'));

        final clip = await renderer.probe(source);
        final noAudio = await renderer.probe(silent);
        expect(clip.hasAudio, true);
        expect(noAudio.hasAudio, false);
        final transitions = VideoTransition.values;
        final clips = List.generate(
          6,
          (i) => clip.copyWith(
            id: 'clip_$i',
            start: .1,
            end: .8,
            speed: i == 1 ? 1.25 : 1,
            volume: i == 2 ? 0 : .6,
            filter: VideoFilter.values[i],
            effect: VideoEffect.values[i % VideoEffect.values.length],
            transition: transitions[i % transitions.length],
            transitionDuration: .1,
            cropX: .4,
            cropY: .6,
            zoom: 1.1,
          ),
        );
        final document = VideoDocument(
          clips: clips,
          texts: const [
            VideoText(
              id: 'caption',
              text: "Offline 100% 'quoted' : ; [safe]",
              start: .1,
              end: 2,
            ),
          ],
          overlay: VideoOverlay(
            path: overlayPath,
            start: .2,
            end: 2,
            opacity: .7,
          ),
          musicPath: music,
          musicVolume: .2,
        );
        final output = await renderer.render(
          document,
          shortEdge: 720,
          onProgress: (value, stage) {
            debugPrint('720p ${value.toStringAsFixed(2)} $stage');
          },
        );
        expect([output.width, output.height], [1280, 720]);
        final exported = await renderer.probe(output.path);
        expect(exported.sourceDuration, closeTo(document.duration, .3));
        expect(
          await native.publish(
            output.path,
            'FrameLab_smoke_720.mp4',
            video: true,
          ),
          startsWith('content://'),
        );
        await renderer.release(output.path);
        expect(await File(output.path).exists(), false);

        final portrait = await renderer.render(
          VideoDocument(clips: [noAudio], canvas: VideoCanvas.portrait),
          shortEdge: 1080,
          onProgress: (value, stage) {
            debugPrint('1080p ${value.toStringAsFixed(2)} $stage');
          },
        );
        expect([portrait.width, portrait.height], [1080, 1920]);
        expect((await renderer.probe(portrait.path)).hasAudio, true);
        await renderer.release(portrait.path);

        final pending = renderer.render(
          VideoDocument(clips: [clip]),
          shortEdge: 720,
          onProgress: (_, _) {},
        );
        final cancelled = expectLater(
          pending,
          throwsA(isA<VideoRenderCancelled>()),
        );
        await renderer.cancel();
        await cancelled;
        debugPrint(
          'Native diagnostics after smoke: ${await native.diagnostics()}',
        );
      } finally {
        watchdog.cancel();
        await renderer.dispose();
        if (await fixtures.exists()) await fixtures.delete(recursive: true);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
