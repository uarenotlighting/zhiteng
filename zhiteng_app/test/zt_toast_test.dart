import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/data/pain_repository.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/features/record/record_page.dart';
import 'package:zhiteng_app/state/controllers.dart';
import 'package:zhiteng_app/widgets/zt_motion.dart';
import 'package:zhiteng_app/widgets/zt_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saving an ongoing pain without edits is not a new change', () {
    final now = DateTime.now();
    final location = PainLocation(
      id: 'loc-1',
      bodyPartId: 'quick_head_center',
      normalizedX: 0.5,
      normalizedY: 0.3,
      view: 'front',
      layer: BodyLayer.skin,
      shape: PainShape.point,
      region: BodyRegion.head,
      partName: '头部',
      certainty: 'approximate',
    );
    final entry = PainEntry(
      id: 'pain-1',
      createdAt: now,
      startedAt: now.subtract(const Duration(hours: 1)),
      intensity0to10: 3,
      locations: [location],
    );
    final spot = PainSpotDraft.fromLocation(location);
    final sensations = <String>[...location.sensations];
    final outcome = applyPainUpdate(
      previous: entry,
      draft: PainMomentDraft(
        startedAt: entry.startedAt,
        changeAt: now,
        locations: [
          spot.toLocation(
            intensity0to10: entry.intensity0to10,
            sensations: sensations,
          ),
        ],
        intensity0to10: entry.intensity0to10,
        medications: entry.medications,
      ),
      newId: () => 'new-moment',
    );
    expect(outcome.saved, isFalse, reason: outcome.message);
  });

  tearDown(() {
    ZtToast.dismiss();
  });

  testWidgets('only one toast exists, and a result replaces loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Column(
              children: [
                TextButton(
                  onPressed: () => ZtToast.loading(context, '正在保存…'),
                  child: const Text('加载'),
                ),
                TextButton(
                  onPressed: () => ZtToast.text(context, '先出现的提示'),
                  child: const Text('第一条'),
                ),
                TextButton(
                  onPressed: () => ZtToast.failure(context, '请先添加一个痛点'),
                  child: const Text('失败'),
                ),
              ],
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('加载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('正在保存…'), findsOneWidget);
    expect(find.byKey(const ValueKey('zt-toast')), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('正在保存…'), findsOneWidget);

    await tester.tap(find.text('第一条'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('正在保存…'), findsNothing);
    expect(find.text('先出现的提示'), findsOneWidget);
    expect(find.byKey(const ValueKey('zt-toast')), findsOneWidget);

    await tester.tap(find.text('失败'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('先出现的提示'), findsNothing);
    expect(find.text('请先添加一个痛点'), findsOneWidget);
    expect(find.byKey(const ValueKey('zt-toast')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    expect(find.text('请先添加一个痛点'), findsNothing);
    expect(find.byKey(const ValueKey('zt-toast')), findsNothing);
  });

  testWidgets('saving without a pain spot shows a toast that goes away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: buildLightTheme(), home: const RecordPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.widgetWithText(ZtPressableScale, '保存本次记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));

    expect(find.text('请先添加一个痛点'), findsWidgets);
    expect(find.text('正在保存…'), findsNothing);
    expect(find.byKey(const ValueKey('zt-toast')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2200));
    expect(find.byKey(const ValueKey('zt-toast')), findsNothing);
  });

  testWidgets('saving an unchanged ongoing pain replaces the loading toast', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    final entry = PainEntry(
      id: 'pain-1',
      createdAt: now,
      startedAt: now.subtract(const Duration(hours: 1)),
      intensity0to10: 3,
      locations: [
        PainLocation(
          id: 'loc-1',
          bodyPartId: 'head',
          normalizedX: 0.5,
          normalizedY: 0.3,
          view: 'front',
          layer: BodyLayer.skin,
          shape: PainShape.point,
          region: BodyRegion.head,
          partName: '头部',
        ),
      ],
    );

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PainRecordsController(_UnchangedRepository()),
        child: MaterialApp(
          theme: buildLightTheme(),
          home: RecordPage(ending: entry),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.widgetWithText(ZtPressableScale, '保存，继续记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('正在保存…'), findsNothing);
    expect(find.text('没有新的变化'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 2200));
    expect(find.byKey(const ValueKey('zt-toast')), findsNothing);
  });
}

class _UnchangedRepository extends PainRepository {
  @override
  Future<PainUpdateOutcome> reviseEntry({
    required PainEntry previous,
    required PainMomentDraft draft,
  }) async {
    await Future<void>.delayed(Duration.zero);
    return const PainUpdateOutcome.unchanged();
  }
}
