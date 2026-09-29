import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/features/record/body_annotate_page.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/features/record/widgets/body_3d_webview.dart';
import 'package:zhiteng_app/features/record/widgets/marker_controls.dart';
import 'package:zhiteng_app/features/record/widgets/schematic_body_locator.dart';

// Run only on an iOS/Android device: the real asset server, GLBs, WebView,
// renderer and navigation are exercised. No repository/database is modified.
// Failure modes to cover before implementation:
// - rapid presses drop the last movement or leave an unbounded command queue;
// - interrupted holds keep repeating after release, mode switch or inactivity;
// - an older mask/layer load overwrites the last view/anatomy selection;
// - expensive surface redraws prevent unrelated controls from responding;
// - saving immediately captures stale coordinates or slider values.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    '2D and 3D controls retain final input under bursts',
    (tester) async {
      final report = <String, dynamic>{
        'startedAt': DateTime.now().toUtc().toIso8601String(),
        'scope': 'real annotation routes; no user database writes',
        'checks': <Map<String, dynamic>>[],
      };
      binding.reportData = report;
      final checks = report['checks'] as List<Map<String, dynamic>>;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: buildLightTheme(),
          home: const Scaffold(body: Center(child: Text('E2E route host'))),
        ),
      );

      Future<PainSpotDraft?> open(PainSpotDraft initial) {
        return navigator.currentState!.push<PainSpotDraft>(
          MaterialPageRoute(builder: (_) => BodyAnnotatePage(initial: initial)),
        );
      }

      try {
        final saved2d = open(_fixture(use3d: false));
        await _wait(tester, () => find.text('保存修改').evaluate().isNotEmpty);
        await tester.pump(const Duration(seconds: 2));
        await _openTools(tester);
        final before2d = _locator(tester);
        for (var i = 0; i < 12; i++) {
          await tester.tap(_button('向右移动'));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 600));
        expect(_locator(tester).x, greaterThan(before2d.x));
        checks.add({'check': '2d_rapid_position', 'x': _locator(tester).x});

        // Every transition starts before the preceding 340 ms animation ends.
        for (final view in ['左侧', '背面', '正面', '右侧', '正面']) {
          await tester.tap(find.text(view));
          await tester.pump(const Duration(milliseconds: 32));
        }
        await tester.pump(const Duration(milliseconds: 850));
        expect(_locator(tester).view, 'front');
        expect(
          tester.widget<BodyViewSegment>(find.byType(BodyViewSegment)).value,
          'front',
        );
        final afterViews = _xy(tester);
        await tester.pump(const Duration(milliseconds: 650));
        expect(
          _xy(tester),
          afterViews,
          reason: 'An older mask must not retarget the mark',
        );
        checks.add({
          'check': '2d_last_view_wins',
          'view': 'front',
          'xy': afterViews,
        });

        final hold2d = await tester.startGesture(
          tester.getCenter(_button('向上移动')),
        );
        await tester.pump(const Duration(milliseconds: 760));
        await hold2d.up();
        await tester.pump(const Duration(milliseconds: 250));
        final released2d = _xy(tester);
        await tester.pump(const Duration(milliseconds: 650));
        expect(_xy(tester), released2d, reason: 'Release must cancel repeats');
        checks.add({'check': '2d_hold_release_stable', 'xy': released2d});

        final interrupted = await tester.startGesture(
          tester.getCenter(_button('向下移动')),
        );
        await tester.pump(const Duration(milliseconds: 400));
        // Deliver the OS lifecycle notification through the real binding.
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await tester.pump(const Duration(milliseconds: 200));
        final paused = _xy(tester);
        await tester.pump(const Duration(milliseconds: 600));
        expect(
          _xy(tester),
          paused,
          reason: 'Inactive app must stop held buttons',
        );
        await interrupted.up();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pump(const Duration(milliseconds: 200));
        checks.add({'check': '2d_inactive_hold_stops', 'xy': paused});

        await _dragSlider(tester, _sideSlider('长短'), vertical: true);
        await _dragSlider(tester, _sideSlider('粗细'), vertical: true);
        await _dragSlider(tester, _angleSlider(), vertical: false);
        final final2d = _locator(tester);
        await binding.takeScreenshot('2d-after-burst');
        await tester.tap(find.text('保存修改'));
        await _wait(
          tester,
          () => find.byType(BodyAnnotatePage).evaluate().isEmpty,
        );
        final result2d = await saved2d;
        expect(result2d, isNotNull);
        expect(result2d!.view, final2d.view);
        expect(result2d.x, closeTo(final2d.x, 1e-7));
        expect(result2d.y, closeTo(final2d.y, 1e-7));
        expect(result2d.markerScale, closeTo(final2d.markerScale, 1e-7));
        expect(result2d.lineLength, closeTo(final2d.lineLength, 1e-7));
        expect(result2d.lineAngle, closeTo(final2d.lineAngle, 1e-7));
        checks.add({
          'check': '2d_save_retains_controls',
          'saved': _saved(result2d),
        });

        final saved3d = open(_fixture(use3d: true));
        await _wait(
          tester,
          () => find.byType(WebViewWidget).evaluate().isNotEmpty,
        );
        await _waitScene(
          tester,
          (s) => s['ready'] == true && s['marker'] != null,
          timeout: const Duration(seconds: 90),
        );
        await _openTools(tester);
        await _waitScene(tester, (s) => s['surfacePending'] == false);
        final initial3d = await _scene(tester);

        // Cold organ request interleaved with a different anatomy selection.
        for (final layer in ['器官', '骨骼', '肌肉', '器官']) {
          await tester.tap(find.text(layer).first);
          await tester.pump(const Duration(milliseconds: 40));
        }
        await _waitScene(
          tester,
          (s) => (s['layers'] as List).contains('organ'),
          timeout: const Duration(seconds: 90),
        );
        for (final group in ['心脏', '肺', '泌尿', '心脏']) {
          final item = find.text(group);
          await tester.ensureVisible(item);
          await tester.tap(item);
          await tester.pump(const Duration(milliseconds: 40));
        }
        await _waitScene(
          tester,
          (s) => s['organGroup'] == 'heart' && s['surfacePending'] == false,
        );
        expect(
          tester.widget<Body3dWebView>(find.byType(Body3dWebView)).organGroup,
          'heart',
        );
        checks.add({
          'check': '3d_cold_layers_last_group_wins',
          'state': await _scene(tester),
        });

        // Warm anatomy/view changes must not let old asynchronous work win.
        for (final layer in ['骨骼', '肌肉', '器官', '肌肉']) {
          await tester.tap(find.text(layer).first);
          await tester.pump(const Duration(milliseconds: 32));
        }
        for (final view in ['背面', '左侧', '右侧', '背面', '正面']) {
          await tester.tap(find.text(view));
          await tester.pump(const Duration(milliseconds: 32));
        }
        await _waitScene(
          tester,
          (s) =>
              s['view'] == 'front' &&
              (s['layers'] as List).contains('muscle') &&
              s['surfacePending'] == false,
        );
        expect(
          tester.widget<BodyViewSegment>(find.byType(BodyViewSegment)).value,
          'front',
        );
        checks.add({
          'check': '3d_warm_layers_view_last_wins',
          'state': await _scene(tester),
        });

        // Cross-control bursts include movement and depth while line draping is active.
        final start3d = await _scene(tester);
        for (var i = 0; i < 8; i++) {
          await tester.tap(_button(i.isEven ? '向右移动' : '向上移动'));
          await tester.pump(const Duration(milliseconds: 18));
        }
        for (var i = 0; i < 3; i++) {
          await tester.tap(_button('往体内移'));
          await tester.pump(const Duration(milliseconds: 18));
        }
        await _waitScene(tester, (s) => s['surfacePending'] == false);
        final moved3d = await _scene(tester);
        expect(moved3d['marker'], isNot(start3d['marker']));
        expect((moved3d['marker'] as Map)['depth'], greaterThan(0));
        final hold3d = await tester.startGesture(
          tester.getCenter(_button('向左移动')),
        );
        await tester.pump(const Duration(milliseconds: 720));
        await hold3d.up();
        await tester.pump(const Duration(milliseconds: 400));
        final released3d = (await _scene(tester))['marker'];
        await tester.pump(const Duration(milliseconds: 700));
        expect(
          (await _scene(tester))['marker'],
          released3d,
          reason: '3D hold release must not leave queued/ghost movement',
        );
        checks.add({
          'check': '3d_burst_and_hold_release',
          'state': await _scene(tester),
        });

        await _dragSlider(tester, _sideSlider('长短'), vertical: true);
        await _dragSlider(tester, _angleSlider(), vertical: false);
        await _dragSlider(tester, _sideSlider('粗细'), vertical: true);
        final expected = tester.widget<Body3dWebView>(
          find.byType(Body3dWebView),
        );
        await _waitScene(
          tester,
          (s) =>
              ((s['markerScale'] as num) - expected.markerScale).abs() < 1e-7 &&
              ((s['lineLength'] as num) - expected.lineLength).abs() < 1e-7 &&
              ((s['lineAngle'] as num) - expected.lineAngle).abs() < 1e-7 &&
              s['surfacePending'] == false,
        );
        await binding.takeScreenshot('3d-after-burst');

        // Save in the same frame as the final adjustment, without a settle delay.
        final depthBeforeSave =
            ((await _scene(tester))['marker'] as Map)['depth'] as num;
        await tester.tap(_button('往体内移'));
        await tester.tap(find.text('保存修改'));
        await _wait(
          tester,
          () => find.byType(BodyAnnotatePage).evaluate().isEmpty,
          timeout: const Duration(seconds: 20),
        );
        final result3d = await saved3d;
        expect(result3d, isNotNull);
        expect(result3d!.has3d, isTrue);
        expect(result3d.markerScale, closeTo(expected.markerScale, 1e-7));
        expect(result3d.lineLength, closeTo(expected.lineLength, 1e-7));
        expect(result3d.lineAngle, closeTo(expected.lineAngle, 1e-7));
        expect(
          result3d.depthMeters,
          greaterThan(depthBeforeSave),
          reason: 'Save must flush the final depth press',
        );
        checks.add({
          'check': '3d_save_immediately_flushes',
          'saved': _saved(result3d),
          'initialRenderer': initial3d,
        });

        final reopened = open(result3d);
        await _waitScene(
          tester,
          (s) => s['ready'] == true && s['marker'] != null,
          timeout: const Duration(seconds: 90),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('保存修改'));
        await _wait(
          tester,
          () => find.byType(BodyAnnotatePage).evaluate().isEmpty,
        );
        final resultAgain = await reopened;
        expect(resultAgain!.depthMeters, closeTo(result3d.depthMeters!, 1e-7));
        expect(resultAgain.lineAngle, closeTo(result3d.lineAngle, 1e-7));
        checks.add({
          'check': '3d_reopen_preserves_final',
          'saved': _saved(resultAgain),
        });
        expect(tester.takeException(), isNull);
        report['passed'] = true;
      } catch (error, stack) {
        report['passed'] = false;
        report['error'] = error.toString();
        report['stack'] = stack.toString();
        try {
          await binding.takeScreenshot('failure');
        } catch (_) {
          // Keep the original failure if the device cannot take a screenshot.
        }
        rethrow;
      } finally {
        report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}

PainSpotDraft _fixture({required bool use3d}) => PainSpotDraft(
  id: 'control-responsiveness-${use3d ? '3d' : '2d'}',
  x: 0.5,
  y: 0.4,
  view: 'front',
  layer: BodyLayer.skin,
  shape: PainShape.line,
  region: BodyRegion.full,
  partName: '腹部',
  bodyPartId: 'abdomen',
  markerScale: 1,
  lineLength: 1,
  lineAngle: 0,
  depthState: 'surface',
  use3d: use3d,
  localX: use3d ? 0 : null,
  localY: use3d ? 0.2 : null,
  localZ: use3d ? 0.1 : null,
  depthMeters: use3d ? 0 : null,
  shownAnatomy: use3d ? BodyLayer.muscle : null,
);

Finder _button(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
);

Finder _sideSlider(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_SideScale',
    ),
  ),
  matching: find.byType(Slider),
);

Finder _angleSlider() => find.byWidgetPredicate(
  (widget) =>
      widget is Slider && widget.min == -math.pi && widget.max == math.pi,
);

SchematicBodyLocator _locator(WidgetTester tester) =>
    tester.widget<SchematicBodyLocator>(find.byType(SchematicBodyLocator));
List<double> _xy(WidgetTester tester) => [
  _locator(tester).x,
  _locator(tester).y,
];

Future<void> _openTools(WidgetTester tester) async {
  if (_button('向上移动').evaluate().isNotEmpty) return;
  await tester.tap(find.textContaining('疼痛模式'));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _dragSlider(
  WidgetTester tester,
  Finder slider, {
  required bool vertical,
}) async {
  final gesture = await tester.startGesture(tester.getCenter(slider));
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(vertical ? const Offset(0, -4) : const Offset(3, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pump();
}

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 12),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for UI after $timeout');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<Map<String, dynamic>> _scene(WidgetTester tester) async {
  final controller = tester
      .widget<WebViewWidget>(find.byType(WebViewWidget))
      .platform
      .params
      .controller;
  final result = await controller.runJavaScriptReturningResult(
    'JSON.stringify(window.ZhitengBridge?.controlsState?.() || {})',
  );
  dynamic decoded = result is String ? jsonDecode(result) : result;
  if (decoded is String) decoded = jsonDecode(decoded);
  return Map<String, dynamic>.from(decoded as Map);
}

Future<void> _waitScene(
  WidgetTester tester,
  bool Function(Map<String, dynamic>) ready, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  Map<String, dynamic> last = {};
  while (true) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(WebViewWidget).evaluate().isNotEmpty) {
      last = await _scene(tester);
      if (last.isNotEmpty && ready(last)) return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail('Renderer did not settle after $timeout: $last');
    }
  }
}

Map<String, dynamic> _saved(PainSpotDraft spot) => {
  'view': spot.view,
  'region': spot.region.wire,
  'use3d': spot.use3d,
  'x': spot.x,
  'y': spot.y,
  'localX': spot.localX,
  'localY': spot.localY,
  'localZ': spot.localZ,
  'depth': spot.depthMeters,
  'scale': spot.markerScale,
  'length': spot.lineLength,
  'angle': spot.lineAngle,
};
