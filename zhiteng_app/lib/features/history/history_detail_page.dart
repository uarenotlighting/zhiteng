import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/pain_models.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/pain_body_snapshot.dart';
import '../../widgets/pain_timeline_view.dart';
import '../../widgets/zt_motion.dart';
import 'history_body_page.dart';
import 'history_formatters.dart';

class HistoryDetailPage extends StatelessWidget {
  const HistoryDetailPage({super.key, required this.entry});

  final PainEntry entry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final showBody = entry.locations.any(
      (location) => !isQuickPainLocation(location),
    );
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ZtSwipeBackPage(
      child: Scaffold(
        appBar: AppBar(
          leading: (ModalRoute.of(context)?.canPop ?? false)
              ? const ZtBackButton()
              : null,
          title: const Text('这次疼痛'),
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + bottomInset),
          children: [
            if (showBody) ...[
              ZtOpenContainer<void>(
                closedBorderRadius: BorderRadius.circular(20),
                closedClipBehavior: Clip.none,
                openBuilder: (_) => HistoryBodyPage(locations: entry.locations),
                closedBuilder: (_, open) => ZtPressableScale(
                  onTap: open,
                  child: Container(
                    height: 340,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.bodyStageFor(dark: dark),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    foregroundDecoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.stageFrame(dark: dark),
                      ),
                    ),
                    child: PainBodySnapshot(locations: entry.locations),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            Text(
              painPointNames(entry),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: dark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(painDurationLabel(entry), style: TextStyle(color: muted)),
            const SizedBox(height: 22),
            _SectionTitle('详细信息'),
            const SizedBox(height: 10),
            _DetailSurface(
              children: [
                _DetailRow(
                  label: '开始时间',
                  value: DateFormat('yyyy/MM/dd HH:mm').format(entry.startedAt),
                ),
                _DetailRow(
                  label: '结束时间',
                  value: entry.endedAt == null
                      ? '仍在持续'
                      : DateFormat('yyyy/MM/dd HH:mm').format(entry.endedAt!),
                ),
                _DetailRow(
                  label: '持续时长',
                  value: painDurationLabel(entry).substring(3),
                ),
                _DetailRow(
                  label: '疼痛程度',
                  value:
                      '${entry.intensity0to10}/10 · ${entry.intensityCaption}',
                ),
                _DetailRow(
                  label: '疼痛感觉',
                  value: latestPainSensations(entry).isEmpty
                      ? '未补充'
                      : latestPainSensations(entry).join('、'),
                ),
                _DetailRow(
                  label: '补充说明',
                  value: entry.notes.trim().isEmpty
                      ? '未补充'
                      : entry.notes.trim(),
                  divider: entry.medications.isNotEmpty,
                ),
                if (entry.medications.isNotEmpty)
                  _DetailRow(
                    label: '用药记录',
                    value: entry.medications
                        .map((item) => '${item.name} ${item.doseText}')
                        .join('、'),
                    divider: false,
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _SectionTitle('疼痛位置'),
            const SizedBox(height: 10),
            for (var i = 0; i < entry.locations.length; i++) ...[
              _LocationSurface(location: entry.locations[i], index: i + 1),
              if (i != entry.locations.length - 1) const SizedBox(height: 10),
            ],
            const SizedBox(height: 26),
            _SectionTitle('时间线'),
            const SizedBox(height: 14),
            PainTimelineView(
              startedAt: entry.startedAt,
              moments: entry.timeline,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
    );
  }
}

class _DetailSurface extends StatelessWidget {
  const _DetailSurface({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.divider = true,
  });

  final String label;
  final String value;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: divider
            ? Border(
                bottom: BorderSide(
                  color: dark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: TextStyle(fontSize: 13, color: muted)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationSurface extends StatelessWidget {
  const _LocationSurface({required this.location, required this.index});

  final PainLocation location;
  final int index;

  @override
  Widget build(BuildContext context) {
    final mode = isQuickPainLocation(location)
        ? '速记'
        : location.coordinateMode == '3d'
        ? '3D 人体模型'
        : '2D 人体模型';
    final model = isQuickPainLocation(location)
        ? '未使用人体模型'
        : '${location.displayAnatomyLayer.label}模型${_organGroupSuffix(location)}';
    final depth = switch (location.depthState) {
      'surface' => '表面',
      'known' when location.depthMeters != null =>
        '皮下约 ${(location.depthMeters! * 100).toStringAsFixed(1)} cm',
      'internal_unknown' => location.layer.label,
      _ => '说不清楚',
    };
    return _DetailSurface(
      children: [
        _DetailRow(label: '痛点 $index', value: location.partName),
        _DetailRow(label: '记录方式', value: mode),
        _DetailRow(label: '显示模型', value: model),
        _DetailRow(label: '形态与深度', value: '${location.shape.label} · $depth'),
        _DetailRow(
          label: '程度与感觉',
          value: [
            '${location.intensity0to10}/10',
            ...location.sensations,
          ].join(' · '),
          divider: false,
        ),
      ],
    );
  }

  String _organGroupSuffix(PainLocation location) {
    if (location.displayAnatomyLayer != BodyLayer.organ ||
        location.organGroup == 'all') {
      return '';
    }
    final group = switch (location.organGroup) {
      'digestive' => '消化系统',
      'respiratory' => '呼吸系统',
      'urinary' => '泌尿系统',
      'reproductive' => '生殖系统',
      'nervous' => '神经系统',
      _ => location.organGroup,
    };
    return ' · $group';
  }
}
