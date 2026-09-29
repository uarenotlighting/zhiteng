import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/theme/app_colors.dart';
import 'zt_motion.dart';

class ZtButton extends StatelessWidget {
  const ZtButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.expand = true,
    this.attention = true,
    this.pulse = false,
    this.shimmer = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool expand;
  final bool attention;
  final bool pulse;
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? AppColors.darkPrimary : AppColors.lightPrimary;
    final fg = dark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary;
    final disabledBg = dark ? AppColors.darkDisabled : AppColors.lightDisabled;

    final child = Text(
      label,
      style: TextStyle(
        color: enabled
            ? fg
            : (dark ? AppColors.darkTextTertiary : Colors.white70),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );

    final canTap = enabled && onPressed != null;
    return ZtPressableScale(
      onTap: canTap ? onPressed : null,
      haptic: ZtHaptic.medium,
      tapScale: 0.96,
      child: ZtAttentionMotion(
        enabled: canTap && attention,
        pulse: attention && pulse,
        // 光影掠过暂时不接入按钮；保留这行便于后续按需恢复。
        // shimmer: attention && shimmer,
        shimmer: false,
        child: IgnorePointer(
          child: SizedBox(
            width: expand ? double.infinity : null,
            height: 52,
            child: FilledButton(
              onPressed: canTap ? () {} : null,
              style: FilledButton.styleFrom(
                backgroundColor: enabled ? bg : disabledBg,
                foregroundColor: fg,
                disabledBackgroundColor: disabledBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Extra width when [ZtChip.onDelete] is shown: 4px gap + 14px icon,
/// with the right padding reduced from 16 to 8.
const double ztChipDeleteExtraWidth = 10;

class ZtChip extends StatelessWidget {
  const ZtChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.ghost = false,
    this.onDelete,
    this.haptic = ZtHaptic.selection,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool ghost;
  final VoidCallback? onDelete;

  /// Recent-item chips that immediately save use a firmer tap than a toggle.
  final ZtHaptic haptic;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
        : (ghost
              ? Colors.transparent
              : (dark ? AppColors.darkElevated : AppColors.lightPrimarySoft));
    final fg = selected
        ? (dark ? AppColors.darkOnPrimary : AppColors.lightOnPrimary)
        : (dark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);

    return ZtPressableScale(
      onTap: onTap,
      haptic: haptic,
      tapScale: 0.94,
      child: Material(
        color: bg,
        shape: StadiumBorder(
          side: ghost
              ? BorderSide(
                  color: dark ? AppColors.darkBorder : AppColors.lightBorder,
                )
              : BorderSide.none,
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, onDelete == null ? 16 : 8, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (onDelete != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ztHaptic(context, ZtHaptic.medium);
                    onDelete!();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.close, size: 14, color: fg),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
