import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/widgets/zt_toast.dart';

// End-to-end failure modes covered before the toast implementation:
// - a toast stretches into the full-width SnackBar shown in the old UI;
// - a toast sits behind or on top of the bottom navigation bar;
// - text, success, failure, and loading feedback cannot replace one another;
// - loading feedback disappears on a timer or cannot be dismissed explicitly;
// - a timed toast remains in the overlay after its duration;
// - dark mode leaves the toast with unreadable foreground/background colors.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('toast feedback variants share one compact overlay', (
    tester,
  ) async {
    binding.reportData = {
      'variants': ['text', 'success', 'failure', 'loading'],
      'placement': 'floating above bottom navigation',
      'themes': ['light', 'dark'],
    };

    await tester.pumpWidget(
      MaterialApp(
        theme: buildLightTheme(),
        darkTheme: buildDarkTheme(),
        home: const _ToastHost(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('纯文字'));
    await tester.pump(const Duration(milliseconds: 240));
    final toast = find.byKey(const ValueKey('zt-toast'));
    expect(toast, findsOneWidget);
    expect(find.text('已复制到剪贴板'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final toastRect = tester.getRect(toast);
    final navigationRect = tester.getRect(find.byType(NavigationBar));
    expect(toastRect.width, lessThan(360));
    expect(toastRect.bottom, lessThan(navigationRect.top));
    await binding.takeScreenshot('toast-text-light');

    await tester.pump(const Duration(seconds: 3));
    expect(toast, findsNothing);

    await tester.tap(find.text('成功'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('已经帮你记下来了。'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await binding.takeScreenshot('toast-success-light');

    await tester.tap(find.text('失败'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('暂时没有保存成功'), findsOneWidget);
    expect(find.text('已经帮你记下来了。'), findsNothing);
    expect(find.byIcon(Icons.priority_high_rounded), findsOneWidget);

    await tester.tap(find.text('加载'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('正在保存…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('正在保存…'), findsOneWidget);
    await binding.takeScreenshot('toast-loading-light');

    await tester.tap(find.text('关闭 loading'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(toast, findsNothing);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('成功'));
    await tester.pump(const Duration(milliseconds: 240));
    expect(find.text('已经帮你记下来了。'), findsOneWidget);
    final darkToast = tester.widget<Material>(toast);
    expect(darkToast.color, isNot(ThemeData.dark().scaffoldBackgroundColor));
    await binding.takeScreenshot('toast-success-dark');
    ZtToast.dismiss();
    await tester.pump(const Duration(milliseconds: 160));
  });
}

class _ToastHost extends StatefulWidget {
  const _ToastHost();

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _themeMode == ThemeMode.dark ? buildDarkTheme() : buildLightTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Toast 验证'),
          actions: [
            IconButton(
              onPressed: () => setState(() {
                _themeMode = _themeMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
              }),
              icon: const Icon(Icons.dark_mode_outlined),
            ),
          ],
        ),
        body: Builder(
          builder: (context) => Center(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(
                  onPressed: () => ZtToast.text(context, '已复制到剪贴板'),
                  child: const Text('纯文字'),
                ),
                FilledButton(
                  onPressed: () => ZtToast.success(context, '已经帮你记下来了。'),
                  child: const Text('成功'),
                ),
                FilledButton(
                  onPressed: () => ZtToast.failure(context, '暂时没有保存成功'),
                  child: const Text('失败'),
                ),
                FilledButton(
                  onPressed: () => ZtToast.loading(context, '正在保存…'),
                  child: const Text('加载'),
                ),
                OutlinedButton(
                  onPressed: ZtToast.dismiss,
                  child: const Text('关闭 loading'),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.edit_note), label: '记录'),
            NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          ],
        ),
      ),
    );
  }
}
