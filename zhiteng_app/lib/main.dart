import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'data/pain_repository.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/shell/main_shell.dart';
import 'state/controllers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = AppSettingsController();
  final repository = PainRepository();
  final records = PainRecordsController(repository);
  await settings.bootstrap();
  await records.refresh();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: records),
      ],
      child: const ZhitengApp(),
    ),
  );
}

class ZhitengApp extends StatelessWidget {
  const ZhitengApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    final Widget stage = !settings.ready
        ? const Scaffold(
            key: ValueKey('loading'),
            body: Center(child: CircularProgressIndicator()),
          )
        : settings.onboardingCompleted
        ? const MainShell(key: ValueKey('main'))
        : OnboardingPage(key: const ValueKey('onboarding'), settings: settings);

    return MaterialApp(
      title: '知疼',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildLightTheme(reduceAnimations: settings.reduceAnimations),
      darkTheme: buildDarkTheme(reduceAnimations: settings.reduceAnimations),
      themeMode: settings.themeMode,
      home: AnimatedSwitcher(
        duration: settings.reduceAnimations
            ? Duration.zero
            : const Duration(milliseconds: 350),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final reduceMotion =
              settings.reduceAnimations ||
              WidgetsBinding
                  .instance
                  .platformDispatcher
                  .accessibilityFeatures
                  .disableAnimations;
          if (reduceMotion) return child;
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: stage,
      ),
    );
  }
}
