import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/models/pain_models.dart';
import '../core/theme/app_colors.dart';

String formatPainMomentClock(DateTime at, DateTime startedAt) {
  final sameDay =
      at.year == startedAt.year &&
      at.month == startedAt.month &&
      at.day == startedAt.day;
  if (sameDay) return DateFormat('HH:mm').format(at);
  return DateFormat('MM/dd HH:mm').format(at);
}

String painEpisodeWhen(PainEntry entry) {
  final start = DateFormat('MM/dd HH:mm').format(entry.startedAt);
  final ended = entry.endedAt;
  if (ended == null) return start;
  final end = formatPainMomentClock(ended, entry.startedAt);
  return '$start–$end';
}

class PainTimelineView extends StatelessWidget {
  const PainTimelineView({
    super.key,
    required this.startedAt,
    required this.moments,
  });

  final DateTime startedAt;
  final List<PainMoment> moments;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final primary = dark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final connector = dark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextTertiary;
    const lineWidth = 1.5;
    const nodeSize = 8.0;
    const railGap = 14.0;
    const rowGap = 26.0;
    const titleSize = 16.0;
    const titleHeight = 1.25;
    final textScaler = MediaQuery.textScalerOf(context);
    final titleLineHeight = textScaler.scale(titleSize) * titleHeight;
    final nodeCenterY = titleLineHeight / 2;
    final titleStyle = TextStyle(
      color: primary,
      fontSize: titleSize,
      fontWeight: FontWeight.w600,
      height: titleHeight,
    );
    final timeStyle = TextStyle(
      color: muted,
      fontSize: 13,
      height: titleHeight,
    );
    final detailStyle = TextStyle(color: muted, fontSize: 14, height: 1.45);
    final lines = painCourseLines(moments);
    return Column(
      children: [
        for (var i = 0; i < lines.length; i++)
          Stack(
            children: [
              if (i > 0)
                Positioned(
                  left: nodeSize / 2 - lineWidth / 2,
                  top: 0,
                  width: lineWidth,
                  height: nodeCenterY,
                  child: ColoredBox(color: connector),
                ),
              if (i < lines.length - 1)
                Positioned(
                  left: nodeSize / 2 - lineWidth / 2,
                  top: nodeCenterY,
                  bottom: 0,
                  width: lineWidth,
                  child: ColoredBox(color: connector),
                ),
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == lines.length - 1 ? 0 : rowGap,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: nodeSize,
                      height: titleLineHeight,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == lines.length - 1
                                ? AppColors.painMarker
                                : connector,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: nodeSize),
                        ),
                      ),
                    ),
                    const SizedBox(width: railGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(lines[i].title, style: titleStyle),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                formatPainMomentClock(
                                  lines[i].moment.at,
                                  startedAt,
                                ),
                                style: timeStyle,
                              ),
                            ],
                          ),
                          if (lines[i].detail.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(lines[i].detail, style: detailStyle),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}
