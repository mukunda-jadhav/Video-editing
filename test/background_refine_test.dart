import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/features/photo_editor/data/background_refine_renderer.dart';
import 'package:framelab/features/photo_editor/data/photo_renderer.dart';
import 'package:framelab/features/photo_editor/domain/background_brush.dart';
import 'package:framelab/features/photo_editor/presentation/background_refine_screen.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ui.Image> texture(int alpha) async {
    final source = img.Image(width: 100, height: 80, numChannels: 4);
    for (final pixel in source) {
      pixel.setRgba(160, 80, 30, alpha);
    }
    return decodePhoto(img.encodePng(source));
  }

  Future<img.Image> raster(
    List<BackgroundBrushStroke> strokes, {
    int? initialAlpha,
  }) async {
    final original = await texture(200);
    final initial = initialAlpha == null ? null : await texture(initialAlpha);
    try {
      return img.decodePng(
        await renderRefinedBackground(
          original: original,
          initial: initial,
          strokes: strokes,
          width: 100,
          height: 80,
        ),
      )!;
    } finally {
      original.dispose();
      initial?.dispose();
    }
  }

  BackgroundBrushStroke brush(
    BackgroundBrushMode mode, {
    List<Offset> points = const [Offset(.5, .5)],
    double radius = .1,
  }) => BackgroundBrushStroke(mode: mode, radius: radius, points: points);

  test(
    'erase preserves untouched alpha and restore replaces original alpha/color',
    () async {
      final erased = await raster([brush(BackgroundBrushMode.erase)]);
      expect(erased.getPixel(50, 40).a, 0);
      expect(erased.getPixel(5, 5).a, 200);
      final restored = await raster([
        brush(BackgroundBrushMode.erase),
        brush(BackgroundBrushMode.restore),
      ]);
      expect(restored.getPixel(50, 40).a, 200);
      expect(restored.getPixel(50, 40).r, closeTo(160, 2));
      expect(restored.getPixel(50, 40).g, closeTo(80, 2));
    },
  );

  test(
    'restore works after automatic removal and continuous stroke fills overlap',
    () async {
      final restored = await raster([
        brush(
          BackgroundBrushMode.restore,
          points: const [Offset(.2, .5), Offset(.8, .5)],
        ),
      ], initialAlpha: 0);
      for (final x in [20, 30, 50, 70, 80]) {
        expect(restored.getPixel(x, 40).a, 200, reason: 'restore x=$x');
      }
      expect(restored.getPixel(50, 5).a, 0);
    },
  );

  test(
    'brush mapping uses fitted photo coordinates and output dimensions are bounded',
    () {
      final rect = backgroundRefineImageRect(
        const Size(300, 600),
        const Size(400, 200),
      );
      expect(backgroundRefinePoint(rect.center, rect), const Offset(.5, .5));
      expect(
        backgroundRefinePoint(
          Offset(rect.left + rect.width * .25, rect.top + rect.height * .75),
          rect,
        ),
        const Offset(.25, .75),
      );
      expect(
        backgroundRefinePoint(Offset(rect.left, rect.top - 2), rect),
        isNull,
      );
      final capped = backgroundRefineOutputSize(6000, 6000);
      expect(
        capped.width * capped.height,
        lessThanOrEqualTo(backgroundRefineMaxPixels),
      );
      expect(
        backgroundRefineOutputSize(6000, 3000).width,
        lessThanOrEqualTo(4096),
      );
      expect(backgroundRefineOutputSize(100, 80), const Size(100, 80));
    },
  );

  test(
    'undo redo branching keeps immutable stroke snapshots and video maps',
    () {
      final history = BackgroundBrushHistory();
      final points = [const Offset(.4, .6)];
      final stroke = BackgroundBrushStroke(
        mode: BackgroundBrushMode.erase,
        radius: .03,
        points: points,
      );
      history.add(stroke);
      points.clear();
      expect(history.strokes.single.points, const [Offset(.4, .6)]);
      expect(history.strokes.single.toMap(), {
        'mode': 'erase',
        'radius': .03,
        'points': [
          {'x': .4, 'y': .6},
        ],
      });
      history.undo();
      expect(history.canRedo, true);
      history.redo();
      expect(history.strokes.length, 1);
      history.undo();
      history.add(brush(BackgroundBrushMode.restore));
      expect(history.canRedo, false);
    },
  );

  test(
    'saved manual brushes round trip and reject malformed nonfinite coordinates',
    () {
      final original = brush(
        BackgroundBrushMode.restore,
        points: const [Offset(.25, .75), Offset(.5, .5)],
      );
      expect(
        BackgroundBrushStroke.fromMap(original.toMap()).toMap(),
        original.toMap(),
      );
      expect(
        () => BackgroundBrushStroke.fromMap({
          ...original.toMap(),
          'radius': double.nan,
        }),
        throwsFormatException,
      );
      expect(
        () => BackgroundBrushStroke.fromMap({
          ...original.toMap(),
          'points': [
            {'x': double.infinity, 'y': .5},
          ],
        }),
        throwsFormatException,
      );
      expect(
        () => BackgroundBrushStroke.fromMap({
          ...original.toMap(),
          'mode': 'unknown',
        }),
        throwsFormatException,
      );
    },
  );

  Future<File> createSource(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final folder = await Directory.systemTemp.createTemp(
          'background-refine-',
        );
        addTearDown(() => folder.delete(recursive: true));
        final image = img.Image(width: 100, height: 80, numChannels: 4);
        for (final pixel in image) {
          pixel.setRgba(160, 80, 30, 200);
        }
        return File('${folder.path}/source.png')
          ..writeAsBytesSync(img.encodePng(image));
      }))!;

  Future<void> loaded(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump();
      if (find
          .byKey(const ValueKey('background-refine-canvas'))
          .evaluate()
          .isNotEmpty) {
        return;
      }
    }
    fail('Manual cutout did not load');
  }

  testWidgets(
    'brush preview is live, undo/redo works, and Apply returns refined local PNG',
    (tester) async {
      final source = await createSource(tester);
      String? result;
      List<BackgroundBrushStroke>? applied;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => BackgroundRefineScreen(
                        originalPath: source.path,
                        onApplied: (strokes) => applied = strokes,
                      ),
                    ),
                  );
                },
                child: const Text('Open cutout'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open cutout'));
      await tester.pump(const Duration(milliseconds: 350));
      await loaded(tester);
      await tester.pumpAndSettle();
      final canvas = find.byKey(const ValueKey('background-refine-canvas'));
      final originalTexture =
          tester.widget<CustomPaint>(canvas).painter!
              as BackgroundRefinePainter;
      await tester.tapAt(tester.getCenter(canvas));
      await tester.pump();
      var painter =
          tester.widget<CustomPaint>(canvas).painter!
              as BackgroundRefinePainter;
      expect(identical(painter.original, originalTexture.original), true);
      expect(painter.strokes.single.points.single.dx, closeTo(.5, .01));
      await tester.tap(find.byTooltip('Undo brush'));
      await tester.pump();
      painter =
          tester.widget<CustomPaint>(canvas).painter!
              as BackgroundRefinePainter;
      expect(painter.strokes, isEmpty);
      await tester.tap(find.byTooltip('Redo brush'));
      await tester.pump();
      expect(
        (tester.widget<CustomPaint>(canvas).painter! as BackgroundRefinePainter)
            .strokes
            .length,
        1,
      );
      await tester.tap(find.byTooltip('Apply cutout'));
      for (var i = 0; i < 50 && result == null; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(applied!.length, 1);
      final bytes = (await tester.runAsync(() => File(result!).readAsBytes()))!;
      final cutout = img.decodePng(bytes)!;
      expect((cutout.width, cutout.height), (100, 80));
      expect(cutout.getPixel(50, 40).a, lessThan(60));
      expect(cutout.getPixel(5, 5).a, 200);
      expect(File(source.path).existsSync(), true);
    },
  );

  testWidgets('reopened manual refinement seeds strokes and supports undo', (
    tester,
  ) async {
    final source = await createSource(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: BackgroundRefineScreen(
          originalPath: source.path,
          initialStrokes: [brush(BackgroundBrushMode.erase)],
        ),
      ),
    );
    await loaded(tester);
    final canvas = find.byKey(const ValueKey('background-refine-canvas'));
    expect(
      (tester.widget<CustomPaint>(canvas).painter! as BackgroundRefinePainter)
          .strokes
          .length,
      1,
    );
    await tester.tap(find.byTooltip('Undo brush'));
    await tester.pump();
    expect(
      (tester.widget<CustomPaint>(canvas).painter! as BackgroundRefinePainter)
          .strokes,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zoomed brush points map back to original source coordinates', (
    tester,
  ) async {
    final source = await createSource(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: BackgroundRefineScreen(originalPath: source.path),
      ),
    );
    await loaded(tester);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.identity()
      ..translateByDouble(-70, -40, 0, 1)
      ..scaleByDouble(1.3, 1.3, 1, 1);
    await tester.pump();
    final canvas = find.byKey(const ValueKey('background-refine-canvas'));
    final painter =
        tester.widget<CustomPaint>(canvas).painter! as BackgroundRefinePainter;
    final point = Offset(
      painter.imageRect!.left + painter.imageRect!.width * .4,
      painter.imageRect!.top + painter.imageRect!.height * .6,
    );
    final box = tester.renderObject<RenderBox>(canvas);
    await tester.tapAt(box.localToGlobal(point));
    await tester.pump();
    final after =
        tester.widget<CustomPaint>(canvas).painter! as BackgroundRefinePainter;
    expect(after.strokes.single.points.single.dx, closeTo(.4, .001));
    expect(after.strokes.single.points.single.dy, closeTo(.6, .001));
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('manual toolbar fits $size at large text size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = await createSource(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: BackgroundRefineScreen(originalPath: source.path),
        ),
      );
      await loaded(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
