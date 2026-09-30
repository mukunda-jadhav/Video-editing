import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/video_editor/data/ffmpeg_video_renderer.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'default hardware encoder or fallback produces a valid export',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Encoder verification'))),
      );
      await tester.runAsync(() async {
        final temp = await getTemporaryDirectory();
        final fixtures = await temp.createTemp('encoder_smoke_');
        final renderer = FfmpegVideoRenderer();
        try {
          final source = '${fixtures.path}/source.mp4';
          final generated = await FFmpegKit.executeWithArguments([
            '-y',
            '-f',
            'lavfi',
            '-i',
            'testsrc2=size=320x180:rate=30',
            '-t',
            '1',
            '-c:v',
            'mpeg4',
            '-q:v',
            '3',
            source,
          ]);
          expect(ReturnCode.isSuccess(await generated.getReturnCode()), true);
          final clip = await renderer.probe(source);
          final result = await renderer.render(
            VideoDocument(clips: [clip]),
            shortEdge: 720,
            onProgress: (progress, stage) =>
                debugPrint('Default encoder $progress $stage'),
          );
          expect([result.width, result.height], [1280, 720]);
          expect(
            (await renderer.probe(result.path)).sourceDuration,
            closeTo(1, .3),
          );
          debugPrint('Verified default encoder result: ${result.codec}');
          await renderer.release(result.path);
          expect(await File(result.path).exists(), false);
        } finally {
          await renderer.dispose();
          await fixtures.delete(recursive: true);
        }
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
