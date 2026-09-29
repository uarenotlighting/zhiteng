import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/theme/app_colors.dart';
import '../../state/controllers.dart';
import '../../widgets/zt_motion.dart';
import '../../widgets/zt_toast.dart';
import 'profile_section.dart';
import 'settings_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final records = context.watch<PainRecordsController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          ZtPressableScale(
            pressEnabled: true,
            tapScale: 0.92,
            child: IconButton(
              tooltip: '设置',
              onPressed: () {
                ztHaptic(context, ZtHaptic.light);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
                );
              },
              icon: const Icon(Icons.settings_outlined),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          ProfileSection(
            title: '数据',
            child: Column(
              children: [
                ZtPressableScale(
                  pressEnabled: true,
                  tapScale: 0.98,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('导出全部记录 (JSON)'),
                    subtitle: const Text('可复制后备份，或交给后续 PDF/就医摘要能力'),
                    trailing: const Icon(Icons.copy_outlined, size: 20),
                    onTap: () async {
                      ztHaptic(context, ZtHaptic.light);
                      try {
                        final json = await records.exportJson();
                        await Clipboard.setData(ClipboardData(text: json));
                        if (!context.mounted) return;
                        ZtToast.success(context, '已复制到剪贴板');
                      } catch (_) {
                        if (!context.mounted) return;
                        ZtToast.failure(context, '暂时无法复制，请稍后再试');
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ZtPressableScale(
                  pressEnabled: true,
                  tapScale: 0.98,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '清空本地演示数据',
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFDC6671)
                            : AppColors.painStrong,
                      ),
                    ),
                    onTap: () async {
                      ztHaptic(context, ZtHaptic.medium);
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('清空本地记录？'),
                          content: const Text('只会删除本机数据，不会影响尚未接入的云端账号。'),
                          actions: [
                            ZtPressableScale(
                              pressEnabled: true,
                              tapScale: 0.94,
                              child: TextButton(
                                onPressed: () {
                                  ztHaptic(context, ZtHaptic.light);
                                  Navigator.pop(context, false);
                                },
                                child: const Text('取消'),
                              ),
                            ),
                            ZtPressableScale(
                              pressEnabled: true,
                              tapScale: 0.94,
                              child: TextButton(
                                onPressed: () {
                                  ztHaptic(context, ZtHaptic.heavy);
                                  Navigator.pop(context, true);
                                },
                                child: const Text('清空'),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await records.clearAll();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ProfileSection(
            title: '关于',
            child: Text(
              '知疼帮助你记录疼痛位置、时间和变化，方便回顾与就医沟通。'
              '产品不提供疾病诊断或用药处方。\n\n'
              'App 技术路线：Flutter + SQLite；3D 定位参考「疼痛坐标」交互，'
              '使用 Three.js 加载低模 GLB（Blender 管线兼容）。',
              style: TextStyle(
                height: 1.55,
                color: dark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
