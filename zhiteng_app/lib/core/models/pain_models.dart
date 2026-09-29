import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';

import 'body_model.dart';
export 'body_model.dart';

enum PainShape { point, area, line, radiate }

enum BodyLayer { skin, muscle, bone, organ, unknown }

// Keep the existing wire names so previously saved head/lower/full records
// remain readable; upper is an additional focus frame, not a new body model.
enum BodyRegion { head, upper, lower, full }

/// Plain-language, user-reported pain qualities. These describe a feeling;
/// they are not diagnoses. Keep wire values identical to the visible labels
/// so exports remain understandable without a separate lookup table.
const painSensationOptions = <String>[
  '刺痛',
  '跳痛',
  '抽痛',
  '阵痛',
  '钝痛',
  '隐痛',
  '锐痛',
  '酸痛',
  '胀痛',
  '灼热痛',
  '麻痛',
  '针扎样',
  '电击样',
  '刀割样',
  '撕裂样',
  '抽搐样',
  '痉挛样',
  '绞痛',
  '压迫痛',
  '紧绷痛',
  '搏动痛',
  '触碰痛',
  '放射痛',
  '游走痛',
  '冷痛',
  '痒痛',
  '说不清楚',
];

/// A custom sensation is one word, not a sentence. Count characters the way
/// the text field does so a long phrase cannot be stored.
const int customPainSensationMaxLength = 8;

/// Trims a user-typed sensation down to one word.
///
/// Returns null when nothing remains or the word is longer than
/// [customPainSensationMaxLength]. Built-in labels are left unchanged so the
/// caller can select them without copying them into the personal list.
String? normalizeCustomPainSensation(String raw) {
  final word = raw.replaceAll(RegExp(r'\s+'), '');
  if (word.isEmpty || word.characters.length > customPainSensationMaxLength) {
    return null;
  }
  return word;
}

/// Three identical graphemes in a row, whatever they are: 汉字、字母、数字、
/// emoji、标点 or symbols. "啊啊" is fine; "啊啊啊" and "aaa" are not.
bool hasThreeIdenticalCharactersInARow(String word) {
  final chars = word.characters;
  if (chars.length < 3) return false;
  String? previous;
  var run = 0;
  for (final char in chars) {
    if (char == previous) {
      run++;
      if (run >= 3) return true;
    } else {
      previous = char;
      run = 1;
    }
  }
  return false;
}

/// Newest personal words stay first. A built-in label is not copied into the
/// personal list; typing it again only selects the shared chip.
List<String> rememberCustomPainSensation(List<String> saved, String word) {
  if (painSensationOptions.contains(word)) return List<String>.from(saved);
  return [word, ...saved.where((item) => item != word)];
}

Set<String> togglePainSensation(Set<String> current, String sensation) {
  final next = {...current};
  if (next.remove(sensation)) return next;
  if (sensation == '说不清楚') return {'说不清楚'};
  next
    ..remove('说不清楚')
    ..add(sensation);
  return next;
}

extension PainShapeX on PainShape {
  String get label => switch (this) {
    PainShape.point => '点',
    PainShape.area => '片',
    PainShape.line => '线',
    PainShape.radiate => '放射',
  };

  String get wire => name;
  static PainShape fromWire(String? value) => PainShape.values.firstWhere(
    (e) => e.name == value,
    orElse: () => PainShape.point,
  );
}

extension BodyLayerX on BodyLayer {
  String get label => switch (this) {
    BodyLayer.skin => '皮肤',
    BodyLayer.muscle => '肌肉',
    BodyLayer.bone => '骨骼',
    BodyLayer.organ => '器官',
    BodyLayer.unknown => '说不清楚',
  };

  String get depthLabel => switch (this) {
    BodyLayer.skin => '皮肤',
    BodyLayer.muscle => '肌肉',
    BodyLayer.bone => '骨骼',
    BodyLayer.organ => '器官',
    BodyLayer.unknown => '说不清楚',
  };

  String get wire => name;
  static BodyLayer fromWire(String? value) => BodyLayer.values.firstWhere(
    (e) => e.name == value,
    orElse: () => BodyLayer.skin,
  );
}

extension BodyRegionX on BodyRegion {
  String get label => switch (this) {
    BodyRegion.head => '头部',
    BodyRegion.upper => '上身',
    BodyRegion.lower => '下身',
    BodyRegion.full => '全身',
  };

  String get coverageLabel => switch (this) {
    BodyRegion.head => '头、颈、肩',
    BodyRegion.upper => '上肢、手、上身',
    BodyRegion.lower => '下肢、脚',
    BodyRegion.full => '完整人体',
  };

  String get wire => name;
  static BodyRegion fromWire(String? value) => BodyRegion.values.firstWhere(
    (e) => e.name == value,
    orElse: () => BodyRegion.full,
  );
}

class PainLocation {
  PainLocation({
    required this.id,
    required this.bodyPartId,
    required this.normalizedX,
    required this.normalizedY,
    required this.view,
    required this.layer,
    required this.shape,
    required this.region,
    required this.partName,
    this.side = 'unknown',
    this.intensity0to10 = 3,
    this.sensations = const [],
    this.certainty = 'approximate',
    this.localX,
    this.localY,
    this.localZ,
    this.meshId,
    this.surfaceRegionId,
    this.surfaceRegionSourceName,
    this.anatomicalStructureId,
    this.anatomicalSourceName,
    this.depthMeters,
    this.markerScale = painMarkerMinScale,
    this.lineLength = 1,
    this.lineAngle = 0,
    this.shownAnatomy,
    this.organGroup = 'all',
    this.isolateOrganGroup = false,
    this.frameZoom = 1,
    this.frameFocusX,
    this.frameFocusY,
    String? coordinateMode,
    String? depthState,
  }) : coordinateMode = coordinateMode ?? (localX == null ? '2d' : '3d'),
       depthState =
           depthState ??
           (localX == null
               ? switch (layer) {
                   BodyLayer.skin => 'surface',
                   BodyLayer.unknown => 'unknown',
                   _ => 'internal_unknown',
                 }
               : switch (layer) {
                   BodyLayer.skin => 'surface',
                   BodyLayer.unknown => 'unknown',
                   _ => 'known',
                 });

  final String id;
  final String bodyPartId;
  final double normalizedX;
  final double normalizedY;
  final String view;
  final BodyLayer layer;
  final PainShape shape;
  final BodyRegion region;
  final String partName;
  final String side;
  final int intensity0to10;
  final List<String> sensations;
  final String certainty;
  final double? localX;
  final double? localY;
  final double? localZ;
  final String? meshId;

  /// Exact source region transferred from Z-Anatomy's segmented surface onto
  /// the continuous neutral shell. This is stable across both 2D and 3D.
  final String? surfaceRegionId;
  final String? surfaceRegionSourceName;

  /// Stable ID and original label of the Z-Anatomy / BodyParts3D structure
  /// used to resolve the coarse user-facing body area.
  final String? anatomicalStructureId;
  final String? anatomicalSourceName;

  /// Distance below the skin along the view ray when placed in 3D (metres).
  final double? depthMeters;

  /// Indicator size chosen by the user, as a multiple of the default marker
  /// (default radius [painMarkerBaseRadiusMeters]). Roughly how large the
  /// painful spot felt.
  final double markerScale;

  /// Line-mark length as a multiple of [painLineBaseLengthMeters]. Ignored
  /// for shapes other than [PainShape.line].
  final double lineLength;

  /// Line direction in radians around the outward surface normal.
  /// 0 runs along the body. Positive turns the line counter-clockwise when
  /// looking at the surface. The stroke is rebuilt on the body, not spun as
  /// a rigid bar.
  final double lineAngle;

  /// Anatomy model visible in the 3D workbench when this spot was saved.
  /// This differs from [layer], which describes the marker's tissue depth.
  final BodyLayer? shownAnatomy;

  /// Organ visibility state saved with a 3D organ-model placement.
  final String organGroup;
  final bool isolateOrganGroup;

  /// Camera magnification relative to [region]'s default frame. 1 is the
  /// 头部 / 上身 / 下身 / 全身 chip. Larger means the user had zoomed in.
  final double frameZoom;

  /// Normalized image point the camera was looking at. Null uses the region
  /// centre, so older records still open on the chip they saved.
  final double? frameFocusX;
  final double? frameFocusY;
  final String coordinateMode;
  final String depthState;

  /// Model that should be reconstructed in history previews.
  ///
  /// Older 3D records did not persist [shownAnatomy]. Use their saved tissue
  /// layer when it identifies an anatomy model; otherwise fall back to the
  /// workbench's historical muscle default. 2D records use the layer chosen
  /// by the user.
  BodyLayer get displayAnatomyLayer {
    if (coordinateMode == '3d') {
      final selected = shownAnatomy;
      if (selected == BodyLayer.muscle ||
          selected == BodyLayer.bone ||
          selected == BodyLayer.organ) {
        return selected!;
      }
      if (layer == BodyLayer.muscle ||
          layer == BodyLayer.bone ||
          layer == BodyLayer.organ) {
        return layer;
      }
      return BodyLayer.muscle;
    }
    return layer == BodyLayer.unknown ? BodyLayer.skin : layer;
  }

  /// Approximate radius of the marked spot on the body, metres.
  /// For a line this is the stroke thickness; length is [lineLengthMeters].
  double get extentMeters => painMarkerBaseRadiusMeters * markerScale;

  /// End-to-end length of a line mark, metres.
  double get lineLengthMeters => painLineBaseLengthMeters * lineLength;

  Map<String, dynamic> toJson() => {
    'id': id,
    'bodyPartId': bodyPartId,
    'normalizedX': normalizedX,
    'normalizedY': normalizedY,
    'view': view,
    'layer': layer.wire,
    'shape': shape.wire,
    'region': region.wire,
    'partName': partName,
    'side': side,
    'intensity0to10': intensity0to10,
    'intensityLabel': intensityLabel(intensity0to10),
    'sensations': sensations,
    'certainty': certainty,
    'coordinateMode': coordinateMode,
    'depthState': depthState,
    'geometryType': shape == PainShape.area ? 'area' : 'point',
    'localXYZ': localX == null ? null : {'x': localX, 'y': localY, 'z': localZ},
    'depthMeters': depthMeters,
    'markerScale': markerScale,
    'extentMeters': extentMeters,
    'lineLength': lineLength,
    'lineLengthMeters': lineLengthMeters,
    'lineAngle': lineAngle,
    'shownAnatomy': shownAnatomy?.wire,
    'organGroup': organGroup,
    'isolateOrganGroup': isolateOrganGroup,
    'frameZoom': frameZoom,
    'frameFocusX': frameFocusX,
    'frameFocusY': frameFocusY,
    'meshId': meshId,
    'surfaceRegionId': surfaceRegionId,
    'surfaceRegionSourceName': surfaceRegionSourceName,
    'anatomicalStructureId': anatomicalStructureId,
    'anatomicalSourceName': anatomicalSourceName,
    'bodyModelVersion': bodyModelVersion,
    'coordinateSystemVersion': coordinateSystemVersion,
    'anatomicalMappingVersion': anatomicalMappingVersion,
  };

  factory PainLocation.fromJson(Map<String, dynamic> json) {
    final xyz = json['localXYZ'] as Map<String, dynamic>?;
    return PainLocation(
      id: json['id'] as String? ?? const Uuid().v4(),
      bodyPartId: json['bodyPartId'] as String? ?? 'unknown',
      normalizedX: (json['normalizedX'] as num?)?.toDouble() ?? 0.5,
      normalizedY: (json['normalizedY'] as num?)?.toDouble() ?? 0.35,
      view: json['view'] as String? ?? 'front',
      layer: BodyLayerX.fromWire(json['layer'] as String?),
      shape: PainShapeX.fromWire(json['shape'] as String?),
      region: BodyRegionX.fromWire(json['region'] as String?),
      partName: json['partName'] as String? ?? '身体',
      side: json['side'] as String? ?? 'unknown',
      intensity0to10: json['intensity0to10'] as int? ?? 3,
      sensations: (json['sensations'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      certainty: json['certainty'] as String? ?? 'approximate',
      localX: (xyz?['x'] as num?)?.toDouble(),
      localY: (xyz?['y'] as num?)?.toDouble(),
      localZ: (xyz?['z'] as num?)?.toDouble(),
      meshId: json['meshId'] as String?,
      surfaceRegionId: json['surfaceRegionId'] as String?,
      surfaceRegionSourceName: json['surfaceRegionSourceName'] as String?,
      anatomicalStructureId: json['anatomicalStructureId'] as String?,
      anatomicalSourceName: json['anatomicalSourceName'] as String?,
      depthMeters: (json['depthMeters'] as num?)?.toDouble(),
      // Records predating adjustable size used scale 1. Preserve their size
      // even though newly created markers now start at the minimum.
      markerScale: (json['markerScale'] as num?)?.toDouble() ?? 1,
      lineLength: (json['lineLength'] as num?)?.toDouble() ?? 1,
      lineAngle: (json['lineAngle'] as num?)?.toDouble() ?? 0,
      shownAnatomy: json['shownAnatomy'] == null
          ? null
          : BodyLayerX.fromWire(json['shownAnatomy'] as String?),
      organGroup: json['organGroup'] as String? ?? 'all',
      isolateOrganGroup: json['isolateOrganGroup'] as bool? ?? false,
      frameZoom: (json['frameZoom'] as num?)?.toDouble() ?? 1,
      frameFocusX: (json['frameFocusX'] as num?)?.toDouble(),
      frameFocusY: (json['frameFocusY'] as num?)?.toDouble(),
      coordinateMode: json['coordinateMode'] as String?,
      depthState: json['depthState'] as String?,
    );
  }
}

/// Units a dose can be written in. The number is stored separately so a
/// later review can still read “1 片” without parsing the label.
const medicationDoseUnits = <String>[
  '片',
  '粒',
  '毫克',
  '毫升',
  '克',
  '滴',
  '支',
  '袋',
  '贴',
];

/// One medicine taken around this pain. Empty means the person did not
/// record a dose; it is not a claim that they took nothing.
class MedicationRecord {
  const MedicationRecord({
    required this.name,
    required this.doseAmount,
    required this.doseUnit,
    required this.takenAt,
  });

  final String name;
  final double doseAmount;
  final String doseUnit;
  final DateTime takenAt;

  String get doseText {
    final whole = doseAmount == doseAmount.roundToDouble();
    final amount = whole
        ? doseAmount.toStringAsFixed(0)
        : doseAmount.toString();
    return '$amount $doseUnit';
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'doseAmount': doseAmount,
    'doseUnit': doseUnit,
    'takenAt': takenAt.toIso8601String(),
  };

  factory MedicationRecord.fromJson(Map<String, dynamic> json) {
    return MedicationRecord(
      name: json['name'] as String? ?? '',
      doseAmount: (json['doseAmount'] as num?)?.toDouble() ?? 0,
      doseUnit: json['doseUnit'] as String? ?? medicationDoseUnits.first,
      takenAt: DateTime.parse(json['takenAt'] as String),
    );
  }
}

String formatMedicationDose(double amount) {
  if (amount == amount.roundToDouble()) return amount.toStringAsFixed(0);
  return amount.toString();
}

/// One confirmed moment in a pain episode. Later edits append a new moment;
/// they do not rewrite an earlier one, except the start time of [started].
enum PainMomentKind { started, changed, medication, note, ended }

PainMomentKind painMomentKindFromWire(String? value) {
  return PainMomentKind.values.firstWhere(
    (kind) => kind.name == value,
    orElse: () => PainMomentKind.changed,
  );
}

int _painMomentRank(PainMomentKind kind) => switch (kind) {
  PainMomentKind.started => 0,
  PainMomentKind.changed => 1,
  PainMomentKind.medication => 2,
  PainMomentKind.note => 3,
  PainMomentKind.ended => 4,
};

bool isBeforeMinute(DateTime a, DateTime b) {
  final left = DateTime(a.year, a.month, a.day, a.hour, a.minute);
  final right = DateTime(b.year, b.month, b.day, b.hour, b.minute);
  return left.isBefore(right);
}

bool isAfterMinute(DateTime a, DateTime b) => isBeforeMinute(b, a);

bool sameMinute(DateTime a, DateTime b) =>
    !isBeforeMinute(a, b) && !isBeforeMinute(b, a);

class PainMoment {
  const PainMoment({
    required this.id,
    required this.at,
    required this.kind,
    this.intensity0to10,
    this.sensations = const [],
    this.locations = const [],
    this.medication,
    this.note = '',
  });

  final String id;
  final DateTime at;
  final PainMomentKind kind;
  final int? intensity0to10;
  final List<String> sensations;
  final List<PainLocation> locations;
  final MedicationRecord? medication;
  final String note;

  PainMoment copyWith({DateTime? at}) {
    return PainMoment(
      id: id,
      at: at ?? this.at,
      kind: kind,
      intensity0to10: intensity0to10,
      sensations: sensations,
      locations: locations,
      medication: medication,
      note: note,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'kind': kind.name,
    'intensity0to10': intensity0to10,
    'sensations': sensations,
    'locations': locations.map((location) => location.toJson()).toList(),
    'medication': medication?.toJson(),
    'note': note,
  };

  factory PainMoment.fromJson(Map<String, dynamic> json) {
    final rawLocations = json['locations'] as List<dynamic>? ?? const [];
    final rawMedication = json['medication'];
    return PainMoment(
      id: json['id'] as String? ?? const Uuid().v4(),
      at: DateTime.parse(json['at'] as String),
      kind: painMomentKindFromWire(json['kind'] as String?),
      intensity0to10: json['intensity0to10'] as int?,
      sensations: (json['sensations'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      locations: rawLocations
          .map(
            (item) =>
                PainLocation.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      medication: rawMedication is Map
          ? MedicationRecord.fromJson(Map<String, dynamic>.from(rawMedication))
          : null,
      note: json['note'] as String? ?? '',
    );
  }
}

/// What the record page is asking to store. [changeAt] stamps body, feeling,
/// and intensity changes. Each medicine keeps its own time.
class PainMomentDraft {
  const PainMomentDraft({
    required this.startedAt,
    required this.changeAt,
    required this.locations,
    required this.intensity0to10,
    this.endedAt,
    this.medications = const [],
    this.supplement = '',
  });

  final DateTime startedAt;
  final DateTime changeAt;
  final DateTime? endedAt;
  final List<PainLocation> locations;
  final int intensity0to10;
  final List<MedicationRecord> medications;
  final String supplement;
}

class PainTimelineUpdate {
  const PainTimelineUpdate({
    required this.moments,
    required this.startedAt,
    required this.endedAt,
    required this.locations,
    required this.intensity0to10,
    required this.medications,
    required this.notes,
  });

  final List<PainMoment> moments;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<PainLocation> locations;
  final int intensity0to10;
  final List<MedicationRecord> medications;
  final String notes;
}

class PainUpdateOutcome {
  const PainUpdateOutcome.saved(this.update) : message = null;
  const PainUpdateOutcome.unchanged() : update = null, message = null;
  const PainUpdateOutcome.rejected(String this.message) : update = null;

  final PainTimelineUpdate? update;
  final String? message;

  bool get saved => update != null;
  bool get unchanged => update == null && message == null;
}

class PainRecordRejected implements Exception {
  const PainRecordRejected(this.message);
  final String message;

  @override
  String toString() => message;
}

class CaptionedPainMoment {
  const CaptionedPainMoment({required this.moment, required this.caption});

  final PainMoment moment;
  final String caption;
}

/// One step on the course timeline: a short action title and the record body.
class PainCourseLine {
  const PainCourseLine({
    required this.moment,
    required this.title,
    required this.detail,
  });

  final PainMoment moment;
  final String title;
  final String detail;
}

class PainEntry {
  PainEntry({
    required this.id,
    required this.createdAt,
    required this.startedAt,
    required this.locations,
    required this.intensity0to10,
    this.endedAt,
    this.status = 'ongoing',
    this.notes = '',
    this.medications = const [],
    this.moments = const [],
    this.sourcePlatform = 'app',
    this.completionState = 'minimal',
    this.syncVersion = 1,
  });

  final String id;
  final DateTime createdAt;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final List<PainLocation> locations;
  final int intensity0to10;
  final String notes;
  final List<MedicationRecord> medications;

  /// Confirmed moments. Empty means a record saved before timelines existed;
  /// [timeline] rebuilds them from the snapshot fields.
  final List<PainMoment> moments;
  final String sourcePlatform;
  final String completionState;
  final int syncVersion;

  String get primaryPartName {
    if (locations.isEmpty) return '未标记部位';
    if (locations.length == 1) return locations.first.partName;
    return '${locations.first.partName} 等${locations.length}处';
  }

  /// A pain stays on the home list until the user records when it stopped.
  bool get isOngoing => endedAt == null;

  String get intensityCaption => intensityLabel(intensity0to10);

  /// Stored moments, or a one-time reconstruction for older snapshots.
  List<PainMoment> get timeline =>
      moments.isNotEmpty ? moments : synthesizePainMoments(this);

  CaptionedPainMoment? get latestCourseMoment {
    final lines = captionedPainMoments(timeline);
    if (lines.isEmpty) return null;
    return lines.last;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt?.toIso8601String(),
    'status': status,
    'locations': locations.map((e) => e.toJson()).toList(),
    'intensity0to10': intensity0to10,
    'intensityLabel': intensityLabel(intensity0to10),
    'notes': notes,
    'medications': medications.map((item) => item.toJson()).toList(),
    'moments': timeline.map((moment) => moment.toJson()).toList(),
    'sourcePlatform': sourcePlatform,
    'completionState': completionState,
    'syncVersion': syncVersion,
    'bodyModelVersion': bodyModelVersion,
  };

  factory PainEntry.fromJson(Map<String, dynamic> json) {
    final rawLocations = json['locations'] as List<dynamic>? ?? const [];
    return PainEntry(
      id: json['id'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      endedAt: json['endedAt'] == null
          ? null
          : DateTime.parse(json['endedAt'] as String),
      status: json['status'] as String? ?? 'ongoing',
      locations: rawLocations
          .map(
            (e) => PainLocation.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(),
      intensity0to10: json['intensity0to10'] as int? ?? 3,
      notes: json['notes'] as String? ?? '',
      medications: (json['medications'] as List<dynamic>? ?? const [])
          .map(
            (item) => MedicationRecord.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(),
      moments: (json['moments'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                PainMoment.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(),
      sourcePlatform: json['sourcePlatform'] as String? ?? 'app',
      completionState: json['completionState'] as String? ?? 'minimal',
      syncVersion: json['syncVersion'] as int? ?? 1,
    );
  }

  String encode() => jsonEncode(toJson());

  static PainEntry decode(String raw) =>
      PainEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}

List<PainMoment> sortPainMoments(List<PainMoment> moments) {
  final indexed = moments.indexed.toList();
  indexed.sort((a, b) {
    final byTime = a.$2.at.compareTo(b.$2.at);
    if (byTime != 0) return byTime;
    final byRank = _painMomentRank(
      a.$2.kind,
    ).compareTo(_painMomentRank(b.$2.kind));
    if (byRank != 0) return byRank;
    return a.$1.compareTo(b.$1);
  });
  return [for (final item in indexed) item.$2];
}

List<String> sensationsOf(List<PainLocation> locations) {
  final seen = <String>[];
  for (final location in locations) {
    for (final sensation in location.sensations) {
      if (!seen.contains(sensation)) seen.add(sensation);
    }
  }
  return seen;
}

/// Rebuilds a timeline for a snapshot that was saved before moments existed.
List<PainMoment> synthesizePainMoments(PainEntry entry) {
  final moments = <PainMoment>[
    PainMoment(
      id: '${entry.id}:started',
      at: entry.startedAt,
      kind: PainMomentKind.started,
      intensity0to10: entry.intensity0to10,
      sensations: sensationsOf(entry.locations),
      locations: entry.locations,
    ),
    if (entry.notes.trim().isNotEmpty)
      PainMoment(
        id: '${entry.id}:note',
        at: entry.startedAt,
        kind: PainMomentKind.note,
        note: entry.notes.trim(),
      ),
    for (var i = 0; i < entry.medications.length; i++)
      PainMoment(
        id: '${entry.id}:med:$i',
        at: entry.medications[i].takenAt,
        kind: PainMomentKind.medication,
        medication: entry.medications[i],
      ),
    if (entry.endedAt != null)
      PainMoment(
        id: '${entry.id}:ended',
        at: entry.endedAt!,
        kind: PainMomentKind.ended,
        intensity0to10: entry.intensity0to10,
      ),
  ];
  return sortPainMoments(moments);
}

String notesFromMoments(List<PainMoment> moments) {
  return [
    for (final moment in sortPainMoments(moments))
      if (moment.kind == PainMomentKind.note && moment.note.trim().isNotEmpty)
        moment.note.trim(),
  ].join('\n');
}

String ongoingDurationLabel(DateTime startedAt, DateTime now) {
  final start = DateTime(
    startedAt.year,
    startedAt.month,
    startedAt.day,
    startedAt.hour,
    startedAt.minute,
  );
  final current = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  var minutes = current.difference(start).inMinutes;
  if (minutes <= 0) return '刚刚开始';
  if (minutes < 60) return '已持续 $minutes 分钟';
  final hours = minutes ~/ 60;
  minutes %= 60;
  if (hours < 24) {
    return minutes == 0 ? '已持续 $hours 小时' : '已持续 $hours 小时 $minutes 分';
  }
  final days = hours ~/ 24;
  final restHours = hours % 24;
  if (restHours == 0) return '已持续 $days 天';
  return '已持续 $days 天 $restHours 小时';
}

/// Lowest to highest level recorded on the episode, for a history summary.
String intensityCourseLabel(PainEntry entry) {
  final values = <int>[
    for (final moment in entry.timeline)
      if (moment.kind == PainMomentKind.started ||
          moment.kind == PainMomentKind.changed)
        if (moment.intensity0to10 != null) moment.intensity0to10!,
  ];
  if (values.isEmpty) return '${entry.intensity0to10} 级';
  var low = values.first;
  var high = values.first;
  for (final value in values) {
    if (value < low) low = value;
    if (value > high) high = value;
  }
  if (low == high) return '$low 级';
  return '$low 级到 $high 级';
}

List<String> latestPainSensations(PainEntry entry) {
  final body = _latestBodyMoment(entry.timeline);
  if (body != null) return body.sensations;
  return sensationsOf(entry.locations);
}

List<CaptionedPainMoment> captionedPainMoments(List<PainMoment> moments) {
  final sorted = sortPainMoments(moments);
  PainMoment? body;
  final lines = <CaptionedPainMoment>[];
  for (final moment in sorted) {
    lines.add(
      CaptionedPainMoment(
        moment: moment,
        caption: painMomentCaption(moment, previousBody: body),
      ),
    );
    if (moment.kind == PainMomentKind.started ||
        moment.kind == PainMomentKind.changed) {
      body = moment;
    }
  }
  return lines;
}

String painMomentCaption(PainMoment moment, {PainMoment? previousBody}) {
  return switch (moment.kind) {
    PainMomentKind.started => _startedCaption(moment),
    PainMomentKind.changed =>
      previousBody == null ? '记下了变化' : _changeCaption(previousBody, moment),
    PainMomentKind.medication =>
      moment.medication == null
          ? '记录了用药'
          : '吃了${moment.medication!.name} ${moment.medication!.doseText}',
    PainMomentKind.note => moment.note,
    PainMomentKind.ended => '结束',
  };
}

List<PainCourseLine> painCourseLines(List<PainMoment> moments) {
  final sorted = sortPainMoments(moments);
  PainMoment? body;
  final lines = <PainCourseLine>[];
  for (final moment in sorted) {
    lines.add(_courseLine(moment, previousBody: body));
    if (moment.kind == PainMomentKind.started ||
        moment.kind == PainMomentKind.changed) {
      body = moment;
    }
  }
  return lines;
}

PainCourseLine _courseLine(PainMoment moment, {PainMoment? previousBody}) {
  return switch (moment.kind) {
    PainMomentKind.started => PainCourseLine(
      moment: moment,
      title: '开始',
      detail: _startedDetail(moment),
    ),
    PainMomentKind.changed => _changedCourse(moment, previousBody),
    PainMomentKind.medication => PainCourseLine(
      moment: moment,
      title: '用药',
      detail: moment.medication == null
          ? ''
          : '${moment.medication!.name} ${moment.medication!.doseText}',
    ),
    PainMomentKind.note => PainCourseLine(
      moment: moment,
      title: '补充',
      detail: moment.note.trim(),
    ),
    PainMomentKind.ended => PainCourseLine(
      moment: moment,
      title: '结束',
      detail: '',
    ),
  };
}

PainCourseLine _changedCourse(PainMoment moment, PainMoment? previous) {
  if (previous == null) {
    return PainCourseLine(moment: moment, title: '修改', detail: '记下了变化');
  }
  final diff = _bodyDiff(previous, moment);
  if (diff.isEmpty) {
    return PainCourseLine(moment: moment, title: '修改', detail: '记下了变化');
  }
  final titles = <String>[
    if (diff.added.isNotEmpty) '新增',
    if (diff.intensity != null || diff.geometry || diff.sensation != null) '修改',
    if (diff.removed.isNotEmpty) '删除',
  ];
  final sole = titles.length == 1 ? titles.single : null;
  final detail = [
    if (diff.intensity != null) diff.intensity!,
    if (diff.added.isNotEmpty)
      sole == '新增' ? diff.added.join('、') : '增加${diff.added.join('、')}',
    if (diff.removed.isNotEmpty)
      sole == '删除' ? diff.removed.join('、') : '去掉${diff.removed.join('、')}',
    if (diff.geometry) '调整了痛点',
    if (diff.sensation != null) diff.sensation!,
  ].join(' · ');
  return PainCourseLine(
    moment: moment,
    title: titles.join(' · '),
    detail: detail,
  );
}

/// Appends confirmed moments. Returns unchanged when an open pain has nothing
/// new. The first moment's time can move; its contents stay as first written.
PainUpdateOutcome applyPainUpdate({
  required PainEntry? previous,
  required PainMomentDraft draft,
  required String Function() newId,
}) {
  final supplement = draft.supplement.trim();
  final rejection = _rejectDraft(previous: previous, draft: draft);
  if (rejection != null) return PainUpdateOutcome.rejected(rejection);
  final medicationError = _rejectMedications(
    previous == null ? draft.medications : _medicationsToCheck(previous, draft),
    startedAt: draft.startedAt,
    endedAt: draft.endedAt,
  );
  if (medicationError != null) {
    return PainUpdateOutcome.rejected(medicationError);
  }

  if (previous == null) {
    final sensations = sensationsOf(draft.locations);
    final moments = <PainMoment>[
      PainMoment(
        id: newId(),
        at: draft.startedAt,
        kind: PainMomentKind.started,
        intensity0to10: draft.intensity0to10,
        sensations: sensations,
        locations: draft.locations,
      ),
      for (final medication in draft.medications)
        PainMoment(
          id: newId(),
          at: medication.takenAt,
          kind: PainMomentKind.medication,
          medication: medication,
        ),
      if (supplement.isNotEmpty)
        PainMoment(
          id: newId(),
          at: draft.startedAt,
          kind: PainMomentKind.note,
          note: supplement,
        ),
      if (draft.endedAt != null)
        PainMoment(
          id: newId(),
          at: draft.endedAt!,
          kind: PainMomentKind.ended,
          intensity0to10: draft.intensity0to10,
        ),
    ];
    final sorted = sortPainMoments(moments);
    return PainUpdateOutcome.saved(
      PainTimelineUpdate(
        moments: sorted,
        startedAt: draft.startedAt,
        endedAt: draft.endedAt,
        locations: draft.locations,
        intensity0to10: draft.intensity0to10,
        medications: draft.medications,
        notes: notesFromMoments(sorted),
      ),
    );
  }

  final existing = [...previous.timeline];
  final startedIndex = existing.indexWhere(
    (moment) => moment.kind == PainMomentKind.started,
  );
  final startChanged = !sameMinute(previous.startedAt, draft.startedAt);
  if (startChanged && startedIndex >= 0) {
    existing[startedIndex] = existing[startedIndex].copyWith(
      at: draft.startedAt,
    );
  }

  final body = _latestBodyMoment(existing);
  final bodyChanged = body == null || !_sameBody(body, draft);
  final freshMedications = _newMedications(existing, draft.medications);
  final finishing = draft.endedAt != null && previous.endedAt == null;
  if (finishing &&
      (bodyChanged || supplement.isNotEmpty) &&
      isBeforeMinute(draft.endedAt!, draft.changeAt)) {
    return const PainUpdateOutcome.rejected('结束时间不能早于这次变化');
  }
  if (finishing &&
      previous.timeline.any(
        (moment) =>
            moment.kind != PainMomentKind.started &&
            isBeforeMinute(draft.endedAt!, moment.at),
      )) {
    return const PainUpdateOutcome.rejected('结束时间不能早于已经记下的经过');
  }
  if (!startChanged &&
      !bodyChanged &&
      freshMedications.isEmpty &&
      supplement.isEmpty &&
      !finishing) {
    return const PainUpdateOutcome.unchanged();
  }

  final sensations = sensationsOf(draft.locations);
  final added = <PainMoment>[
    if (bodyChanged)
      PainMoment(
        id: newId(),
        at: draft.changeAt,
        kind: PainMomentKind.changed,
        intensity0to10: draft.intensity0to10,
        sensations: sensations,
        locations: draft.locations,
      ),
    for (final medication in freshMedications)
      PainMoment(
        id: newId(),
        at: medication.takenAt,
        kind: PainMomentKind.medication,
        medication: medication,
      ),
    if (supplement.isNotEmpty)
      PainMoment(
        id: newId(),
        at: draft.changeAt,
        kind: PainMomentKind.note,
        note: supplement,
      ),
    if (finishing)
      PainMoment(
        id: newId(),
        at: draft.endedAt!,
        kind: PainMomentKind.ended,
        intensity0to10: draft.intensity0to10,
      ),
  ];
  final sorted = sortPainMoments([...existing, ...added]);
  return PainUpdateOutcome.saved(
    PainTimelineUpdate(
      moments: sorted,
      startedAt: draft.startedAt,
      endedAt: finishing ? draft.endedAt : previous.endedAt,
      locations: bodyChanged ? draft.locations : previous.locations,
      intensity0to10: bodyChanged
          ? draft.intensity0to10
          : previous.intensity0to10,
      medications: [...previous.medications, ...freshMedications],
      notes: notesFromMoments(sorted),
    ),
  );
}

String? _rejectDraft({
  required PainEntry? previous,
  required PainMomentDraft draft,
}) {
  final now = DateTime.now();
  if (isAfterMinute(draft.startedAt, now)) return '开始时间不能晚于现在';
  if (isAfterMinute(draft.changeAt, now)) return '这次变化的时间不能晚于现在';
  if (isBeforeMinute(draft.changeAt, draft.startedAt)) {
    return '这次变化的时间不能早于开始时间';
  }
  final endedAt = draft.endedAt;
  if (endedAt != null) {
    if (isAfterMinute(endedAt, now)) return '结束时间不能晚于现在';
    if (isBeforeMinute(endedAt, draft.startedAt)) return '结束时间不能早于开始时间';
    if (previous == null && isBeforeMinute(endedAt, draft.changeAt)) {
      return '结束时间不能早于这次变化';
    }
  }
  if (previous != null && !sameMinute(previous.startedAt, draft.startedAt)) {
    final blocked = previous.timeline.any(
      (moment) =>
          moment.kind != PainMomentKind.started &&
          isBeforeMinute(moment.at, draft.startedAt),
    );
    if (blocked) return '开始时间不能晚于已经记下的经过';
  }
  return null;
}

PainMoment? _latestBodyMoment(List<PainMoment> moments) {
  for (final moment in sortPainMoments(moments).reversed) {
    if (moment.kind == PainMomentKind.started ||
        moment.kind == PainMomentKind.changed) {
      return moment;
    }
  }
  return null;
}

bool _sameBody(PainMoment moment, PainMomentDraft draft) {
  if (moment.intensity0to10 != draft.intensity0to10) return false;
  if (!_sameStringSet(moment.sensations, sensationsOf(draft.locations))) {
    return false;
  }
  return _sameGeometry(moment.locations, draft.locations);
}

bool _sameStringSet(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final rest = {...b};
  if (rest.length != b.length) return _sameMultiset(a, b);
  return a.every(rest.contains);
}

bool _sameMultiset(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final counts = <String, int>{};
  for (final item in a) {
    counts[item] = (counts[item] ?? 0) + 1;
  }
  for (final item in b) {
    final next = (counts[item] ?? 0) - 1;
    if (next < 0) return false;
    counts[item] = next;
  }
  return true;
}

bool _sameGeometry(List<PainLocation> a, List<PainLocation> b) {
  return _sameMultiset(
    a.map(_locationSignature).toList(),
    b.map(_locationSignature).toList(),
  );
}

String _locationSignature(PainLocation location) {
  String n(double? value) => value == null ? '' : value.toStringAsFixed(3);
  return [
    location.id,
    location.partName,
    location.shape.wire,
    location.layer.wire,
    location.region.wire,
    location.view,
    location.side,
    location.certainty,
    location.depthState,
    n(location.normalizedX),
    n(location.normalizedY),
    n(location.localX),
    n(location.localY),
    n(location.localZ),
    n(location.markerScale),
    n(location.lineLength),
    n(location.lineAngle),
  ].join('|');
}

List<MedicationRecord> _medicationsToCheck(
  PainEntry previous,
  PainMomentDraft draft,
) {
  final fresh = _newMedications(previous.timeline, draft.medications);
  if (draft.endedAt != null ||
      !sameMinute(previous.startedAt, draft.startedAt)) {
    return draft.medications;
  }
  return fresh;
}

String? _rejectMedications(
  List<MedicationRecord> medications, {
  required DateTime startedAt,
  DateTime? endedAt,
}) {
  final now = DateTime.now();
  for (final medication in medications) {
    if (isBeforeMinute(medication.takenAt, startedAt)) {
      return '用药时间不能早于开始时间';
    }
    if (endedAt != null && isBeforeMinute(endedAt, medication.takenAt)) {
      return '用药时间不能晚于结束时间';
    }
    if (isAfterMinute(medication.takenAt, now)) return '用药时间不能晚于现在';
  }
  return null;
}

List<MedicationRecord> _newMedications(
  List<PainMoment> existing,
  List<MedicationRecord> all,
) {
  final pool = [
    for (final moment in existing)
      if (moment.kind == PainMomentKind.medication && moment.medication != null)
        moment.medication!,
  ];
  final fresh = <MedicationRecord>[];
  for (final medication in all) {
    final index = pool.indexWhere((item) => _sameMedication(item, medication));
    if (index >= 0) {
      pool.removeAt(index);
    } else {
      fresh.add(medication);
    }
  }
  return fresh;
}

bool _sameMedication(MedicationRecord a, MedicationRecord b) {
  return a.name == b.name &&
      a.doseAmount == b.doseAmount &&
      a.doseUnit == b.doseUnit &&
      sameMinute(a.takenAt, b.takenAt);
}

List<String> _extraNames(List<String> baseline, List<String> next) {
  final counts = <String, int>{};
  for (final name in baseline) {
    counts[name] = (counts[name] ?? 0) + 1;
  }
  final extra = <String>[];
  for (final name in next) {
    final left = counts[name] ?? 0;
    if (left > 0) {
      counts[name] = left - 1;
    } else {
      extra.add(name);
    }
  }
  return extra;
}

String _partSummary(List<PainLocation> locations) {
  if (locations.isEmpty) return '';
  if (locations.length == 1) return locations.first.partName;
  return '${locations.first.partName}等${locations.length}处';
}

String _startedDetail(PainMoment moment) {
  final parts = <String>[];
  if (moment.intensity0to10 != null) parts.add('${moment.intensity0to10} 级');
  final where = _partSummary(moment.locations);
  if (where.isNotEmpty) parts.add(where);
  if (moment.sensations.isNotEmpty) parts.add(moment.sensations.join('、'));
  return parts.join(' · ');
}

String _startedCaption(PainMoment moment) {
  final detail = _startedDetail(moment);
  if (detail.isEmpty) return '开始';
  return '开始 · $detail';
}

class _BodyDiff {
  const _BodyDiff({
    this.intensity,
    this.added = const [],
    this.removed = const [],
    this.geometry = false,
    this.sensation,
  });

  final String? intensity;
  final List<String> added;
  final List<String> removed;
  final bool geometry;
  final String? sensation;

  bool get isEmpty =>
      intensity == null &&
      added.isEmpty &&
      removed.isEmpty &&
      !geometry &&
      sensation == null;
}

_BodyDiff _bodyDiff(PainMoment previous, PainMoment next) {
  final previousIntensity = previous.intensity0to10;
  final nextIntensity = next.intensity0to10;
  final added = _extraNames(
    previous.locations.map((location) => location.partName).toList(),
    next.locations.map((location) => location.partName).toList(),
  );
  final removed = _extraNames(
    next.locations.map((location) => location.partName).toList(),
    previous.locations.map((location) => location.partName).toList(),
  );
  final sensationChanged = !_sameStringSet(
    previous.sensations,
    next.sensations,
  );
  return _BodyDiff(
    intensity: previousIntensity != nextIntensity && nextIntensity != null
        ? '改为 $nextIntensity 级'
        : null,
    added: added,
    removed: removed,
    geometry:
        added.isEmpty &&
        removed.isEmpty &&
        !_sameGeometry(previous.locations, next.locations),
    sensation: sensationChanged
        ? (next.sensations.isEmpty
              ? '感觉记不清了'
              : '感觉改为${next.sensations.join('、')}')
        : null,
  );
}

String _changeCaption(PainMoment previous, PainMoment next) {
  final diff = _bodyDiff(previous, next);
  if (diff.isEmpty) return '记下了变化';
  return [
    if (diff.intensity != null) diff.intensity!,
    if (diff.added.isNotEmpty) '增加${diff.added.join('、')}',
    if (diff.removed.isNotEmpty) '去掉${diff.removed.join('、')}',
    if (diff.geometry) '调整了痛点',
    if (diff.sensation != null) diff.sensation!,
  ].join(' · ');
}

/// Short everyday name for one step on the 1–10 pain slider.
///
/// These describe how the pain gets in the way. They are not diagnoses.
String intensityLabel(int value) {
  return switch (value) {
    <= 0 => '不明显',
    1 => '隐约',
    2 => '有一点疼',
    3 => '一直有感觉',
    4 => '比较明显',
    5 => '需要停一下',
    6 => '比较难受',
    7 => '很难受',
    8 => '非常难受',
    9 => '只能撑着',
    _ => '完全无法忍受',
  };
}

/// A fuller plain-language line for the same step, shown while choosing.
String intensityDetail(int value) {
  return switch (value) {
    <= 0 => '现在几乎不疼。',
    1 => '几乎不影响，不留意就过去了。',
    2 => '能感觉到，该做的事都还能做。',
    3 => '一直在，但还能照常活动。',
    4 => '做事会走神，需要忍一下。',
    5 => '得歇一歇，简单的事还能完成。',
    6 => '很多事做不下去，想先歇着。',
    7 => '只能应付最必要的事。',
    8 => '很难集中精神，几乎待不住。',
    9 => '只能躺着或撑着，别的顾不上。',
    _ => '能想到的最疼，需要马上处理。',
  };
}

String guessPartName({
  required double x,
  required double y,
  required BodyRegion region,
  required String view,
}) {
  // 2D picks are normalized against the FULL 768×1280 image even when a
  // local region is zoomed in. Region must never change their meaning.
  // The shared ortho export covers 1.08 × body height with centred padding.
  final lateral = view == 'left' || view == 'right'
      ? 0.0 // A side silhouette alone cannot identify the left/right arm.
      : (x - 0.5).abs() * 1.08 * 768 / 1280;
  return guessPartNameOnBody(
    heightFromFeet: 1.04 - y * 1.08,
    lateralFromCenter: lateral,
    view: view,
  );
}

/// Major regions shared by quick add and the body model.
///
/// Taps on the model can still resolve a finer spot (肘部、前臂、手腕、手指、
/// 肩胛部、脚踝、脚跟、足趾). Quick add only offers these names.
abstract final class CoarseBodyArea {
  static const head = '头部';
  static const neck = '颈部';
  static const shoulder = '肩部';
  static const chest = '胸部';
  static const upperBack = '上背部';
  static const abdomen = '腹部';
  static const waist = '腰部';
  static const hip = '髋部';
  static const buttock = '臀部';
  static const upperArm = '上臂';
  static const hand = '手部';
  static const thigh = '大腿';
  static const knee = '膝部';
  static const calf = '小腿';
  static const foot = '脚部';
}

/// Converts a named Z-Anatomy / BodyParts3D structure into the deliberately
/// coarse body-area vocabulary shown by the recorder.
///
/// Source meshes remain much more specific (for example "clavicular head of
/// pectoralis major").  The recorder is a localisation tool, not an anatomy
/// diagnosis UI, so it keeps that source ID in [PainLocation.bodyPartId] while
/// presenting a stable, non-diagnostic area name here.
String? partNameFromAnatomicalSource(
  String? sourceName, {
  required String view,
}) {
  if (sourceName == null || sourceName.trim().isEmpty) return null;
  final name = sourceName.toLowerCase();
  bool hasAny(Iterable<String> tokens) => tokens.any(name.contains);

  // Small/distal structures must be checked before broad terms such as bone,
  // anterior or posterior that occur throughout the atlas.
  if (hasAny(const [
    'toe',
    'phalange of foot',
    'digits of foot',
    'metatars',
    'hallucis',
    'hallucial',
  ])) {
    return '足趾';
  }
  if (hasAny(const ['heel', 'calcaneus'])) return '脚跟';
  if (hasAny(const ['ankle', 'talus', 'malleol', 'retromalleolar'])) {
    return '脚踝';
  }
  if (hasAny(const [
    'foot',
    'pedal region',
    'tarsal',
    'sole',
    'plantar',
    'longitudinal arch',
    'transverse arch',
  ])) {
    return CoarseBodyArea.foot;
  }
  if (hasAny(const ['patella', 'knee', 'popliteal']))
    return CoarseBodyArea.knee;
  if (hasAny(const [
    'leg',
    'calf',
    'crural',
    'tibia',
    'fibula',
    'gastrocnemius',
    'soleus',
  ])) {
    return CoarseBodyArea.calf;
  }
  if (hasAny(const ['thigh', 'femur', 'femoral', 'quadriceps'])) {
    return CoarseBodyArea.thigh;
  }
  if (hasAny(const ['finger', 'phalange of hand', 'digits of hand'])) {
    return '手指';
  }
  if (hasAny(const ['wrist', 'carpal', 'radial foveola'])) return '手腕';
  if (hasAny(const ['hand', 'metacarp', 'pollicis', 'palm'])) {
    return CoarseBodyArea.hand;
  }
  if (hasAny(const ['elbow', 'olecranon', 'cubital fossa'])) return '肘部';
  if (hasAny(const ['forearm', 'antebrachial', 'radius', 'ulna'])) return '前臂';
  if (hasAny(const [
    'upper arm',
    'region of arm',
    'brachial',
    'humerus',
    'biceps',
    'triceps',
    'bicipital groove',
  ])) {
    return CoarseBodyArea.upperArm;
  }

  if (hasAny(const ['deltoid', 'acromial', 'shoulder'])) {
    return CoarseBodyArea.shoulder;
  }
  if (hasAny(const ['scapular', 'interscapular', 'infrascapular', 'scapula'])) {
    return '肩胛部';
  }
  if (hasAny(const ['lumbar', 'sacrum', 'sacral', 'sacrospinal'])) {
    return CoarseBodyArea.waist;
  }
  if (hasAny(const ['gluteal', 'buttock', 'coccyx']))
    return CoarseBodyArea.buttock;
  if (hasAny(const ['hip', 'inguinal', 'iliac', 'pelvi', 'pubic'])) {
    return CoarseBodyArea.hip;
  }
  // Check pectoral before abdominal: Z-Anatomy contains an "abdominal part of
  // pectoralis major", which is still a chest structure.
  if (hasAny(const [
    'pectoral',
    'thoracic',
    'thorax',
    'mammary',
    'presternal',
    'infraclavicular',
    'deltopectoral',
    'sternum',
    'rib',
    'intercostal',
    'lung',
  ])) {
    return view == 'back' ? CoarseBodyArea.upperBack : CoarseBodyArea.chest;
  }
  if (hasAny(const [
    'abdomin',
    'epigastric',
    'hypochondriac',
    'hypogastric',
    'umbilical',
    'umbilicus',
    'region of abdomen',
    'stomach',
    'colon',
    'liver',
    'spleen',
    'pancreas',
  ])) {
    return CoarseBodyArea.abdomen;
  }
  if (hasAny(const [
    'trapezius',
    'latissimus',
    'back region',
    'vertebral region',
  ])) {
    return CoarseBodyArea.upperBack;
  }
  if (hasAny(const [
    'neck',
    'cervical',
    'sternocleidomastoid',
    'supraclavicular',
    'carotid triangle',
    'muscular triangle',
  ])) {
    return CoarseBodyArea.neck;
  }
  if (hasAny(const [
    'scalp',
    'head',
    'cranial',
    'skull',
    'frontal',
    'parietal',
    'temporal',
    'occipital',
    'orbital',
    'auricular',
    'auricle',
    'antihelix',
    'antihelic',
    'antitragus',
    'tragus',
    'concha',
    'conchae',
    'helix',
    'scapha',
    'fossa triangularis',
    'triangular fossa',
    'intertragic',
    'incisure',
    'eminentia',
    'mastoid',
    'buccal',
    'zygomatic',
    'parotideomasseteric',
    'nasal',
    'oral region',
    'mouth',
    'labial',
    'philtrum',
    'nasolabial',
    'mental region',
    'mentolabial',
    'submandibular',
    'submental',
  ])) {
    return CoarseBodyArea.head;
  }
  return null;
}

/// Approximate, non-diagnostic name on the neutral body shell. Fractions are
/// measured in body heights, not pixels in the current camera/crop. 3D sends
/// these from its surface entry; 2D derives them from the full-body image.
String guessPartNameOnBody({
  required double heightFromFeet,
  required double lateralFromCenter,
  required String view,
  String? anatomicalSourceName,
}) {
  final lateral = lateralFromCenter.abs();
  late final String geometric;
  if (heightFromFeet >= 0.85) {
    geometric = CoarseBodyArea.head;
  } else if (heightFromFeet >= 0.785) {
    geometric = lateral > 0.105 ? CoarseBodyArea.shoulder : CoarseBodyArea.neck;
    // The pectoral surface reaches much farther from the centre line than the
    // previous 0.085 threshold. That threshold labelled most upper-chest picks
    // as shoulder, especially after orbiting the 3D camera.
  } else if (heightFromFeet >= 0.715 && lateral >= 0.125) {
    geometric = CoarseBodyArea.shoulder;
  } else if (lateral >= 0.125 && heightFromFeet > 0.375) {
    if (heightFromFeet >= 0.615) {
      geometric = CoarseBodyArea.upperArm;
    } else if (heightFromFeet >= 0.58) {
      geometric = '肘部';
    } else if (heightFromFeet >= 0.485) {
      geometric = '前臂';
    } else if (heightFromFeet >= 0.445) {
      geometric = '手腕';
    } else {
      geometric = CoarseBodyArea.hand;
    }
  } else if (heightFromFeet >= 0.64) {
    geometric = view == 'back'
        ? CoarseBodyArea.upperBack
        : CoarseBodyArea.chest;
  } else if (heightFromFeet >= 0.53) {
    geometric = view == 'back' ? CoarseBodyArea.waist : CoarseBodyArea.abdomen;
  } else if (heightFromFeet >= 0.435) {
    geometric = view == 'back' ? CoarseBodyArea.buttock : CoarseBodyArea.hip;
  } else if (heightFromFeet >= 0.285) {
    geometric = CoarseBodyArea.thigh;
  } else if (heightFromFeet >= 0.245) {
    geometric = CoarseBodyArea.knee;
  } else if (heightFromFeet >= 0.08) {
    geometric = CoarseBodyArea.calf;
  } else {
    geometric = CoarseBodyArea.foot;
  }

  final fromModel = partNameFromAnatomicalSource(
    anatomicalSourceName,
    view: view,
  );
  if (fromModel == null || fromModel == geometric) return geometric;

  // Thin structures can cross a coarse body-area boundary (abdominal fascia
  // reaches the lower chest, for example). Only let model metadata refine to
  // an immediately adjacent product area; otherwise the spatial surface area
  // remains the safer description of where the user actually touched.
  const compatibleRefinements = <String, Set<String>>{
    CoarseBodyArea.shoulder: {CoarseBodyArea.upperArm, '肩胛部'},
    CoarseBodyArea.upperArm: {CoarseBodyArea.shoulder, '肘部'},
    '肘部': {CoarseBodyArea.upperArm, '前臂'},
    '前臂': {'肘部', '手腕'},
    '手腕': {'前臂', CoarseBodyArea.hand},
    CoarseBodyArea.hand: {'手腕', '手指'},
    CoarseBodyArea.upperBack: {'肩胛部'},
    CoarseBodyArea.hip: {CoarseBodyArea.buttock, CoarseBodyArea.thigh},
    CoarseBodyArea.buttock: {CoarseBodyArea.hip, CoarseBodyArea.thigh},
    CoarseBodyArea.thigh: {
      CoarseBodyArea.hip,
      CoarseBodyArea.buttock,
      CoarseBodyArea.knee,
    },
    CoarseBodyArea.knee: {CoarseBodyArea.thigh, CoarseBodyArea.calf},
    CoarseBodyArea.calf: {CoarseBodyArea.knee, '脚踝'},
    CoarseBodyArea.foot: {'脚踝', '脚跟', '足趾'},
  };
  return compatibleRefinements[geometric]?.contains(fromModel) ?? false
      ? fromModel
      : geometric;
}
