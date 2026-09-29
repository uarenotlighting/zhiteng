import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/haptics.dart';
import '../state/controllers.dart';

/// System "reduce motion", or the in-app switch for page transitions and presses.
bool ztAnimationsReduced(BuildContext context, {bool listen = true}) {
  if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return true;
  final settings = Provider.of<AppSettingsController?>(context, listen: listen);
  return settings?.reduceAnimations ?? false;
}

const Duration ztPressScaleDuration = Duration(milliseconds: 120);
const Curve ztPressScaleCurve = Curves.easeOut;

/// Shared-container route transition matching Pixlure's 300ms OpenContainer.
class ZtOpenContainer<T extends Object?> extends StatelessWidget {
  const ZtOpenContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.onClosed,
    this.closedBorderRadius = const BorderRadius.all(Radius.circular(16)),
    this.closedClipBehavior = Clip.antiAlias,
  });

  final Widget Function(BuildContext context, VoidCallback open) closedBuilder;
  final WidgetBuilder openBuilder;
  final ValueChanged<T?>? onClosed;
  final BorderRadius closedBorderRadius;

  /// The closed card draws its own border. Clipping here cuts that stroke off
  /// at the rounded corners.
  final Clip closedClipBehavior;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = ztAnimationsReduced(context);
    if (reduceMotion) {
      return closedBuilder(context, () => _openWithoutMotion(context));
    }
    final pageColor = Theme.of(context).scaffoldBackgroundColor;
    return OpenContainer<T>(
      transitionDuration: const Duration(milliseconds: 300),
      transitionType: ContainerTransitionType.fadeThrough,
      closedColor: Colors.transparent,
      openColor: pageColor,
      middleColor: pageColor,
      closedElevation: 0,
      openElevation: 0,
      clipBehavior: closedClipBehavior,
      closedShape: RoundedRectangleBorder(borderRadius: closedBorderRadius),
      openShape: const RoundedRectangleBorder(),
      onClosed: onClosed,
      tappable: false,
      closedBuilder: closedBuilder,
      openBuilder: (context, _) => openBuilder(context),
    );
  }

  void _openWithoutMotion(BuildContext context) {
    Navigator.of(context)
        .push<T>(
          PageRouteBuilder<T>(
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
            pageBuilder: (context, _, _) => openBuilder(context),
          ),
        )
        .then((value) => onClosed?.call(value));
  }
}

/// Unified press feedback, matching the interaction rhythm used by Pixlure.
///
/// This deliberately uses pointer scale rather than a Material ink response so
/// it remains visible while the app-wide ripple/highlight overlays stay off.
class ZtPressableScale extends StatefulWidget {
  const ZtPressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.tapScale = 0.96,
    this.duration = ztPressScaleDuration,
    this.curve = ztPressScaleCurve,
    this.pressEnabled,
    this.haptic = ZtHaptic.light,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double tapScale;
  final Duration duration;
  final Curve curve;
  final bool? pressEnabled;

  /// Played when [onTap] runs. Child buttons that own the tap play their own.
  final ZtHaptic haptic;

  @override
  State<ZtPressableScale> createState() => _ZtPressableScaleState();
}

class _ZtPressableScaleState extends State<ZtPressableScale> {
  double _scale = 1;

  void _setPressed(bool pressed) {
    if (!mounted) return;
    final reduceMotion = ztAnimationsReduced(context, listen: false);
    final next = pressed && !reduceMotion ? widget.tapScale : 1.0;
    if (_scale == next) return;
    setState(() => _scale = next);
  }

  @override
  void didUpdateWidget(covariant ZtPressableScale oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.pressEnabled ?? widget.onTap != null) == false && _scale != 1) {
      _scale = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tapEnabled = widget.onTap != null;
    final pressEnabled = widget.pressEnabled ?? tapEnabled;
    final reduceMotion = ztAnimationsReduced(context);

    Widget result = AnimatedScale(
      scale: reduceMotion ? 1 : _scale,
      duration: reduceMotion ? Duration.zero : widget.duration,
      curve: widget.curve,
      alignment: Alignment.center,
      child: widget.child,
    );

    if (pressEnabled) {
      result = Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: result,
      );
    }

    if (!tapEnabled) return result;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        ztHaptic(context, widget.haptic);
        widget.onTap!();
      },
      child: result,
    );
  }
}

/// Low-key attention treatment for a primary action: 1100ms breathing and a
/// 2000ms light sweep. It adds only translucent light and never replaces the
/// child's own semantic colors.
class ZtAttentionMotion extends StatefulWidget {
  const ZtAttentionMotion({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.pulse = true,
    this.shimmer = true,
  });

  final Widget child;
  final bool enabled;
  final BorderRadius borderRadius;
  final bool pulse;
  final bool shimmer;

  @override
  State<ZtAttentionMotion> createState() => _ZtAttentionMotionState();
}

class _ZtAttentionMotionState extends State<ZtAttentionMotion>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;
  late final Animation<double> _pulse;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulse = Tween<double>(begin: 1, end: 1.045).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant ZtAttentionMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.pulse != widget.pulse ||
        oldWidget.shimmer != widget.shimmer) {
      _syncAnimations();
    }
  }

  void _syncAnimations() {
    final animate = widget.enabled && !_reduceMotion;
    if (animate && widget.pulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController
        ..stop()
        ..value = 0;
    }
    if (animate && widget.shimmer) {
      if (!_shimmerController.isAnimating) _shimmerController.repeat();
    } else {
      _shimmerController
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _shimmerController]),
      builder: (context, child) {
        final scale = widget.enabled && widget.pulse && !_reduceMotion
            ? _pulse.value
            : 1.0;
        return Transform.scale(
          scale: scale,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                child!,
                if (widget.enabled && widget.shimmer && !_reduceMotion)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment(
                          -1.7 + _shimmerController.value * 3.4,
                          0,
                        ),
                        child: FractionallySizedBox(
                          widthFactor: 0.34,
                          heightFactor: 1.7,
                          child: Transform.rotate(
                            angle: -0.24,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    Color(0x26FFFFFF),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Pixlure-style right-swipe dismissal, constrained to the left edge so it
/// cannot steal horizontal gestures from charts, sliders, or body controls.
class ZtSwipeBackPage extends StatefulWidget {
  const ZtSwipeBackPage({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<ZtSwipeBackPage> createState() => _ZtSwipeBackPageState();
}

class _ZtSwipeBackPageState extends State<ZtSwipeBackPage> {
  double _dragDx = 0;

  void _reset() => _dragDx = 0;

  void _finish(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldPop = _dragDx > 72 || (velocity > 500 && _dragDx > 48);
    _reset();
    if (!shouldPop || !Navigator.of(context).canPop()) return;
    ztHaptic(context, ZtHaptic.light);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final gestureTop = MediaQuery.paddingOf(context).top + kToolbarHeight;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: gestureTop,
          bottom: 0,
          width: 28,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => _reset(),
            onHorizontalDragUpdate: (details) {
              if (details.delta.dx > 0) _dragDx += details.delta.dx;
            },
            onHorizontalDragEnd: _finish,
            onHorizontalDragCancel: _reset,
          ),
        ),
      ],
    );
  }
}

/// App-bar back control. Same light impact as swiping the page away.
class ZtBackButton extends StatelessWidget {
  const ZtBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ZtPressableScale(
      pressEnabled: true,
      tapScale: 0.9,
      child: BackButton(
        onPressed: () {
          ztHaptic(context, ZtHaptic.light);
          Navigator.maybePop(context);
        },
      ),
    );
  }
}

/// Global 300ms fade + scale transition used by every Material route.
///
/// [reduceMotion] removes that transition: the route duration becomes zero
/// and the page appears in place.
class ZtPageTransitionsBuilder extends PageTransitionsBuilder {
  const ZtPageTransitionsBuilder({this.reduceMotion = false});

  final bool reduceMotion;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst ||
        reduceMotion ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}
