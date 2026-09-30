import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/features/photo_editor/data/photo_renderer.dart';
import 'package:framelab/features/photo_editor/domain/photo_document.dart';
import 'package:framelab/features/photo_editor/presentation/photo_editor_screen.dart';

void main() {
  Widget editor({
    PhotoDocument? document,
    Future<void> Function(Map<String, dynamic>, String, String?)? save,
    double textScale = 1,
  }) => MaterialApp(
    theme: AppTheme.dark,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: PhotoEditorScreen(
      initialData: document?.toJson(),
      onSave: save ?? (_, title, thumbnail) async {},
      removeBackground: (path) async => path,
      exportBytes: (Uint8List bytes, String name) async => name,
      pickImage: () async => null,
    ),
  );

  for (final scenario in <(Size, double)>[
    (const Size(375, 812), 1),
    (const Size(812, 375), 1),
    (const Size(375, 812), 2.5),
  ]) {
    testWidgets('editor fits ${scenario.$1} at ${scenario.$2} text scale', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(editor(textScale: scenario.$2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      expect(find.text('Import a photo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'a template automatically saves and basic edits stay account-free',
    (tester) async {
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        editor(
          document: PhotoDocument(title: 'Template'),
          save: (data, title, thumbnail) async {
            saves.add(data);
          },
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(saves.single['title'], 'Template');
      await tester.tap(find.text('Crop'));
      await tester.pump();
      await tester.tap(find.text('Flip'));
      await tester.tap(find.text('Rotate 90°'));
      await tester.pump(const Duration(seconds: 1));
      expect(saves.length, 2);
      expect(saves.last['rotation'], 1);
      expect(saves.last['flipHorizontal'], isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('all filters and high-resolution export are freely available', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      editor(
        document: PhotoDocument(width: 64, height: 64),
        save: (data, title, thumbnail) async => saves.add(data),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Filters'));
    await tester.pump();
    await tester.tap(find.text('Fade'));
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last['filter'], 'Fade');
    expect(find.textContaining('Pro'), findsNothing);
    await tester.tap(find.text('Export PNG'));
    await tester.pumpAndSettle();
    expect(find.text('High resolution PNG'), findsOneWidget);
    expect(find.textContaining('Pro'), findsNothing);
    Navigator.of(tester.element(find.text('High resolution PNG'))).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'brightness drag repaints each frame and commits once on release',
    (tester) async {
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        editor(
          document: PhotoDocument(),
          save: (data, title, thumbnail) async => saves.add(data),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      PhotoPainter painter() =>
          (tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('photo-live-preview')),
                  )
                  .painter!
              as PhotoPainter);
      final composition = painter().composition;
      for (final value in [1.15, 1.4, 1.75]) {
        tester
            .widget<Slider>(
              find.byKey(const ValueKey('photo-slider-Brightness')),
            )
            .onChanged!(value);
        await tester.pump(const Duration(milliseconds: 16));
        expect(painter().document.brightness, value);
        expect(painter().composition, same(composition));
        expect(
          photoColorMatrix(painter().document).first,
          closeTo(value, .0001),
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(saves.length, 1, reason: 'A drag must not persist every frame.');
      }
      tester
          .widget<Slider>(find.byKey(const ValueKey('photo-slider-Brightness')))
          .onChangeEnd!(1.75);
      await tester.pump(const Duration(seconds: 1));
      expect(saves.length, 2);
      expect(saves.last['brightness'], 1.75);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(painter().document.brightness, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('crop and layout resize react on the next frame', (tester) async {
    await tester.pumpWidget(editor(document: PhotoDocument()));
    await tester.pump(const Duration(seconds: 1));
    PhotoPainter painter() =>
        (tester
                .widget<CustomPaint>(
                  find.byKey(const ValueKey('photo-live-preview')),
                )
                .painter!
            as PhotoPainter);
    await tester.tap(find.text('Crop'));
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const ValueKey('photo-slider-Left')))
        .onChanged!(.3);
    await tester.pump(const Duration(milliseconds: 16));
    expect(painter().document.cropLeft, .3);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    tester
        .widget<Slider>(find.byKey(const ValueKey('photo-slider-Left')))
        .onChangeEnd!(.3);
    await tester.ensureVisible(find.text('Layout'));
    await tester.tap(find.text('Layout'));
    await tester.pump();
    await tester.tap(find.text('Story / Reel'));
    await tester.pump(const Duration(milliseconds: 16));
    expect(painter().document.width, 1080);
    expect(painter().document.height, 1920);
    final canvasSize = tester.getSize(
      find.byKey(const ValueKey('photo-live-preview')),
    );
    expect(canvasSize.aspectRatio, closeTo(9 / 16, .0001));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('canvas selection supports keyboard movement and undo', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    final doc = PhotoDocument(
      width: 1000,
      height: 1000,
      layers: [
        PhotoLayer(
          id: 'shape',
          kind: 'rect',
          x: .3,
          y: .3,
          width: .4,
          height: .4,
        ),
      ],
    );
    await tester.pumpWidget(
      editor(
        document: doc,
        save: (data, title, thumbnail) async {
          saves.add(data);
        },
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final canvas = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is PhotoPainter,
    );
    // An arrow without a selection must never be replayed when a layer is
    // selected later.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.tapAt(tester.getCenter(canvas));
    // The canvas also supports double-tap text editing. Let the recognizer
    // resolve the single tap and allow its focus request to take effect.
    await tester.pump(kDoubleTapTimeout);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(seconds: 1));
    expect(
      ((saves.last['layers'] as List).first as Map)['x'],
      closeTo(.301, .00001),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(seconds: 1));
    expect(((saves.last['layers'] as List).first as Map)['x'], .3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(seconds: 1));
    expect(
      ((saves.last['layers'] as List).first as Map)['x'],
      closeTo(.301, .00001),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'text remains editable after insertion and saves actual content',
    (tester) async {
      final saves = <Map<String, dynamic>>[];
      await tester.pumpWidget(
        editor(
          save: (data, title, thumbnail) async {
            saves.add(data);
          },
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Text'));
      await tester.pump();
      await tester.tap(find.text('Add text'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Hello FrameLab');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit selected text'));
      await tester.pumpAndSettle();
      expect(find.text('Hello FrameLab'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.enterText(find.byType(TextField), 'A second draft');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(
        ((saves.last['layers'] as List).first as Map)['text'],
        'A second draft',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('canvas resize validates dimensions and closes safely', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      editor(save: (data, title, thumbnail) async => saves.add(data)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Layout'));
    await tester.tap(find.text('Layout'));
    await tester.pump();
    await tester.ensureVisible(find.text('Custom size'));
    await tester.tap(find.text('Custom size'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.tap(find.text('Resize'));
    await tester.pump();
    expect(find.text('Enter dimensions from 64 to 4096.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '1280');
    await tester.enterText(find.byType(TextField).last, '720');
    await tester.tap(find.text('Resize'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(saves.last['width'], 1280);
    expect(saves.last['height'], 720);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Custom size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
