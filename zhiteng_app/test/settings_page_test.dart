import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiteng_app/core/theme/app_theme.dart';
import 'package:zhiteng_app/data/pain_repository.dart';
import 'package:zhiteng_app/features/profile/profile_page.dart';
import 'package:zhiteng_app/features/profile/settings_page.dart';
import 'package:zhiteng_app/state/controllers.dart';
import 'package:zhiteng_app/widgets/zt_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('profile settings icon opens appearance and feedback switches', (
    tester,
  ) async {
    final settings = AppSettingsController();
    final records = PainRecordsController(PainRepository());

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: records),
        ],
        child: MaterialApp(theme: buildLightTheme(), home: const ProfilePage()),
      ),
    );

    expect(find.text('外观'), findsNothing);

    await tester.tap(find.byTooltip('设置'));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('浅色模式'), findsOneWidget);
    expect(find.text('暗色模式'), findsOneWidget);
    expect(find.text('减少动画效果'), findsOneWidget);
    expect(find.text('关闭触感反馈'), findsOneWidget);
  });

  testWidgets('reduce animations turns off press scale and page transitions', (
    tester,
  ) async {
    final settings = AppSettingsController();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: const _MotionSettingsHost(),
      ),
    );

    final button = find.text('按一下');
    final scale = find.descendant(
      of: find.byType(ZtButton),
      matching: find.byType(AnimatedScale),
    );
    final press = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.widget<AnimatedScale>(scale).scale, 0.96);
    await press.up();
    await tester.pump(const Duration(milliseconds: 140));

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('减少动画效果'));
    await tester.pumpAndSettle();
    expect(settings.reduceAnimations, isTrue);

    final theme = Theme.of(tester.element(find.byType(SettingsPage)));
    final transition =
        theme.pageTransitionsTheme.builders[Theme.of(
          tester.element(find.byType(SettingsPage)),
        ).platform]!;
    expect(transition.transitionDuration, Duration.zero);

    await tester.tap(find.text('关闭触感反馈'));
    await tester.pumpAndSettle();
    expect(settings.disableHapticFeedback, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final pressAgain = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 20));
    expect(tester.widget<AnimatedScale>(scale).scale, 1);
    await pressAgain.up();
  });
}

class _MotionSettingsHost extends StatelessWidget {
  const _MotionSettingsHost();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    return MaterialApp(
      theme: buildLightTheme(reduceAnimations: settings.reduceAnimations),
      darkTheme: buildDarkTheme(reduceAnimations: settings.reduceAnimations),
      home: Scaffold(
        body: Column(
          children: [
            const ZtButton(label: '按一下', onPressed: _noop),
            Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                child: const Text('打开设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _noop() {}
