import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/core/theme/app_theme.dart';
import 'package:framelab/core/widgets/filter_strip.dart';

void main() {
  const options = [
    FilterOption(value: 'Original', label: 'Original', group: 'Essentials'),
    FilterOption(value: 'Warm', label: 'Warm', group: 'Portrait'),
    FilterOption(value: 'Noir', label: 'Noir', group: 'Film'),
  ];
  Widget screen({
    ValueChanged<String>? onSelected,
    ValueChanged<double>? onChanged,
    VoidCallback? onEnd,
    TextScaler scaler = TextScaler.noScaling,
  }) => MaterialApp(
    theme: AppTheme.dark,
    home: MediaQuery(
      data: MediaQueryData(textScaler: scaler),
      child: Scaffold(
        body: SingleChildScrollView(
          child: FilterStrip<String>(
            options: options,
            selected: 'Original',
            onSelected: onSelected ?? (_) {},
            previewBuilder: (value) => ColoredBox(
              color: value == 'Warm' ? Colors.orange : Colors.grey,
            ),
            intensity: .7,
            onIntensityChanged: onChanged ?? (_) {},
            onIntensityChangeEnd: onEnd ?? () {},
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'category browsing preserves selection and tap applies the look',
    (tester) async {
      String? picked;
      await tester.pumpWidget(screen(onSelected: (v) => picked = v));
      await tester.tap(find.text('Portrait'));
      await tester.pump();
      expect(find.byKey(const ValueKey('filter-Warm')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-Original')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('filter-Warm')));
      expect(picked, 'Warm');
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(find.byKey(const ValueKey('filter-Original')), findsOneWidget);
    },
  );

  testWidgets('strength gives live values and commits once at release', (
    tester,
  ) async {
    var commits = 0;
    final values = <double>[];
    await tester.pumpWidget(
      screen(onChanged: values.add, onEnd: () => commits++),
    );
    final slider = find.byKey(const ValueKey('filter-strength'));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(values, isNotEmpty);
    expect(commits, 0);
    await gesture.up();
    expect(commits, 1);
  });

  testWidgets('small landscape and large text have no overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(screen(scaler: const TextScaler.linear(2)));
    expect(tester.takeException(), isNull);
  });
}
