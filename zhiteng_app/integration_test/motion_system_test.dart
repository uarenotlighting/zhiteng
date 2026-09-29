import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/features/history/history_detail_page.dart';
import 'package:zhiteng_app/features/record/body_annotate_page.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/widgets/zt_controls.dart';
import 'package:zhiteng_app/widgets/zt_motion.dart';

// End-to-end failure modes covered before this verification was added:
// - Material ripples remain visible on one class of button;
// - press feedback does not reach the 0.96 target or remains stuck after lift;
// - a normal route loses the 300ms OpenContainer transition;
// - a normal detail route cannot be dismissed by a deliberate right swipe;
// - the body-model workbench accidentally inherits swipe-to-dismiss;
// - motion work changes the existing semantic colors or body workflow.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('global motion system preserves route and body behavior', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final report = <String, dynamic>{
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'checks': <String>[],
    };
    final checks = report['checks'] as List<String>;
    binding.reportData = report;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: buildLightTheme(),
        home: const _MotionHost(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final hostContext = tester.element(find.byKey(const ValueKey('host')));
    final theme = Theme.of(hostContext);
    expect(theme.splashFactory, NoSplash.splashFactory);
    expect(theme.splashColor, Colors.transparent);
    expect(theme.highlightColor, Colors.transparent);
    expect(
      theme.textButtonTheme.style?.overlayColor?.resolve({WidgetState.pressed}),
      Colors.transparent,
    );
    checks.add('material tap overlays disabled globally');

    final primary = find.byKey(const ValueKey('primary-action'));
    final attentionMotion = find.descendant(
      of: primary,
      matching: find.byType(ZtAttentionMotion),
    );
    expect(attentionMotion, findsOneWidget);
    expect(tester.widget<ZtAttentionMotion>(attentionMotion).pulse, isFalse);
    expect(tester.widget<ZtAttentionMotion>(attentionMotion).shimmer, isFalse);
    checks.add('primary action breathing and shimmer are both disabled');
    final pressScale = find.descendant(
      of: primary,
      matching: find.byType(AnimatedScale),
    );
    expect(pressScale, findsOneWidget);
    final press = await tester.startGesture(tester.getCenter(primary));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.widget<AnimatedScale>(pressScale).scale, 0.96);
    await press.up();
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.widget<AnimatedScale>(pressScale).scale, 1);
    checks.add('primary action scales to 0.96 and releases to 1.0');
    await binding.takeScreenshot('motion-primary-action');

    final openContainer = find.byWidgetPredicate(
      (widget) => widget is OpenContainer,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open-detail')),
        matching: openContainer,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('open-body')),
        matching: openContainer,
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('open-detail')));
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.text('这次疼痛'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.byType(ZtSwipeBackPage), findsOneWidget);
    checks.add('detail route uses OpenContainer and swipe-back wrapper');

    await tester.timedDragFrom(
      const Offset(8, 320),
      const Offset(124, 0),
      const Duration(milliseconds: 260),
    );
    await tester.pump(const Duration(milliseconds: 380));
    expect(find.byKey(const ValueKey('host')), findsOneWidget);
    expect(find.text('这次疼痛'), findsNothing);
    checks.add('detail route dismisses after a deliberate edge right-swipe');

    await tester.tap(find.byKey(const ValueKey('open-body')));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.byType(BodyAnnotatePage), findsOneWidget);
    expect(find.byType(ZtSwipeBackPage), findsNothing);
    await tester.timedDragFrom(
      const Offset(8, 320),
      const Offset(124, 0),
      const Duration(milliseconds: 260),
    );
    await tester.pump(const Duration(milliseconds: 420));
    expect(find.byType(BodyAnnotatePage), findsOneWidget);
    checks.add(
      'body-model route uses OpenContainer but ignores edge right-swipe',
    );
    await binding.takeScreenshot('motion-body-no-swipe-back');

    await tester.tap(find.text('保存修改'));
    await tester.pump(const Duration(milliseconds: 650));
    expect(find.byKey(const ValueKey('host')), findsOneWidget);
    expect(find.text('motion-e2e-body'), findsOneWidget);
    checks.add('body-model OpenContainer returns the saved pain-spot result');
    report['finishedAt'] = DateTime.now().toUtc().toIso8601String();
  });
}

class _MotionHost extends StatefulWidget {
  const _MotionHost();

  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost> {
  String? _bodyResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('host'),
      appBar: AppBar(title: const Text('动效验证')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ZtButton(
              key: const ValueKey('primary-action'),
              label: '主要操作',
              onPressed: () {},
            ),
            const SizedBox(height: 24),
            ZtOpenContainer<void>(
              key: const ValueKey('open-detail'),
              openBuilder: (_) => HistoryDetailPage(entry: _entry()),
              closedBuilder: (_, open) => ZtPressableScale(
                onTap: open,
                child: const SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Center(child: Text('打开详情')),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ZtOpenContainer<PainSpotDraft>(
              key: const ValueKey('open-body'),
              openBuilder: (_) => BodyAnnotatePage(initial: _bodyDraft()),
              onClosed: (result) => setState(() => _bodyResult = result?.id),
              closedBuilder: (_, open) => ZtPressableScale(
                onTap: open,
                child: const SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: Center(child: Text('打开人体模型')),
                ),
              ),
            ),
            if (_bodyResult != null)
              Text(_bodyResult!, key: const ValueKey('body-result')),
          ],
        ),
      ),
    );
  }
}

PainEntry _entry() {
  final now = DateTime(2026, 9, 28, 12);
  return PainEntry(
    id: 'motion-e2e-entry',
    createdAt: now,
    startedAt: now.subtract(const Duration(hours: 1)),
    endedAt: now,
    status: 'completed',
    intensity0to10: 4,
    notes: '',
    locations: [
      PainLocation(
        id: 'quick_head',
        bodyPartId: 'quick_head',
        normalizedX: 0.5,
        normalizedY: 0.15,
        view: 'front',
        layer: BodyLayer.skin,
        shape: PainShape.point,
        region: BodyRegion.head,
        partName: '头部',
        intensity0to10: 4,
        sensations: ['隐痛'],
        certainty: 'approximate',
        coordinateMode: '2d',
      ),
    ],
  );
}

PainSpotDraft _bodyDraft() {
  return const PainSpotDraft(
    id: 'motion-e2e-body',
    x: 0.5,
    y: 0.42,
    view: 'front',
    layer: BodyLayer.skin,
    shape: PainShape.point,
    region: BodyRegion.full,
    partName: '身体',
    bodyPartId: 'body',
    markerScale: 1,
    lineLength: 1,
    lineAngle: 0,
    depthState: 'surface',
    use3d: false,
  );
}
