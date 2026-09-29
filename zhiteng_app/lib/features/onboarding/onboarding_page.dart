import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../state/controllers.dart';
import '../../widgets/zt_controls.dart';

class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key, required this.settings});

  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '知疼',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: dark
                      ? AppColors.darkTextPrimary
                      : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '用身体地图记录疼痛，逐渐看懂自己的变化，也让就医表达更清楚。',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  color: dark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 28),
              _Point(title: '标出位置', body: '在 3D 或示意人体上点选，区分表面与深处。', dark: dark),
              _Point(title: '留下时间与强度', body: '发作时先记下来，恢复后再补充也没关系。', dark: dark),
              _Point(
                title: '给医生看得懂的材料',
                body: '可导出记录；后续会支持批量就医摘要。',
                dark: dark,
              ),
              const Spacer(),
              Text(
                '知疼不是诊断工具，也不会替代医生的判断。',
                style: TextStyle(
                  fontSize: 12,
                  color: dark
                      ? AppColors.darkTextTertiary
                      : AppColors.lightTextTertiary,
                ),
              ),
              const SizedBox(height: 14),
              ZtButton(
                label: '开始使用',
                onPressed: () => settings.completeOnboarding(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.title, required this.body, required this.dark});

  final String title;
  final String body;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: AppColors.painMarker,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    height: 1.45,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
