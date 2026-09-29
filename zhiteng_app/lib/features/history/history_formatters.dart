import '../../core/models/pain_models.dart';

String painPointNames(PainEntry entry) {
  final names = <String>[];
  for (final location in entry.locations) {
    if (!names.contains(location.partName)) names.add(location.partName);
  }
  return names.isEmpty ? '未标记痛点' : names.join('、');
}

String painDurationLabel(PainEntry entry) {
  final end = entry.endedAt ?? DateTime.now();
  final duration = end.difference(entry.startedAt);
  if (duration.inMinutes <= 0) return '持续不到 1 分钟';
  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  final parts = <String>[
    if (days > 0) '$days 天',
    if (hours > 0) '$hours 小时',
    if (minutes > 0 && days == 0) '$minutes 分',
  ];
  return '持续 ${parts.join(' ')}';
}
