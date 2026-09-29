import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/pain_models.dart';
import '../data/pain_repository.dart';

class AppSettingsController extends ChangeNotifier {
  static const _themeKey = 'zhiteng_theme_mode';
  static const _onboardingKey = 'zhiteng_onboarding_done';
  static const _reduceAnimationsKey = 'zhiteng_reduce_animations';
  static const _disableHapticFeedbackKey = 'zhiteng_disable_haptic_feedback';

  ThemeMode themeMode = ThemeMode.system;
  bool onboardingCompleted = false;

  /// Skips page transitions and button press scale.
  bool reduceAnimations = false;

  /// Tap haptics should no-op when this is true. Check it before vibrating.
  bool disableHapticFeedback = false;
  bool ready = false;

  Future<void> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_themeKey) ?? 'system';
    themeMode = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    onboardingCompleted = prefs.getBool(_onboardingKey) ?? false;
    reduceAnimations = prefs.getBool(_reduceAnimationsKey) ?? false;
    disableHapticFeedback = prefs.getBool(_disableHapticFeedbackKey) ?? false;
    ready = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    final wire = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await prefs.setString(_themeKey, wire);
    notifyListeners();
  }

  Future<void> setReduceAnimations(bool value) async {
    if (reduceAnimations == value) return;
    reduceAnimations = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_reduceAnimationsKey, value);
  }

  Future<void> setDisableHapticFeedback(bool value) async {
    if (disableHapticFeedback == value) return;
    disableHapticFeedback = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disableHapticFeedbackKey, value);
  }

  Future<void> completeOnboarding() async {
    onboardingCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
    notifyListeners();
  }
}

class PainRecordsController extends ChangeNotifier {
  PainRecordsController(this._repository);

  final PainRepository _repository;
  List<PainEntry> entries = const [];
  bool loading = true;

  List<PainEntry> get ongoingEntries =>
      entries.where((entry) => entry.isOngoing).toList(growable: false);

  List<PainEntry> get finishedEntries =>
      entries.where((entry) => !entry.isOngoing).toList(growable: false);

  Future<void> refresh() async {
    loading = true;
    notifyListeners();
    entries = await _repository.listEntries();
    loading = false;
    notifyListeners();
  }

  Future<PainEntry> save({
    required DateTime startedAt,
    DateTime? endedAt,
    required List<PainLocation> locations,
    required int intensity0to10,
    required String notes,
    List<MedicationRecord> medications = const [],
  }) async {
    final entry = await _repository.saveEntry(
      startedAt: startedAt,
      endedAt: endedAt,
      locations: locations,
      intensity0to10: intensity0to10,
      notes: notes,
      medications: medications,
    );
    await refresh();
    return entry;
  }

  /// Appends whatever changed on an open pain. Nothing new leaves the record
  /// as it was and reports [PainUpdateOutcome.unchanged].
  Future<PainUpdateOutcome> revise({
    required PainEntry previous,
    required PainMomentDraft draft,
  }) async {
    final outcome = await _repository.reviseEntry(
      previous: previous,
      draft: draft,
    );
    if (outcome.saved) await refresh();
    return outcome;
  }

  Future<String> exportJson() => _repository.exportJson();

  Future<void> clearAll() async {
    await _repository.deleteAll();
    await refresh();
  }
}
