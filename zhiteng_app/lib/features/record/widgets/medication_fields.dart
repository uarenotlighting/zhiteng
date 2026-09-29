import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/zt_motion.dart';

/// Largest dose the stepper will reach. Typed values are also capped at 8
/// characters by [NonNegativeDecimalInputFormatter].
const double doseAmountMax = 99999999;

/// Keeps a dose field to digits and one decimal point. Minus signs and other
/// characters are rejected, including when they are pasted in.
class NonNegativeDecimalInputFormatter extends TextInputFormatter {
  const NonNegativeDecimalInputFormatter({
    this.maxLength = 8,
    this.decimalDigits = 3,
  });

  final int maxLength;
  final int decimalDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final pattern = RegExp('^\\d*\\.?\\d{0,$decimalDigits}\$');
    if (text.length > maxLength || !pattern.hasMatch(text)) return oldValue;
    return newValue;
  }
}

/// Parses a dose the person is still typing. Empty and a trailing dot are not
/// numbers yet.
double? parseDoseAmount(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == '.') return null;
  final value = double.tryParse(text);
  if (value == null || value.isNaN || value.isInfinite || value < 0) {
    return null;
  }
  return value;
}

String formatDoseAmount(double value) {
  final clamped = value.clamp(0, doseAmountMax).toDouble();
  final rounded = (clamped * 1000).roundToDouble() / 1000;
  if ((rounded - rounded.truncateToDouble()).abs() < 1e-9) {
    return rounded.truncate().toString();
  }
  var text = rounded.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.replaceFirst(RegExp(r'\.$'), '');
}

/// Steps a dose by 1. Empty becomes 1 when increasing, and stays empty when
/// decreasing. Results never go below 0.
String stepDoseAmount(String raw, int direction) {
  final current = parseDoseAmount(raw);
  if (current == null) return direction > 0 ? '1' : raw;
  var next = current + direction;
  if (next < 0) next = 0;
  if (next > doseAmountMax) next = doseAmountMax;
  return formatDoseAmount(next);
}

class DoseQuantityField extends StatefulWidget {
  const DoseQuantityField({
    super.key,
    required this.controller,
    this.onChanged,
    this.scrollPadding = EdgeInsets.zero,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final EdgeInsets scrollPadding;

  @override
  State<DoseQuantityField> createState() => _DoseQuantityFieldState();
}

class _DoseQuantityFieldState extends State<DoseQuantityField> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focusNode.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(covariant DoseQuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focusNode.removeListener(_rebuild);
    _focusNode.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _step(int direction) {
    final next = stepDoseAmount(widget.controller.text, direction);
    if (next == widget.controller.text) return;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    ztSelectionClick(context);
    widget.onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = dark ? AppColors.darkBorder : AppColors.lightBorder;
    final focused = _focusNode.hasFocus;
    final amount = parseDoseAmount(widget.controller.text);
    final canDecrease = amount != null && amount > 0;
    final canIncrease = amount == null || amount < doseAmountMax;
    return SizedBox(
      height: 44,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused
                ? (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
                : border,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DoseStepButton(
              icon: Icons.remove,
              label: '减少剂量',
              enabled: canDecrease,
              onTap: () => _step(-1),
            ),
            _DoseDivider(color: border),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                textInputAction: TextInputAction.done,
                expands: true,
                maxLines: null,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                scrollPadding: widget.scrollPadding,
                inputFormatters: const [NonNegativeDecimalInputFormatter()],
                decoration: InputDecoration(
                  hintText: '数量',
                  hintStyle: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: dark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                  filled: false,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                onChanged: widget.onChanged,
              ),
            ),
            _DoseDivider(color: border),
            _DoseStepButton(
              icon: Icons.add,
              label: '增加剂量',
              enabled: canIncrease,
              onTap: () => _step(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _DoseDivider extends StatelessWidget {
  const _DoseDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1,
      child: Center(
        child: SizedBox(height: 20, child: ColoredBox(color: color)),
      ),
    );
  }
}

class _DoseStepButton extends StatelessWidget {
  const _DoseStepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = enabled
        ? (dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary)
        : (dark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary);
    return ZtPressableScale(
      onTap: enabled ? onTap : null,
      haptic: ZtHaptic.none,
      tapScale: 0.92,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, size: 18, color: color, semanticLabel: label),
      ),
    );
  }
}

class DoseUnitButton extends StatelessWidget {
  const DoseUnitButton({super.key, required this.unit, required this.onTap});

  final String unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      haptic: ZtHaptic.selection,
      tapScale: 0.96,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: dark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              unit,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_down,
              size: 14,
              color: dark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// iOS pull-down menu: rounded, blurred, with a check on the current choice.
Future<String?> showIosOptionMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<String> options,
  required String selected,
}) {
  final anchor = _anchorRect(anchorKey);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (context, animation, secondaryAnimation, child) => child,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final media = MediaQuery.of(dialogContext);
      const menuWidth = 168.0;
      const itemExtent = 44.0;
      final separatorExtent = options.length > 1
          ? (options.length - 1) * 0.5
          : 0.0;
      final contentHeight = options.length * itemExtent + separatorExtent;
      final bottomLimit = media.size.height - media.viewInsets.bottom - 8;
      final topSafe = media.padding.top + 8;
      final below = anchor == null
          ? contentHeight
          : bottomLimit - (anchor.bottom + 6);
      final above = anchor == null ? 0.0 : anchor.top - 6 - topSafe;
      final room = math.max(44.0, math.max(below, above));
      final maxHeight = math.max(44.0, bottomLimit - topSafe);
      final menuHeight = math.min(contentHeight, math.min(room, maxHeight));
      final openAbove = anchor != null && below < menuHeight && above > below;
      var top = anchor == null
          ? (media.size.height - menuHeight) / 2
          : (openAbove ? anchor.top - 6 - menuHeight : anchor.bottom + 6);
      top = top.clamp(topSafe, math.max(topSafe, bottomLimit - menuHeight));
      var left = anchor == null
          ? (media.size.width - menuWidth) / 2
          : anchor.right - menuWidth;
      left = left.clamp(8.0, math.max(8.0, media.size.width - menuWidth - 8));
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
                alignment: openAbove
                    ? Alignment.bottomRight
                    : Alignment.topRight,
                child: _IosOptionMenu(
                  dark: dark,
                  height: menuHeight,
                  options: options,
                  selected: selected,
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Rect? _anchorRect(GlobalKey key) {
  final box = key.currentContext?.findRenderObject();
  if (box is! RenderBox || !box.hasSize || !box.attached) return null;
  final origin = box.localToGlobal(Offset.zero);
  return origin & box.size;
}

class _IosOptionMenu extends StatelessWidget {
  const _IosOptionMenu({
    required this.dark,
    required this.height,
    required this.options,
    required this.selected,
  });

  final bool dark;
  final double height;
  final List<String> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final separator = dark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA);
    final textColor = dark ? Colors.white : Colors.black;
    // Dialog routes sit under MaterialApp's fallback text style (red glyphs,
    // yellow underline). inherit: false drops that decoration.
    final itemStyle = TextStyle(
      inherit: false,
      fontSize: 17,
      height: 1.2,
      fontWeight: FontWeight.w400,
      color: textColor,
      decoration: TextDecoration.none,
    );
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: itemStyle,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.45 : 0.16),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xE61C1C1E)
                      : const Color(0xF2FFFFFF),
                  border: Border.all(
                    color: dark
                        ? const Color(0xFF48484A)
                        : const Color(0x14000000),
                  ),
                ),
                child: SizedBox(
                  height: height,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      indent: 16,
                      color: separator,
                    ),
                    itemBuilder: (context, index) {
                      final option = options[index];
                      final isSelected = option == selected;
                      return SizedBox(
                        height: 44,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            ztSelectionClick(context);
                            Navigator.of(context).pop(option);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: itemStyle,
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    CupertinoIcons.check_mark,
                                    size: 18,
                                    color: textColor,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _systemDateTimeChannel = MethodChannel('zhiteng/system_datetime');

/// Opens the platform date and time picker.
///
/// iOS presents `UIDatePicker`. Android presents `DatePickerDialog` and then
/// `TimePickerDialog`.
Future<DateTime?> showIosDateTimePicker({
  required BuildContext context,
  required DateTime initialDateTime,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) async {
  final millis = await _systemDateTimeChannel.invokeMethod<int>('pick', {
    'initial': initialDateTime.millisecondsSinceEpoch,
    'minimum': minimumDate?.millisecondsSinceEpoch,
    'maximum': maximumDate?.millisecondsSinceEpoch,
  });
  if (millis == null) return null;
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
