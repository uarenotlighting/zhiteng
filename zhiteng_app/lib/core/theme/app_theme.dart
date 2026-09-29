import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/zt_motion.dart';
import 'app_colors.dart';

const WidgetStateProperty<Color?> _noTapOverlay =
    WidgetStatePropertyAll<Color?>(Colors.transparent);

ButtonStyle _withoutButtonOverlay(ButtonStyle? style) {
  return (style ?? const ButtonStyle()).copyWith(overlayColor: _noTapOverlay);
}

ThemeData _withoutTapOverlays(ThemeData theme) {
  return theme.copyWith(
    splashColor: Colors.transparent,
    highlightColor: Colors.transparent,
    hoverColor: Colors.transparent,
    focusColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    iconButtonTheme: IconButtonThemeData(
      style: _withoutButtonOverlay(theme.iconButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: _withoutButtonOverlay(theme.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: _withoutButtonOverlay(theme.elevatedButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: _withoutButtonOverlay(theme.outlinedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: _withoutButtonOverlay(theme.filledButtonTheme.style),
    ),
    tabBarTheme: theme.tabBarTheme.copyWith(overlayColor: _noTapOverlay),
  );
}

PageTransitionsTheme _pageTransitions({required bool reduceAnimations}) {
  final builder = ZtPageTransitionsBuilder(reduceMotion: reduceAnimations);
  return PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: builder,
      TargetPlatform.iOS: builder,
      TargetPlatform.macOS: builder,
      TargetPlatform.windows: builder,
      TargetPlatform.linux: builder,
      TargetPlatform.fuchsia: builder,
    },
  );
}

ThemeData buildLightTheme({bool reduceAnimations = false}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.lightPage,
    colorScheme: const ColorScheme.light(
      primary: AppColors.lightPrimary,
      onPrimary: AppColors.lightOnPrimary,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightTextPrimary,
      secondary: AppColors.lightTextSecondary,
      outline: AppColors.lightBorder,
    ),
  );

  return _withoutTapOverlays(
    base.copyWith(
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.lightPage,
        foregroundColor: AppColors.lightTextPrimary,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.lightTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.lightBorder,
      cardTheme: CardThemeData(
        color: AppColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.lightBorder),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.lightPage,
        selectedItemColor: AppColors.lightPrimary,
        unselectedItemColor: AppColors.lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: _navigationBarTheme(
        backgroundColor: AppColors.lightPage,
        selectedColor: AppColors.lightPrimary,
        unselectedColor: AppColors.lightTextSecondary,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.lightPrimary,
        inactiveTrackColor: AppColors.lightPrimarySoft,
        thumbColor: AppColors.lightPrimary,
        overlayColor: Colors.transparent,
      ),
      pageTransitionsTheme: _pageTransitions(
        reduceAnimations: reduceAnimations,
      ),
    ),
  );
}

ThemeData buildDarkTheme({bool reduceAnimations = false}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.darkPage,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.darkPrimary,
      onPrimary: AppColors.darkOnPrimary,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      secondary: AppColors.darkTextSecondary,
      outline: AppColors.darkBorder,
    ),
  );

  return _withoutTapOverlays(
    base.copyWith(
      appBarTheme: const AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: AppColors.darkPage,
        foregroundColor: AppColors.darkTextPrimary,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.darkTextPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerColor: AppColors.darkBorder,
      cardTheme: CardThemeData(
        color: AppColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.darkElevated,
        selectedItemColor: AppColors.darkPrimary,
        unselectedItemColor: AppColors.darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: _navigationBarTheme(
        backgroundColor: AppColors.darkElevated,
        selectedColor: AppColors.darkPrimary,
        unselectedColor: AppColors.darkTextSecondary,
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: AppColors.darkPrimary,
        inactiveTrackColor: AppColors.darkPrimarySoft,
        thumbColor: AppColors.darkPrimary,
        overlayColor: Colors.transparent,
      ),
      pageTransitionsTheme: _pageTransitions(
        reduceAnimations: reduceAnimations,
      ),
    ),
  );
}

NavigationBarThemeData _navigationBarTheme({
  required Color backgroundColor,
  required Color selectedColor,
  required Color unselectedColor,
}) {
  Color itemColor(Set<WidgetState> states) {
    return states.contains(WidgetState.selected)
        ? selectedColor
        : unselectedColor;
  }

  return NavigationBarThemeData(
    backgroundColor: backgroundColor,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    indicatorColor: Colors.transparent,
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    iconTheme: WidgetStateProperty.resolveWith(
      (states) => IconThemeData(color: itemColor(states)),
    ),
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        color: itemColor(states),
        fontSize: 12,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w600
            : FontWeight.w500,
      ),
    ),
  );
}
