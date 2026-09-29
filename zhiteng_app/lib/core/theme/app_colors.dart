import 'package:flutter/material.dart';

/// UI tokens sampled from the Cursor chat light/dark chrome.
/// Avatar colors are not part of this palette.
/// Pain colors and [bodyClinical] / [bodyStage] stay on their own scale.
abstract final class AppColors {
  // Light
  static const lightPage = Color(0xFFFCFCFC);
  static const lightSurface = Color(0xFFEEEEEE);
  static const lightSubtle = Color(0xFFE1E1E1);
  static const lightPrimary = Color(0xFF141414);
  static const lightPrimaryPressed = Color(0xFF0A0A0A);
  static const lightPrimarySoft = Color(0xFFE8E8E8);
  static const lightTextPrimary = Color(0xFF141414);
  static const lightTextSecondary = Color(0xFF5E5E5E);
  static const lightTextTertiary = Color(0xFF8E8E8E);
  static const lightBorder = Color(0xFFE4E4E4);
  static const lightDisabled = Color(0xFFC8C8C8);
  static const lightOnPrimary = Color(0xFFFFFFFF);
  static const lightLink = Color(0xFF1D66C0);

  // Dark
  static const darkPage = Color(0xFF070707);
  static const darkSurface = Color(0xFF262626);
  static const darkElevated = Color(0xFF2F2F2F);
  static const darkPrimary = Color(0xFFE8E8E8);
  static const darkPrimaryPressed = Color(0xFFD0D0D0);
  static const darkPrimarySoft = Color(0xFF313131);
  static const darkTextPrimary = Color(0xFFE8E8E8);
  static const darkTextSecondary = Color(0xFF939393);
  static const darkTextTertiary = Color(0xFF6A6A6A);
  static const darkBorder = Color(0xFF333333);
  static const darkDisabled = Color(0xFF3A3A3A);
  static const darkOnPrimary = Color(0xFF141414);
  static const darkLink = Color(0xFF6AA6F5);

  // Pain semantics (not brand)
  static const painMarker = Color(0xFFE64340);
  static const painMild = Color(0xFFC49A36);
  static const painModerate = Color(0xFFD46F3D);
  static const painStrong = Color(0xFFC44755);
  static const painSevere = Color(0xFF8E2943);

  /// Bright red for the top step only.
  static const painMax = Color(0xFFFF0000);

  // Clinical body (疼痛坐标-like neutral mesh)
  static const bodyClinical = Color(0xFFB0B0B0);

  /// Near-white drafting paper behind the body in light mode. The WebView
  /// draws its own grid on top of this, so it must match `assets/web/body3d.html`.
  static const bodyStage = Color(0xFFFCFCFC);

  /// Stage fill behind the body model. Light mode keeps [bodyStage]. Dark mode
  /// uses the same elevated gray as the history list and detail snapshots.
  static Color bodyStageFor({required bool dark}) =>
      dark ? darkElevated : bodyStage;

  /// Stroke around a history card or body snapshot. Stronger than the regular
  /// border so the frame stays visible against both the page and the stage.
  static Color stageFrame({required bool dark}) =>
      dark ? const Color(0xFF5A5A5A) : const Color(0xFFC6C6C6);

  /// Unfilled track of the length / size sliders that sit on the body stage.
  /// [darkBorder] (#333) on [darkElevated] (#2F2F2F) and [lightBorder] on the
  /// paper stage both disappear, especially in dark mode.
  static Color stageScaleTrack({required bool dark}) =>
      dark ? const Color(0xFFE0E0E0) : const Color(0xFF4F4F4F);

  /// Outline behind [stageScaleTrack] so the line still reads when it crosses
  /// the pale body mesh.
  static Color stageScaleTrackHalo({required bool dark}) =>
      dark ? const Color(0xB3000000) : const Color(0xF2FFFFFF);
}

Color intensityColor(int intensity0to10, {required bool dark}) {
  final yellow = dark ? const Color(0xFFD6B455) : AppColors.painMild;
  final step = intensity0to10.clamp(1, 10);
  return Color.lerp(yellow, AppColors.painMax, (step - 1) / 9)!;
}
