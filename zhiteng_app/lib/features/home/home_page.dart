import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../state/controllers.dart';
import '../../widgets/zt_controls.dart';
import '../../widgets/zt_motion.dart';
import '../record/record_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final records = context.watch<PainRecordsController>();
    final ongoing = records.ongoingEntries;

    return Scaffold(
      appBar: AppBar(title: const Text('知疼')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: dark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: dark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '让每一次疼痛，都被看见。',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                      color: dark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在身体上标出位置，留下时间和强度。就医时可以说得更清楚。',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: dark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ZtOpenContainer<void>(
                    closedBorderRadius: BorderRadius.circular(14),
                    openBuilder: (_) => const RecordPage(),
                    closedBuilder: (_, open) =>
                        ZtButton(label: '记一次疼痛', onPressed: open),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '正在记录的疼痛',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: dark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${ongoing.length} 条',
                  style: TextStyle(
                    color: dark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                ),
              ],
            ),
            if (ongoing.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '点进去可以补充变化，也可以记下结束。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: records.loading
                  ? const Center(child: CircularProgressIndicator())
                  : ongoing.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: dark
                              ? AppColors.darkElevated
                              : AppColors.lightPrimarySoft,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '现在没有还在持续的疼痛。',
                          style: TextStyle(
                            color: dark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('home-ongoing-pain-list'),
                      padding: const EdgeInsets.only(bottom: 28),
                      itemCount: ongoing.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final entry = ongoing[index];
                        final time = DateFormat(
                          'MM/dd HH:mm',
                        ).format(entry.startedAt);
                        return ZtOpenContainer<void>(
                          closedBorderRadius: BorderRadius.circular(16),
                          openBuilder: (_) => RecordPage(ending: entry),
                          closedBuilder: (_, open) => ZtPressableScale(
                            onTap: open,
                            child: Material(
                              color: dark
                                  ? AppColors.darkSurface
                                  : AppColors.lightSurface,
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: dark
                                        ? AppColors.darkBorder
                                        : AppColors.lightBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: const BoxDecoration(
                                        color: AppColors.painMarker,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.primaryPartName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '从 $time 开始 · 现在 ${entry.intensity0to10} 级',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: dark
                                                  ? AppColors.darkTextSecondary
                                                  : AppColors
                                                        .lightTextSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      '${entry.intensity0to10}/10',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: intensityColor(
                                          entry.intensity0to10,
                                          dark: dark,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: dark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextTertiary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
