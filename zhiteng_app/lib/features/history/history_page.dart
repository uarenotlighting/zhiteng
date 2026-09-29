import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/pain_models.dart';
import '../../core/theme/app_colors.dart';
import '../../state/controllers.dart';
import '../../widgets/pain_body_snapshot.dart';
import '../../widgets/zt_motion.dart';
import 'history_detail_page.dart';
import 'history_formatters.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final records = context.watch<PainRecordsController>();
    final finished = records.finishedEntries;

    return Scaffold(
      appBar: AppBar(title: const Text('疼痛记录')),
      body: records.loading
          ? const Center(child: CircularProgressIndicator())
          : finished.isEmpty
          ? Center(
              child: Text(
                '结束之后的疼痛会留在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  height: 1.5,
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            )
          : HistoryRecordGrid(entries: finished),
    );
  }
}

class HistoryRecordGrid extends StatelessWidget {
  const HistoryRecordGrid({super.key, required this.entries});

  final List<PainEntry> entries;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 274,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) => HistoryRecordCard(entry: entries[index]),
    );
  }
}

class HistoryRecordCard extends StatelessWidget {
  const HistoryRecordCard({super.key, required this.entry});

  final PainEntry entry;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final surface = dark ? AppColors.darkSurface : AppColors.lightSurface;
    final sensations = latestPainSensations(entry);
    final duration = painDurationLabel(entry).replaceFirst('持续 ', '');
    return ZtOpenContainer<void>(
      closedBorderRadius: BorderRadius.circular(18),
      closedClipBehavior: Clip.none,
      openBuilder: (_) => HistoryDetailPage(entry: entry),
      closedBuilder: (_, open) => ZtPressableScale(
        onTap: open,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(18),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.stageFrame(dark: dark)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 148,
                width: double.infinity,
                child: PainBodySnapshot(
                  locations: entry.locations,
                  compact: true,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              painPointNames(entry),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          const Text('疼痛等级：', style: TextStyle(fontSize: 10)),
                          Text(
                            '${entry.intensity0to10}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: intensityColor(
                                entry.intensity0to10,
                                dark: dark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _SensationTags(sensations: sensations, dark: dark),
                      const SizedBox(height: 7),
                      _CardTimeLine(
                        label: '开始时间：',
                        value: DateFormat(
                          'MM/dd HH:mm',
                        ).format(entry.startedAt),
                        color: muted,
                      ),
                      const SizedBox(height: 2),
                      _CardTimeLine(
                        label: '结束时间：',
                        value: entry.endedAt == null
                            ? '仍在持续'
                            : DateFormat('MM/dd HH:mm').format(entry.endedAt!),
                        color: muted,
                      ),
                      const SizedBox(height: 2),
                      _CardTimeLine(
                        label: '持续时长：',
                        value: duration,
                        color: muted,
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SensationTags extends StatelessWidget {
  const _SensationTags({required this.sensations, required this.dark});

  final List<String> sensations;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final visible = sensations.isEmpty
        ? const ['未记录感受']
        : sensations.length <= 2
        ? sensations
        : [sensations.first, '+${sensations.length - 1}'];
    return SizedBox(
      height: 21,
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Flexible(
              child: Container(
                key: const ValueKey('history-sensation-tag'),
                constraints: const BoxConstraints(maxWidth: 72),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: dark
                      ? AppColors.darkElevated
                      : AppColors.lightPrimarySoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  visible[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardTimeLine extends StatelessWidget {
  const _CardTimeLine({
    required this.label,
    required this.value,
    required this.color,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 10, height: 1.2, color: color)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w400,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
