import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/models/pain_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/zt_motion.dart';
import 'body_3d_webview.dart';
import 'control_throttle.dart';

/// "正面 / 左侧 / 右侧 / 背面" pill shown over the top of the stage.
class BodyViewSegment extends StatelessWidget {
  const BodyViewSegment({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark
            ? AppColors.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in bodyViewOptions)
            _SegmentOption(
              label: option.$2,
              selected: value == option.$1,
              onTap: () => onChanged(option.$1),
            ),
        ],
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      haptic: ZtHaptic.selection,
      tapScale: 0.92,
      child: Material(
        color: selected
            ? (dark ? AppColors.darkElevated : AppColors.lightSubtle)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? (dark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary)
                  : (dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Which body side sits at each edge of the stage for a canonical view.
/// Returns (leftEdgeLabel, rightEdgeLabel).
(String, String) bodyEdgeLabels(String view) => switch (view) {
  'back' => ('左', '右'),
  'left' => ('前', '后'),
  'right' => ('后', '前'),
  _ => ('右', '左'),
};

/// Fine positioning for the marker, after a tap has placed it:
/// a D-pad that slides the point in the screen plane and a vertical control
/// that pushes it deeper into the body or back toward the skin.
class MarkerJoystick extends StatelessWidget {
  const MarkerJoystick({
    super.key,
    required this.enabled,
    required this.depthCaption,
    required this.onPlane,
    this.onDepth,
    this.hint,
  });

  final bool enabled;
  final String depthCaption;

  /// Screen-plane step in metres: (+dx right, +dy up).
  final void Function(double dx, double dy) onPlane;

  /// Depth step in metres: positive = deeper. Null hides the depth pad
  /// (the 2D map has no depth axis).
  final ValueChanged<double>? onDepth;

  /// Help text shown while enabled; defaults to the 3D depth explanation.
  final String? hint;

  static const double planeStep = 0.006;
  // A 4 mm tap was both visually imperceptible at full-body scale and still
  // counted as "surface" (the surface epsilon is also 4 mm). One centimetre
  // gives immediate feedback while press-and-hold remains fine-grained.
  static const double depthStep = 0.01;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = dark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextSecondary;
    final onDepth = this.onDepth;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                _DirectionPad(
                  enabled: enabled,
                  onStep: (dx, dy) => onPlane(dx * planeStep, dy * planeStep),
                ),
                const SizedBox(height: 6),
                Text('平面移动', style: TextStyle(fontSize: 11, color: hint)),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('位置', style: TextStyle(fontSize: 12, color: hint)),
                    const SizedBox(height: 4),
                    Text(
                      depthCaption,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: dark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      enabled
                          ? (this.hint ?? '按住可连续移动；\n点“侧看深度”，查看红点沿虚线深入。')
                          : '先在人体上点一下，再微调。',
                      style: TextStyle(fontSize: 11, height: 1.4, color: hint),
                    ),
                  ],
                ),
              ),
            ),
            if (onDepth != null) ...[
              const SizedBox(width: 12),
              Column(
                children: [
                  _DepthPad(
                    enabled: enabled,
                    onStep: (dz) => onDepth(dz * depthStep),
                  ),
                  const SizedBox(height: 6),
                  Text('深度', style: TextStyle(fontSize: 11, color: hint)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "+ / −" zoom pill floating at the stage edge, like the reference app's
/// magnifier buttons. Hold to keep zooming.
class StageZoomControl extends StatelessWidget {
  const StageZoomControl({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.onReset,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final divider = Container(
      width: 22,
      height: 1,
      color: dark ? AppColors.darkBorder : AppColors.lightBorder,
    );
    return Container(
      decoration: BoxDecoration(
        color: dark
            ? AppColors.darkSurface.withValues(alpha: 0.92)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.3 : 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RepeatButton(icon: Icons.add, semantic: '放大人体', onStep: onZoomIn),
          divider,
          _RepeatButton(
            icon: Icons.remove,
            semantic: '缩小人体',
            onStep: onZoomOut,
          ),
          if (onReset != null) ...[
            divider,
            Semantics(
              button: true,
              label: '恢复默认大小',
              child: ZtPressableScale(
                onTap: onReset,
                tapScale: 0.88,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: Icon(
                    Icons.fit_screen_outlined,
                    size: 18,
                    color: dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Indicator size: how big the painful spot is. Slider from
/// [painMarkerMinScale] to [painMarkerMaxScale] with a live preview dot.
class MarkerSizeSlider extends StatefulWidget {
  const MarkerSizeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.label = '指示器\n大小',
    this.min = painMarkerMinScale,
    this.max = painMarkerMaxScale,
    this.bar = false,
    this.readout,
    this.divisions = 10,
    this.preview,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final String label;
  final double min;
  final double max;

  /// Rounded bar instead of a dot, used for line length.
  final bool bar;

  /// Right-hand caption. Defaults to the marker diameter in centimetres.
  final String Function(double value)? readout;

  final int divisions;

  /// Replaces the size dot. Used to show a line turning with [value].
  final Widget Function(double value)? preview;

  @override
  State<MarkerSizeSlider> createState() => _MarkerSizeSliderState();
}

class _MarkerSizeSliderState extends State<MarkerSizeSlider> {
  late double _displayValue;
  late double _lastEmittedValue;
  late final ControlThrottle<double> _changes;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _displayValue = _lastEmittedValue = widget.value;
    _changes = ControlThrottle<double>(
      onValue: (value) {
        if (!mounted || !widget.enabled || value == _lastEmittedValue) return;
        _lastEmittedValue = value;
        widget.onChanged(value);
      },
    );
  }

  @override
  void didUpdateWidget(covariant MarkerSizeSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reconfigured =
        oldWidget.min != widget.min ||
        oldWidget.max != widget.max ||
        oldWidget.label != widget.label ||
        !widget.enabled;
    final externalChange =
        oldWidget.value != widget.value && widget.value != _lastEmittedValue;
    if (reconfigured || externalChange) {
      _changes.cancel();
      _dragging = false;
      _displayValue = _lastEmittedValue = widget.value;
    } else if (!_dragging && oldWidget.value != widget.value) {
      _displayValue = widget.value;
    }
  }

  @override
  void dispose() {
    _changes.dispose();
    super.dispose();
  }

  void _change(double value) {
    setState(() => _displayValue = value);
    _changes.add(value);
  }

  @override
  Widget build(BuildContext context) {
    final value = _displayValue;
    final enabled = widget.enabled;
    final label = widget.label;
    final min = widget.min;
    final max = widget.max;
    final bar = widget.bar;
    final readout = widget.readout;
    final divisions = widget.divisions;
    final preview = widget.preview;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hint = dark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextSecondary;
    final formatValue =
        readout ??
        (double v) =>
            '约 ${(painMarkerBaseRadiusMeters * v * 2 * 100).toStringAsFixed(1)} cm';
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                label,
                style: TextStyle(fontSize: 11, height: 1.3, color: hint),
              ),
            ),
            SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: preview != null
                    ? preview!(value)
                    : bar
                    ? Container(
                        width:
                            6 + 22 * ((value - min) / (max - min)).clamp(0, 1),
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.painMarker.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      )
                    : Container(
                        width: 8 + 8 * value,
                        height: 8 + 8 * value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.painMarker.withValues(alpha: 0.9),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.painMarker.withValues(
                                alpha: 0.25,
                              ),
                              blurRadius: 6,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  activeTrackColor: AppColors.painMarker,
                  thumbColor: AppColors.painMarker,
                  overlayColor: Colors.transparent,
                  inactiveTrackColor: dark
                      ? AppColors.darkBorder
                      : AppColors.lightBorder,
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  semanticFormatterCallback: (v) => formatValue(
                    v,
                  ).replaceAll('cm', '厘米').replaceAll('mm', '毫米'),
                  onChangeStart: (_) {
                    _dragging = true;
                    ztHaptic(context, ZtHaptic.selection);
                  },
                  onChanged: _change,
                  onChangeEnd: (_) {
                    _changes.flush();
                    _dragging = false;
                    ztHaptic(context, ZtHaptic.selection);
                  },
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                formatValue(value),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: hint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectionPad extends StatelessWidget {
  const _DirectionPad({required this.onStep, required this.enabled});

  final void Function(double dx, double dy) onStep;
  final bool enabled;

  static const double size = 104;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dark ? AppColors.darkElevated : AppColors.lightSurface,
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.painMarker,
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: _RepeatButton(
              enabled: enabled,
              icon: Icons.keyboard_arrow_up,
              semantic: '向上移动',
              onStep: () => onStep(0, 1),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _RepeatButton(
              enabled: enabled,
              icon: Icons.keyboard_arrow_down,
              semantic: '向下移动',
              onStep: () => onStep(0, -1),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _RepeatButton(
              enabled: enabled,
              icon: Icons.keyboard_arrow_left,
              semantic: '向左移动',
              onStep: () => onStep(-1, 0),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _RepeatButton(
              enabled: enabled,
              icon: Icons.keyboard_arrow_right,
              semantic: '向右移动',
              onStep: () => onStep(1, 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _DepthPad extends StatelessWidget {
  const _DepthPad({required this.onStep, required this.enabled});

  /// +1 deeper, -1 shallower.
  final ValueChanged<double> onStep;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 44,
      height: _DirectionPad.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: dark ? AppColors.darkElevated : AppColors.lightSurface,
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RepeatButton(
            enabled: enabled,
            icon: Icons.keyboard_arrow_up,
            semantic: '往表面移',
            onStep: () => onStep(-1),
          ),
          Text(
            '浅\n深',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              height: 1.2,
              color: dark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ),
          _RepeatButton(
            enabled: enabled,
            icon: Icons.keyboard_arrow_down,
            semantic: '往体内移',
            onStep: () => onStep(1),
          ),
        ],
      ),
    );
  }
}

/// Fires once on press, then repeats while held.
class _RepeatButton extends StatefulWidget {
  const _RepeatButton({
    required this.icon,
    required this.semantic,
    required this.onStep,
    this.enabled = true,
  });

  final IconData icon;
  final String semantic;
  final VoidCallback onStep;
  final bool enabled;

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton>
    with WidgetsBindingObserver {
  Timer? _delay;
  Timer? _repeat;
  late final ControlThrottle<bool> _steps;
  late final ZtHapticCadence _haptics;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _steps = ControlThrottle<bool>(
      onValue: (_) {
        if (!mounted || !widget.enabled) return;
        widget.onStep();
        _haptics.step(context);
      },
    );
    _haptics = ZtHapticCadence();
  }

  void _start() {
    if (_pressed || !widget.enabled) return;
    _cancelRepeat();
    setState(() => _pressed = true);
    _steps.add(true);
    _delay = Timer(const Duration(milliseconds: 280), () {
      _delay = null;
      if (!mounted || !_pressed || !widget.enabled) return;
      _repeat = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (!mounted || !_pressed || !widget.enabled) {
          _stop();
          return;
        }
        _steps.add(true);
      });
    });
  }

  void _cancelRepeat() {
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
  }

  void _stop() {
    if (!_pressed) return;
    _pressed = false;
    _cancelRepeat();
    _steps.flush();
    if (!mounted) return;
    _haptics.end(context);
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant _RepeatButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      final wasPressed = _pressed;
      _cancelRepeat();
      _steps.cancel();
      _pressed = false;
      if (wasPressed) _haptics.end(context);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) return;
    _stop();
    _steps.cancel();
  }

  @override
  void deactivate() {
    _cancelRepeat();
    _steps.cancel();
    _pressed = false;
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRepeat();
    _steps.dispose();
    _haptics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      button: true,
      label: widget.semantic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _start(),
        onTapUp: (_) => _stop(),
        onTapCancel: _stop,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed
                ? (dark ? AppColors.darkPrimarySoft : AppColors.lightSubtle)
                : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 22,
            color: dark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
        ),
      ),
    );
  }
}
