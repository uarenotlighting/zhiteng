import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zhiteng_app/core/models/pain_models.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/features/trends/trends_page.dart';

// End-to-end failure modes covered before implementation:
// - changing one chart's time range silently changes every other chart;
// - time ranges do not filter old records or lose the all-time option;
// - one generic chart is reused instead of suitable line/bar/pie/scatter views;
// - tapping a chart crashes or does not enable its built-in tooltip handling;
// - returning to/rebuilding the page repeats an unchanged aggregation;
// - sparse and empty histories overflow or render misleading zero charts.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'each trend chart filters independently and reuses cached analysis',
    (tester) async {
      final now = DateTime(2026, 9, 28, 12);
      final cache = TrendAnalyticsCache();
      final hostKey = GlobalKey<_TrendHostState>();

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: _TrendHost(
            key: hostKey,
            entries: _fixtures(now),
            now: now,
            cache: cache,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('疼痛变化'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('5 条记录'), findsOneWidget);
      expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots,
        hasLength(2),
      );

      final firstComputationCount = cache.computationCount;
      hostKey.currentState!.rebuildWithoutChangingData();
      await tester.pumpAndSettle();
      expect(cache.computationCount, firstComputationCount);

      await tester.tap(find.text('记录以来').first);
      await tester.pumpAndSettle();
      expect(cache.computationCount, firstComputationCount);

      final line = tester.widget<LineChart>(find.byType(LineChart));
      expect(line.data.lineTouchData.enabled, isTrue);
      expect(line.data.lineBarsData.single.spots, hasLength(5));
      await tester.tapAt(tester.getRect(find.byType(LineChart)).center);
      await tester.pump(const Duration(milliseconds: 200));
      binding.reportData = {
        'charts': ['line', 'bar', 'pie', 'scatter'],
        'ranges': ['week', 'month', 'year', 'all'],
        'records': 5,
        'cacheComputations': cache.computationCount,
        'tooltipsEnabled': true,
        'independentRanges': true,
      };
      await binding.takeScreenshot('trends-line-all-time');

      final verticalScroll = find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      );
      await tester.scrollUntilVisible(
        find.text('部位分布').first,
        300,
        scrollable: verticalScroll,
      );
      await tester.pumpAndSettle();
      final bar = tester.widget<BarChart>(find.byType(BarChart).first);
      expect(bar.data.barTouchData.enabled, isTrue);
      expect(bar.data.barGroups, hasLength(2), reason: '部位图应保持最近一周，不跟随折线图切换');
      await tester.tapAt(tester.getRect(find.byType(BarChart).first).center);

      await tester.scrollUntilVisible(
        find.text('疼痛程度').first,
        300,
        scrollable: verticalScroll,
      );
      await tester.pumpAndSettle();
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      expect(pie.data.pieTouchData.enabled, isTrue);
      await tester.tapAt(
        tester.getRect(find.byType(PieChart)).centerRight - const Offset(20, 0),
      );

      await tester.scrollUntilVisible(
        find.text('持续时长 × 强度').first,
        300,
        scrollable: verticalScroll,
      );
      await tester.pumpAndSettle();
      final scatter = tester.widget<ScatterChart>(find.byType(ScatterChart));
      expect(scatter.data.scatterTouchData.enabled, isTrue);
      await tester.tapAt(tester.getRect(find.byType(ScatterChart)).center);

      await tester.scrollUntilVisible(
        find.text('疼痛感受').first,
        300,
        scrollable: verticalScroll,
      );
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsWidgets);
      await tester.tapAt(tester.getRect(find.byType(BarChart).last).center);

      await binding.takeScreenshot('trends-all-time-interactive-charts');
    },
  );

  testWidgets('trend dashboard explains an empty history', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(
          body: TrendsDashboard(entries: const [], now: DateTime(2026, 9, 28)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有可分析的记录'), findsOneWidget);
    expect(find.byType(LineChart), findsNothing);
    expect(find.byType(PieChart), findsNothing);
  });
}

class _TrendHost extends StatefulWidget {
  const _TrendHost({
    super.key,
    required this.entries,
    required this.now,
    required this.cache,
  });

  final List<PainEntry> entries;
  final DateTime now;
  final TrendAnalyticsCache cache;

  @override
  State<_TrendHost> createState() => _TrendHostState();
}

class _TrendHostState extends State<_TrendHost> {
  void rebuildWithoutChangingData() => setState(() {});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('变化趋势')),
    body: TrendsDashboard(
      entries: widget.entries,
      now: widget.now,
      cache: widget.cache,
    ),
  );
}

List<PainEntry> _fixtures(DateTime now) => [
  _entry(
    'today',
    now.subtract(const Duration(hours: 2)),
    8,
    '左肩',
    sensations: const ['刺痛', '酸痛'],
    hours: 1.5,
  ),
  _entry(
    'week',
    now.subtract(const Duration(days: 5)),
    4,
    '腰部',
    sensations: const ['酸痛'],
    hours: 3,
  ),
  _entry(
    'month',
    now.subtract(const Duration(days: 18)),
    6,
    '左肩',
    sensations: const ['胀痛'],
    hours: 8,
  ),
  _entry(
    'year',
    now.subtract(const Duration(days: 160)),
    3,
    '膝部',
    sensations: const ['隐痛'],
    hours: 26,
  ),
  _entry(
    'old',
    now.subtract(const Duration(days: 500)),
    9,
    '头部',
    sensations: const ['跳痛'],
    hours: 0.5,
  ),
];

PainEntry _entry(
  String id,
  DateTime startedAt,
  int intensity,
  String part, {
  required List<String> sensations,
  required double hours,
}) {
  final location = PainLocation(
    id: 'location-$id',
    bodyPartId: part,
    normalizedX: 0.5,
    normalizedY: 0.4,
    view: 'front',
    layer: id == 'today' ? BodyLayer.muscle : BodyLayer.skin,
    shape: PainShape.point,
    region: BodyRegion.upper,
    partName: part,
    intensity0to10: intensity,
    sensations: sensations,
  );
  return PainEntry(
    id: id,
    createdAt: startedAt,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(minutes: (hours * 60).round())),
    status: 'ended',
    locations: [location],
    intensity0to10: intensity,
  );
}
