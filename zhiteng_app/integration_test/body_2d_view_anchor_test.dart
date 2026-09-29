import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/features/record/body_annotate_page.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/features/record/widgets/schematic_body_locator.dart';

// End-to-end failure modes covered before the implementation change:
// - a canonical 2D turn enlarges the body along the old chord transition;
// - a newer view tap must continue from the visible in-flight turn frame;
// - front -> side -> back accumulates lossy edge projections;
// - returning to the original view does not restore the placed body point;
// - a mask finishing late rebases the point and changes a later view;
// - saving immediately after a turn persists a transient screen coordinate.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    '2D point stays anchored while the body changes view',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      final report = <String, dynamic>{
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'checks': <Map<String, dynamic>>[],
      };
      final checks = report['checks'] as List<Map<String, dynamic>>;
      binding.reportData = report;

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: buildLightTheme(),
          home: const Scaffold(body: Center(child: Text('2D anchor E2E host'))),
        ),
      );

      final saved = navigator.currentState!.push<PainSpotDraft>(
        MaterialPageRoute(
          builder: (_) => const BodyAnnotatePage(initial: _spot),
        ),
      );
      await _wait(tester, () => find.text('保存修改').evaluate().isNotEmpty);
      await tester.pump(const Duration(seconds: 2));

      final initial = _point(tester);
      final initialScale = _bodyScale(tester);
      checks.add({'view': 'front-before', 'point': initial});
      await binding.takeScreenshot('2d-anchor-front-before');

      await tester.tap(find.text('左侧'));
      await tester.pump(const Duration(milliseconds: 170));
      final midpointScale = _bodyScale(tester);
      expect(midpointScale, closeTo(initialScale, initialScale * 0.02));
      checks.add({
        'view': 'turn-midpoint',
        'scale': midpointScale,
        'initialScale': initialScale,
      });
      await tester.tap(find.text('正面'));
      await tester.pump(const Duration(milliseconds: 400));

      for (final target in const [
        ('左侧', 'left'),
        ('右侧', 'right'),
        ('背面', 'back'),
        ('正面', 'front'),
      ]) {
        await tester.tap(find.text(target.$1));
        await tester.pump(const Duration(milliseconds: 96));
        expect(_bodyScale(tester), closeTo(initialScale, initialScale * 0.02));
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(_locator(tester).view, 'front');
      expect(_point(tester)[0], closeTo(initial[0], 1e-7));
      expect(_point(tester)[1], closeTo(initial[1], 1e-7));
      checks.add({
        'view': 'rapid-turns-returned',
        'scale': _bodyScale(tester),
        'point': _point(tester),
      });

      for (final target in const [('左侧', 'left'), ('背面', 'back')]) {
        await tester.tap(find.text(target.$1));
        await tester.pump(const Duration(milliseconds: 850));
        final locator = _locator(tester);
        expect(locator.view, target.$2);
        checks.add({'view': target.$2, 'point': _point(tester)});
        await binding.takeScreenshot('2d-anchor-${target.$2}');
      }

      await tester.tap(find.text('正面'));
      await tester.pump(const Duration(milliseconds: 850));
      final returned = _point(tester);
      expect(returned[0], closeTo(initial[0], 1e-7));
      expect(returned[1], closeTo(initial[1], 1e-7));
      checks.add({'view': 'front-returned', 'point': returned});
      await binding.takeScreenshot('2d-anchor-front-returned');

      await tester.tap(find.text('保存修改'));
      await _wait(
        tester,
        () => find.byType(BodyAnnotatePage).evaluate().isEmpty,
      );
      final result = await saved;
      expect(result, isNotNull);
      expect(result!.view, 'front');
      expect(result.x, closeTo(initial[0], 1e-7));
      expect(result.y, closeTo(initial[1], 1e-7));
      checks.add({
        'view': 'saved',
        'point': [result.x, result.y],
      });
      report['passed'] = true;
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

const _spot = PainSpotDraft(
  id: 'body-2d-view-anchor-e2e',
  x: 0.38,
  y: 0.42,
  view: 'front',
  layer: BodyLayer.skin,
  shape: PainShape.point,
  region: BodyRegion.full,
  partName: '腹部',
  bodyPartId: 'abdomen',
  markerScale: 1,
  lineLength: 1,
  lineAngle: 0,
  depthState: 'surface',
  use3d: false,
);

SchematicBodyLocator _locator(WidgetTester tester) =>
    tester.widget<SchematicBodyLocator>(find.byType(SchematicBodyLocator));

List<double> _point(WidgetTester tester) => [
  _locator(tester).x,
  _locator(tester).y,
];

double _bodyScale(WidgetTester tester) {
  final transforms = find.descendant(
    of: find.byType(SchematicBodyLocator),
    matching: find.byType(Transform),
  );
  expect(transforms, findsOneWidget);
  return tester.widget<Transform>(transforms).transform.getMaxScaleOnAxis();
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final until = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(until)) {
      throw TestFailure('Timed out waiting for the 2D body route');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
