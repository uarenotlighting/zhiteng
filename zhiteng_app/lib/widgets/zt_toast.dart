import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

enum _ZtToastKind { text, success, failure, loading }

/// App-wide singleton toast.
///
/// At most one toast is inserted in the root overlay. A new call replaces the
/// current toast immediately. [text], [success], and [failure] dismiss
/// themselves; [loading] stays until one of those replaces it, or until
/// [dismiss].
abstract final class ZtToast {
  static const Duration _textDuration = Duration(milliseconds: 2200);
  static const Duration _resultDuration = Duration(milliseconds: 2000);
  static const Duration _exitDuration = Duration(milliseconds: 240);

  static OverlayEntry? _entry;
  static final GlobalKey<_ZtToastOverlayState> _toastKey =
      GlobalKey<_ZtToastOverlayState>();
  static Timer? _timer;
  static Timer? _exitFallback;
  static _ToastContent? _content;
  static int _token = 0;

  static void text(
    BuildContext context,
    String message, {
    Duration duration = _textDuration,
  }) {
    _show(
      context,
      message: message,
      kind: _ZtToastKind.text,
      duration: duration,
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration duration = _resultDuration,
  }) {
    _show(
      context,
      message: message,
      kind: _ZtToastKind.success,
      duration: duration,
    );
  }

  static void failure(
    BuildContext context,
    String message, {
    Duration duration = _resultDuration,
  }) {
    _show(
      context,
      message: message,
      kind: _ZtToastKind.failure,
      duration: duration,
    );
  }

  /// Shows persistent progress feedback. Call [dismiss], [success], [failure],
  /// or [text] when the operation finishes.
  static void loading(BuildContext context, String message) {
    _show(context, message: message, kind: _ZtToastKind.loading);
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    _content = null;
    final entry = _entry;
    if (entry == null) return;
    final state = _toastKey.currentState;
    if (state == null || !state.mounted) {
      _entry = null;
      _cancelExitFallback();
      _remove(entry);
      return;
    }
    var removed = false;
    void removeOnce() {
      if (removed) return;
      removed = true;
      if (identical(_entry, entry)) _entry = null;
      _cancelExitFallback();
      _remove(entry);
    }

    state.hide(removeOnce);
    // Exit animation can stall if its ticker never ticks. Drop the entry anyway.
    if (!removed) {
      _exitFallback = Timer(_exitDuration, removeOnce);
    }
  }

  static void _show(
    BuildContext context, {
    required String message,
    required _ZtToastKind kind,
    Duration? duration,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _timer?.cancel();
    _timer = null;
    _cancelExitFallback();
    final media = MediaQuery.of(context);
    final token = ++_token;
    _content = _ToastContent(
      message: normalized,
      kind: kind,
      dark: Theme.of(context).brightness == Brightness.dark,
      reduceMotion: media.disableAnimations,
      bottom: math.max(
        math.max(media.viewPadding.bottom + 88.0, 120.0),
        media.viewInsets.bottom + 24.0,
      ),
      token: token,
    );

    final existing = _entry;
    if (existing == null || !existing.mounted) {
      final entry = OverlayEntry(builder: (_) => _buildToast());
      _entry = entry;
      overlay.insert(entry);
    } else {
      // Keep the same overlay entry so a loading toast cannot stay behind
      // the result that replaces it.
      existing.markNeedsBuild();
    }

    if (duration != null) {
      _timer = Timer(duration, () {
        if (_content?.token == token) dismiss();
      });
    }
  }

  static Widget _buildToast() {
    final content = _content;
    if (content == null) return const SizedBox.shrink();
    return _ZtToastOverlay(
      key: _toastKey,
      message: content.message,
      kind: content.kind,
      dark: content.dark,
      reduceMotion: content.reduceMotion,
      bottom: content.bottom,
    );
  }

  static void _cancelExitFallback() {
    _exitFallback?.cancel();
    _exitFallback = null;
  }

  static void _remove(OverlayEntry entry) {
    if (entry.mounted) entry.remove();
  }
}

class _ToastContent {
  const _ToastContent({
    required this.message,
    required this.kind,
    required this.dark,
    required this.reduceMotion,
    required this.bottom,
    required this.token,
  });

  final String message;
  final _ZtToastKind kind;
  final bool dark;
  final bool reduceMotion;
  final double bottom;
  final int token;
}

class _ZtToastOverlay extends StatefulWidget {
  const _ZtToastOverlay({
    super.key,
    required this.message,
    required this.kind,
    required this.dark,
    required this.reduceMotion,
    required this.bottom,
  });

  final String message;
  final _ZtToastKind kind;
  final bool dark;
  final bool reduceMotion;
  final double bottom;

  @override
  State<_ZtToastOverlay> createState() => _ZtToastOverlayState();
}

class _ZtToastOverlayState extends State<_ZtToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 120),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacity = curved;
    _scale = Tween<double>(begin: 0.96, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(curved);
    if (widget.reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void hide(VoidCallback onHidden) {
    if (widget.reduceMotion) {
      onHidden();
      return;
    }
    _controller.reverse().whenComplete(onHidden);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.dark
        ? AppColors.darkPrimary
        : AppColors.lightPrimary;
    final foreground = widget.dark
        ? AppColors.darkOnPrimary
        : AppColors.lightOnPrimary;
    return Positioned(
      left: 20,
      right: 20,
      bottom: widget.bottom,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Semantics(
            container: true,
            liveRegion: true,
            label: widget.message,
            child: FadeTransition(
              opacity: _opacity,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: _scale,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Material(
                      key: const ValueKey('zt-toast'),
                      color: background,
                      elevation: widget.dark ? 0 : 10,
                      shadowColor: Colors.black.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.kind == _ZtToastKind.text
                              ? 18
                              : 14,
                          vertical: 13,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.kind != _ZtToastKind.text) ...[
                              _ToastIndicator(
                                kind: widget.kind,
                                color: foreground,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                widget.message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: foreground,
                                  fontSize: 14,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _ToastIndicator extends StatelessWidget {
  const _ToastIndicator({required this.kind, required this.color});

  final _ZtToastKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (kind == _ZtToastKind.loading) {
      return SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: color,
          strokeCap: StrokeCap.round,
        ),
      );
    }
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.5),
      ),
      child: Icon(
        kind == _ZtToastKind.success
            ? Icons.check_rounded
            : Icons.priority_high_rounded,
        size: 14,
        color: color,
      ),
    );
  }
}
