import 'dart:io';
import 'dart:async';

import 'package:video_player/video_player.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/features/templates/domain/template_catalog.dart';
import 'package:framelab/features/video_editor/domain/video_document.dart';
import 'package:framelab/features/video_editor/domain/video_renderer.dart';
import 'package:framelab/features/video_editor/presentation/video_editor_screen.dart';

class _FakePlayer extends VideoPlayerController {
  _FakePlayer(String path, {this.initializeGate, this.initializeError})
    : super.file(File(path));
  final Completer<void>? initializeGate;
  Completer<void>? seekGate;
  final Object? initializeError;
  int seekCalls = 0;
  int disposeCalls = 0;
  int simultaneousSeeks = 0;
  int maxSimultaneousSeeks = 0;
  @override
  Future<void> initialize() async {
    await initializeGate?.future;
    if (initializeError != null) throw initializeError!;
    value = const VideoPlayerValue(
      duration: Duration(seconds: 20),
      size: Size(1920, 1080),
      isInitialized: true,
    );
  }

  @override
  Future<void> setLooping(bool looping) async =>
      value = value.copyWith(isLooping: looping);
  @override
  Future<void> setPlaybackSpeed(double speed) async =>
      value = value.copyWith(playbackSpeed: speed);
  @override
  Future<void> setVolume(double volume) async =>
      value = value.copyWith(volume: volume);
  @override
  Future<void> seekTo(Duration position) async {
    seekCalls++;
    simultaneousSeeks++;
    if (simultaneousSeeks > maxSimultaneousSeeks) {
      maxSimultaneousSeeks = simultaneousSeeks;
    }
    await seekGate?.future;
    value = value.copyWith(position: position);
    simultaneousSeeks--;
  }

  @override
  Future<void> play() async => value = value.copyWith(isPlaying: true);
  @override
  Future<void> pause() async => value = value.copyWith(isPlaying: false);
  @override
  Future<void> dispose() async {
    disposeCalls++;
    await super.dispose();
  }
}

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
    VideoPlayerController Function(String)? playerFactory,
    Future<String?> Function(String, double)? thumbnailLoader,
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
      pickVideos: pickVideos ?? () async => [],
      pickAudio: () async => null,
      pickImage: () async => null,
      publishVideo: (_, name) async => name,
      renderer: renderer,
      playerFactory: playerFactory ?? (path) => _FakePlayer(path),
      thumbnailLoader: thumbnailLoader,
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

  Future<void> selectTool(WidgetTester tester, String tool) async {
    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('video-editor-toolbar')),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(tool),
      80,
      scrollable: scrollable,
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.tap(find.text(tool));
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
    final template = templateCatalog.firstWhere((template) => template.video);
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
    await tester.tap(find.text('First caption').last);
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
    final renderer = _FakeRenderer();
    var attempts = 0;
    await tester.pumpWidget(
      editor(
        renderer: renderer,
        initialData: timeline().toJson(),
        playerFactory: (path) {
          attempts++;
          return _FakePlayer(
            path,
            initializeError: StateError('Unsupported test codec'),
          );
        },
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.textContaining('This clip could not be played.'),
      findsOneWidget,
    );
    expect(find.text('arrival.mp4'), findsOneWidget);
    expect(renderer.renderCalls, 0);
    expect(attempts, 1);
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(seconds: 1));
    expect(renderer.renderCalls, 0);
    expect(attempts, 2);
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
  testWidgets(
    'brightness and canvas react in one frame without encoding or replacing the decoder',
    (tester) async {
      setViewport(tester, const Size(400, 840));
      final renderer = _FakeRenderer();
      final players = <_FakePlayer>[];
      final saves = <VideoDocument>[];
      await tester.pumpWidget(
        editor(
          renderer: renderer,
          initialData: timeline().toJson(),
          playerFactory: (path) {
            final player = _FakePlayer(path);
            players.add(player);
            return player;
          },
          save: (data, _, _) async => saves.add(VideoDocument.fromJson(data)),
        ),
      );
      await tester.pumpAndSettle();
      await selectTool(tester, 'Adjust');
      final initialColor = tester
          .widget<ColorFiltered>(find.byKey(const ValueKey('video-live-color')))
          .colorFilter;
      final controls = find.descendant(
        of: find.byKey(const ValueKey('Adjust')),
        matching: find.byType(Slider),
      );
      // A burst of continuous events must never create media work or codecs.
      for (var i = 1; i <= 60; i++) {
        tester.widget<Slider>(controls.first).onChanged!(i / 120);
        await tester.pump();
      }
      final finalColor = tester
          .widget<ColorFiltered>(find.byKey(const ValueKey('video-live-color')))
          .colorFilter;
      expect(finalColor, isNot(initialColor));
      expect(players, hasLength(1));
      expect(
        identical(
          tester.widget<VideoPlayer>(find.byType(VideoPlayer)).controller,
          players.single,
        ),
        isTrue,
      );
      expect(renderer.renderCalls, 0);
      await selectTool(tester, 'Canvas');
      final cropBefore = tester
          .widget<Positioned>(find.byKey(const ValueKey('video-live-crop')))
          .width!;
      final canvasControls = find.descendant(
        of: find.byKey(const ValueKey('Canvas')),
        matching: find.byType(Slider),
      );
      tester.widget<Slider>(canvasControls.first).onChanged!(2);
      await tester.pump();
      expect(
        tester
            .widget<Positioned>(find.byKey(const ValueKey('video-live-crop')))
            .width,
        closeTo(cropBefore * 2, .01),
      );
      expect(renderer.renderCalls, 0);
      expect(players, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(saves.last.clips.first.brightness, .5);
      expect(saves.last.clips.first.zoom, 2);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets('source initialization is coalesced while live edits arrive', (
    tester,
  ) async {
    setViewport(tester, const Size(400, 840));
    final gate = Completer<void>();
    final players = <_FakePlayer>[];
    final renderer = _FakeRenderer();
    await tester.pumpWidget(
      editor(
        renderer: renderer,
        initialData: timeline().toJson(),
        playerFactory: (path) {
          final player = _FakePlayer(path, initializeGate: gate);
          players.add(player);
          return player;
        },
      ),
    );
    await tester.pump();
    await selectTool(tester, 'Adjust');
    final brightness = find
        .descendant(
          of: find.byKey(const ValueKey('Adjust')),
          matching: find.byType(Slider),
        )
        .first;
    for (var i = 0; i < 50; i++) {
      tester.widget<Slider>(brightness).onChanged!(.4);
      await tester.pump();
    }
    expect(players, hasLength(1));
    expect(renderer.renderCalls, 0);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-live-color')), findsOneWidget);
    expect(players.single.disposeCalls, 0);
    await finish(tester);
    expect(players.single.disposeCalls, 1);
  });

  testWidgets(
    'scrubbing shows the latest position and coalesces in-flight native seeks',
    (tester) async {
      setViewport(tester, const Size(400, 840));
      final player = _FakePlayer('/private/arrival.mp4');
      final renderer = _FakeRenderer();
      await tester.pumpWidget(
        editor(
          renderer: renderer,
          initialData: timeline().toJson(),
          playerFactory: (_) => player,
        ),
      );
      await tester.pumpAndSettle();
      final gate = Completer<void>();
      player.seekGate = gate;
      final finder = find.byKey(const ValueKey('video-timeline-scrubber'));
      var scrubber = tester.widget<Slider>(finder);
      scrubber.onChangeStart!(0);
      for (var i = 1; i <= 50; i++) {
        scrubber.onChanged!(i / 10);
      }
      await tester.pump(const Duration(milliseconds: 40));
      expect(tester.widget<Slider>(finder).value, 5);
      expect(
        player.seekCalls,
        2,
      ); // Initial trim seek and one coalesced drag seek.
      scrubber = tester.widget<Slider>(finder);
      for (var i = 0; i < 50; i++) {
        scrubber.onChanged!(6);
      }
      scrubber.onChangeEnd!(6);
      await tester.pump();
      expect(tester.widget<Slider>(finder).value, 6);
      expect(player.maxSimultaneousSeeks, 1);
      player.seekGate = null;
      gate.complete();
      await tester.pumpAndSettle();
      expect(player.value.position, const Duration(seconds: 6));
      expect(player.seekCalls, 3);
      expect(player.maxSimultaneousSeeks, 1);
      expect(renderer.renderCalls, 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );

  testWidgets(
    'play advances split clips from the same source to their exact trimmed start',
    (tester) async {
      setViewport(tester, const Size(400, 840));
      final player = _FakePlayer('/private/arrival.mp4');
      var factories = 0;
      final renderer = _FakeRenderer();
      final document = VideoDocument(
        clips: const [
          VideoClip(
            id: 'a',
            path: '/private/arrival.mp4',
            sourceDuration: 8,
            end: 2,
          ),
          VideoClip(
            id: 'b',
            path: '/private/arrival.mp4',
            sourceDuration: 8,
            start: 2,
            end: 4,
          ),
        ],
      );
      await tester.pumpWidget(
        editor(
          renderer: renderer,
          initialData: document.toJson(),
          playerFactory: (_) {
            factories++;
            return player;
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Play preview'));
      await tester.pump();
      player.value = player.value.copyWith(
        position: const Duration(milliseconds: 1980),
      );
      await tester.pumpAndSettle();
      expect(player.value.position, const Duration(seconds: 2));
      expect(player.value.isPlaying, isTrue);
      expect(factories, 1);
      expect(renderer.renderCalls, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'only explicit composition preview invokes the rendering pipeline',
    (tester) async {
      setViewport(tester, const Size(400, 840));
      final renderer = _FakeRenderer();
      await tester.pumpWidget(
        editor(renderer: renderer, initialData: timeline().toJson()),
      );
      await tester.pumpAndSettle();
      expect(renderer.renderCalls, 0);
      await tester.tap(
        find.byTooltip('Preview composition with music and transitions'),
      );
      await tester.pumpAndSettle();
      expect(renderer.renderCalls, 1);
      await selectTool(tester, 'Filters');
      await tester.ensureVisible(find.text('Cinema'));
      await tester.tap(find.text('Cinema'));
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cinema'))
            .selected,
        isTrue,
      );
      expect(renderer.renderCalls, 1);
      expect(find.textContaining('Pro'), findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'continuous scrubbing decodes new positions before the finger is released',
    (tester) async {
      setViewport(tester, const Size(400, 840));
      final player = _FakePlayer('/private/arrival.mp4');
      final renderer = _FakeRenderer();
      await tester.pumpWidget(
        editor(
          renderer: renderer,
          initialData: timeline().toJson(),
          playerFactory: (_) => player,
        ),
      );
      await tester.pumpAndSettle();
      final finder = find.byKey(const ValueKey('video-timeline-scrubber'));
      tester.widget<Slider>(finder).onChangeStart!(0);
      for (var i = 1; i <= 20; i++) {
        tester.widget<Slider>(finder).onChanged!(i / 10);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // A debounce would only move the thumb; throttled native seeks keep frames
      // changing throughout the gesture with bounded codec operations.
      expect(player.seekCalls, greaterThan(3));
      expect(player.seekCalls, lessThan(15));
      expect(player.value.position.inMilliseconds, greaterThan(1000));
      expect(player.maxSimultaneousSeeks, 1);
      tester.widget<Slider>(finder).onChangeEnd!(2);
      await tester.pumpAndSettle();
      expect(player.value.position, const Duration(seconds: 2));
      expect(renderer.renderCalls, 0);
      await finish(tester);
    },
  );

  testWidgets(
    'pending filmstrip thumbnails never block live edits or trigger duplicate loads',
    (tester) async {
      setViewport(tester, const Size(400, 840));
      final gate = Completer<String?>();
      final requests = <String>{};
      var calls = 0;
      final renderer = _FakeRenderer();
      await tester.pumpWidget(
        editor(
          renderer: renderer,
          initialData: timeline().toJson(),
          thumbnailLoader: (path, seconds) {
            calls++;
            requests.add('$path:$seconds');
            return gate.future;
          },
        ),
      );
      await tester.pump();
      await selectTool(tester, 'Adjust');
      final brightness = find
          .descendant(
            of: find.byKey(const ValueKey('Adjust')),
            matching: find.byType(Slider),
          )
          .first;
      final before = tester
          .widget<ColorFiltered>(find.byKey(const ValueKey('video-live-color')))
          .colorFilter;
      for (var i = 0; i < 30; i++) {
        tester.widget<Slider>(brightness).onChanged!(.3);
        await tester.pump();
      }
      expect(
        tester
            .widget<ColorFiltered>(
              find.byKey(const ValueKey('video-live-color')),
            )
            .colorFilter,
        isNot(before),
      );
      expect(calls, requests.length);
      expect(calls, inInclusiveRange(3, 6));
      expect(renderer.renderCalls, 0);
      gate.complete(null); // Missing thumbnails fall back to a clip icon.
      await tester.pumpAndSettle();
      expect(find.text('arrival.mp4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
}
