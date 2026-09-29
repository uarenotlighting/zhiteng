import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/features/record/body_annotate_page.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/features/record/widgets/body_3d_webview.dart';

// End-to-end failure modes covered before the implementation change:
// - even one canonical turn visibly zooms in along its straight-line chord;
// - an interrupted view turn promotes its temporary close-up to final zoom;
// - repeated rapid turns ratchet the camera closer on every interruption;
// - a clear-band/layout reframe freezes an in-flight turn at its close-up;
// - the selected view settles correctly while camera distance stays wrong;
// - only Reset can restore the original frame after the burst.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'rapid 3D view changes return to the established zoom',
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
          home: const Scaffold(body: Center(child: Text('3D view E2E host'))),
        ),
      );
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => const BodyAnnotatePage(initial: _spot),
        ),
      );

      await _wait(
        tester,
        () => find.byType(WebViewWidget).evaluate().isNotEmpty,
      );
      await _waitFrame(tester);
      await tester.pump(const Duration(milliseconds: 700));
      final initial = await _frame(tester);
      checks.add(_check('initial', initial));
      await binding.takeScreenshot('3d-rapid-view-initial');

      await tester.tap(find.text('左侧'));
      await _realDelay(tester, const Duration(milliseconds: 170));
      final turnMidpoint = await _frame(tester);
      expect(turnMidpoint.zoom, closeTo(initial.zoom, 0.02));
      checks.add(_check('turn-midpoint', turnMidpoint));
      await _realDelay(tester, const Duration(milliseconds: 400));
      await tester.tap(find.text('正面'));
      await _realDelay(tester, const Duration(milliseconds: 400));

      await _burst(tester, const [
        '左侧',
        '右侧',
        '背面',
        '正面',
        '背面',
        '左侧',
        '右侧',
        '正面',
        '左侧',
        '背面',
        '右侧',
        '正面',
      ]);
      final first = await _frame(tester);
      expect(first.zoom, closeTo(initial.zoom, 0.02));
      checks.add(_check('first-burst', first));

      await _burst(tester, const [
        '背面',
        '正面',
        '右侧',
        '左侧',
        '背面',
        '右侧',
        '左侧',
        '正面',
        '右侧',
        '背面',
        '左侧',
        '正面',
      ]);
      final second = await _frame(tester);
      expect(second.zoom, closeTo(initial.zoom, 0.02));
      checks.add(_check('second-burst', second));

      // Reproduce the real page race deterministically: the top/bottom chrome
      // is measured after layout and can change while a view turn is running.
      final body = tester.widget<Body3dWebView>(find.byType(Body3dWebView));
      await tester.tap(find.text('背面'));
      await _realDelay(tester, const Duration(milliseconds: 96));
      await _state(
        tester,
      ).setStageChrome(body.topChrome + 18, body.bottomChrome + 12);
      await _realDelay(tester, const Duration(milliseconds: 80));
      await _burst(tester, const ['左侧', '正面', '右侧', '正面']);
      final reframed = await _frame(tester);
      expect(reframed.zoom, closeTo(initial.zoom, 0.02));
      checks.add(_check('layout-reframe-during-turn', reframed));

      await _state(tester).setStageChrome(body.topChrome, body.bottomChrome);
      await _realDelay(tester, const Duration(milliseconds: 500));
      final restoredChrome = await _frame(tester);
      expect(restoredChrome.zoom, closeTo(initial.zoom, 0.02));
      expect(restoredChrome.distance, closeTo(initial.distance, 0.02));
      checks.add(_check('restored-layout', restoredChrome));
      await binding.takeScreenshot('3d-rapid-view-settled');

      report['passed'] = true;
      report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

const _spot = PainSpotDraft(
  id: 'body-3d-rapid-view-e2e',
  x: 0.5,
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
  use3d: true,
  localX: 0,
  localY: 0.95,
  localZ: 0.12,
  depthMeters: 0,
  shownAnatomy: BodyLayer.muscle,
);

Future<void> _burst(WidgetTester tester, List<String> views) async {
  for (final view in views) {
    await tester.tap(find.text(view));
    // The WebView bridge coalesces camera commands for 64 ms. A 16 ms test
    // only exercised the last coalesced value, unlike a person's fast taps.
    // 96 ms dispatches every turn while still interrupting its 340 ms motion.
    await _realDelay(tester, const Duration(milliseconds: 96));
  }
  await _realDelay(tester, const Duration(milliseconds: 850));
}

Future<void> _realDelay(WidgetTester tester, Duration duration) async {
  // Three.js uses WebView performance.now(), not Flutter's fake test clock.
  await Future<void>.delayed(duration);
  await tester.pump();
}

Future<void> _waitFrame(WidgetTester tester) async {
  final until = DateTime.now().add(const Duration(seconds: 90));
  while (await _state(tester).readCameraFrame() == null) {
    if (DateTime.now().isAfter(until)) {
      throw TestFailure('Timed out waiting for the 3D camera frame');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Body3dWebViewState _state(WidgetTester tester) =>
    tester.state<Body3dWebViewState>(find.byType(Body3dWebView));

Future<
  ({
    double zoom,
    double distance,
    double fitDistance,
    double x,
    double y,
    double z,
  })
>
_frame(WidgetTester tester) async {
  final frame = await _state(tester).readCameraFrame();
  if (frame == null) throw TestFailure('3D camera frame is unavailable');
  return frame;
}

Map<String, dynamic> _check(
  String name,
  ({
    double zoom,
    double distance,
    double fitDistance,
    double x,
    double y,
    double z,
  })
  frame,
) => {
  'check': name,
  'zoom': frame.zoom,
  'distance': frame.distance,
  'fitDistance': frame.fitDistance,
  'target': [frame.x, frame.y, frame.z],
};

Future<void> _wait(
  WidgetTester tester,
  bool Function() ready, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final until = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(until)) {
      throw TestFailure('Timed out waiting for the 3D body route');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}
