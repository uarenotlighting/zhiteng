import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/haptics.dart';
import '../../core/models/pain_models.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/zt_controls.dart';
import 'pain_spot_draft.dart';

/// A body area that quick add can place without opening the workbench.
class QuickBodyPart {
  const QuickBodyPart({
    required this.id,
    required this.name,
    required this.y,
    required this.region,
    this.view = 'front',
    this.lateral = 0,
    this.allowCenter = false,
  });

  final String id;
  final String name;
  final double y;
  final BodyRegion region;
  final String view;

  /// Distance from the midline in the same units as [guessPartName].
  final double lateral;
  final bool allowCenter;
}

const quickBodyParts = <QuickBodyPart>[
  QuickBodyPart(
    id: 'head',
    name: CoarseBodyArea.head,
    y: 0.13,
    region: BodyRegion.head,
    allowCenter: true,
  ),
  QuickBodyPart(
    id: 'neck',
    name: CoarseBodyArea.neck,
    y: 0.20,
    region: BodyRegion.head,
    allowCenter: true,
  ),
  QuickBodyPart(
    id: 'shoulder',
    name: CoarseBodyArea.shoulder,
    y: 0.27,
    region: BodyRegion.upper,
    lateral: 0.16,
  ),
  QuickBodyPart(
    id: 'chest',
    name: CoarseBodyArea.chest,
    y: 0.31,
    region: BodyRegion.upper,
    allowCenter: true,
  ),
  QuickBodyPart(
    id: 'upper_back',
    name: CoarseBodyArea.upperBack,
    y: 0.31,
    region: BodyRegion.upper,
    view: 'back',
    allowCenter: true,
  ),
  QuickBodyPart(
    id: 'abdomen',
    name: CoarseBodyArea.abdomen,
    y: 0.43,
    region: BodyRegion.upper,
    allowCenter: true,
  ),
  QuickBodyPart(
    id: 'waist',
    name: CoarseBodyArea.waist,
    y: 0.43,
    region: BodyRegion.upper,
    view: 'back',
    allowCenter: true,
  ),
  QuickBodyPart(
    id: 'hip',
    name: CoarseBodyArea.hip,
    y: 0.52,
    region: BodyRegion.lower,
  ),
  QuickBodyPart(
    id: 'buttock',
    name: CoarseBodyArea.buttock,
    y: 0.52,
    region: BodyRegion.lower,
    view: 'back',
  ),
  QuickBodyPart(
    id: 'upper_arm',
    name: CoarseBodyArea.upperArm,
    y: 0.35,
    region: BodyRegion.upper,
    lateral: 0.18,
  ),
  QuickBodyPart(
    id: 'hand',
    name: CoarseBodyArea.hand,
    y: 0.58,
    region: BodyRegion.upper,
    lateral: 0.16,
  ),
  QuickBodyPart(
    id: 'thigh',
    name: CoarseBodyArea.thigh,
    y: 0.63,
    region: BodyRegion.lower,
    lateral: 0.08,
  ),
  QuickBodyPart(
    id: 'knee',
    name: CoarseBodyArea.knee,
    y: 0.72,
    region: BodyRegion.lower,
    lateral: 0.08,
  ),
  QuickBodyPart(
    id: 'calf',
    name: CoarseBodyArea.calf,
    y: 0.81,
    region: BodyRegion.lower,
    lateral: 0.06,
  ),
  QuickBodyPart(
    id: 'foot',
    name: CoarseBodyArea.foot,
    y: 0.94,
    region: BodyRegion.lower,
    lateral: 0.06,
  ),
];

String sidedPartName(String name, String side) {
  return switch (side) {
    'left' => '左侧$name',
    'right' => '右侧$name',
    _ => name,
  };
}

/// Screen x for a body side. Front view labels the image's right edge as 左.
double quickNormalizedX(QuickBodyPart part, String side) {
  if (side == 'center' || part.lateral == 0 && side == 'center') return 0.5;
  const imageScale = 1.08 * 768 / 1280;
  final offset = part.lateral <= 0 ? 0.12 : part.lateral / imageScale;
  final bodyLeftOnImageRight = side == 'left';
  if (part.view == 'back') {
    return bodyLeftOnImageRight ? 0.5 - offset : 0.5 + offset;
  }
  return bodyLeftOnImageRight ? 0.5 + offset : 0.5 - offset;
}

PainSpotDraft quickPainSpot({
  required QuickBodyPart part,
  required String side,
  required bool deep,
  String? id,
}) {
  final resolvedSide = part.allowCenter || part.lateral == 0
      ? side
      : (side == 'center' ? 'left' : side);
  return PainSpotDraft(
    id: id ?? const Uuid().v4(),
    x: quickNormalizedX(part, resolvedSide),
    y: part.y,
    view: part.view,
    layer: deep ? BodyLayer.muscle : BodyLayer.skin,
    shape: PainShape.point,
    region: part.region,
    partName: sidedPartName(part.name, resolvedSide),
    bodyPartId: 'quick_${part.id}_$resolvedSide',
    markerScale: painMarkerMinScale,
    lineLength: 1,
    lineAngle: 0,
    depthState: deep ? 'internal_unknown' : 'surface',
    use3d: false,
    side: resolvedSide,
    quick: true,
  );
}

/// A body spot from a saved record, shown under “最近使用”.
class QuickRecentShortcut {
  const QuickRecentShortcut({required this.label, required this.spot});

  final String label;
  final PainSpotDraft spot;
}

/// The first three pain spots from saved records, newest record first.
///
/// Matching labels are kept once. An empty list means the sheet hides
/// “最近使用”.
List<QuickRecentShortcut> recentQuickShortcuts(
  List<PainEntry> entries, {
  int limit = 3,
}) {
  final ordered = [...entries]
    ..sort((a, b) {
      final byStart = b.startedAt.compareTo(a.startedAt);
      if (byStart != 0) return byStart;
      return b.createdAt.compareTo(a.createdAt);
    });
  final seen = <String>{};
  final result = <QuickRecentShortcut>[];
  for (final entry in ordered) {
    for (final location in entry.locations) {
      final spot = PainSpotDraft.fromLocation(location);
      final label = _recentUseLabel(spot);
      if (label.isEmpty || !seen.add(label)) continue;
      result.add(QuickRecentShortcut(label: label, spot: spot));
      if (result.length >= limit) return result;
    }
  }
  return result;
}

String _recentUseLabel(PainSpotDraft spot) {
  final name = spot.partName.trim();
  if (name.isEmpty) return '';
  if (name.startsWith('左') || name.startsWith('右')) return name;
  return switch (spot.side) {
    'left' => '左侧$name',
    'right' => '右侧$name',
    _ => name,
  };
}

Future<PainSpotDraft?> showQuickAddSheet(
  BuildContext context, {
  List<QuickRecentShortcut> recent = const [],
  PainSpotDraft? initial,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return showModalBottomSheet<PainSpotDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: dark ? AppColors.darkPage : AppColors.lightPage,
    constraints: const BoxConstraints(maxWidth: double.infinity),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => _QuickAddSheet(recent: recent, initial: initial),
  );
}

/// Part and side previously chosen in quick add, if this draft came from it.
(QuickBodyPart, String)? quickDraftSelection(PainSpotDraft spot) {
  const prefix = 'quick_';
  if (spot.bodyPartId.startsWith(prefix)) {
    final rest = spot.bodyPartId.substring(prefix.length);
    for (final part in quickBodyParts) {
      final head = '${part.id}_';
      if (!rest.startsWith(head)) continue;
      final side = rest.substring(head.length);
      if (side == 'left' || side == 'right' || side == 'center') {
        return (part, side);
      }
    }
  }
  var name = spot.partName;
  var side = spot.side;
  if (name.startsWith('左侧')) {
    name = name.substring(2);
    side = 'left';
  } else if (name.startsWith('右侧')) {
    name = name.substring(2);
    side = 'right';
  }
  for (final part in quickBodyParts) {
    if (part.name != name) continue;
    if (side != 'left' && side != 'right' && side != 'center') side = 'left';
    return (part, side);
  }
  return null;
}

class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet({required this.recent, this.initial});

  final List<QuickRecentShortcut> recent;
  final PainSpotDraft? initial;

  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  QuickBodyPart? _part;
  String _side = 'left';
  bool _deep = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    final selection = quickDraftSelection(initial);
    if (selection != null) {
      _part = selection.$1;
      _side = selection.$2;
    }
    _deep =
        initial.depthState == 'internal_unknown' ||
        initial.layer == BodyLayer.muscle;
  }

  void _finish(QuickBodyPart part, String side, {bool? deep}) {
    Navigator.of(context).pop(
      quickPainSpot(
        part: part,
        side: side,
        deep: deep ?? _deep,
        id: widget.initial?.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final part = _part;
    final recent = widget.recent;

    return SizedBox(
      width: double.infinity,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initial == null ? '快速添加痛点' : '修改痛点',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '选一个大概位置就行，不必打开人体模型。',
                style: TextStyle(color: muted, fontSize: 13),
              ),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '最近使用',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in recent)
                      ZtChip(
                        label: item.label,
                        selected: false,
                        haptic: ZtHaptic.medium,
                        onTap: () => Navigator.of(context).pop(
                          item.spot.duplicate(
                            id: widget.initial?.id,
                            partName: item.label,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text(
                '部位',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in quickBodyParts)
                    ZtChip(
                      label: option.name,
                      selected: part?.id == option.id,
                      onTap: () => setState(() {
                        _part = option;
                        if (!option.allowCenter && _side == 'center') {
                          _side = 'left';
                        }
                      }),
                    ),
                ],
              ),
              if (part != null) ...[
                const SizedBox(height: 14),
                Text(
                  '左右侧',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in [
                      ('left', '左侧'),
                      ('right', '右侧'),
                      if (part.allowCenter) ('center', '中间'),
                    ])
                      ZtChip(
                        label: option.$2,
                        selected: _side == option.$1,
                        onTap: () => setState(() => _side = option.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  '表面或深处',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ZtChip(
                      label: '表面',
                      selected: !_deep,
                      onTap: () => setState(() => _deep = false),
                    ),
                    ZtChip(
                      label: '深处',
                      selected: _deep,
                      onTap: () => setState(() => _deep = true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ZtButton(
                  label: widget.initial == null ? '添加这个痛点' : '保存修改',
                  onPressed: () => _finish(part, _side),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
