import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../state/controllers.dart';
import '../../widgets/zt_motion.dart';
import 'profile_section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();

    final canPop = ModalRoute.of(context)?.canPop ?? false;
    return ZtSwipeBackPage(
      child: Scaffold(
        appBar: AppBar(
          leading: canPop ? const ZtBackButton() : null,
          title: const Text('设置'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            ProfileSection(
              title: '外观',
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    ZtPressableScale(
                      pressEnabled: true,
                      tapScale: 0.98,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_themeModeLabel(mode)),
                        trailing: Icon(
                          settings.themeMode == mode
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: settings.themeMode == mode
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outline,
                        ),
                        onTap: () {
                          ztHaptic(context, ZtHaptic.selection);
                          settings.setThemeMode(mode);
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ProfileSection(
              title: '交互',
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('减少动画效果'),
                    subtitle: const Text('关闭页面转场和按钮点击动效'),
                    value: settings.reduceAnimations,
                    onChanged: (value) {
                      ztHaptic(context, ZtHaptic.selection);
                      settings.setReduceAnimations(value);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('关闭触感反馈'),
                    subtitle: const Text('关闭点击时的震动'),
                    value: settings.disableHapticFeedback,
                    onChanged: (disable) {
                      if (disable) {
                        ztHaptic(context, ZtHaptic.selection);
                        settings.setDisableHapticFeedback(true);
                      } else {
                        settings.setDisableHapticFeedback(false);
                        ztHaptic(context, ZtHaptic.medium);
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色模式',
    ThemeMode.dark => '暗色模式',
  };
}
