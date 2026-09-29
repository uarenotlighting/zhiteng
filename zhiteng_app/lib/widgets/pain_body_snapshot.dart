import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/models/pain_models.dart';
import '../core/theme/app_colors.dart';
import '../features/record/widgets/schematic_body_locator.dart';

const _bodyImageSize = Size(768, 1280);

/// A lightweight, read-only reconstruction of the body view saved with a
/// pain entry. It deliberately avoids the interactive locator's mask loading,
/// animation frames and gesture handling so a history grid can show many
/// records without warming the full editor.
class PainBodySnapshot extends StatelessWidget {
  PainBodySnapshot({
    super.key,
    required List<PainLocation> locations,
    this.compact = false,
  }) : visibleLocations = List.unmodifiable(
         locations.where((location) => !isQuickPainLocation(location)),
       ),
       hasBodyImage = locations.any(
         (location) => !isQuickPainLocation(location),
       ),
       region = painSnapshotRegion(locations);

  final List<PainLocation> visibleLocations;
  final bool compact;
  final bool hasBodyImage;
  final BodyRegion region;

  PainLocation? get primaryLocation =>
      visibleLocations.isEmpty ? null : visibleLocations.last;

  String get modelMode => primaryLocation?.coordinateMode == '3d' ? '3d' : '2d';

  BodyLayer get anatomyLayer =>
      primaryLocation?.displayAnatomyLayer ?? BodyLayer.skin;

  String get assetPath {
    final view = primaryLocation?.view ?? 'front';
    return 'assets/models/2d/layers/${anatomyLayer.wire}/$view.webp';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final stage = AppColors.bodyStageFor(dark: dark);
    if (!hasBodyImage) {
      final muted = dark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary;
      return ColoredBox(
        color: stage,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_outlined, size: compact ? 24 : 30, color: muted),
              const SizedBox(height: 6),
              Text(
                '速记记录',
                style: TextStyle(
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 3),
                Text('本次未使用人体模型', style: TextStyle(fontSize: 12, color: muted)),
              ],
            ],
          ),
        ),
      );
    }

    final view = primaryLocation!.view;
    final crop = snapshotCropFor(locations: visibleLocations, region: region);
    return ColoredBox(
      color: stage,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          if (size.isEmpty) return const SizedBox.shrink();
          final transform = _SnapshotTransform.fit(size, crop);
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: _SnapshotGridPainter(dark: dark, compact: compact),
                ),
                Positioned(
                  left: transform.offset.dx,
                  top: transform.offset.dy,
                  width: _bodyImageSize.width * transform.scale,
                  height: _bodyImageSize.height * transform.scale,
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.high,
                  ),
                ),
                CustomPaint(
                  painter: _SnapshotMarksPainter(
                    locations: visibleLocations,
                    view: view,
                    transform: transform,
                    compact: compact,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

bool isQuickPainLocation(PainLocation location) {
  return location.bodyPartId.startsWith('quick_');
}

/// Chooses one framing region for the whole entry. Multiple marks in the same
/// region stay zoomed together; marks that span regions use a full-body view.
///
/// The region is the one saved with the mark. Screen Y is not consulted: a
/// zoomed or rotated camera moves that number without moving the body frame.
BodyRegion painSnapshotRegion(List<PainLocation> locations) {
  final marked = locations.where((location) => !isQuickPainLocation(location));
  final regions = <BodyRegion>{for (final item in marked) item.region};
  if (regions.isEmpty || regions.length > 1) return BodyRegion.full;
  return regions.single;
}

/// Crop for the saved camera. A shared region uses that mark's zoom and aim.
/// Mixed regions open the full body so neither mark is framed out.
Rect snapshotCropFor({
  required List<PainLocation> locations,
  required BodyRegion region,
}) {
  final marked = locations
      .where((location) => !isQuickPainLocation(location))
      .toList();
  final primary = marked.isEmpty ? null : marked.last;
  final saved = primary != null && primary.region == region;
  final focus =
      saved && primary.frameFocusX != null && primary.frameFocusY != null
      ? Offset(primary.frameFocusX!, primary.frameFocusY!)
      : null;
  return bodyFrameCrop(
    region: region,
    frameZoom: saved ? primary.frameZoom : 1,
    focus: focus,
  );
}

class _SnapshotTransform {
  const _SnapshotTransform({required this.scale, required this.offset});

  factory _SnapshotTransform.fit(Size viewport, Rect crop) {
    final sourceCrop = Rect.fromLTWH(
      crop.left * _bodyImageSize.width,
      crop.top * _bodyImageSize.height,
      crop.width * _bodyImageSize.width,
      crop.height * _bodyImageSize.height,
    );
    final scale = math.min(
      viewport.width / sourceCrop.width,
      viewport.height / sourceCrop.height,
    );
    final offset = viewport.center(Offset.zero) - sourceCrop.center * scale;
    return _SnapshotTransform(scale: scale, offset: offset);
  }

  final double scale;
  final Offset offset;

  Offset project(Offset normalized) {
    return Offset(
              normalized.dx * _bodyImageSize.width,
              normalized.dy * _bodyImageSize.height,
            ) *
            scale +
        offset;
  }
}

class _SnapshotGridPainter extends CustomPainter {
  const _SnapshotGridPainter({required this.dark, required this.compact});

  final bool dark;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dark ? const Color(0x12FFFFFF) : const Color(0x0D191919)
      ..strokeWidth = 1;
    final gap = compact ? 22.0 : 28.0;
    for (var x = size.width / 2 % gap; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = size.height / 2 % gap; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SnapshotGridPainter oldDelegate) {
    return dark != oldDelegate.dark || compact != oldDelegate.compact;
  }
}

class _SnapshotMarksPainter extends CustomPainter {
  const _SnapshotMarksPainter({
    required this.locations,
    required this.view,
    required this.transform,
    required this.compact,
  });

  final List<PainLocation> locations;
  final String view;
  final _SnapshotTransform transform;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    for (final location in locations) {
      final normalized = bodySnapshotImagePoint(location, view);
      final point = transform.project(normalized);
      if (point.dx < -20 ||
          point.dy < -20 ||
          point.dx > size.width + 20 ||
          point.dy > size.height + 20) {
        continue;
      }
      _paintMark(canvas, point, location);
    }
  }

  void _paintMark(Canvas canvas, Offset point, PainLocation location) {
    final base = compact ? 4.2 : 5.4;
    final radius = (base * location.markerScale.clamp(0.65, 2.4)).clamp(
      compact ? 3.5 : 4.5,
      compact ? 10.0 : 15.0,
    );
    final red = AppColors.painMarker;
    final internal = location.layer != BodyLayer.skin;
    final solid = Paint()..color = red.withValues(alpha: internal ? 0.78 : 1);
    final halo = Paint()
      ..color = red.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, radius * 0.45);

    switch (location.shape) {
      case PainShape.point:
        canvas.drawCircle(point, radius, solid);
        canvas.drawCircle(point, radius * 1.65, halo);
        break;
      case PainShape.area:
        canvas.drawCircle(
          point,
          radius * 2.5,
          Paint()..color = red.withValues(alpha: 0.28),
        );
        canvas.drawCircle(point, radius * 2.5, halo);
        canvas.drawCircle(point, radius * 0.75, solid);
        break;
      case PainShape.line:
        final direction = _lineDirection(location, view);
        final span = direction.distance;
        if (span >= 0.05) {
          final half = math.max(radius * 2.8, 14 * location.lineLength) * span;
          final unit = direction / span;
          canvas.drawLine(
            point - unit * half,
            point + unit * half,
            Paint()
              ..color = red.withValues(alpha: 0.92)
              ..strokeWidth = math.max(2.5, radius * 0.65)
              ..strokeCap = StrokeCap.round,
          );
        }
        canvas.drawCircle(point, radius * 0.55, solid);
        break;
      case PainShape.radiate:
        canvas.drawCircle(point, radius * 0.8, solid);
        for (final factor in const [1.8, 3.0]) {
          canvas.drawCircle(
            point,
            radius * factor,
            Paint()
              ..color = red.withValues(alpha: factor < 2 ? 0.65 : 0.38)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4,
          );
        }
        for (var i = 0; i < 8; i++) {
          final angle = i * math.pi / 4;
          final direction = Offset(math.cos(angle), math.sin(angle));
          canvas.drawLine(
            point + direction * radius * 1.2,
            point + direction * radius * 3.2,
            Paint()
              ..color = red.withValues(alpha: 0.72)
              ..strokeWidth = 1.4
              ..strokeCap = StrokeCap.round,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SnapshotMarksPainter oldDelegate) {
    return locations != oldDelegate.locations ||
        view != oldDelegate.view ||
        transform.scale != oldDelegate.transform.scale ||
        transform.offset != oldDelegate.transform.offset ||
        compact != oldDelegate.compact;
  }
}

/// Where a saved mark sits on the orthographic body image for [view].
///
/// 2D taps are already in that image. A 3D mark's stored normalized point is
/// the perspective camera's screen position, so orbit, zoom, region framing
/// and depth slide it away from the body. The saved local coordinate is
/// projected onto the same ortho frame the image was rendered with.
Offset bodySnapshotImagePoint(PainLocation location, String view) {
  final x = location.localX;
  final y = location.localY;
  final z = location.localZ;
  if (x != null && y != null && z != null) {
    final projected = projectBodyPointToImage(x: x, y: y, z: z, view: view);
    return Offset(projected.x, projected.y);
  }
  return _remapToView(location, view);
}

/// Image-space line direction. Same-view strokes keep their saved angle;
/// another canonical view keeps the part that is still on screen.
Offset _lineDirection(PainLocation location, String view) {
  final align = bodyViewRightAlignment(location.view, view);
  return Offset(
    math.sin(location.lineAngle) * align,
    -math.cos(location.lineAngle),
  );
}

Offset _remapToView(PainLocation location, String target) {
  final source = location.view;
  final x = location.normalizedX.clamp(0.0, 1.0);
  final y = location.normalizedY.clamp(0.0, 1.0);
  if (source == target) return Offset(x, y);
  final sourceProfile = source == 'left' || source == 'right';
  final targetProfile = target == 'left' || target == 'right';
  if (sourceProfile == targetProfile) return Offset(1 - x, y);
  if (targetProfile) {
    final edge = source == 'front'
        ? (target == 'left' ? 0.0 : 1.0)
        : (target == 'left' ? 1.0 : 0.0);
    return Offset(edge, y);
  }
  final bodyLeft = source == 'left';
  final edge = bodyLeft
      ? (target == 'front' ? 1.0 : 0.0)
      : (target == 'front' ? 0.0 : 1.0);
  return Offset(edge, y);
}
