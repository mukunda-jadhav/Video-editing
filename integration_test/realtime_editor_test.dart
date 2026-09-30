import 'dart:io';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/core/media/native_media_service.dart';
import 'package:framelab/features/photo_editor/data/photo_renderer.dart';
import 'package:framelab/features/photo_editor/domain/photo_document.dart';
import 'package:framelab/features/photo_editor/presentation/photo_editor_screen.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_renderer.dart';
import 'package:framelab/features/video_editor/presentation/video_editor_screen.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), true, reason: 'Native editor did not become ready.');
}

Future<void> tapTool(WidgetTester tester, String label) async {
  for (var attempt = 0; attempt < 14; attempt++) {
    final text = find.text(label);
    final visible = text.hitTestable();
    if (visible.evaluate().isNotEmpty) {
      await tester.tap(visible.first);
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
    var distance = -150.0;
    if (text.evaluate().isNotEmpty && tester.getCenter(text.first).dx < 0) {
      distance = 150;
    }
    final toolbar = find
        .byWidgetPredicate(
          (widget) =>
              widget is ListView && widget.scrollDirection == Axis.horizontal,
        )
        .last;
    await tester.drag(toolbar, Offset(distance, 0));
    await tester.pump(const Duration(milliseconds: 300));
  }
  fail('Could not reveal tool $label.');
}

class _NoAutomaticRender implements VideoRenderer {
  int renders = 0;
  @override
  Future<VideoClip> probe(String path) async => VideoClip(
    id: 'fixture',
    path: path,
    sourceDuration: 4,
    end: 4,
    width: 320,
    height: 180,
    hasAudio: false,
  );
  @override
  Future<VideoRenderResult> render(
    VideoDocument document, {
    required int shortEdge,
    required void Function(double, String) onProgress,
  }) async {
    renders++;
    throw StateError('Editing must not encode a preview.');
  }

  @override
  Future<void> cancel() async {}
  @override
  Future<void> release(String path) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('photo brightness and size repaint immediately on cached texture', (
    tester,
  ) async {
    final support = await getApplicationSupportDirectory();
    final file = File('${support.path}/realtime-photo.png');
    final fixture = img.Image(width: 1600, height: 1000);
    img.fill(fixture, color: img.ColorRgb8(90, 100, 110));
    await file.writeAsBytes(img.encodePng(fixture));
    final document = PhotoDocument(imagePath: file.path);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: PhotoEditorScreen(
          initialData: document.toJson(),
          onSave: (_, _, _) async {},
          removeBackground: (p) async => p,
          exportBytes: (_, _) async => 'unused',
          pickImage: () async => null,
        ),
      ),
    );
    final canvas = find.byKey(const ValueKey('photo-live-preview'));
    PhotoPainter painter() =>
        tester.widget<CustomPaint>(canvas).painter! as PhotoPainter;
    await waitFor(
      tester,
      () =>
          canvas.evaluate().isNotEmpty &&
          painter().composition?.foreground != null,
    );
    final source = painter().composition?.foreground;
    final brightness = find.byKey(const ValueKey('photo-slider-Brightness'));
    await tester.ensureVisible(brightness);
    final rect = tester.getRect(brightness);
    final gesture = await tester.startGesture(rect.center);
    var changed = false;
    for (var i = 1; i <= 8; i++) {
      await gesture.moveTo(rect.center + Offset(i * 5, 0));
      await tester.pump(const Duration(milliseconds: 16));
      expect(identical(painter().composition?.foreground, source), true);
      changed |= painter().document.brightness != 1;
    }
    expect(changed, true);
    await gesture.up();
    await tester.pump();
    await tapTool(tester, 'Layout');
    await tester.pump();
    await tester.ensureVisible(find.text('Story / Reel'));
    await tester.tap(find.text('Story / Reel'));
    await tester.pump();
    expect(painter().document.width, 1080);
    expect(painter().document.height, 1920);
    expect(identical(painter().composition?.foreground, source), true);
    expect(tester.takeException(), isNull);
    debugPrint(
      'Realtime photo: 8 gesture frames reuse the native image; layout updates next frame.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'video color canvas and scrub never encode an automatic preview',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final file = '${support.path}/realtime-video.mp4';
      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-f',
        'lavfi',
        '-i',
        'color=c=gray:size=320x180:rate=24',
        '-t',
        '4',
        '-an',
        '-c:v',
        'mpeg4',
        '-q:v',
        '3',
        '-pix_fmt',
        'yuv420p',
        file,
      ]);
      expect(ReturnCode.isSuccess(await session.getReturnCode()), true);
      const native = NativeMediaService();
      final thumbnail = await native.getVideoThumbnail(file, timeSeconds: 1);
      final thumbImage = img.decodeImage(await File(thumbnail).readAsBytes())!;
      expect(thumbImage.width, lessThanOrEqualTo(160));
      expect(thumbImage.height, lessThanOrEqualTo(160));
      expect(await native.getVideoThumbnail(file, timeSeconds: 1), thumbnail);
      final renderer = _NoAutomaticRender();
      final clip = await renderer.probe(file);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: VideoEditorScreen(
            initialData: VideoDocument(clips: [clip]).toJson(),
            renderer: renderer,
            onSave: (_, _, _) async {},
            pickVideos: () async => [],
            pickAudio: () async => null,
            pickImage: () async => null,
            publishVideo: (_, _) async => 'unused',
          ),
        ),
      );
      await waitFor(
        tester,
        () => find.byType(VideoPlayer).evaluate().isNotEmpty,
      );
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      expect(controller.value.isInitialized, true);
      await tapTool(tester, 'Adjust');
      await tester.pump();
      final slider = find.byWidgetPredicate(
        (w) => w is Slider && w.min == -.5 && w.max == .5,
      );
      await tester.ensureVisible(slider);
      final rect = tester.getRect(slider);
      final before = tester
          .widget<ColorFiltered>(find.byKey(const ValueKey('video-live-color')))
          .colorFilter;
      final gesture = await tester.startGesture(rect.center);
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(rect.center + Offset(i * 5, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          identical(
            tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
            controller,
          ),
          true,
        );
        expect(renderer.renders, 0);
      }
      await gesture.up();
      await tester.pump();
      expect(
        tester
            .widget<ColorFiltered>(
              find.byKey(const ValueKey('video-live-color')),
            )
            .colorFilter,
        isNot(before),
      );
      await tapTool(tester, 'Canvas');
      await tester.pump();
      await tester.ensureVisible(find.text('9:16'));
      await tester.tap(find.text('9:16'));
      await tester.pump();
      expect(
        tester
            .widget<AspectRatio>(
              find.byKey(const ValueKey('video-preview-canvas')),
            )
            .aspectRatio,
        closeTo(9 / 16, .001),
      );
      expect(
        identical(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          controller,
        ),
        true,
      );
      expect(renderer.renders, 0);
      final scrubber = find.byKey(const ValueKey('video-timeline-scrubber'));
      await tester.drag(scrubber, const Offset(65, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.value.position, greaterThan(Duration.zero));
      expect(renderer.renders, 0);
      expect(tester.takeException(), isNull);
      debugPrint(
        'Realtime video: original native player retained through 8 drag frames and scrub; 0 encode jobs.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
