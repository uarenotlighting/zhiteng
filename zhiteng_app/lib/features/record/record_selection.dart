import 'package:flutter/foundation.dart';

import '../../core/models/pain_models.dart';

/// The quick 2D locator is the first view users see. The 3D view remains
/// mounted offstage so its bundled model can finish loading in the background.
const bool defaultRecordUses3d = false;

@immutable
class RecordRegionSelection {
  const RecordRegionSelection({
    this.twoDimensional = BodyRegion.full,
    this.threeDimensional = BodyRegion.full,
  });

  final BodyRegion twoDimensional;
  final BodyRegion threeDimensional;

  BodyRegion active({required bool use3d}) =>
      use3d ? threeDimensional : twoDimensional;

  RecordRegionSelection select(BodyRegion region, {required bool use3d}) {
    return RecordRegionSelection(
      twoDimensional: use3d ? twoDimensional : region,
      threeDimensional: use3d ? region : threeDimensional,
    );
  }
}

/// Point / line / patch / radiate stay on the mode that picked them.
/// Switching views does not copy the other mode's choice; both start as a point.
@immutable
class RecordShapeSelection {
  const RecordShapeSelection({
    this.twoDimensional = PainShape.point,
    this.threeDimensional = PainShape.point,
  });

  final PainShape twoDimensional;
  final PainShape threeDimensional;

  PainShape active({required bool use3d}) =>
      use3d ? threeDimensional : twoDimensional;

  RecordShapeSelection select(PainShape shape, {required bool use3d}) {
    return RecordShapeSelection(
      twoDimensional: use3d ? twoDimensional : shape,
      threeDimensional: use3d ? shape : threeDimensional,
    );
  }
}

/// A placed spot on one body mode. 2D and 3D each keep their own mark, so
/// switching modes does not copy the other side's location.
@immutable
class RecordBodyMark {
  const RecordBodyMark({
    this.picked = false,
    this.x = 0.5,
    this.y = 0.35,
    this.view = 'front',
    this.partName = '身体',
    this.bodyPartId = 'body',
    this.side = 'unknown',
    this.layer = BodyLayer.skin,
    this.depthState = 'surface',
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
  });

  final bool picked;
  final double x;
  final double y;
  final String view;
  final String partName;
  final String bodyPartId;
  final String side;
  final BodyLayer layer;
  final String depthState;
  final double? localX;
  final double? localY;
  final double? localZ;
  final double? depthMeters;
  final String? meshId;
  final String? surfaceRegionId;
  final String? surfaceRegionSourceName;
  final String? anatomicalStructureId;
  final String? anatomicalSourceName;
  final String organGroup;
  final bool isolateOrganGroup;
  final BodyLayer? shownAnatomy;

  bool get has3d => localX != null && localY != null && localZ != null;

  @override
  bool operator ==(Object other) {
    return other is RecordBodyMark &&
        other.picked == picked &&
        other.x == x &&
        other.y == y &&
        other.view == view &&
        other.partName == partName &&
        other.bodyPartId == bodyPartId &&
        other.side == side &&
        other.layer == layer &&
        other.depthState == depthState &&
        other.localX == localX &&
        other.localY == localY &&
        other.localZ == localZ &&
        other.depthMeters == depthMeters &&
        other.meshId == meshId &&
        other.surfaceRegionId == surfaceRegionId &&
        other.surfaceRegionSourceName == surfaceRegionSourceName &&
        other.anatomicalStructureId == anatomicalStructureId &&
        other.anatomicalSourceName == anatomicalSourceName &&
        other.organGroup == organGroup &&
        other.isolateOrganGroup == isolateOrganGroup &&
        other.shownAnatomy == shownAnatomy;
  }

  @override
  int get hashCode => Object.hashAll([
    picked,
    x,
    y,
    view,
    partName,
    bodyPartId,
    side,
    layer,
    depthState,
    localX,
    localY,
    localZ,
    depthMeters,
    meshId,
    surfaceRegionId,
    surfaceRegionSourceName,
    anatomicalStructureId,
    anatomicalSourceName,
    organGroup,
    isolateOrganGroup,
    shownAnatomy,
  ]);
}

/// Independent placed spots for the 2D map and the 3D model.
@immutable
class RecordMarkSelection {
  const RecordMarkSelection({
    this.twoDimensional = const RecordBodyMark(),
    this.threeDimensional = const RecordBodyMark(),
  });

  final RecordBodyMark twoDimensional;
  final RecordBodyMark threeDimensional;

  RecordBodyMark active({required bool use3d}) =>
      use3d ? threeDimensional : twoDimensional;

  RecordMarkSelection write(RecordBodyMark mark, {required bool use3d}) {
    return RecordMarkSelection(
      twoDimensional: use3d ? twoDimensional : mark,
      threeDimensional: use3d ? mark : threeDimensional,
    );
  }
}

double regionDefaultY(BodyRegion region) => switch (region) {
  BodyRegion.head => 0.22,
  BodyRegion.upper => 0.4,
  BodyRegion.lower => 0.7,
  BodyRegion.full => 0.35,
};
