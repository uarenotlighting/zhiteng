import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/pain_models.dart';
import '../../core/theme/app_colors.dart';
import '../../state/controllers.dart';
import '../../widgets/zt_motion.dart';

class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key});

  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage>
    with AutomaticKeepAliveClientMixin {
  final TrendAnalyticsCache _cache = TrendAnalyticsCache();
  late final DateTime _openedAt = DateTime.now();

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final entries = context.select<PainRecordsController, List<PainEntry>>(
      (records) => records.entries,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('变化趋势')),
      body: TrendsDashboard(entries: entries, now: _openedAt, cache: _cache),
    );
  }
}

enum TrendRange {
  week('最近一周', Duration(days: 7)),
  month('最近一个月', Duration(days: 30)),
  year('最近一年', Duration(days: 365)),
  all('记录以来', null);

  const TrendRange(this.label, this.duration);
  final String label;
  final Duration? duration;
}

/// Keeps aggregations alive across tab switches and ordinary parent rebuilds.
/// A snapshot changes only when the range or meaningful record fields change.
class TrendAnalyticsCache {
  final Map<int, TrendAnalytics> _snapshots = {};
  int computationCount = 0;
  int? _entryFingerprint;

  TrendAnalytics resolve({
    required List<PainEntry> entries,
    required TrendRange range,
    required DateTime now,
  }) {
    final fingerprint = _fingerprint(entries);
    if (_entryFingerprint != fingerprint) {
      _entryFingerprint = fingerprint;
      _snapshots.clear();
    }
    final day = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    final key = Object.hash(fingerprint, range, day);
    return _snapshots.putIfAbsent(key, () {
      computationCount++;
      return TrendAnalytics.fromEntries(
        entries: entries,
        range: range,
        now: now,
        cacheKey: key,
      );
    });
  }

  static int _fingerprint(List<PainEntry> entries) => Object.hashAll(
    entries.map(
      (entry) => Object.hash(
        entry.id,
        entry.syncVersion,
        entry.startedAt.millisecondsSinceEpoch,
        entry.endedAt?.millisecondsSinceEpoch,
        entry.intensity0to10,
        Object.hashAll(
          entry.locations.map(
            (location) => Object.hash(
              location.partName,
              location.layer,
              location.shape,
              Object.hashAll(location.sensations),
            ),
          ),
        ),
      ),
    ),
  );
}

class TrendAnalytics {
  const TrendAnalytics({
    required this.cacheKey,
    required this.entries,
    required this.averageIntensity,
    required this.partCounts,
    required this.severityCounts,
    required this.sensationCounts,
    required this.layerCounts,
    required this.completed,
  });

  factory TrendAnalytics.fromEntries({
    required List<PainEntry> entries,
    required TrendRange range,
    required DateTime now,
    required int cacheKey,
  }) {
    final cutoff = range.duration == null
        ? null
        : now.subtract(range.duration!);
    final filtered =
        entries
            .where(
              (entry) => cutoff == null || !entry.startedAt.isBefore(cutoff),
            )
            .toList(growable: false)
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    final partCounts = <String, int>{};
    final severityCounts = <String, int>{
      '轻度 1–3': 0,
      '中度 4–6': 0,
      '较强 7–8': 0,
      '重度 9–10': 0,
    };
    final sensationCounts = <String, int>{};
    final layerCounts = <String, int>{};
    var sum = 0;

    for (final entry in filtered) {
      sum += entry.intensity0to10;
      final severity = switch (entry.intensity0to10) {
        <= 3 => '轻度 1–3',
        <= 6 => '中度 4–6',
        <= 8 => '较强 7–8',
        _ => '重度 9–10',
      };
      severityCounts[severity] = severityCounts[severity]! + 1;

      final seenParts = <String>{};
      final seenSensations = <String>{};
      final seenLayers = <String>{};
      for (final location in entry.locations) {
        seenParts.add(
          location.partName.trim().isEmpty ? '未标记部位' : location.partName,
        );
        seenLayers.add(location.layer.label);
        seenSensations.addAll(location.sensations);
      }
      if (seenParts.isEmpty) seenParts.add('未标记部位');
      for (final value in seenParts) {
        partCounts[value] = (partCounts[value] ?? 0) + 1;
      }
      for (final value in seenSensations) {
        sensationCounts[value] = (sensationCounts[value] ?? 0) + 1;
      }
      for (final value in seenLayers) {
        layerCounts[value] = (layerCounts[value] ?? 0) + 1;
      }
    }

    final completed = filtered
        .where((entry) => entry.endedAt != null)
        .toList(growable: false);
    return TrendAnalytics(
      cacheKey: cacheKey,
      entries: filtered,
      averageIntensity: filtered.isEmpty ? 0 : sum / filtered.length,
      partCounts: _ranked(partCounts),
      severityCounts: severityCounts,
      sensationCounts: _ranked(sensationCounts),
      layerCounts: _ranked(layerCounts),
      completed: completed,
    );
  }

  final int cacheKey;
  final List<PainEntry> entries;
  final double averageIntensity;
  final Map<String, int> partCounts;
  final Map<String, int> severityCounts;
  final Map<String, int> sensationCounts;
  final Map<String, int> layerCounts;
  final List<PainEntry> completed;

  String get mostFrequentPart =>
      partCounts.isEmpty ? '—' : partCounts.keys.first;

  static Map<String, int> _ranked(Map<String, int> source) {
    final values = source.entries.toList()
      ..sort((a, b) {
        final count = b.value.compareTo(a.value);
        return count == 0 ? a.key.compareTo(b.key) : count;
      });
    return Map.fromEntries(values);
  }
}

class TrendsDashboard extends StatefulWidget {
  const TrendsDashboard({
    super.key,
    required this.entries,
    this.now,
    this.cache,
  });

  final List<PainEntry> entries;
  final DateTime? now;
  final TrendAnalyticsCache? cache;

  @override
  State<TrendsDashboard> createState() => _TrendsDashboardState();
}

class _TrendsDashboardState extends State<TrendsDashboard>
    with AutomaticKeepAliveClientMixin {
  late final TrendAnalyticsCache _ownedCache = TrendAnalyticsCache();

  TrendAnalyticsCache get _cache => widget.cache ?? _ownedCache;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final summary = _cache.resolve(
      entries: widget.entries,
      range: TrendRange.all,
      now: widget.now ?? DateTime.now(),
    );
    final muted = _muted(context);

    return ListView(
      key: const PageStorageKey('trends-dashboard-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          '从记录里看见变化',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          '只展示你记下的规律，不代表医学诊断或因果关系。',
          style: TextStyle(color: muted, height: 1.45),
        ),
        const SizedBox(height: 16),
        if (widget.entries.isEmpty)
          const _EmptyTrendState(hasAnyEntries: false)
        else ...[
          Text('全部记录概览', style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 8),
          _SummaryStrip(analysis: summary),
          const SizedBox(height: 14),
          _ScopedTrendChart(
            chartId: 'line',
            entries: widget.entries,
            now: widget.now,
            cache: _cache,
            builder: (analysis, range, onRangeChanged) => _LineTrendCard(
              analysis: analysis,
              range: range,
              onRangeChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 14),
          _ScopedTrendChart(
            chartId: 'parts',
            entries: widget.entries,
            now: widget.now,
            cache: _cache,
            builder: (analysis, range, onRangeChanged) => _RankedBarCard(
              title: '部位分布',
              subtitle: '每条记录的疼痛位置出现次数',
              values: analysis.partCounts,
              emptyText: '这些记录还没有标记位置',
              color: _healthBlue(context),
              range: range,
              onRangeChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 14),
          _ScopedTrendChart(
            chartId: 'severity',
            entries: widget.entries,
            now: widget.now,
            cache: _cache,
            builder: (analysis, range, onRangeChanged) => _SeverityCard(
              analysis: analysis,
              range: range,
              onRangeChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 14),
          _ScopedTrendChart(
            chartId: 'duration',
            entries: widget.entries,
            now: widget.now,
            cache: _cache,
            builder: (analysis, range, onRangeChanged) => _DurationScatterCard(
              analysis: analysis,
              range: range,
              onRangeChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 14),
          _ScopedTrendChart(
            chartId: 'sensations',
            entries: widget.entries,
            now: widget.now,
            cache: _cache,
            builder: (analysis, range, onRangeChanged) => _RankedBarCard(
              title: '疼痛感受',
              subtitle: '刺痛、酸痛等感受的记录频次',
              values: analysis.sensationCounts,
              emptyText: '这段时间还没有记录疼痛感受',
              color: _healthPurple(context),
              range: range,
              onRangeChanged: onRangeChanged,
            ),
          ),
          const SizedBox(height: 14),
          _ScopedTrendChart(
            chartId: 'layers',
            entries: widget.entries,
            now: widget.now,
            cache: _cache,
            builder: (analysis, range, onRangeChanged) => _LayerBreakdown(
              analysis: analysis,
              range: range,
              onRangeChanged: onRangeChanged,
            ),
          ),
        ],
      ],
    );
  }
}

typedef _ScopedChartBuilder =
    Widget Function(
      TrendAnalytics analysis,
      TrendRange range,
      ValueChanged<TrendRange> onRangeChanged,
    );

class _ScopedTrendChart extends StatefulWidget {
  const _ScopedTrendChart({
    required this.chartId,
    required this.entries,
    required this.now,
    required this.cache,
    required this.builder,
  });

  final String chartId;
  final List<PainEntry> entries;
  final DateTime? now;
  final TrendAnalyticsCache cache;
  final _ScopedChartBuilder builder;

  @override
  State<_ScopedTrendChart> createState() => _ScopedTrendChartState();
}

class _ScopedTrendChartState extends State<_ScopedTrendChart> {
  TrendRange _range = TrendRange.week;

  @override
  Widget build(BuildContext context) {
    final analysis = widget.cache.resolve(
      entries: widget.entries,
      range: _range,
      now: widget.now ?? DateTime.now(),
    );
    return RepaintBoundary(
      key: ValueKey('${widget.chartId}-${analysis.cacheKey}'),
      child: widget.builder(
        analysis,
        _range,
        (value) => setState(() => _range = value),
      ),
    );
  }
}

class _ChartRangeSelector extends StatelessWidget {
  const _ChartRangeSelector({required this.selected, required this.onSelected});
  final TrendRange selected;
  final ValueChanged<TrendRange> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final range in TrendRange.values)
          Semantics(
            button: true,
            selected: selected == range,
            label: range.label,
            child: ZtPressableScale(
              onTap: () => onSelected(range),
              haptic: ZtHaptic.selection,
              tapScale: 0.92,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected == range
                      ? _rangeSelected(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(
                    color: selected == range
                        ? _rangeSelected(context)
                        : Colors.transparent,
                  ),
                ),
                child: Text(
                  switch (range) {
                    TrendRange.week => '近一周',
                    TrendRange.month => '近一月',
                    TrendRange.year => '近一年',
                    TrendRange.all => '记录以来',
                  },
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected == range
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: selected == range
                        ? _rangeSelectedText(context)
                        : _muted(context),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.analysis});
  final TrendAnalytics analysis;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryTile(
            label: '记录',
            value: '${analysis.entries.length} 条记录',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(
            label: '平均强度',
            value: '${analysis.averageIntensity.toStringAsFixed(1)}/10',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SummaryTile(label: '常见部位', value: analysis.mostFrequentPart),
        ),
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(context, radius: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: _muted(context))),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.range,
    required this.onRangeChanged,
    this.interactive = true,
  });
  final String title;
  final String subtitle;
  final Widget child;
  final TrendRange range;
  final ValueChanged<TrendRange> onRangeChanged;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12, color: _muted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (interactive) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  size: 13,
                  color: _muted(context),
                ),
                const SizedBox(width: 4),
                Text(
                  '点按或拖动图表查看详情',
                  style: TextStyle(fontSize: 10, color: _muted(context)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          child,
          const SizedBox(height: 18),
          Divider(height: 1, color: _border(context)),
          const SizedBox(height: 14),
          _ChartRangeSelector(selected: range, onSelected: onRangeChanged),
        ],
      ),
    );
  }
}

class _LineTrendCard extends StatelessWidget {
  const _LineTrendCard({
    required this.analysis,
    required this.range,
    required this.onRangeChanged,
  });
  final TrendAnalytics analysis;
  final TrendRange range;
  final ValueChanged<TrendRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final entries = analysis.entries;
    if (entries.isEmpty) {
      return _ChartCard(
        title: '疼痛变化',
        subtitle: '每次记录的强度（0–10）',
        range: range,
        onRangeChanged: onRangeChanged,
        interactive: false,
        child: const _InlineEmpty(text: '这个时间范围内还没有记录'),
      );
    }
    final primary = _healthPink(context);
    final labelStyle = TextStyle(color: _muted(context), fontSize: 10);
    final dateFormat = DateFormat('MM/dd');
    return _ChartCard(
      title: '疼痛变化',
      subtitle: '每次记录的强度（0–10）',
      range: range,
      onRangeChanged: onRangeChanged,
      child: SizedBox(
        height: 224,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, entries.length - 1).toDouble(),
            minY: 0,
            maxY: 10,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: 2,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: _chartGrid(context), strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 2,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) =>
                      Text(value.toInt().toString(), style: labelStyle),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: entries.length <= 4
                      ? 1
                      : math.max(1, (entries.length / 3).floorToDouble()),
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 ||
                        index >= entries.length ||
                        (value - index).abs() > .1) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        dateFormat.format(entries[index].startedAt),
                        style: labelStyle,
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              enabled: true,
              handleBuiltInTouches: true,
              touchCallback: (event, response) {
                if (response?.lineBarSpots?.isNotEmpty ?? false) {
                  _playChartTap(context, event);
                }
              },
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => _tooltipColor(context),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spots) => spots.map((spot) {
                  final index = spot.x.round().clamp(0, entries.length - 1);
                  final entry = entries[index];
                  return LineTooltipItem(
                    '${DateFormat('MM/dd HH:mm').format(entry.startedAt)}\n${entry.primaryPartName} · ${entry.intensity0to10}/10',
                    TextStyle(
                      color: _tooltipText(context),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (final item in entries.indexed)
                    FlSpot(
                      item.$1.toDouble(),
                      item.$2.intensity0to10.toDouble(),
                    ),
                ],
                color: primary,
                barWidth: 3,
                isCurved: entries.length > 2,
                curveSmoothness: .24,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 4.5,
                        color: _surface(context),
                        strokeColor: _healthPink(context),
                        strokeWidth: 2.5,
                      ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      primary.withValues(alpha: .14),
                      primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ],
          ),
          duration: const Duration(milliseconds: 240),
        ),
      ),
    );
  }
}

class _RankedBarCard extends StatelessWidget {
  const _RankedBarCard({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.emptyText,
    required this.color,
    required this.range,
    required this.onRangeChanged,
  });
  final String title;
  final String subtitle;
  final Map<String, int> values;
  final String emptyText;
  final Color color;
  final TrendRange range;
  final ValueChanged<TrendRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final ranked = values.entries.take(6).toList(growable: false);
    if (ranked.isEmpty) {
      return _ChartCard(
        title: title,
        subtitle: subtitle,
        range: range,
        onRangeChanged: onRangeChanged,
        interactive: false,
        child: _InlineEmpty(text: emptyText),
      );
    }
    final maxValue = ranked.map((item) => item.value).reduce(math.max);
    final labelStyle = TextStyle(color: _muted(context), fontSize: 10);
    return _ChartCard(
      title: title,
      subtitle: subtitle,
      range: range,
      onRangeChanged: onRangeChanged,
      child: SizedBox(
        height: 220,
        child: BarChart(
          BarChartData(
            minY: 0,
            maxY: (maxValue + 1).toDouble(),
            alignment: BarChartAlignment.spaceAround,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: 1,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: _chartGrid(context), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 1,
                  reservedSize: 22,
                  getTitlesWidget: (value, meta) =>
                      Text(value.toInt().toString(), style: labelStyle),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 35,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= ranked.length) {
                      return const SizedBox.shrink();
                    }
                    final label = ranked[index].key;
                    return SideTitleWidget(
                      meta: meta,
                      child: SizedBox(
                        width: 48,
                        child: Text(
                          label.length > 4
                              ? '${label.substring(0, 4)}…'
                              : label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: labelStyle,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              enabled: true,
              handleBuiltInTouches: true,
              touchCallback: (event, response) {
                if (response?.spot != null) _playChartTap(context, event);
              },
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => _tooltipColor(context),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                    BarTooltipItem(
                      '${ranked[group.x].key}\n${ranked[group.x].value} 次',
                      TextStyle(
                        color: _tooltipText(context),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
              ),
            ),
            barGroups: [
              for (final item in ranked.indexed)
                BarChartGroupData(
                  x: item.$1,
                  barRods: [
                    BarChartRodData(
                      toY: item.$2.value.toDouble(),
                      width: ranked.length > 4 ? 20 : 28,
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          duration: const Duration(milliseconds: 240),
        ),
      ),
    );
  }
}

class _SeverityCard extends StatefulWidget {
  const _SeverityCard({
    required this.analysis,
    required this.range,
    required this.onRangeChanged,
  });
  final TrendAnalytics analysis;
  final TrendRange range;
  final ValueChanged<TrendRange> onRangeChanged;

  @override
  State<_SeverityCard> createState() => _SeverityCardState();
}

class _SeverityCardState extends State<_SeverityCard> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final values = widget.analysis.severityCounts.entries.toList();
    final total = widget.analysis.entries.length;
    final colors = [
      _healthYellow(context),
      _healthOrange(context),
      _healthRed(context),
      _healthPink(context),
    ];
    if (total == 0) {
      return _ChartCard(
        title: '疼痛程度',
        subtitle: '不同强度区间的记录占比',
        range: widget.range,
        onRangeChanged: widget.onRangeChanged,
        interactive: false,
        child: const _InlineEmpty(text: '这个时间范围内还没有记录'),
      );
    }
    return _ChartCard(
      title: '疼痛程度',
      subtitle: '不同强度区间的记录占比',
      range: widget.range,
      onRangeChanged: widget.onRangeChanged,
      child: Column(
        children: [
          SizedBox(
            height: 184,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 50,
                    sectionsSpace: 3,
                    pieTouchData: PieTouchData(
                      enabled: true,
                      touchCallback: (event, response) {
                        if (!event.isInterestedForInteractions ||
                            response?.touchedSection == null) {
                          return;
                        }
                        _playChartTap(context, event);
                        setState(
                          () => _touched =
                              response!.touchedSection!.touchedSectionIndex,
                        );
                      },
                    ),
                    sections: [
                      for (final item in values.indexed)
                        PieChartSectionData(
                          value: item.$2.value.toDouble(),
                          color: colors[item.$1],
                          radius: _touched == item.$1 ? 52 : 44,
                          showTitle: item.$2.value > 0,
                          title: '${(item.$2.value / total * 100).round()}%',
                          titleStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  duration: const Duration(milliseconds: 220),
                ),
                IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$total',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '条记录',
                        style: TextStyle(fontSize: 10, color: _muted(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final item in values.indexed)
                _LegendDot(
                  color: colors[item.$1],
                  label: '${item.$2.key}  ${item.$2.value}',
                  selected: _touched == item.$1,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DurationScatterCard extends StatelessWidget {
  const _DurationScatterCard({
    required this.analysis,
    required this.range,
    required this.onRangeChanged,
  });
  final TrendAnalytics analysis;
  final TrendRange range;
  final ValueChanged<TrendRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final entries = analysis.completed;
    if (entries.isEmpty) {
      return _ChartCard(
        title: '持续时长 × 强度',
        subtitle: '看疼痛强度是否随持续时间变化',
        range: range,
        onRangeChanged: onRangeChanged,
        interactive: false,
        child: const _InlineEmpty(text: '记录结束时间后，这里会显示关系散点'),
      );
    }
    final hours = [
      for (final entry in entries)
        entry.endedAt!.difference(entry.startedAt).inMinutes / 60,
    ];
    final maxHours = math.max(1.0, hours.reduce(math.max));
    final labelStyle = TextStyle(color: _muted(context), fontSize: 10);
    return _ChartCard(
      title: '持续时长 × 强度',
      subtitle: '横轴为持续小时，纵轴为疼痛强度',
      range: range,
      onRangeChanged: onRangeChanged,
      child: SizedBox(
        height: 224,
        child: ScatterChart(
          ScatterChartData(
            minX: 0,
            maxX: maxHours * 1.12,
            minY: 0,
            maxY: 10,
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: _chartGrid(context), strokeWidth: 1),
              getDrawingVerticalLine: (_) =>
                  FlLine(color: _chartGrid(context), strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 2,
                  reservedSize: 25,
                  getTitlesWidget: (value, meta) =>
                      Text(value.toInt().toString(), style: labelStyle),
                ),
              ),
              bottomTitles: AxisTitles(
                axisNameWidget: Text('小时', style: labelStyle),
                axisNameSize: 18,
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: maxHours <= 4 ? 1 : maxHours / 4,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      value < 10
                          ? value.toStringAsFixed(1)
                          : value.round().toString(),
                      style: labelStyle,
                    ),
                  ),
                ),
              ),
            ),
            scatterTouchData: ScatterTouchData(
              enabled: true,
              handleBuiltInTouches: true,
              touchSpotThreshold: 24,
              touchTooltipData: ScatterTouchTooltipData(
                getTooltipColor: (_) => _tooltipColor(context),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (spot) {
                  final index = _spotIndex(entries, hours, spot);
                  final entry = entries[index];
                  return ScatterTooltipItem(
                    '${entry.primaryPartName}\n${_durationLabel(hours[index])} · ${entry.intensity0to10}/10',
                    textStyle: TextStyle(
                      color: _tooltipText(context),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  );
                },
              ),
            ),
            scatterSpots: [
              for (final item in entries.indexed)
                ScatterSpot(
                  hours[item.$1],
                  item.$2.intensity0to10.toDouble(),
                  dotPainter: FlDotCirclePainter(
                    radius: 7,
                    color: _healthRed(context),
                    strokeWidth: 2,
                    strokeColor: _surface(context),
                  ),
                ),
            ],
          ),
          duration: const Duration(milliseconds: 240),
        ),
      ),
    );
  }

  static int _spotIndex(
    List<PainEntry> entries,
    List<double> hours,
    ScatterSpot spot,
  ) {
    for (var index = 0; index < entries.length; index++) {
      if ((hours[index] - spot.x).abs() < .001 &&
          entries[index].intensity0to10 == spot.y.round()) {
        return index;
      }
    }
    return 0;
  }
}

class _LayerBreakdown extends StatelessWidget {
  const _LayerBreakdown({
    required this.analysis,
    required this.range,
    required this.onRangeChanged,
  });
  final TrendAnalytics analysis;
  final TrendRange range;
  final ValueChanged<TrendRange> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    final entries = analysis.layerCounts.entries.toList();
    if (entries.isEmpty) {
      return _ChartCard(
        title: '疼痛层次',
        subtitle: '皮肤、肌肉、骨骼或器官的标记分布',
        range: range,
        onRangeChanged: onRangeChanged,
        interactive: false,
        child: const _InlineEmpty(text: '这个时间范围内还没有记录疼痛层次'),
      );
    }
    final total = entries.fold<int>(0, (sum, item) => sum + item.value);
    return _ChartCard(
      title: '疼痛层次',
      subtitle: '皮肤、肌肉、骨骼或器官的标记分布',
      range: range,
      onRangeChanged: onRangeChanged,
      interactive: false,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 14,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in entries.indexed)
                    Expanded(
                      flex: item.$2.value,
                      child: ColoredBox(color: _layerColor(context, item.$1)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              for (final item in entries.indexed)
                _LegendDot(
                  color: _layerColor(context, item.$1),
                  label:
                      '${item.$2.key} ${(item.$2.value / total * 100).round()}%',
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _layerColor(BuildContext context, int index) => [
    _healthCyan(context),
    _healthOrange(context),
    _healthPurple(context),
    _healthRed(context),
    _healthGray(context),
  ][index % 5];
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    this.selected = false,
  });
  final Color color;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: EdgeInsets.symmetric(horizontal: selected ? 8 : 0, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? color.withValues(alpha: .12) : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11, color: _muted(context))),
        ],
      ),
    );
  }
}

class _EmptyTrendState extends StatelessWidget {
  const _EmptyTrendState({required this.hasAnyEntries});
  final bool hasAnyEntries;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 54),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: _soft(context),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.query_stats, color: _muted(context), size: 28),
          ),
          const SizedBox(height: 18),
          Text(
            hasAnyEntries ? '这段时间还没有记录' : '还没有可分析的记录',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            hasAnyEntries ? '试试切换到更长的时间范围。' : '完成几次疼痛记录后，这里会自动形成趋势。',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted(context), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted(context)),
      ),
    ),
  );
}

String _durationLabel(double hours) {
  if (hours < 1) return '${(hours * 60).round()} 分钟';
  if (hours < 24) return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} 小时';
  return '${(hours / 24).toStringAsFixed(1)} 天';
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;
Color _surface(BuildContext context) =>
    _isDark(context) ? AppColors.darkSurface : AppColors.lightSurface;
Color _muted(BuildContext context) => _isDark(context)
    ? AppColors.darkTextSecondary
    : AppColors.lightTextSecondary;
Color _border(BuildContext context) =>
    _isDark(context) ? AppColors.darkBorder : AppColors.lightBorder;
Color _soft(BuildContext context) =>
    _isDark(context) ? AppColors.darkElevated : AppColors.lightSubtle;
Color _rangeSelected(BuildContext context) =>
    _isDark(context) ? const Color(0xFF3A3A3A) : AppColors.lightPrimary;
Color _rangeSelectedText(BuildContext context) =>
    _isDark(context) ? AppColors.darkTextPrimary : AppColors.lightOnPrimary;
Color _tooltipColor(BuildContext context) => _isDark(context)
    ? AppColors.darkElevated
    : AppColors.lightTextPrimary.withValues(alpha: 0.92);
Color _tooltipText(BuildContext context) =>
    _isDark(context) ? AppColors.darkTextPrimary : AppColors.lightOnPrimary;

Color _healthPink(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFF375F) : const Color(0xFFFF2D55);
Color _healthRed(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFF453A) : const Color(0xFFFF3B30);
Color _healthOrange(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500);
Color _healthYellow(BuildContext context) =>
    _isDark(context) ? const Color(0xFFFFD60A) : const Color(0xFFFFCC00);
Color _healthBlue(BuildContext context) =>
    _isDark(context) ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
Color _healthCyan(BuildContext context) =>
    _isDark(context) ? const Color(0xFF64D2FF) : const Color(0xFF32ADE6);
Color _healthPurple(BuildContext context) =>
    _isDark(context) ? const Color(0xFFBF5AF2) : const Color(0xFFAF52DE);
Color _healthGray(BuildContext context) => const Color(0xFF8E8E93);
Color _chartGrid(BuildContext context) =>
    _border(context).withValues(alpha: .72);

BoxDecoration _cardDecoration(BuildContext context, {double radius = 18}) =>
    BoxDecoration(
      color: _surface(context),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: _isDark(context)
          ? const []
          : const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
    );

void _playChartTap(BuildContext context, FlTouchEvent event) {
  if (event is! FlTapUpEvent) return;
  ztHaptic(context, ZtHaptic.selection);
}
