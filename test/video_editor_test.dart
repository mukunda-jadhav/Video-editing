import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/features/templates/domain/template_catalog.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_renderer.dart';
import 'package:framelab/features/video_editor/presentation/video_editor_screen.dart';

class _FakeRenderer implements VideoRenderer {
  int renderCalls = 0;
  int disposeCalls = 0;
  final List<String> probed = [];
  Object? renderError;

  @override
  Future<VideoClip> probe(String path) async {
    probed.add(path);
    return VideoClip(id: path, path: path, sourceDuration: 8, end: 8);
  }

  @override
  Future<VideoRenderResult> render(
    VideoDocument document, {
    required int shortEdge,
    required void Function(double progress, String stage) onProgress,
  }) async {
    renderCalls++;
    // Rendering stops at the injected boundary, before video_player or any
    // native codec is invoked. Widget tests exercise editor behavior only.
    throw renderError ?? const VideoRenderCancelled();
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> release(String path) async {}

  @override
  Future<void> dispose() async => disposeCalls++;
}

void main() {
  VideoDocument timeline() => VideoDocument(
    title: 'Weekend film',
    clips: const [
      VideoClip(
        id: 'first',
        path: '/private/arrival.mp4',
        sourceDuration: 8,
        end: 8,
      ),
      VideoClip(
        id: 'second',
        path: '/private/sunset.mp4',
        sourceDuration: 5,
        end: 5,
      ),
    ],
  );

  Widget editor({
    required _FakeRenderer renderer,
    Map<String, dynamic>? initialData,
    double textScale = 1,
    Future<void> Function(Map<String, dynamic>, String, String?)? save,
    Future<List<String>> Function()? pickVideos,
  }) => MaterialApp(
    theme: AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: VideoEditorScreen(
      initialData: initialData,
      onSave: save ?? (_, title, thumbnail) async {},
      ensurePro: () async => false,
      isPro: false,
      pickVideos: pickVideos ?? () async => [],
      pickAudio: () async => null,
      pickImage: () async => null,
      publishVideo: (_, name) async => name,
      renderer: renderer,
    ),
  );

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  for (final size in [const Size(360, 640), const Size(640, 360)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('timeline fits $size with $textScale text scale', (
        tester,
      ) async {
        setViewport(tester, size);
        final renderer = _FakeRenderer();
        await tester.pumpWidget(
          editor(
            renderer: renderer,
            initialData: timeline().toJson(),
            textScale: textScale,
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('arrival.mp4'), findsOneWidget);
        expect(find.byTooltip('Transition after clip 1: cut'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Add videos to timeline'));
        expect(
          find.byTooltip('Add videos to timeline').hitTestable(),
          findsOneWidget,
        );
        await finish(tester);
        expect(renderer.disposeCalls, 1);
      });
    }
  }

  testWidgets('empty reel template keeps its text when videos are imported', (
    tester,
  ) async {
    final renderer = _FakeRenderer();
    final template = templateCatalog.firstWhere(
      (template) => template.video && !template.premium,
    );
    final saves = <VideoDocument>[];
    await tester.pumpWidget(
      editor(
        renderer: renderer,
        initialData: template.createRecipe(),
        pickVideos: () async => ['/private/my-clip.mp4'],
        save: (data, title, thumbnail) async =>
            saves.add(VideoDocument.fromJson(data)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(template.title), findsOneWidget);
    expect(find.text('Choose videos'), findsOneWidget);
    expect(renderer.renderCalls, 0);
    // Opening an unchanged template does not create a new saved project.
    expect(saves, isEmpty);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == 'Export video',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Choose videos'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(renderer.probed, ['/private/my-clip.mp4']);
    expect(
      saves.last.texts.first.text,
      template.headline.replaceAll('\n', ' '),
    );
    expect(saves.last.clips.single.path, '/private/my-clip.mp4');
    expect(saves.last.canvas, VideoCanvas.portrait);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('timeline split saves two clips and undo restores the source', (
    tester,
  ) async {
    final saves = <VideoDocument>[];
    await tester.pumpWidget(
      editor(
        renderer: _FakeRenderer(),
        initialData: timeline().toJson(),
        save: (data, title, thumbnail) async =>
            saves.add(VideoDocument.fromJson(data)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Split'));
    await tester.tap(find.text('Split'));
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last.clips, hasLength(3));
    expect(saves.last.clips.first.end, 4);
    expect(saves.last.clips[1].start, 4);
    expect(saves.last.duration, 13);
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last.clips, hasLength(2));
    expect(saves.last.clips.first.end, 8);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('text can be added edited and undone without losing clip edits', (
    tester,
  ) async {
    setViewport(tester, const Size(800, 900));
    final saves = <VideoDocument>[];
    await tester.pumpWidget(
      editor(
        renderer: _FakeRenderer(),
        initialData: timeline().toJson(),
        save: (data, title, thumbnail) async =>
            saves.add(VideoDocument.fromJson(data)),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Text'));
    await tester.tap(find.text('Text'));
    await tester.pump();
    await tester.tap(find.text('Add text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'First caption');
    await tester.tap(find.byTooltip('Save text'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last.texts.single.text, 'First caption');
    await tester.tap(find.text('First caption'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A revised caption');
    await tester.tap(find.byTooltip('Save text'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last.texts.single.text, 'A revised caption');
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last.texts.single.text, 'First caption');
    expect(saves.last.clips.map((clip) => clip.path), [
      '/private/arrival.mp4',
      '/private/sunset.mp4',
    ]);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('rename dialog saves safely and save failures can be retried', (
    tester,
  ) async {
    final saves = <VideoDocument>[];
    var shouldFail = true;
    await tester.pumpWidget(
      editor(
        renderer: _FakeRenderer(),
        initialData: timeline().toJson(),
        save: (data, title, thumbnail) async {
          if (shouldFail) throw const FileSystemException('Storage is full');
          saves.add(VideoDocument.fromJson(data));
        },
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Weekend film'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'A better title');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Project could not be saved.'), findsOneWidget);
    expect(saves, isEmpty);
    shouldFail = false;
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 1));
    expect(saves.single.title, 'A better title');
    expect(find.text('Saved on device'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('preview failure keeps timeline editable and can be retried', (
    tester,
  ) async {
    final renderer = _FakeRenderer()
      ..renderError = StateError('Unsupported test codec');
    await tester.pumpWidget(
      editor(renderer: renderer, initialData: timeline().toJson()),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.textContaining('Preview could not be created.'),
      findsOneWidget,
    );
    expect(find.text('arrival.mp4'), findsOneWidget);
    expect(renderer.renderCalls, 1);
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 1));
    expect(renderer.renderCalls, 2);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'unsupported saved recipe is visible and never auto-overwritten',
    (tester) async {
      var saves = 0;
      final renderer = _FakeRenderer();
      await tester.pumpWidget(
        editor(
          renderer: renderer,
          initialData: {'schemaVersion': 99, 'type': 'video'},
          save: (_, title, thumbnail) async => saves++,
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.textContaining('Your saved file has not been changed.'),
        findsOneWidget,
      );
      expect(saves, 0);
      expect(renderer.renderCalls, 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('empty template fits a small phone with large text', (
    tester,
  ) async {
    setViewport(tester, const Size(360, 640));
    final renderer = _FakeRenderer();
    await tester.pumpWidget(
      editor(
        renderer: renderer,
        initialData: templateCatalog
            .firstWhere((template) => template.video)
            .createRecipe(),
        textScale: 2,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Choose videos'));
    expect(find.text('Choose videos').hitTestable(), findsOneWidget);
    expect(renderer.renderCalls, 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets(
    'caption editor stays usable with large text and keyboard inset',
    (tester) async {
      setViewport(tester, const Size(360, 640));
      final saves = <VideoDocument>[];
      await tester.pumpWidget(
        editor(
          renderer: _FakeRenderer(),
          initialData: timeline().toJson(),
          textScale: 2,
          save: (data, title, thumbnail) async =>
              saves.add(VideoDocument.fromJson(data)),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.ensureVisible(find.text('Text'));
      await tester.tap(find.text('Text'));
      await tester.pump();
      await tester.ensureVisible(find.text('Add text'));
      await tester.tap(find.text('Add text'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'My mobile caption');
      expect(find.byTooltip('Save text').hitTestable(), findsOneWidget);
      await tester.tap(find.byTooltip('Save text'));
      await tester.pumpAndSettle();
      tester.view.resetViewInsets();
      await tester.pump(const Duration(seconds: 1));
      expect(saves.last.texts.single.text, 'My mobile caption');
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
}
