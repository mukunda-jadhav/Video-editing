import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/app/providers.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/features/entitlements/data/local_mock_entitlement_repository.dart';
import 'package:framelab/features/entitlements/presentation/premium_screen.dart';

class _Storage implements MockEntitlementStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  Future<LocalMockEntitlementRepository> mount(
    WidgetTester tester, {
    bool enabled = true,
    double scale = 1,
  }) async {
    final repository = LocalMockEntitlementRepository(
      storage: _Storage(),
      enabled: enabled,
    );
    await repository.initialize();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          entitlementRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: const Scaffold(body: PremiumScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  Future<void> openBuy(WidgetTester tester) async {
    final buy = find.text('Buy monthly Pro · test only');
    await tester.ensureVisible(buy);
    await tester.tap(buy);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'browsing Pro never asks for signup; Keep Free dismisses purchase intent',
    (tester) async {
      await mount(tester);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Local test mode · no charges'), findsOneWidget);
      await openBuy(tester);
      expect(
        find.widgetWithText(TextFormField, 'Email for local test'),
        findsOneWidget,
      );
      expect(find.textContaining('No email is sent'), findsOneWidget);
      await tester.tap(find.text('Keep Free'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    },
  );

  testWidgets(
    'invalid email stays inline; displayed test code activates local-only Pro',
    (tester) async {
      final repository = await mount(tester);
      await openBuy(tester);
      await tester.enterText(find.byType(TextFormField), 'invalid');
      await tester.tap(find.text('Generate test code'));
      // A focused TextField's caret intentionally blinks, so settle only the
      // validation frame while the checkout dialog remains open.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(repository.current.isProAt(DateTime.now()), isFalse);
      await tester.enterText(find.byType(TextFormField), 'tester@example.com');
      await tester.tap(find.text('Generate test code'));
      await tester.pump(const Duration(milliseconds: 300));
      final display = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      final code = RegExp(r'\d{6}').firstMatch(display.data!)!.group(0)!;
      await tester.enterText(find.byType(TextFormField), code);
      await tester.tap(find.text('Activate test Pro · no charges'));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(repository.current.isProAt(DateTime.now()), isTrue);
      expect(find.text('Local test Pro is active'), findsOneWidget);
      expect(find.textContaining('No money was charged'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await repository.dispose();
    },
  );

  testWidgets(
    'disabled release test adapter keeps purchase controls disabled',
    (tester) async {
      await mount(tester, enabled: false);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Buy monthly Pro · test only'),
      );
      expect(button.onPressed, isNull);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('Restore local test purchase'), findsNothing);
    },
  );

  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets(
      'Pro checkout scrolls at $size with large text and reduced motion',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, scale: 1.8);
        await openBuy(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Keep Free'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
