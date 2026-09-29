import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhiteng_app/core/haptics.dart';
import 'package:zhiteng_app/features/profile/settings_page.dart';
import 'package:zhiteng_app/features/record/widgets/marker_controls.dart';
import 'package:zhiteng_app/state/controllers.dart';
import 'package:zhiteng_app/widgets/zt_controls.dart';
import 'package:zhiteng_app/widgets/zt_motion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String?> impacts;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    impacts = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            impacts.add(call.arguments as String?);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pump(
    WidgetTester tester, {
    required Widget home,
    AppSettingsController? settings,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings ?? AppSettingsController(),
        child: MaterialApp(home: Scaffold(body: home)),
      ),
    );
  }

  testWidgets('taps use a stronger impact as the action gets heavier', (
    tester,
  ) async {
    await pump(
      tester,
      home: Column(
        children: [
          const ZtButton(label: '保存', onPressed: _noop),
          ZtChip(label: '跳痛', selected: false, onTap: _noop),
          const _LevelButton('删除', ZtHaptic.heavy),
        ],
      ),
    );

    await tester.tap(_pressable(find.text('跳痛')));
    await tester.tap(_pressable(find.text('保存')));
    await tester.tap(find.text('删除'));
    await tester.pump();

    expect(impacts, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
    ]);
  });

  testWidgets(
    'the settings switch silences later taps and confirms when reopened',
    (tester) async {
      final settings = AppSettingsController();
      await pump(
        tester,
        settings: settings,
        home: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                },
                child: const Text('打开设置'),
              ),
              const ZtButton(label: '保存', onPressed: _noop),
            ],
          ),
        ),
      );

      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      impacts.clear();

      await tester.tap(find.text('关闭触感反馈'));
      await tester.pumpAndSettle();
      expect(settings.disableHapticFeedback, isTrue);
      expect(impacts, ['HapticFeedbackType.selectionClick']);

      await tester.pageBack();
      await tester.pumpAndSettle();
      impacts.clear();

      await tester.tap(_pressable(find.text('保存')));
      await tester.pump();
      expect(impacts, isEmpty);

      await tester.tap(find.text('打开设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭触感反馈'));
      await tester.pumpAndSettle();
      expect(settings.disableHapticFeedback, isFalse);
      expect(impacts, ['HapticFeedbackType.mediumImpact']);
    },
  );

  testWidgets('a muted subtree stays silent', (tester) async {
    await pump(
      tester,
      home: const ZtHapticsScope(
        enabled: false,
        child: ZtButton(label: '完成本痛点', onPressed: _noop),
      ),
    );

    await tester.tap(_pressable(find.text('完成本痛点')));
    await tester.pump();

    expect(impacts, isEmpty);
  });

  testWidgets('a held control pulses on a cadence and confirms the release', (
    tester,
  ) async {
    await pump(tester, home: const _CadenceHost());

    await tester.tap(find.text('步进'));
    await tester.pump();
    expect(impacts, ['HapticFeedbackType.selectionClick']);

    await tester.tap(find.text('步进'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(impacts, ['HapticFeedbackType.selectionClick']);

    await tester.tap(find.text('松开'));
    await tester.pump(const Duration(milliseconds: 180));
    expect(impacts, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  testWidgets('held-control haptics follow the settings switch', (
    tester,
  ) async {
    final settings = AppSettingsController()..disableHapticFeedback = true;
    await pump(tester, settings: settings, home: const _CadenceHost());

    await tester.tap(find.text('步进'));
    await tester.tap(find.text('松开'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(impacts, isEmpty);
  });

  testWidgets('a size slider vibrates when grabbed and when released', (
    tester,
  ) async {
    await pump(tester, home: MarkerSizeSlider(value: 1.5, onChanged: (_) {}));

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pump();

    expect(impacts, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
  });
}

class _LevelButton extends StatelessWidget {
  const _LevelButton(this.label, this.level);

  final String label;
  final ZtHaptic level;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => ztHaptic(context, level),
      child: Text(label),
    );
  }
}

class _CadenceHost extends StatefulWidget {
  const _CadenceHost();

  @override
  State<_CadenceHost> createState() => _CadenceHostState();
}

class _CadenceHostState extends State<_CadenceHost> {
  final _cadence = ZtHapticCadence(gap: const Duration(milliseconds: 180));

  @override
  void dispose() {
    _cadence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextButton(
          onPressed: () => _cadence.step(context),
          child: const Text('步进'),
        ),
        TextButton(
          onPressed: () => _cadence.end(context),
          child: const Text('松开'),
        ),
      ],
    );
  }
}

Finder _pressable(Finder label) {
  return find.ancestor(of: label, matching: find.byType(ZtPressableScale));
}

void _noop() {}
