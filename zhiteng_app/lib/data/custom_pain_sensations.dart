import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/pain_models.dart';

/// Personal pain words typed by this user.
///
/// Stored only on this device for now, newest first, and kept apart from
/// [painSensationOptions]. A later account sync can upload this list and keep
/// it as this user's own sensation vocabulary on the server. Do not merge
/// these words into the shared catalog, and do not treat a missing server
/// copy as permission to delete the local list.
class CustomPainSensationStore {
  static const storageKey = 'zhiteng_custom_pain_sensations_v1';

  Future<List<String>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(storageKey) ?? const <String>[];
    final words = <String>[];
    for (final raw in saved) {
      final word = normalizeCustomPainSensation(raw);
      if (word == null ||
          painSensationOptions.contains(word) ||
          hasThreeIdenticalCharactersInARow(word)) {
        continue;
      }
      if (!words.contains(word)) words.add(word);
    }
    return words;
  }

  Future<List<String>> remember(String raw) async {
    final word = normalizeCustomPainSensation(raw);
    final current = await load();
    if (word == null || hasThreeIdenticalCharactersInARow(word)) return current;
    final next = rememberCustomPainSensation(current, word);
    if (identicalWords(next, current)) return current;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, next);
    return next;
  }

  Future<List<String>> forget(String raw) async {
    final word = normalizeCustomPainSensation(raw);
    final current = await load();
    if (word == null) return current;
    final next = [
      for (final item in current)
        if (item != word) item,
    ];
    if (identicalWords(next, current)) return current;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(storageKey, next);
    return next;
  }

  static bool identicalWords(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
