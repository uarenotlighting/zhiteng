/// Shared body-model constants (Blender pipeline → GLB).
library;

import 'dart:math' as math;

/// Keep these in sync with ../zhiteng_body3d/export/manifest.json.
const String bodyModelVersion = 'zhiteng_zanatomy_neutral_20260922_v24';
const String coordinateSystemVersion = 'zanatomy_ortho_v1';
const String anatomicalMappingVersion = 'zanatomy_surface_regions_v2';

/// Bundled copy of the export manifest; the 3D viewer reads the version from
/// it at runtime so saved picks carry the geometry they were made on.
const String bodyModelManifestPath = 'assets/models/manifest.json';

const Map<String, String> bodyModelAssetPaths = {
  'skin': 'assets/models/skin.glb',
  'region': 'assets/models/region.glb',
  'muscle': 'assets/models/muscle.glb',
  'bone': 'assets/models/bone.glb',
  'organ': 'assets/models/organ.glb',
};

/// Smallest useful 3D payload. Nothing else may compete with the visible shell
/// before its first rendered frame.
const List<String> bodyModelInitialLayers = ['skin'];

/// Layers read from their local URLs after the skin's first rendered frame.
/// The region proxy is non-visual; organs are intentionally excluded and stay
/// strictly on demand.
const List<String> bodyModelBackgroundLayers = ['muscle', 'bone', 'region'];

/// Visual layers that define completion of the normal background warm-up.
const Set<String> bodyModelDefaultLayers = {'skin', 'muscle', 'bone'};

class OrganGroupOption {
  const OrganGroupOption(this.id, this.label);

  final String id;
  final String label;
}

/// Stable groups embedded in organ.glb. The viewer uses these IDs for colour,
/// focus and isolate behaviour; labels remain product copy owned by Flutter.
const List<OrganGroupOption> organGroupOptions = [
  OrganGroupOption('all', '全部'),
  OrganGroupOption('heart', '心脏'),
  OrganGroupOption('lung', '肺'),
  OrganGroupOption('hepatobiliary', '肝胆'),
  OrganGroupOption('digestive', '胃肠'),
  OrganGroupOption('urinary', '泌尿'),
];

const String body2dAssetDirectory = 'assets/models/2d';

/// World bounds of the shipped skin shell, metres. Y is up, the body faces
/// +Z, and body-left is +X. These are the skin.glb position bounds plus the
/// root node translation for [bodyModelVersion].
const double bodySkinMinX = -0.3351817727088928;
const double bodySkinMinY = 0.0011576414108276367;
const double bodySkinMinZ = -0.1464390754699707;
const double bodySkinMaxX = 0.3346092104911804;
const double bodySkinMaxY = 1.9238839149475098;
const double bodySkinMaxZ = 0.13779152929782867;

/// Orthographic image of a 3D point, in the same normalized space as a 2D tap.
///
/// The 2D maps are rendered by a camera on the named axis, looking at the
/// skin-bounds centre, with ortho scale `max(height × 1.08, width × 1.75)`
/// and a 768×1280 frame. That position does not move when the recording
/// camera orbits, zooms, or pushes the marker deeper along the view axis.
/// Screen-space `normalizedX` / `normalizedY` from a 3D pick do move, so a
/// saved preview has to use this projection instead.
({double x, double y}) projectBodyPointToImage({
  required double x,
  required double y,
  required double z,
  required String view,
}) {
  const centerX = (bodySkinMinX + bodySkinMaxX) / 2;
  const centerY = (bodySkinMinY + bodySkinMaxY) / 2;
  const centerZ = (bodySkinMinZ + bodySkinMaxZ) / 2;
  const height = bodySkinMaxY - bodySkinMinY;
  const width = bodySkinMaxX - bodySkinMinX;
  // 1.08 matches body2dOrthoPadding; 1.75 matches the Blender / viewer frame.
  final orthoScale = math.max(height * 1.08, width * 1.75);
  const aspect = 768 / 1280;
  final horizontal = switch (view) {
    'back' => -(x - centerX),
    'left' => -(z - centerZ),
    'right' => z - centerZ,
    _ => x - centerX,
  };
  return (
    x: 0.5 + horizontal / (orthoScale * aspect),
    y: 0.5 - (y - centerY) / orthoScale,
  );
}

/// How much of a line's screen-right component survives on [to].
///
/// Canonical views share world-up, so only the sideways part of a stroke
/// changes. Front/back and left/right mirror it; a face shown from the side
/// loses it because that direction is now depth.
double bodyViewRightAlignment(String from, String to) {
  (double, double) right(String view) => switch (view) {
    'back' => (-1.0, 0.0),
    'left' => (0.0, -1.0),
    'right' => (0.0, 1.0),
    _ => (1.0, 0.0),
  };
  final source = right(from);
  final target = right(to);
  return source.$1 * target.$1 + source.$2 * target.$2;
}

/// Radius of the pain indicator at scale 1, in body metres. Must match
/// `STYLE.marker.radius` in assets/web/body3d.html.
const double painMarkerBaseRadiusMeters = 0.014;

/// Radius of a line stroke at scale 1. Keep in sync with the line tube in
/// assets/web/body3d.html; the minimum scale gives a 3 mm wide line.
const double painLineBaseRadiusMeters = 0.003;

/// End-to-end length of a line mark at length scale 1. Must match the
/// `0.08 * lineLength` half-length in assets/web/body3d.html.
const double painLineBaseLengthMeters = 0.16;

/// Indicator size range offered to the user, as multiples of the base radius.
const double painMarkerMinScale = 0.5;
const double painMarkerMaxScale = 3.0;

/// Line-length range, as multiples of [painLineBaseLengthMeters].
const double painLineMinLength = 0.4;
const double painLineMaxLength = 3.0;
