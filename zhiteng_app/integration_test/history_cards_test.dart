import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/features/history/history_page.dart';
import 'package:zhiteng_app/widgets/pain_body_snapshot.dart';

// End-to-end failure modes covered before implementation:
// - the history list falls back to one wide row instead of two tall cards;
// - two nearby pain points are cropped separately or one marker disappears;
// - distant pain points stay zoomed into one body region instead of full body;
// - quick add invents a body screenshot or changes the card's geometry;
// - start/end/duration/pain-point facts are missing from the card;
// - the detail route omits the large image, detailed fields, or timeline.
// - a 2D muscle record is redrawn with the generic skin model;
// - a 3D bone/organ record loses the anatomy model that was visible when saved.
// - the information block is as tall as the image and leaves a large blank gap;
// - pain level, sensation tags, and the three explicit time rows are missing.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('history cards and detail preserve body context', (tester) async {
    final entries = _fixtures()
        .map((entry) => PainEntry.fromJson(entry.toJson()))
        .toList();
    binding.reportData = {
      'cards': entries.length,
      'columns': 2,
      'sameRegion': 'upper',
      'mixedRegion': 'full',
      'quickHasBodyImage': false,
      'modelPreviews': ['2D muscle', '3D bone'],
      'detailSections': ['image', 'details', 'timeline'],
    };
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildLightTheme(),
        home: Scaffold(
          appBar: AppBar(title: const Text('疼痛记录')),
          body: HistoryRecordGrid(entries: entries),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HistoryRecordCard), findsNWidgets(3));
    final first = tester.getRect(find.byType(HistoryRecordCard).at(0));
    final second = tester.getRect(find.byType(HistoryRecordCard).at(1));
    expect((first.top - second.top).abs(), lessThan(1));
    expect(second.left, greaterThan(first.right));
    expect(first.height, greaterThan(first.width * 1.5));
    expect(first.height, lessThanOrEqualTo(305));

    final snapshots = tester
        .widgetList<PainBodySnapshot>(find.byType(PainBodySnapshot))
        .toList();
    expect(snapshots[0].region, BodyRegion.upper);
    expect(snapshots[0].visibleLocations, hasLength(2));
    expect(snapshots[0].modelMode, '2d');
    expect(snapshots[0].anatomyLayer, BodyLayer.muscle);
    expect(snapshots[1].region, BodyRegion.full);
    expect(snapshots[1].visibleLocations, hasLength(2));
    expect(snapshots[1].modelMode, '3d');
    expect(snapshots[1].anatomyLayer, BodyLayer.bone);
    expect(snapshots[2].hasBodyImage, isFalse);
    final firstSnapshot = tester.getRect(find.byType(PainBodySnapshot).first);
    expect(
      firstSnapshot.height,
      greaterThan(first.height - firstSnapshot.height),
    );

    expect(find.text('疼痛等级：'), findsNWidgets(3));
    expect(find.text('胀痛'), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('history-sensation-tag')),
      findsNWidgets(3),
    );
    expect(find.text('开始时间：'), findsNWidgets(3));
    expect(find.text('结束时间：'), findsNWidgets(3));
    expect(find.text('持续时长：'), findsNWidgets(3));
    expect(find.text('2 小时 30 分'), findsNWidgets(3));
    expect(find.text('上腹、下腹'), findsOneWidget);
    expect(find.text('头部、左脚'), findsOneWidget);
    expect(find.text('速记记录'), findsOneWidget);

    await binding.takeScreenshot('history-two-column-cards');
    await tester.tap(find.byType(HistoryRecordCard).first);
    await tester.pumpAndSettle();

    expect(find.text('这次疼痛'), findsOneWidget);
    expect(find.text('详细信息'), findsOneWidget);
    expect(find.byType(PainBodySnapshot), findsOneWidget);
    expect(
      tester.getSize(find.byType(PainBodySnapshot)).height,
      greaterThan(280),
    );
    await binding.takeScreenshot('history-detail');

    await tester.scrollUntilVisible(find.text('疼痛位置'), 280);
    expect(find.text('疼痛位置'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('下腹'), 180);
    expect(find.text('上腹'), findsWidgets);
    expect(find.text('下腹'), findsWidgets);
    await tester.scrollUntilVisible(find.text('时间线'), 280);
    expect(find.text('时间线'), findsOneWidget);
  });
}

List<PainEntry> _fixtures() {
  final end = DateTime(2026, 9, 28, 12, 30);
  PainLocation location({
    required String id,
    required String part,
    required double x,
    required double y,
    required BodyRegion region,
    BodyLayer layer = BodyLayer.skin,
    String coordinateMode = '2d',
    BodyLayer? shownAnatomy,
    String certainty = 'marked',
  }) {
    return PainLocation(
      id: id,
      bodyPartId: id,
      normalizedX: x,
      normalizedY: y,
      view: 'front',
      layer: layer,
      shape: PainShape.point,
      region: region,
      partName: part,
      intensity0to10: 5,
      sensations: const ['胀痛'],
      certainty: certainty,
      coordinateMode: coordinateMode,
      localX: coordinateMode == '3d' ? 0 : null,
      localY: coordinateMode == '3d' ? y : null,
      localZ: coordinateMode == '3d' ? 0 : null,
      shownAnatomy: shownAnatomy,
    );
  }

  PainEntry entry(
    String id,
    List<PainLocation> locations, {
    String notes = '',
  }) {
    return PainEntry(
      id: id,
      createdAt: end,
      startedAt: end.subtract(const Duration(hours: 2, minutes: 30)),
      endedAt: end,
      status: 'completed',
      locations: locations,
      intensity0to10: 5,
      notes: notes,
    );
  }

  return [
    entry('abdomen', [
      location(
        id: 'upper_abdomen',
        part: '上腹',
        x: 0.48,
        y: 0.38,
        region: BodyRegion.upper,
        layer: BodyLayer.muscle,
      ),
      location(
        id: 'lower_abdomen',
        part: '下腹',
        x: 0.52,
        y: 0.45,
        region: BodyRegion.upper,
        layer: BodyLayer.muscle,
      ),
    ], notes: '饭后更明显'),
    entry('head-foot', [
      location(
        id: 'head',
        part: '头部',
        x: 0.5,
        y: 0.12,
        region: BodyRegion.head,
        layer: BodyLayer.skin,
        coordinateMode: '3d',
        shownAnatomy: BodyLayer.bone,
      ),
      location(
        id: 'left_foot',
        part: '左脚',
        x: 0.55,
        y: 0.94,
        region: BodyRegion.lower,
        layer: BodyLayer.bone,
        coordinateMode: '3d',
        shownAnatomy: BodyLayer.bone,
      ),
    ]),
    entry('quick', [
      location(
        id: 'quick_head_center',
        part: '头部',
        x: 0.5,
        y: 0.13,
        region: BodyRegion.head,
        certainty: 'approximate',
      ),
    ]),
  ];
}
