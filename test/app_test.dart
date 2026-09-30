import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/app/app.dart';
import 'package:framelab/app/providers.dart';
import 'package:framelab/features/projects/domain/project_repository.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
  bool reducedMotion = false,
  ProjectRepository? projects,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: reducedMotion);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  await tester.pumpWidget(
    ProviderScope(
      // Make retry user-driven and deterministic for the repository error test.
      retry: (retryCount, error) => null,
      overrides: [
        if (projects != null)
          projectRepositoryProvider.overrideWithValue(projects),
      ],
      child: const FrameLabApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final tab in ['Projects', 'Pro']) {
    testWidgets('system Back from $tab returns to Home', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('New photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('guest can launch and browse Projects and Pro without signup', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('FrameLab'), findsOneWidget);
    expect(find.text('New photo'), findsOneWidget);
    expect(find.text('New video'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(find.text('A fresh canvas'), findsOneWidget);

    await tester.tap(find.text('Pro'));
    await tester.pumpAndSettle();
    expect(find.text('You’re on Free. No account needed.'), findsOneWidget);
    expect(find.text('₹39/month'), findsOneWidget);
    expect(find.text('₹299/year'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('New photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final entry in [
    ('New photo', 'Untitled photo'),
    ('New video', 'My video'),
    ('Explore', 'Find your starting point'),
  ]) {
    testWidgets('${entry.$2} opens and Back returns home', (tester) async {
      await pumpApp(tester);
      await tapVisible(tester, find.text(entry.$1));
      expect(find.text(entry.$2), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('New photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('roadmap remains reachable from settings', (tester) async {
    await pumpApp(tester);
    await tapVisible(tester, find.text('Your studio. Your files.'));
    await tapVisible(tester, find.text('Build roadmap'));
    expect(find.text('The build roadmap'), findsOneWidget);
    expect(find.text('Architecture + home'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Your studio settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project failure can be retried into real repository data', (
    tester,
  ) async {
    final repository = _FailThenLoadProjects();
    await pumpApp(tester, projects: repository);
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(find.text('Couldn’t load your projects'), findsOneWidget);
    expect(repository.calls, 1);
    await tapVisible(tester, find.text('Retry'));
    expect(repository.calls, 2);
    expect(find.text('Weekend in Jaipur'), findsOneWidget);
    expect(find.text('Couldn’t load your projects'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projects show loading until the local repository completes', (
    tester,
  ) async {
    final repository = _PendingProjects();
    await pumpApp(tester, projects: repository);
    await tester.tap(find.text('Projects'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.result.complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('A fresh canvas'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 568),
    const Size(375, 812),
    const Size(800, 1280),
    const Size(1200, 800),
    const Size(844, 390),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'home and navigation fit ${size.width}x${size.height}, text scale $textScale',
        (tester) async {
          await pumpApp(tester, size: size, textScale: textScale);
          expect(tester.takeException(), isNull);
          await tapVisible(tester, find.text('Your studio. Your files.'));
          expect(find.text('Your studio settings'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Projects'));
          await tester.pumpAndSettle();
          expect(find.text('Your projects'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Pro'));
          await tester.pumpAndSettle();
          expect(find.text('₹39/month'), findsOneWidget);
          await tester.ensureVisible(find.text('Local test mode · no charges'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('reduced-motion home remains usable and settles', (tester) async {
    await pumpApp(tester, reducedMotion: true);
    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.text('New photo'))),
      isTrue,
    );
    await tapVisible(tester, find.text('New photo'));
    expect(find.text('Untitled photo'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('New photo'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _FailThenLoadProjects implements ProjectRepository {
  int calls = 0;
  @override
  Future<List<ProjectSummary>> listRecent() async {
    calls += 1;
    if (calls == 1) throw StateError('Simulated local storage failure');
    return [
      ProjectSummary(
        id: 'test-project',
        title: 'Weekend in Jaipur',
        kind: ProjectKind.video,
        updatedAt: DateTime.utc(2026, 9, 28),
      ),
    ];
  }
}

class _PendingProjects implements ProjectRepository {
  final result = Completer<List<ProjectSummary>>();
  @override
  Future<List<ProjectSummary>> listRecent() => result.future;
}
