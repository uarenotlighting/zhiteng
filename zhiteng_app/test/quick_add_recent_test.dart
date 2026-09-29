import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/features/record/pain_spot_draft.dart';
import 'package:zhiteng_app/features/record/quick_add_sheet.dart';

void main() {
  QuickBodyPart part(String id) =>
      quickBodyParts.firstWhere((item) => item.id == id);

  PainLocation spot(QuickBodyPart area, String side) {
    return quickPainSpot(
      part: area,
      side: side,
      deep: false,
    ).toLocation(intensity0to10: 3, sensations: const []);
  }

  PainEntry record({
    required String id,
    required DateTime startedAt,
    List<PainLocation> locations = const [],
    DateTime? createdAt,
  }) {
    return PainEntry(
      id: id,
      createdAt: createdAt ?? startedAt,
      startedAt: startedAt,
      locations: locations,
      intensity0to10: 3,
    );
  }

  test('recent shortcuts stay empty when nothing was recorded', () {
    expect(recentQuickShortcuts(const []), isEmpty);
    expect(
      recentQuickShortcuts([
        record(id: 'blank', startedAt: DateTime(2026, 9, 1)),
      ]),
      isEmpty,
    );
  });

  test('recent shortcuts are the first three spots, newest record first', () {
    final older = record(
      id: 'older',
      startedAt: DateTime(2026, 9, 1),
      locations: [spot(part('foot'), 'left')],
    );
    final newer = record(
      id: 'newer',
      startedAt: DateTime(2026, 9, 20),
      locations: [
        spot(part('head'), 'center'),
        spot(part('shoulder'), 'right'),
        spot(part('waist'), 'left'),
        spot(part('knee'), 'left'),
      ],
    );

    final labels = recentQuickShortcuts([
      older,
      newer,
    ]).map((item) => item.label).toList();

    expect(labels, ['头部', '右侧肩部', '左侧腰部']);
  });

  test('a repeated part does not take another recent slot', () {
    final repeated = spot(part('waist'), 'left');
    final shortcuts = recentQuickShortcuts([
      record(
        id: 'third',
        startedAt: DateTime(2026, 9, 3),
        locations: [spot(part('knee'), 'right')],
      ),
      record(
        id: 'second',
        startedAt: DateTime(2026, 9, 2),
        locations: [repeated],
      ),
      record(
        id: 'first',
        startedAt: DateTime(2026, 9, 1),
        locations: [repeated],
      ),
    ]);

    expect(shortcuts.map((item) => item.label), ['右侧膝部', '左侧腰部']);
  });

  test('a side stored apart from the name is shown on the chip', () {
    final shortcuts = recentQuickShortcuts([
      record(
        id: 'marked',
        startedAt: DateTime(2026, 9, 4),
        locations: [
          PainLocation(
            id: 'scapula',
            bodyPartId: 'scapula',
            normalizedX: 0.3,
            normalizedY: 0.31,
            view: 'back',
            layer: BodyLayer.skin,
            shape: PainShape.point,
            region: BodyRegion.upper,
            partName: '肩胛部',
            side: 'right',
          ),
        ],
      ),
    ]);

    expect(shortcuts.single.label, '右侧肩胛部');
    expect(shortcuts.single.spot.partName, '肩胛部');
    expect(shortcuts.single.spot.side, 'right');
  });

  testWidgets('quick add hides recent use when there is no history', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuickAddSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('最近使用'), findsNothing);
    expect(find.text('部位'), findsOneWidget);
    expect(find.text('左侧腰部'), findsNothing);
  });

  testWidgets('tapping a recent spot reuses that placement', (tester) async {
    final recent = recentQuickShortcuts([
      record(
        id: 'saved',
        startedAt: DateTime(2026, 9, 8),
        locations: [spot(part('waist'), 'left')],
      ),
    ]);
    PainSpotDraft? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showQuickAddSheet(context, recent: recent);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('最近使用'), findsOneWidget);
    expect(find.text('左侧腰部'), findsOneWidget);
    await tester.tap(find.text('左侧腰部'));
    await tester.pumpAndSettle();

    expect(picked?.partName, '左侧腰部');
    expect(picked?.side, 'left');
    expect(picked?.id, isNot(recent.single.spot.id));
  });
}
