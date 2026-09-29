import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/pain_models.dart';

/// One pain spot while a record is being composed.
///
/// The record page stores a list of these. The body workbench creates or
/// replaces exactly one, then returns it.
@immutable
class PainSpotDraft {
  const PainSpotDraft({
    required this.id,
    required this.x,
    required this.y,
    required this.view,
    required this.layer,
    required this.shape,
    required this.region,
    required this.partName,
    required this.bodyPartId,
    required this.markerScale,
    required this.lineLength,
    required this.lineAngle,
    required this.depthState,
    required this.use3d,
    this.side = 'unknown',
    this.localX,
    this.localY,
    this.localZ,
    this.depthMeters,
    this.meshId,
    this.surfaceRegionId,
    this.surfaceRegionSourceName,
    this.anatomicalStructureId,
    this.anatomicalSourceName,
    this.organGroup = 'all',
    this.isolateOrganGroup = false,
    this.shownAnatomy,
    this.frameZoom = 1,
    this.frameFocusX,
    this.frameFocusY,
    this.quick = false,
  });

  final String id;
  final double x;
  final double y;
  final String view;
  final BodyLayer layer;
  final PainShape shape;
  final BodyRegion region;
  final String partName;
  final String bodyPartId;
  final double markerScale;
  final double lineLength;
  final double lineAngle;
  final String depthState;
  final bool use3d;
  final String side;
  final double? localX;
  final double? localY;
  final double? localZ;
  final double? depthMeters;
  final String? meshId;
  final String? surfaceRegionId;
  final String? surfaceRegionSourceName;
  final String? anatomicalStructureId;
  final String? anatomicalSourceName;

  /// Organ subgroup that was showing when this 3D spot was placed.
  final String organGroup;
  final bool isolateOrganGroup;

  /// Anatomy chip that was open (肌肉 / 骨骼 / 器官), separate from the tissue
  /// the depth ray happened to classify.
  final BodyLayer? shownAnatomy;

  /// Camera zoom relative to the selected body region. 1 keeps that frame.
  final double frameZoom;

  /// Normalized image point the camera was aimed at, when the user had
  /// zoomed away from the region centre.
  final double? frameFocusX;
  final double? frameFocusY;

  /// True when the spot came from quick add, not a placed body mark.
  final bool quick;

  bool get has3d => localX != null && localY != null && localZ != null;

  /// Restores a saved spot so an ongoing pain can be opened again.
  factory PainSpotDraft.fromLocation(PainLocation location) {
    final has3d =
        location.localX != null &&
        location.localY != null &&
        location.localZ != null;
    return PainSpotDraft(
      id: location.id,
      x: location.normalizedX,
      y: location.normalizedY,
      view: location.view,
      layer: location.layer,
      shape: location.shape,
      region: location.region,
      partName: location.partName,
      bodyPartId: location.bodyPartId,
      markerScale: location.markerScale,
      lineLength: location.lineLength,
      lineAngle: location.lineAngle,
      depthState: location.depthState,
      use3d: has3d || location.coordinateMode == '3d',
      side: location.side,
      localX: location.localX,
      localY: location.localY,
      localZ: location.localZ,
      depthMeters: location.depthMeters,
      meshId: location.meshId,
      surfaceRegionId: location.surfaceRegionId,
      surfaceRegionSourceName: location.surfaceRegionSourceName,
      anatomicalStructureId: location.anatomicalStructureId,
      anatomicalSourceName: location.anatomicalSourceName,
      organGroup: location.organGroup,
      isolateOrganGroup: location.isolateOrganGroup,
      shownAnatomy: location.shownAnatomy,
      frameZoom: location.frameZoom,
      frameFocusX: location.frameFocusX,
      frameFocusY: location.frameFocusY,
      quick: location.bodyPartId.startsWith('quick_'),
    );
  }

  String get depthLabel {
    if (has3d) {
      if ((depthMeters ?? 0) <= 0.004) return '表面';
      final cm = (depthMeters! * 100).toStringAsFixed(1);
      final where = layer == BodyLayer.muscle ? '' : ' · ${layer.label}';
      return '皮下约 $cm cm$where';
    }
    return switch (depthState) {
      'surface' => '表面',
      'internal_unknown' => layer == BodyLayer.unknown ? '深处' : layer.label,
      _ => '说不清楚',
    };
  }

  /// Card line shared by quick-add and body-annotated spots.
  String get summary => '$partName · ${shape.label} · $depthLabel';

  String get fingerprint => [
    id,
    x,
    y,
    view,
    layer.name,
    shape.name,
    region.name,
    partName,
    bodyPartId,
    markerScale,
    lineLength,
    lineAngle,
    depthState,
    use3d,
    side,
    localX,
    localY,
    localZ,
    depthMeters,
    meshId,
    organGroup,
    isolateOrganGroup,
    shownAnatomy?.name,
    frameZoom,
    frameFocusX,
    frameFocusY,
    quick,
  ].join('|');

  /// Same placement as a new spot. [id] keeps the spot already being edited.
  PainSpotDraft duplicate({String? id, String? partName}) {
    return PainSpotDraft(
      id: id ?? const Uuid().v4(),
      x: x,
      y: y,
      view: view,
      layer: layer,
      shape: shape,
      region: region,
      partName: partName ?? this.partName,
      bodyPartId: bodyPartId,
      markerScale: markerScale,
      lineLength: lineLength,
      lineAngle: lineAngle,
      depthState: depthState,
      use3d: use3d,
      side: side,
      localX: localX,
      localY: localY,
      localZ: localZ,
      depthMeters: depthMeters,
      meshId: meshId,
      surfaceRegionId: surfaceRegionId,
      surfaceRegionSourceName: surfaceRegionSourceName,
      anatomicalStructureId: anatomicalStructureId,
      anatomicalSourceName: anatomicalSourceName,
      organGroup: organGroup,
      isolateOrganGroup: isolateOrganGroup,
      shownAnatomy: shownAnatomy,
      frameZoom: frameZoom,
      frameFocusX: frameFocusX,
      frameFocusY: frameFocusY,
      quick: quick,
    );
  }

  PainLocation toLocation({
    required int intensity0to10,
    required List<String> sensations,
  }) {
    return PainLocation(
      id: id,
      bodyPartId: bodyPartId,
      normalizedX: x,
      normalizedY: y,
      view: view,
      layer: layer,
      shape: shape,
      region: region,
      partName: partName,
      side: side,
      intensity0to10: intensity0to10,
      sensations: sensations,
      certainty: quick ? 'approximate' : 'marked',
      localX: has3d ? localX : null,
      localY: has3d ? localY : null,
      localZ: has3d ? localZ : null,
      depthMeters: has3d ? depthMeters : null,
      markerScale: markerScale,
      lineLength: lineLength,
      lineAngle: lineAngle,
      meshId: has3d ? meshId : null,
      surfaceRegionId: has3d ? surfaceRegionId : null,
      surfaceRegionSourceName: has3d ? surfaceRegionSourceName : null,
      anatomicalStructureId: has3d ? anatomicalStructureId : null,
      anatomicalSourceName: has3d ? anatomicalSourceName : null,
      shownAnatomy: has3d ? shownAnatomy : null,
      frameZoom: frameZoom,
      frameFocusX: frameFocusX,
      frameFocusY: frameFocusY,
      organGroup: has3d ? organGroup : 'all',
      isolateOrganGroup: has3d && isolateOrganGroup,
      coordinateMode: has3d ? '3d' : '2d',
      depthState: has3d
          ? ((depthMeters ?? 0) <= 0.004 ? 'surface' : 'known')
          : depthState,
    );
  }
}
