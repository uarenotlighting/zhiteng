import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/haptics.dart';
import '../../../core/models/pain_models.dart';
import '../../../core/theme/app_colors.dart';

/// A pain mark already placed, drawn behind the one currently being edited.
class Body2dMark {
  const Body2dMark({
    required this.x,
    required this.y,
    required this.view,
    required this.layer,
    required this.shape,
    this.markerScale = painMarkerMinScale,
    this.lineLength = 1,
    this.lineAngle = 0,
  });

  final double x;
  final double y;
  final String view;
  final BodyLayer layer;
  final PainShape shape;
  final double markerScale;
  final double lineLength;
  final double lineAngle;
}

class Body2dPick {
  const Body2dPick({
    required this.normalizedX,
    required this.normalizedY,
    required this.bodyPartId,
    required this.partName,
    required this.reanchorsView,
  });

  final double normalizedX;
  final double normalizedY;
  final String bodyPartId;
  final String partName;

  /// True for a deliberate tap, drag, or nudge. False when a newly loaded
  /// view mask only pulls an already placed point onto that silhouette.
  ///
  /// Keeping these two cases separate prevents a lossy side-view projection
  /// from becoming the source for the next turn.
  final bool reanchorsView;
}

class _MaskRegion {
  const _MaskRegion({
    required this.id,
    required this.sourceName,
    required this.red,
    required this.green,
    required this.blue,
  });

  final String id;
  final String sourceName;
  final int red;
  final int green;
  final int blue;
}

class _DecodedBodyMask {
  const _DecodedBodyMask(this.width, this.height, this.pixels);

  final int width;
  final int height;
  final ByteData pixels;
}

typedef _ShapeGraphics = ({
  List<Offset> linePoints,
  List<Offset> areaRim,
  List<List<Offset>> radiateRings,
  List<List<Offset>> radiateRays,
  bool suppress,
});

/// Must match `PerspectiveCamera` fov in assets/web/body3d.html.
const double body3dFovDegrees = 34;

/// Blender 2D ortho covers `1.08 ×` body height (`ortho_scale` in
/// build_from_zanatomy.render_views). Used to map 3D world framing onto the
/// pre-rendered image.
const double body2dOrthoPadding = 1.08;

/// Overlay chrome on the body stage. Region framing (头部 / 上身 / 下身 / 全身 /
/// 复位) centres the body in the remaining band so these controls do not
/// cover the model. Keep in lockstep with TOP_CHROME / BOTTOM_CHROME in
/// assets/web/body3d.html.
const double bodyStageTopChrome = 56;
const double bodyStageBottomChrome = 36;

/// How much of the clear band the framed body should occupy. Side controls
/// stay in the corners; this only has to clear the full-width bars.
/// Keep in lockstep with `fill` in assets/web/body3d.html.
const double bodyStageFill = 0.92;

/// Extra +/- zoom range around a region frame.
const double body2dMinZoom = 0.6;
const double body2dMaxZoom = 6;

/// Drafting-grid spacing at the full-body framing. The grid represents the
/// same visual plane as the body, so it grows when the view moves closer and
/// shrinks when it moves farther away instead of remaining screen-fixed.
const double bodyStageGridBaseSpacing = 24;

double bodyStageGridSpacing(double zoom) {
  final safeZoom = zoom <= 0 ? body2dRegionZoom(BodyRegion.full) : zoom;
  return bodyStageGridBaseSpacing *
      safeZoom /
      body2dRegionZoom(BodyRegion.full);
}

/// Camera distance as a multiple of body height. Same numbers as
/// `frameRegion` in body3d.html.
double bodyRegionDistanceHeights(BodyRegion region) => switch (region) {
  // Head stops at the shoulders; upper starts there and stops at the hands.
  // Lower starts at the abdomen. Shoulders and the abdomen are in both
  // neighbouring frames on purpose.
  BodyRegion.head => 0.54,
  BodyRegion.upper => 0.85,
  BodyRegion.lower => 1.02,
  BodyRegion.full => 1.95,
};

/// Look-at as a fraction of body height from the feet (0 = soles, 1 = crown).
/// Same numbers as `frameRegion` in body3d.html.
double bodyRegionLookAtFromFeet(BodyRegion region) => switch (region) {
  BodyRegion.head => 0.885,
  BodyRegion.upper => 0.62,
  BodyRegion.lower => 0.27,
  BodyRegion.full => 0.5,
};

/// 2D scale that shows the same world height as the 3D camera for [region].
/// Full-body is slightly under 1 because the 3D camera stands farther back
/// than the 2D image's 8 % padding.
double body2dRegionZoom(BodyRegion region) {
  const fov = body3dFovDegrees * math.pi / 180;
  final visibleHeights =
      2 * bodyRegionDistanceHeights(region) * math.tan(fov / 2);
  return body2dOrthoPadding / visibleHeights;
}

/// Image window for a saved camera. [frameZoom] is 1 at the region chip;
/// larger values are the extra magnification from the +/- buttons.
///
/// The window is the same vertical slice the record camera shows
/// (`body2dRegionZoom`), centred on [focus] or the region centre. History
/// thumbnails use this instead of guessing a crop from the screen Y, which
/// moved when the model was rotated or zoomed.
Rect bodyFrameCrop({
  required BodyRegion region,
  double frameZoom = 1,
  Offset? focus,
}) {
  final relative = frameZoom.isFinite && frameZoom > 0 ? frameZoom : 1.0;
  final absolute = (body2dRegionZoom(region) * relative).clamp(
    body2dMinZoom,
    body2dMaxZoom,
  );
  final height = (1 / absolute).clamp(0.16, 1.0);
  final width = height;
  final center = focus ?? body2dRegionFocus(region);
  final left = (center.dx - width / 2).clamp(0.0, 1 - width);
  final top = (center.dy - height / 2).clamp(0.0, 1 - height);
  return Rect.fromLTWH(left, top, width, height);
}

/// Normalized image point the 3D camera is looking at. Placed at the stage
/// centre, so local regions sit in the middle of the frame like 3D — not pinned
/// to an edge.
Offset body2dRegionFocus(BodyRegion region) {
  final t = bodyRegionLookAtFromFeet(region);
  final ny = (0.5 + body2dOrthoPadding / 2 - t) / body2dOrthoPadding;
  return Offset(0.5, ny);
}

bool _profileView(String view) => view == 'left' || view == 'right';

/// Image x after switching ortho views, before snapping onto the silhouette.
///
/// Front and back (and left and right) are mirrors, so the same side of the
/// body stays on the same side. Moving between a face and a profile keeps the
/// height and lands on the contour for the side that was showing; the mask
/// snap then pulls that edge point onto the body.
Offset remapBodyImagePoint({
  required String from,
  required String to,
  required double x,
  required double y,
}) {
  final ny = y.clamp(0.0, 1.0);
  if (from == to) return Offset(x.clamp(0.0, 1.0), ny);
  final nx = x.clamp(0.0, 1.0);
  final fromProfile = _profileView(from);
  final toProfile = _profileView(to);
  if (fromProfile == toProfile) return Offset(1 - nx, ny);
  if (toProfile) {
    final facingFront = from == 'front';
    final edge = facingFront
        ? (to == 'left' ? 0.0 : 1.0)
        : (to == 'left' ? 1.0 : 0.0);
    return Offset(edge, ny);
  }
  final bodyLeft = from == 'left';
  final edge = bodyLeft
      ? (to == 'front' ? 1.0 : 0.0)
      : (to == 'front' ? 0.0 : 1.0);
  return Offset(edge, ny);
}

double remapBodyLineAngle({
  required String from,
  required String to,
  required double angle,
}) {
  final mirrored =
      (to == 'front' && from == 'back') ||
      (to == 'back' && from == 'front') ||
      (to == 'left' && from == 'right') ||
      (to == 'right' && from == 'left');
  return mirrored ? -angle : angle;
}

/// One end of a 2D line, in normalized image space (y grows downward).
/// [upward] is the end that follows the body at angle 0. [angle] is radians,
/// counter-clockwise on screen — the same sign as `lineAngle` in body3d.html.
Offset bodyLineHeading({required bool upward, required double angle}) {
  final s = math.sin(angle);
  final c = math.cos(angle);
  return upward ? Offset(-s, -c) : Offset(s, c);
}

/// Short caption for a line direction. Zero stays "along the body".
String lineDirectionLabel(double radians) {
  final degrees = (radians * 180 / math.pi).round();
  if (degrees.abs() < 8) return '顺着身体';
  if (degrees > 0) return '逆时针 $degrees°';
  return '顺时针 ${-degrees}°';
}

/// Orthographic body map rendered from the same Blender mother model as 3D.
class SchematicBodyLocator extends StatefulWidget {
  const SchematicBodyLocator({
    super.key,
    required this.x,
    required this.y,
    required this.view,
    required this.region,
    required this.layer,
    required this.shape,
    required this.onChanged,
    this.markerScale = painMarkerMinScale,
    this.lineLength = 1,
    this.lineAngle = 0,
    this.zoom = 1,
    this.showCrosshair = true,
    this.showMarker,
    this.pinnedMarks = const [],
    this.retargetOnViewChange = true,
    this.interactive = true,
    this.initialFocus,
    this.topChrome = bodyStageTopChrome,
    this.bottomChrome = bodyStageBottomChrome,
  });

  final double x;
  final double y;
  final String view;
  final BodyRegion region;
  final BodyLayer layer;
  final PainShape shape;
  final ValueChanged<Body2dPick> onChanged;

  /// Indicator size, multiple of [painMarkerBaseRadiusMeters].
  /// For a line this is the stroke thickness.
  final double markerScale;

  /// Line length, multiple of [painLineBaseLengthMeters].
  final double lineLength;

  /// Radians around the outward normal. 0 runs along the body.
  final double lineAngle;

  /// Magnification of the body map (1 = fit). Zooms about the marker so the
  /// spot being marked stays in view; dragging still places the marker.
  final double zoom;

  /// CAD-style hairlines + reticle through the marker, like the 3D stage.
  final bool showCrosshair;

  /// Draws the pain mark. Null follows [showCrosshair], which is how the
  /// recorder hides the dot until a spot is chosen. A saved record passes
  /// true so the mark stays visible with the crosshair off.
  final bool? showMarker;

  /// Pain marks already confirmed on this record, kept visible while the
  /// user places or edits another one.
  final List<Body2dMark> pinnedMarks;

  /// When false, another picture (front, side, back) does not move or rename
  /// an existing mark. The 3D stage uses this so turning the body only changes
  /// the camera, not where the pain was entered.
  final bool retargetOnViewChange;

  /// False on the read-only history model: taps cannot move the mark, and
  /// zoom stays centred on the saved camera instead of jumping to the marker.
  final bool interactive;

  /// Saved camera aim, in normalized image space. Null starts on the region.
  final Offset? initialFocus;

  /// Pixels kept clear above and below the body, matching the 3D camera.
  final double topChrome;
  final double bottomChrome;

  @override
  State<SchematicBodyLocator> createState() => SchematicBodyLocatorState();
}

class SchematicBodyLocatorState extends State<SchematicBodyLocator>
    with SingleTickerProviderStateMixin {
  static const _imageSize = Size(768, 1280);
  static const _viewTransitionDuration = Duration(milliseconds: 340);
  static const int _viewTransitionFrameCount = 48;
  // Full-resolution turn frames occupy ~180 MiB before the four still views.
  // Motion frames only need stage resolution; keep still views sharp at zoom.
  static const int _turnDecodeWidth = 384;

  _DecodedBodyMask? _mask;
  ByteData? _maskPixels;
  List<_MaskRegion> _regions = const [];
  String? _loadedView;
  final _maskCache = <String, _DecodedBodyMask>{};
  final _graphicsCache = <Record, _ShapeGraphics>{};
  Future<List<_MaskRegion>>? _regionsLoad;
  Timer? _maskDebounce;
  String? _requestedMaskView;
  bool _loadingMask = false;
  Future<void>? _maskLoadFuture;
  late Offset _inputPoint;

  /// Normalized image point the zoom is anchored on. Captured from the marker
  /// when the zoom level changes, so the image does not slide while the user
  /// drags the marker afterwards.
  Offset _zoomFocus = const Offset(0.5, 0.5);
  late final AnimationController _viewTransitionController;
  late Offset _viewTransitionFromDirection;
  late Offset _viewTransitionFromPoint;
  bool _turnFramesPrecached = false;

  double get _viewTransitionEased =>
      Curves.easeOutCubic.transform(_viewTransitionController.value);

  Offset get _viewTransitionDirection => _interpolateViewDirection(
    _viewTransitionFromDirection,
    _viewDirection(widget.view),
    _viewTransitionEased,
  );

  bool get _viewTransitionActive => _viewTransitionController.value < 1;

  /// Canonical turns, like 3D, stay on a unit-radius orbit. The previous chord
  /// interpolation enlarged the body mid-turn and made rapid taps look stuck
  /// at a closer zoom.
  double get _viewTransitionScale => 1;

  String get _bodyImageAsset {
    if (!_viewTransitionActive) {
      return '$body2dAssetDirectory/${widget.view}.webp';
    }
    final direction = _viewTransitionDirection;
    if (direction.distanceSquared < 1e-8) {
      return '$body2dAssetDirectory/${widget.view}.webp';
    }
    final radians = math.atan2(direction.dx, direction.dy);
    final turns = (radians / (2 * math.pi)) % 1;
    final normalized = turns < 0 ? turns + 1 : turns;
    final frame =
        (normalized * _viewTransitionFrameCount).round() %
        _viewTransitionFrameCount;
    return '$body2dAssetDirectory/turn/frame_${frame.toString().padLeft(2, '0')}.webp';
  }

  Offset get _activeTransitionPoint => Offset.lerp(
    _viewTransitionFromPoint,
    Offset(widget.x, widget.y),
    _viewTransitionEased,
  )!;

  Offset _viewDirection(String view) => switch (view) {
    'left' => const Offset(1, 0),
    'right' => const Offset(-1, 0),
    'back' => const Offset(0, -1),
    _ => const Offset(0, 1),
  };

  Offset _interpolateViewDirection(Offset from, Offset to, double t) {
    final fromAngle = math.atan2(from.dx, from.dy);
    final toAngle = math.atan2(to.dx, to.dy);
    final delta = math.atan2(
      math.sin(toAngle - fromAngle),
      math.cos(toAngle - fromAngle),
    );
    final angle = fromAngle + delta * t;
    return Offset(math.sin(angle), math.cos(angle));
  }

  @override
  void initState() {
    super.initState();
    _viewTransitionController = AnimationController(
      vsync: this,
      duration: _viewTransitionDuration,
      value: 1,
    );
    _viewTransitionFromDirection = _viewDirection(widget.view);
    _viewTransitionFromPoint = Offset(widget.x, widget.y);
    _inputPoint = Offset(widget.x, widget.y);
    _zoomFocus = widget.initialFocus ?? body2dRegionFocus(widget.region);
    _loadMask();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_turnFramesPrecached) return;
    _turnFramesPrecached = true;
    unawaited(_precacheTurnFrames());
  }

  Future<void> _precacheTurnFrames() async {
    // Decode one frame at a time and leave time for controls/paint between
    // frames. Never dispatch 48 full-size image decoders simultaneously.
    for (var frame = 0; frame < _viewTransitionFrameCount; frame++) {
      if (!mounted) return;
      await precacheImage(
        ResizeImage(
          AssetImage(
            '$body2dAssetDirectory/turn/frame_${frame.toString().padLeft(2, '0')}.webp',
          ),
          width: _turnDecodeWidth,
        ),
        context,
      );
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  @override
  void dispose() {
    _viewTransitionController.dispose();
    _maskDebounce?.cancel();
    _requestedMaskView = null;
    _maskCache.clear();
    _graphicsCache.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SchematicBodyLocator oldWidget) {
    super.didUpdateWidget(oldWidget);
    final viewChanged = oldWidget.view != widget.view;
    final regionChanged = oldWidget.region != widget.region;
    if (viewChanged || oldWidget.x != widget.x || oldWidget.y != widget.y) {
      _inputPoint = Offset(widget.x, widget.y);
    }
    if (viewChanged) {
      // A new tap redirects the one running animation from its current pose.
      // Restarting from oldWidget.view jumps to an endpoint never reached.
      _viewTransitionFromDirection = _interpolateViewDirection(
        _viewTransitionFromDirection,
        _viewDirection(oldWidget.view),
        _viewTransitionEased,
      );
      _viewTransitionFromPoint = Offset.lerp(
        _viewTransitionFromPoint,
        Offset(oldWidget.x, oldWidget.y),
        _viewTransitionEased,
      )!;
      _maskDebounce?.cancel();
      _maskDebounce = Timer(const Duration(milliseconds: 64), _loadMask);
      _viewTransitionController.forward(from: 0);
    }

    if (viewChanged || regionChanged) {
      // Every orthographic render shares the same camera framing. Keep that
      // framing stable when the picture changes instead of centring the new
      // view on the pain mark. A face/profile remap can put the mark on an
      // image edge; using it as the viewport focus would then push most (or
      // all) of the body outside the stage.
      _zoomFocus = body2dRegionFocus(widget.region);
    } else if (oldWidget.zoom != widget.zoom && widget.interactive) {
      // +/- buttons: zoom about the marker if there is one, else about the
      // region so a reset lands on the same framing as the chip.
      _zoomFocus = widget.showCrosshair
          ? Offset(widget.x, widget.y)
          : body2dRegionFocus(widget.region);
    }
  }

  /// Map the 2D image so the current focus sits in the clear band below the
  /// view-toggle pill (and above the bottom hint), matching 3D `frameRegion`.
  ({double scale, Offset offset}) _viewTransform(
    Size size, {
    double transitionScale = 1,
  }) {
    final top = widget.topChrome;
    final bottom = widget.bottomChrome;
    final contentHeight = math.max(1.0, size.height - top - bottom);
    final rect = _imageRect(size);
    final bodyHeight = rect.height / body2dOrthoPadding;
    final fullZoom = body2dRegionZoom(BodyRegion.full);
    final relative = (widget.zoom <= 0 ? fullZoom : widget.zoom) / fullZoom;
    // The body fills the clear band between the top controls and the
    // full-width bottom bar. Region zoom is relative to that full-body frame.
    final scale = contentHeight * bodyStageFill / bodyHeight * relative;
    final focal = Offset(
      rect.left + rect.width * _zoomFocus.dx,
      rect.top + rect.height * _zoomFocus.dy,
    );
    final center = Offset(size.width / 2, top + contentHeight / 2);
    final offset = center - focal * scale;
    return (
      scale: scale * transitionScale,
      offset: center + (offset - center) * transitionScale,
    );
  }

  Offset _toImageSpace(Offset screen, Size size) {
    final t = _viewTransform(size, transitionScale: _viewTransitionScale);
    return (screen - t.offset) / t.scale;
  }

  Future<List<_MaskRegion>> _loadRegions() async {
    final manifestText = await rootBundle.loadString(
      '$body2dAssetDirectory/regions.json',
    );
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    return (manifest['regions'] as List<dynamic>)
        .map((entry) {
          final item = entry as Map<String, dynamic>;
          final rgb = item['rgb'] as List<dynamic>;
          return _MaskRegion(
            id: item['id'] as String,
            sourceName: item['sourceName'] as String,
            red: rgb[0] as int,
            green: rgb[1] as int,
            blue: rgb[2] as int,
          );
        })
        .toList(growable: false);
  }

  Future<_DecodedBodyMask> _decodeMask(String view) async {
    final bytes = await rootBundle.load('$body2dAssetDirectory/$view-mask.png');
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
    ui.Image? image;
    try {
      image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null)
        throw StateError('Body mask has no pixel data: $view');
      return _DecodedBodyMask(image.width, image.height, pixels);
    } finally {
      image?.dispose();
      codec.dispose();
    }
  }

  void _loadMask() {
    if (!mounted) return;
    _requestedMaskView = widget.view;
    if (!_loadingMask) {
      _maskLoadFuture = _drainMaskLoads();
      unawaited(_maskLoadFuture!);
    }
  }

  /// Complete the final view's mask/silhouette adjustment before saving.
  Future<void> flushControls() async {
    _maskDebounce?.cancel();
    _maskDebounce = null;
    _loadMask();
    while (mounted && (_loadingMask || _requestedMaskView != null)) {
      await _maskLoadFuture;
    }
  }

  Future<void> _drainMaskLoads() async {
    _loadingMask = true;
    try {
      while (mounted && _requestedMaskView != null) {
        final view = _requestedMaskView!;
        _requestedMaskView = null;
        final regions = await (_regionsLoad ??= _loadRegions());
        if (!mounted) return;
        // Requests arriving during decode overwrite the pending view, rather
        // than adding more decoders. Returning to a view reuses its pixels.
        final mask = _maskCache[view] ?? await _decodeMask(view);
        if (!mounted) return;
        _maskCache[view] = mask;
        if (view != widget.view || _requestedMaskView != null) continue;
        setState(() {
          _mask = mask;
          _maskPixels = mask.pixels;
          _regions = regions;
          _loadedView = view;
          _graphicsCache.clear();
        });
        if (widget.retargetOnViewChange) _settleMarkOnBody();
      }
    } catch (error, stack) {
      _regionsLoad = null;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'body locator',
          context: ErrorDescription('loading the 2D body mask'),
        ),
      );
    } finally {
      _loadingMask = false;
      if (mounted && _requestedMaskView != null) {
        _maskLoadFuture = _drainMaskLoads();
        unawaited(_maskLoadFuture!);
      }
    }
  }

  /// Keep a placed mark on the silhouette of the view now showing. A mirrored
  /// or face/profile point can land just outside the other picture.
  void _settleMarkOnBody() {
    if (!widget.showCrosshair || _loadedView != widget.view) return;
    if (_onBody(_inputPoint.dx, _inputPoint.dy)) {
      _emitNormalized(_inputPoint.dx, _inputPoint.dy, reanchorsView: false);
      return;
    }
    final snapped = _nearestOnBody(_inputPoint.dx, _inputPoint.dy);
    if (snapped == null) return;
    _emitNormalized(snapped.dx, snapped.dy, reanchorsView: false);
  }

  Offset? _nearestOnBody(double x, double y) {
    final image = _mask;
    final pixels = _maskPixels;
    if (image == null || pixels == null || _loadedView != widget.view) {
      return null;
    }
    final width = image.width;
    final height = image.height;
    final targetX = (x * (width - 1)).round();
    final targetY = (y * (height - 1)).round();
    Offset? best;
    var bestScore = 1 << 30;
    for (var dy = 0; dy <= 36; dy++) {
      final rows = dy == 0 ? [targetY] : [targetY - dy, targetY + dy];
      for (final sy in rows) {
        if (sy < 0 || sy >= height) continue;
        var rowX = -1;
        var rowDx = 1 << 30;
        for (var sx = 0; sx < width; sx++) {
          if (pixels.getUint8((sy * width + sx) * 4 + 3) < 32) continue;
          final dx = (sx - targetX).abs();
          if (dx < rowDx) {
            rowDx = dx;
            rowX = sx;
          }
        }
        if (rowX < 0) continue;
        final score = rowDx + dy * 8;
        if (score < bestScore) {
          bestScore = score;
          best = Offset(rowX / (width - 1), sy / (height - 1));
        }
      }
      if (best != null && dy > 6 && bestScore < dy * 8) break;
    }
    return best;
  }

  Rect _imageRect(Size size) {
    final widthScale = size.width / _imageSize.width;
    final heightScale = size.height / _imageSize.height;
    final scale = widthScale < heightScale ? widthScale : heightScale;
    final fitted = Size(_imageSize.width * scale, _imageSize.height * scale);
    return Alignment.center.inscribe(fitted, Offset.zero & size);
  }

  /// Joystick step in body metres, (+dx right, +dy up) on screen. Converted
  /// to normalized image units using the render's known scale
  /// (1280 px ≈ 2.05 m tall), then re-resolved against the region mask.
  void nudgeMeters(double dx, double dy) {
    const metersPerImageHeight = 2.05;
    const aspect = 1280 / 768;
    final ny = (_inputPoint.dy - dy / metersPerImageHeight).clamp(0.0, 1.0);
    final nx = (_inputPoint.dx + dx * aspect / metersPerImageHeight).clamp(
      0.0,
      1.0,
    );
    _emitNormalized(nx, ny);
  }

  bool _strokePlaced = false;

  bool _emit(Offset screen, Size size) {
    final rect = _imageRect(size);
    final local = _toImageSpace(screen, size);
    if (!rect.contains(local)) return false;
    final nx = ((local.dx - rect.left) / rect.width).clamp(0.0, 1.0);
    final ny = ((local.dy - rect.top) / rect.height).clamp(0.0, 1.0);
    _emitNormalized(nx, ny);
    return true;
  }

  void _settleStroke() {
    if (!_strokePlaced) return;
    _strokePlaced = false;
    ztHaptic(context, ZtHaptic.selection);
  }

  void _emitNormalized(double nx, double ny, {bool reanchorsView = true}) {
    _inputPoint = Offset(nx, ny);
    final match = _regionAt(nx, ny);
    final fallback = guessPartName(
      x: nx,
      y: ny,
      region: widget.region,
      view: widget.view,
    );
    final isNeutralSurface = match == null || match.id.startsWith('neutral_');
    widget.onChanged(
      Body2dPick(
        normalizedX: nx,
        normalizedY: ny,
        bodyPartId: isNeutralSurface
            ? 'approx_${widget.view}_${(nx * 1000).round()}_${(ny * 1000).round()}'
            : match.id,
        partName: isNeutralSurface
            ? fallback
            : _localizedName(match.sourceName),
        reanchorsView: reanchorsView,
      ),
    );
  }

  _MaskRegion? _regionAt(double x, double y) {
    final image = _mask;
    final pixels = _maskPixels;
    if (image == null || pixels == null || _loadedView != widget.view) {
      return null;
    }
    final px = (x * (image.width - 1)).round();
    final py = (y * (image.height - 1)).round();
    final offset = (py * image.width + px) * 4;
    final alpha = pixels.getUint8(offset + 3);
    if (alpha < 32) return null;
    final red = pixels.getUint8(offset);
    final green = pixels.getUint8(offset + 1);
    final blue = pixels.getUint8(offset + 2);
    _MaskRegion? nearest;
    var nearestDistance = 1 << 30;
    for (final region in _regions) {
      final dr = red - region.red;
      final dg = green - region.green;
      final db = blue - region.blue;
      final distance = dr * dr + dg * dg + db * db;
      if (distance < nearestDistance) {
        nearest = region;
        nearestDistance = distance;
      }
    }
    // ID-mask interiors are exact (edge filtering differs by at most a few
    // RGB units). Reject the handful of opaque reconstruction-gap pixels
    // instead of assigning them to an unrelated nearest palette colour.
    return nearestDistance <= 24 * 24 ? nearest : null;
  }

  String _localizedName(String sourceName) {
    final fromModel = partNameFromAnatomicalSource(
      sourceName,
      view: widget.view,
    );
    if (fromModel != null) return fromModel;
    final name = sourceName.toLowerCase();
    final side = name.endsWith('.l')
        ? '左'
        : name.endsWith('.r')
        ? '右'
        : '';
    const labels = <(String, String)>[
      ('scalp', '头顶'),
      ('forehead', '额部'),
      ('eye', '眼周'),
      ('nose', '鼻部'),
      ('mouth', '口周'),
      ('cheek', '面颊'),
      ('chin', '下巴'),
      ('auricle', '耳部'),
      ('neck', CoarseBodyArea.neck),
      ('shoulder', CoarseBodyArea.shoulder),
      ('deltoid', CoarseBodyArea.shoulder),
      ('scapular', '肩胛部'),
      ('pectoral', CoarseBodyArea.chest),
      ('thoracic', CoarseBodyArea.chest),
      ('mammary', CoarseBodyArea.chest),
      ('abdomen', CoarseBodyArea.abdomen),
      ('abdominal', CoarseBodyArea.abdomen),
      ('lumbar', CoarseBodyArea.waist),
      ('back', CoarseBodyArea.upperBack),
      ('gluteal', CoarseBodyArea.buttock),
      ('hip', CoarseBodyArea.hip),
      ('upper arm', CoarseBodyArea.upperArm),
      ('elbow', '肘部'),
      ('forearm', '前臂'),
      ('wrist', '手腕'),
      ('hand', CoarseBodyArea.hand),
      ('finger', '手指'),
      ('thigh', CoarseBodyArea.thigh),
      ('knee', CoarseBodyArea.knee),
      ('leg', CoarseBodyArea.calf),
      ('calf', CoarseBodyArea.calf),
      ('ankle', '脚踝'),
      ('heel', '脚跟'),
      ('foot', CoarseBodyArea.foot),
      ('toe', '足趾'),
      ('inguinal', '腹股沟'),
      ('pubic', '骨盆区域'),
      ('perineal', '会阴区域'),
    ];
    for (final entry in labels) {
      if (name.contains(entry.$1)) return '$side${entry.$2}';
    }
    return side.isEmpty ? '身体区域' : '$side侧身体';
  }

  bool _onBody(double x, double y) {
    final image = _mask;
    final pixels = _maskPixels;
    if (image == null || pixels == null || _loadedView != widget.view) {
      return false;
    }
    final px = (x * (image.width - 1)).round().clamp(0, image.width - 1);
    final py = (y * (image.height - 1)).round().clamp(0, image.height - 1);
    final alpha = pixels.getUint8((py * image.width + px) * 4 + 3);
    return alpha >= 32;
  }

  /// Steps in normalized image space that stay inside the body mask, bending
  /// where a straight step would leave the silhouette. [distanceMeters] is
  /// along the body, same scale as the 3D skin walk.
  List<Offset> _walkHeading(
    double x,
    double y,
    Offset heading0,
    double distanceMeters,
  ) {
    const metersPerNormY = 2.05;
    const metersPerNormX = 2.05 * 768 / 1280;
    const stepMeters = 0.007;
    final steps = (distanceMeters / stepMeters).round().clamp(2, 90);
    var px = x;
    var py = y;
    var heading = heading0;
    final pts = <Offset>[];
    for (var i = 0; i < steps; i++) {
      Offset? chosen;
      Offset? chosenHeading;
      for (var k = 0; k <= 16; k++) {
        final turn = (k ~/ 2) * 0.22 * (k.isEven ? 1 : -1);
        final c = math.cos(turn);
        final s = math.sin(turn);
        final d = Offset(
          heading.dx * c - heading.dy * s,
          heading.dx * s + heading.dy * c,
        );
        final nx = px + d.dx * stepMeters / metersPerNormX;
        final ny = py + d.dy * stepMeters / metersPerNormY;
        if (nx < 0 || nx > 1 || ny < 0 || ny > 1) continue;
        if (_onBody(nx, ny)) {
          chosen = Offset(nx, ny);
          chosenHeading = d;
          break;
        }
      }
      if (chosen == null || chosenHeading == null) break;
      px = chosen.dx;
      py = chosen.dy;
      heading = chosenHeading;
      pts.add(chosen);
    }
    return pts;
  }

  /// Polyline in normalized image space. Same 16 cm base length and the same
  /// [angle] as the 3D surface tube.
  List<Offset> _bodyLine(double x, double y, double lengthScale, double angle) {
    if (!_onBody(x, y)) return const [];
    return [
      ..._walkHeading(
        x,
        y,
        bodyLineHeading(upward: false, angle: angle),
        0.08 * lengthScale,
      ).reversed,
      Offset(x, y),
      ..._walkHeading(
        x,
        y,
        bodyLineHeading(upward: true, angle: angle),
        0.08 * lengthScale,
      ),
    ];
  }

  /// Rays around [origin]. Angle 0 points up the body, matching 3D `up`.
  List<List<Offset>> _radialWalks(
    double x,
    double y,
    double distanceMeters,
    int sectors,
  ) {
    return [
      for (var sector = 0; sector < sectors; sector++)
        _walkHeading(
          x,
          y,
          Offset(
            math.sin(sector * 2 * math.pi / sectors),
            -math.cos(sector * 2 * math.pi / sectors),
          ),
          distanceMeters,
        ),
    ];
  }

  Offset _pointAtDistance(
    List<Offset> walk,
    Offset origin,
    double distanceMeters,
  ) {
    const stepMeters = 0.007;
    if (walk.isEmpty || distanceMeters <= 0) return origin;
    final index = (distanceMeters / stepMeters).round() - 1;
    if (index < 0) return origin;
    if (index >= walk.length) return walk.last;
    return walk[index];
  }

  List<Offset> _spanWalk(
    List<Offset> walk,
    Offset origin,
    double startMeters,
    double endMeters,
  ) {
    const stepMeters = 0.007;
    final pts = <Offset>[_pointAtDistance(walk, origin, startMeters)];
    for (var i = 0; i < walk.length; i++) {
      final dist = (i + 1) * stepMeters;
      if (dist > startMeters + stepMeters * 0.25 &&
          dist < endMeters - stepMeters * 0.25) {
        pts.add(walk[i]);
      }
    }
    final end = _pointAtDistance(walk, origin, endMeters);
    if ((pts.last - end).distance > 0.0008) pts.add(end);
    return pts;
  }

  _ShapeGraphics _shapeGraphics({
    required double x,
    required double y,
    required PainShape shape,
    required double markerScale,
    required double lineLength,
    required double lineAngle,
    required bool hideUntilOnBody,
  }) {
    final key = (
      widget.view,
      x,
      y,
      shape,
      markerScale,
      lineLength,
      lineAngle,
      hideUntilOnBody,
    );
    final cached = _graphicsCache[key];
    if (cached != null) return cached;
    final graphics = _computeShapeGraphics(
      x: x,
      y: y,
      shape: shape,
      markerScale: markerScale,
      lineLength: lineLength,
      lineAngle: lineAngle,
      hideUntilOnBody: hideUntilOnBody,
    );
    // Animation/zoom rebuilds should not repeat mask walks for every pinned
    // mark. Bound the cache so a long drag cannot retain an unbounded path.
    if (_graphicsCache.length >= 64) {
      _graphicsCache.remove(_graphicsCache.keys.first);
    }
    _graphicsCache[key] = graphics;
    return graphics;
  }

  _ShapeGraphics _computeShapeGraphics({
    required double x,
    required double y,
    required PainShape shape,
    required double markerScale,
    required double lineLength,
    required double lineAngle,
    required bool hideUntilOnBody,
  }) {
    final origin = Offset(x, y);
    final reach = painMarkerBaseRadiusMeters * markerScale;
    final maskReady = _loadedView == widget.view && _maskPixels != null;
    final anchorOnBody = maskReady && _onBody(x, y);
    if (!maskReady) {
      return (
        linePoints: const [],
        areaRim: const [],
        radiateRings: const [],
        radiateRays: const [],
        suppress: hideUntilOnBody,
      );
    }
    var areaRim = const <Offset>[];
    var radiateRings = const <List<Offset>>[];
    var radiateRays = const <List<Offset>>[];
    if (shape == PainShape.area) {
      final walks = _radialWalks(x, y, reach * 2.8, 36);
      final rim = [for (final walk in walks) walk.isEmpty ? origin : walk.last];
      final reached = rim
          .where((point) => (point - origin).distance > 0.002)
          .length;
      if (reached >= 8) areaRim = rim;
    } else if (shape == PainShape.radiate) {
      final walks = _radialWalks(x, y, reach * 3.5, 24);
      final rings = <List<Offset>>[];
      for (final factor in const [2.0, 3.2]) {
        final ring = [
          for (final walk in walks)
            _pointAtDistance(walk, origin, reach * factor),
        ];
        final onBody = ring
            .where((point) => (point - origin).distance > 0.002)
            .length;
        if (onBody >= 12) rings.add(ring);
      }
      final rays = <List<Offset>>[];
      for (var i = 0; i < 8; i++) {
        final span = _spanWalk(walks[i * 3], origin, reach * 1.3, reach * 3.5);
        if (span.length >= 2 && (span.first - span.last).distance > 0.001) {
          rays.add(span);
        }
      }
      radiateRings = rings;
      radiateRays = rays;
    }
    return (
      linePoints: shape == PainShape.line
          ? _bodyLine(x, y, lineLength, lineAngle)
          : const <Offset>[],
      areaRim: areaRim,
      radiateRings: radiateRings,
      radiateRays: radiateRays,
      suppress: hideUntilOnBody && !anchorOnBody,
    );
  }

  ({double x, double y, double angle}) _projectMark(Body2dMark mark) {
    final moved = remapBodyImagePoint(
      from: mark.view,
      to: widget.view,
      x: mark.x,
      y: mark.y,
    );
    final mirrored =
        (widget.view == 'front' && mark.view == 'back') ||
        (widget.view == 'back' && mark.view == 'front') ||
        (widget.view == 'left' && mark.view == 'right') ||
        (widget.view == 'right' && mark.view == 'left');
    return (
      x: moved.dx,
      y: moved.dy,
      angle: mirrored ? -mark.lineAngle : mark.lineAngle,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _viewTransitionController,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final transform = _viewTransform(
            size,
            transitionScale: _viewTransitionScale,
          );
          final activePoint = _activeTransitionPoint;
          final imageRect = _imageRect(size);
          final maskReady = _loadedView == widget.view && _maskPixels != null;
          final showMarker = widget.showMarker ?? widget.showCrosshair;
          // A placed mark whose picture just changed is hidden until it sits
          // on that view's silhouette, so the stroke cannot hang in the margin.
          // A saved record (showMarker without the crosshair) keeps every mark
          // on screen even before that silhouette mask has loaded.
          final active = _shapeGraphics(
            x: activePoint.dx,
            y: activePoint.dy,
            shape: widget.shape,
            markerScale: widget.markerScale,
            lineLength: widget.lineLength,
            lineAngle: widget.lineAngle,
            hideUntilOnBody:
                showMarker && widget.showCrosshair && !_viewTransitionActive,
          );
          final pinnedPainters = <_MarkerPainter>[
            for (final mark in widget.pinnedMarks)
              () {
                final projected = _projectMark(mark);
                final graphics = _shapeGraphics(
                  x: projected.x,
                  y: projected.y,
                  shape: mark.shape,
                  markerScale: mark.markerScale,
                  lineLength: mark.lineLength,
                  lineAngle: projected.angle,
                  hideUntilOnBody: widget.showMarker != true,
                );
                return _MarkerPainter(
                  dark: Theme.of(context).brightness == Brightness.dark,
                  x: projected.x,
                  y: projected.y,
                  imageRect: imageRect,
                  scale: transform.scale,
                  offset: transform.offset,
                  layer: mark.layer,
                  shape: mark.shape,
                  markerScale: mark.markerScale,
                  linePoints: graphics.linePoints,
                  areaRim: graphics.areaRim,
                  radiateRings: graphics.radiateRings,
                  radiateRays: graphics.radiateRays,
                  maskReady: maskReady,
                  suppressMark: graphics.suppress,
                  showCrosshair: false,
                );
              }(),
          ];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanDown: widget.interactive
                ? (details) {
                    _strokePlaced = _emit(details.localPosition, size);
                  }
                : null,
            onPanUpdate: widget.interactive
                ? (details) {
                    if (_emit(details.localPosition, size)) {
                      _strokePlaced = true;
                    }
                  }
                : null,
            onPanEnd: widget.interactive ? (_) => _settleStroke() : null,
            onPanCancel: widget.interactive ? _settleStroke : null,
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Same perspective-scaled drafting grid as the 3D stage.
                  CustomPaint(
                    painter: _StageGridPainter(
                      spacing: bodyStageGridSpacing(widget.zoom),
                      dark: Theme.of(context).brightness == Brightness.dark,
                    ),
                  ),
                  Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(
                        transform.offset.dx,
                        transform.offset.dy,
                        0,
                        1,
                      )
                      ..scaleByDouble(transform.scale, transform.scale, 1, 1),
                    child: Image.asset(
                      _bodyImageAsset,
                      cacheWidth: _viewTransitionActive
                          ? _turnDecodeWidth
                          : null,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                    ),
                  ),
                  if (pinnedPainters.isNotEmpty)
                    CustomPaint(
                      painter: _PinnedMarksPainter(painters: pinnedPainters),
                    ),
                  CustomPaint(
                    painter: _MarkerPainter(
                      dark: Theme.of(context).brightness == Brightness.dark,
                      x: activePoint.dx,
                      y: activePoint.dy,
                      imageRect: imageRect,
                      scale: transform.scale,
                      offset: transform.offset,
                      layer: widget.layer,
                      shape: widget.shape,
                      markerScale: widget.markerScale,
                      linePoints: active.linePoints,
                      areaRim: active.areaRim,
                      radiateRings: active.radiateRings,
                      radiateRays: active.radiateRays,
                      maskReady: maskReady,
                      suppressMark: active.suppress || !showMarker,
                      showCrosshair: widget.showCrosshair,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Faint drafting grid centred on the stage. [spacing] follows the body-map
/// magnification, producing the same near-large / far-small cue as the 3D
/// camera while the line itself stays a crisp screen-space pixel.
class _StageGridPainter extends CustomPainter {
  const _StageGridPainter({required this.spacing, required this.dark});

  final double spacing;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dark ? const Color(0x12FFFFFF) : const Color(0x13000000)
      ..strokeWidth = 1;
    final startX = (size.width / 2) % spacing;
    for (var x = startX; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final startY = (size.height / 2) % spacing;
    for (var y = startY; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StageGridPainter oldDelegate) =>
      oldDelegate.spacing != spacing || oldDelegate.dark != dark;
}

class _PinnedMarksPainter extends CustomPainter {
  const _PinnedMarksPainter({required this.painters});

  final List<_MarkerPainter> painters;

  @override
  void paint(Canvas canvas, Size size) {
    for (final painter in painters) {
      painter.paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _PinnedMarksPainter oldDelegate) {
    if (oldDelegate.painters.length != painters.length) return true;
    for (var i = 0; i < painters.length; i++) {
      if (painters[i].shouldRepaint(oldDelegate.painters[i])) return true;
    }
    return false;
  }
}

/// Marker + crosshair on the 2D map, drawn in screen space so the hairlines
/// span the stage and stay 1 px at any zoom. The marker grows with the zoom
/// like the body does, and with the user's indicator size.
class _MarkerPainter extends CustomPainter {
  const _MarkerPainter({
    required this.x,
    required this.y,
    required this.imageRect,
    required this.scale,
    required this.offset,
    required this.layer,
    required this.shape,
    required this.markerScale,
    required this.linePoints,
    required this.areaRim,
    required this.radiateRings,
    required this.radiateRays,
    required this.maskReady,
    required this.suppressMark,
    required this.showCrosshair,
    required this.dark,
  });

  final double x;
  final double y;
  final Rect imageRect;
  final double scale;
  final Offset offset;
  final BodyLayer layer;
  final PainShape shape;
  final double markerScale;
  final List<Offset> linePoints;
  final List<Offset> areaRim;
  final List<List<Offset>> radiateRings;
  final List<List<Offset>> radiateRays;
  final bool maskReady;
  final bool suppressMark;
  final bool showCrosshair;
  final bool dark;

  Offset _map(Offset n) {
    return Offset(
              imageRect.left + imageRect.width * n.dx,
              imageRect.top + imageRect.height * n.dy,
            ) *
            scale +
        offset;
  }

  Path _pathOf(List<Offset> pts, {bool close = false}) {
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final p = _map(pts[i]);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (close) path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (suppressMark) return;
    final point =
        Offset(
              imageRect.left + imageRect.width * x,
              imageRect.top + imageRect.height * y,
            ) *
            scale +
        offset;
    if (showCrosshair) {
      final hair = Paint()
        ..color = dark ? const Color(0x6BFFFFFF) : const Color(0x6B3C3C3C)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(0, point.dy), Offset(size.width, point.dy), hair);
      canvas.drawLine(Offset(point.dx, 0), Offset(point.dx, size.height), hair);
      final box = Rect.fromCenter(center: point, width: 28, height: 28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box.inflate(1), const Radius.circular(3)),
        Paint()
          ..color = (dark ? Colors.black : Colors.white).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(2)),
        Paint()
          ..color = AppColors.painMarker
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Base radius: a readable dot at fit zoom (the physical 1.4 cm sphere
    // would be ~3 px here), scaled by the user's size and by the zoom so it
    // grows with the body.
    final r = (6.0 * markerScale * scale).clamp(3.0, 400.0);
    final red = AppColors.painMarker;

    if (shape == PainShape.area && areaRim.length >= 3) {
      final patch = _pathOf(areaRim, close: true);
      canvas.drawPath(patch, Paint()..color = red.withValues(alpha: 0.28));
      canvas.drawPath(
        patch,
        Paint()
          ..color = red.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else if (shape == PainShape.area && !maskReady) {
      canvas.drawCircle(
        point,
        r * 2.8,
        Paint()..color = red.withValues(alpha: 0.28),
      );
      canvas.drawCircle(
        point,
        r * 2.8,
        Paint()
          ..color = red.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    } else if (shape == PainShape.line && linePoints.length >= 2) {
      canvas.drawPath(
        _pathOf(linePoints),
        Paint()
          ..color = red.withValues(alpha: 0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth =
              (r * 2 * painLineBaseRadiusMeters / painMarkerBaseRadiusMeters)
                  .clamp(1.0, 28.0)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawCircle(point, r * 0.65, Paint()..color = red);
    } else if (shape == PainShape.line) {
      canvas.drawCircle(point, r * 0.65, Paint()..color = red);
    } else if (shape == PainShape.radiate &&
        (radiateRings.isNotEmpty || radiateRays.isNotEmpty)) {
      for (final ring in radiateRings) {
        canvas.drawPath(
          _pathOf(ring, close: true),
          Paint()
            ..color = red.withValues(
              alpha: ring == radiateRings.first ? 0.6 : 0.36,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth = (r * 0.13).clamp(1.0, 4.0)
            ..strokeJoin = StrokeJoin.round,
        );
      }
      for (final ray in radiateRays) {
        canvas.drawPath(
          _pathOf(ray),
          Paint()
            ..color = red.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (r * 0.22).clamp(1.0, 5.0)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    } else if (shape == PainShape.radiate && !maskReady) {
      for (final (k, alpha) in const [(2.0, 0.6), (3.2, 0.36)]) {
        canvas.drawCircle(
          point,
          r * k,
          Paint()
            ..color = red.withValues(alpha: alpha)
            ..style = PaintingStyle.stroke
            ..strokeWidth = (r * 0.13).clamp(1.0, 4.0),
        );
      }
      for (var index = 0; index < 8; index++) {
        final angle = index * 0.7854;
        canvas.save();
        canvas.translate(point.dx, point.dy);
        canvas.rotate(angle);
        canvas.drawLine(
          Offset(r * 1.3, 0),
          Offset(r * 3.5, 0),
          Paint()
            ..color = red.withValues(alpha: 0.75)
            ..strokeWidth = (r * 0.22).clamp(1.0, 5.0)
            ..strokeCap = StrokeCap.round,
        );
        canvas.restore();
      }
    }
    if (shape != PainShape.line) {
      final internal = layer != BodyLayer.skin;
      canvas.drawCircle(
        point,
        r,
        Paint()..color = red.withValues(alpha: internal ? 0.72 : 1),
      );
      canvas.drawCircle(
        point,
        r * 1.7,
        Paint()
          ..color = red.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (r * 0.5).clamp(2.0, 8.0),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerPainter oldDelegate) {
    return oldDelegate.x != x ||
        oldDelegate.y != y ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.scale != scale ||
        oldDelegate.offset != offset ||
        oldDelegate.layer != layer ||
        oldDelegate.shape != shape ||
        oldDelegate.markerScale != markerScale ||
        oldDelegate.linePoints != linePoints ||
        oldDelegate.areaRim != areaRim ||
        oldDelegate.radiateRings != radiateRings ||
        oldDelegate.radiateRays != radiateRays ||
        oldDelegate.maskReady != maskReady ||
        oldDelegate.suppressMark != suppressMark ||
        oldDelegate.showCrosshair != showCrosshair ||
        oldDelegate.dark != dark;
  }
}
