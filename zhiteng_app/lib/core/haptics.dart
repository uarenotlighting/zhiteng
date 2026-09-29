import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../state/controllers.dart';

/// How strong a tap should feel.
///
/// Pick the level from what the control does, not from how large it is:
/// - [selection] chooses among options (chips, tabs, switches, steps)
/// - [light] opens a page or triggers a secondary control
/// - [medium] commits the main action on the screen
/// - [heavy] deletes or clears something
/// - [none] stays silent
enum ZtHaptic { none, selection, light, medium, heavy }

/// Silences every tap under this widget when [enabled] is false.
class ZtHapticsScope extends InheritedWidget {
  const ZtHapticsScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool enabledOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<ZtHapticsScope>();
    return scope?.enabled ?? true;
  }

  @override
  bool updateShouldNotify(ZtHapticsScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Plays [level] unless this subtree or the settings switch turned haptics off.
void ztHaptic(BuildContext context, ZtHaptic level) {
  if (level == ZtHaptic.none) return;
  if (!ZtHapticsScope.enabledOf(context)) return;
  if (_hapticsDisabled(context)) return;
  switch (level) {
    case ZtHaptic.none:
      return;
    case ZtHaptic.selection:
      HapticFeedback.selectionClick();
    case ZtHaptic.light:
      HapticFeedback.lightImpact();
    case ZtHaptic.medium:
      HapticFeedback.mediumImpact();
    case ZtHaptic.heavy:
      HapticFeedback.heavyImpact();
  }
}

/// Selection click for a tap. Does nothing when haptic feedback is turned off.
void ztSelectionClick(BuildContext context) {
  ztHaptic(context, ZtHaptic.selection);
}

/// Spaces vibrations while a control repeats or is held down.
///
/// [step] is felt immediately, then at most once per [gap], so a joystick or
/// zoom hold is not a buzz on every repeat. [end] makes sure the value that
/// was just released is felt too, without adding a second pulse on top of one
/// that already played.
class ZtHapticCadence {
  ZtHapticCadence({
    this.gap = const Duration(milliseconds: 180),
    this.level = ZtHaptic.selection,
  });

  final Duration gap;
  final ZtHaptic level;
  DateTime? _lastPlayed;
  Timer? _trailing;
  bool _unfelt = false;

  void step(BuildContext context) {
    _unfelt = true;
    _emit(context, force: false);
  }

  void end(BuildContext context) {
    if (!_unfelt) {
      _trailing?.cancel();
      _trailing = null;
      return;
    }
    _emit(context, force: true);
  }

  void dispose() {
    _trailing?.cancel();
    _trailing = null;
  }

  void _emit(BuildContext context, {required bool force}) {
    final now = DateTime.now();
    final last = _lastPlayed;
    final waited = last == null ? gap : now.difference(last);
    if (waited >= gap) {
      _play(context, now);
      return;
    }
    if (!force && _trailing != null) return;
    _trailing?.cancel();
    final remaining = gap - waited;
    _trailing = Timer(remaining, () {
      _trailing = null;
      if (!_unfelt || !context.mounted) return;
      _play(context, DateTime.now());
    });
  }

  void _play(BuildContext context, DateTime now) {
    _trailing?.cancel();
    _trailing = null;
    _unfelt = false;
    _lastPlayed = now;
    ztHaptic(context, level);
  }
}

bool _hapticsDisabled(BuildContext context) {
  final settings = Provider.of<AppSettingsController?>(context, listen: false);
  return settings?.disableHapticFeedback ?? false;
}
