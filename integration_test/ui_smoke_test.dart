import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/photo_editor/presentation/photo_editor_screen.dart';
import 'package:framelab/features/video_editor/presentation/video_editor_screen.dart';
import 'package:framelab/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'guest studio and editable templates work offline on Android',
    (tester) async {
      await app.main();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expect(find.text('New photo'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      final support = await getApplicationSupportDirectory();
      final screenshots = await Directory(
        '${support.path}/qa',
      ).create(recursive: true);
      Future<void> capture(String name) async {
        // Capture Flutter's composited layer without converting the Android
        // surface between interactive steps. Native surface conversion can stall
        // subsequent synthetic taps on some emulator/engine combinations.
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        final image = await boundary
            .toImage(pixelRatio: 2)
            .timeout(const Duration(seconds: 10));
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          await File('${screenshots.path}/$name.png').writeAsBytes(
            data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
        if (const bool.fromEnvironment('CAPTURE_SCREENSHOTS')) {
          final bytes = await File(
            '${screenshots.path}/$name.png',
          ).readAsBytes();
          binding.reportData ??= <String, dynamic>{};
          final images =
              binding.reportData!.putIfAbsent(
                    'screenshots',
                    () => <Map<String, dynamic>>[],
                  )
                  as List<Map<String, dynamic>>;
          images.add({'screenshotName': name, 'bytes': bytes.toList()});
        }
        debugPrint('UI screenshot completed: $name');
      }

      await capture('home');
      await tester.ensureVisible(find.text('Explore'));
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      await capture('templates');
      debugPrint('UI opening editable template');
      await tester.tap(find.text('Everyday studio'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expect(find.byType(PhotoEditorScreen), findsOneWidget);
      expect(find.text('Everyday studio'), findsOneWidget);
      await capture('photo-editor');
      await binding.handlePopRoute();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      await binding.handlePopRoute();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      await tester.ensureVisible(find.text('New video'));
      await tester.tap(find.text('New video'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 20),
      );
      expect(find.byType(VideoEditorScreen), findsOneWidget);
      expect(find.text('Choose videos'), findsOneWidget);
      await capture('video-editor');
      expect(tester.takeException(), isNull);
      debugPrint('Review screenshots saved under ${screenshots.path}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
