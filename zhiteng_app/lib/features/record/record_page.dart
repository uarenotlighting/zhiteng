import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../core/haptics.dart';
import '../../core/models/pain_models.dart';
import '../../core/theme/app_colors.dart';
import '../../data/custom_pain_sensations.dart';
import '../../state/controllers.dart';
import '../../widgets/pain_timeline_view.dart';
import '../../widgets/zt_controls.dart';
import '../../widgets/zt_motion.dart';
import '../../widgets/zt_toast.dart';
import 'body_annotate_page.dart';
import 'pain_spot_draft.dart';
import 'quick_add_sheet.dart';
import 'widgets/medication_fields.dart';

export 'record_selection.dart';

enum _PainTiming { justStarted, ongoingForAWhile, ended }

extension on _PainTiming {
  String get label => switch (this) {
    _PainTiming.justStarted => '刚开始',
    _PainTiming.ongoingForAWhile => '已经一会儿',
    _PainTiming.ended => '已结束',
  };
}

/// Organizes one pain record. Body placement happens on [BodyAnnotatePage];
/// this page only keeps the spots and the shared feeling, intensity, time,
/// medicine, and note.
///
/// Opening an ongoing pain keeps the episode open. Saving appends a moment
/// for whatever changed. Ending is a separate action on the same page.
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, this.ending});

  /// An ongoing pain opened so the user can record what changed, or when it
  /// stopped. Saved spots, feeling, and intensity are shown again.
  final PainEntry? ending;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  final _noteController = TextEditingController();
  final _customSensationController = TextEditingController();
  final _customSensations = CustomPainSensationStore();
  final List<PainSpotDraft> _spots = [];

  int _intensity = 1;
  Set<String> _sensations = {};
  List<String> _savedSensations = const [];
  DateTime _startedAt = DateTime.now();
  DateTime _endedAt = DateTime.now();
  DateTime _changeAt = DateTime.now();
  bool _changeAtTouched = false;
  bool _finishing = false;
  _PainTiming _timing = _PainTiming.justStarted;
  bool? _endJustNow;
  final List<_MedicationDraft> _medications = [];
  bool _presetsExpanded = false;
  bool _savedExpanded = false;
  String? _sensationError;
  String? _validation;

  bool get _continuing => widget.ending != null;

  @override
  void initState() {
    super.initState();
    final ending = widget.ending;
    if (ending != null) {
      _spots.addAll(ending.locations.map(PainSpotDraft.fromLocation));
      _intensity = ending.intensity0to10.clamp(1, 10);
      _sensations = {
        for (final location in ending.locations) ...location.sensations,
      };
      _startedAt = ending.startedAt;
      _changeAt = DateTime.now();
      _endedAt = DateTime.now();
      _presetsExpanded = _sensations.any(painSensationOptions.contains);
    }
    if (_medications.isEmpty) _medications.add(_MedicationDraft());
    _loadSavedSensations();
  }

  Future<void> _loadSavedSensations() async {
    final saved = await _customSensations.load();
    if (!mounted) return;
    setState(() {
      _savedSensations = saved;
      if (_continuing && _sensations.any(saved.contains)) {
        _savedExpanded = true;
      }
    });
  }

  Future<void> _rememberSensation() async {
    final word = normalizeCustomPainSensation(_customSensationController.text);
    if (word == null) {
      setState(() => _sensationError = null);
      return;
    }
    if (hasThreeIdenticalCharactersInARow(word)) {
      setState(() => _sensationError = '不要连续输入 3 个相同的字符');
      return;
    }
    if (painSensationOptions.contains(word)) {
      setState(() {
        _sensationError = null;
        _presetsExpanded = true;
        if (!_sensations.contains(word)) {
          _sensations = togglePainSensation(_sensations, word);
        }
        _customSensationController.clear();
      });
      ZtToast.text(context, '「$word」是常见感觉，已经帮你选上了。');
      return;
    }
    final saved = await _customSensations.remember(word);
    if (!mounted) return;
    setState(() {
      _savedSensations = saved;
      _sensations = togglePainSensation(_sensations, word);
      _customSensationController.clear();
      _sensationError = null;
    });
  }

  Future<void> _confirmForgetSensation(String word) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「$word」？'),
        content: const Text('会从我记录过的里去掉。这次如果已经选上，也会取消。'),
        actions: [
          ZtPressableScale(
            pressEnabled: true,
            tapScale: 0.94,
            child: TextButton(
              onPressed: () {
                ztHaptic(context, ZtHaptic.light);
                Navigator.pop(context, false);
              },
              child: const Text('取消'),
            ),
          ),
          ZtPressableScale(
            pressEnabled: true,
            tapScale: 0.94,
            child: TextButton(
              onPressed: () {
                ztHaptic(context, ZtHaptic.heavy);
                Navigator.pop(context, true);
              },
              child: const Text('删除'),
            ),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    final saved = await _customSensations.forget(word);
    if (!mounted) return;
    setState(() {
      _savedSensations = saved;
      _sensations = {..._sensations}..remove(word);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    _customSensationController.dispose();
    for (final medication in _medications) {
      medication.dispose();
    }
    super.dispose();
  }

  void _acceptWorkbenchResult(PainSpotDraft? result, {int? index}) {
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _spots.add(result);
      } else {
        _spots[index] = result;
      }
      _validation = null;
    });
  }

  Widget _bodyOpenContainer({
    int? index,
    required Widget Function(VoidCallback open) closedBuilder,
    BorderRadius closedBorderRadius = const BorderRadius.all(
      Radius.circular(16),
    ),
  }) {
    final initial = index == null ? null : _spots[index];
    return ZtOpenContainer<PainSpotDraft>(
      closedBorderRadius: closedBorderRadius,
      openBuilder: (_) => BodyAnnotatePage(initial: initial),
      onClosed: (result) => _acceptWorkbenchResult(result, index: index),
      closedBuilder: (_, open) => closedBuilder(open),
    );
  }

  Future<void> _quickAdd({int? index}) async {
    final result = await showQuickAddSheet(
      context,
      recent: recentQuickShortcuts(
        context.read<PainRecordsController>().entries,
      ),
      initial: index == null ? null : _spots[index],
    );
    if (!mounted || result == null) return;
    setState(() {
      if (index == null) {
        _spots.add(result);
      } else {
        _spots[index] = result;
      }
      _validation = null;
    });
  }

  Future<DateTime?> _pickDateTime(
    DateTime initial, {
    required String futureMessage,
    DateTime? minimumDate,
    DateTime? maximumDate,
  }) async {
    final now = _minute(DateTime.now());
    var latest = maximumDate ?? now;
    if (latest.isAfter(now)) latest = now;
    var earliest = minimumDate ?? DateTime(1900);
    if (earliest.isAfter(latest)) earliest = latest;
    var start = _minute(initial);
    if (start.isBefore(earliest)) start = earliest;
    if (start.isAfter(latest)) start = latest;
    FocusManager.instance.primaryFocus?.unfocus();
    // Opening during this tap puts the barrier under the finger, so the same
    // pointer-up dismisses the sheet before it can be seen.
    await _afterPointerUp();
    if (!mounted) return null;
    final selected = await showIosDateTimePicker(
      context: context,
      initialDateTime: start,
      minimumDate: earliest,
      maximumDate: latest,
    );
    if (!mounted || selected == null) return null;
    if (selected.isAfter(DateTime.now())) {
      setState(() => _validation = futureMessage);
      return null;
    }
    return selected;
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final earliestEnd = _minute(_startedAt).add(const Duration(minutes: 1));
    if (isEnd && earliestEnd.isAfter(_minute(DateTime.now()))) {
      setState(() => _validation = '结束时间要晚于开始时间');
      return;
    }
    final selected = await _pickDateTime(
      isEnd ? _endedAt : _startedAt,
      futureMessage: '时间不能晚于现在',
      minimumDate: isEnd ? earliestEnd : null,
    );
    if (!mounted || selected == null) return;
    if (isEnd && !selected.isAfter(_minute(_startedAt))) {
      setState(() => _validation = '结束时间要晚于开始时间');
      return;
    }
    setState(() {
      if (isEnd) {
        _endedAt = selected;
      } else {
        _startedAt = selected;
      }
      _validation = null;
    });
  }

  Future<void> _pickChangeTime() async {
    final selected = await _pickDateTime(
      _changeAtTouched ? _changeAt : DateTime.now(),
      futureMessage: '时间不能晚于现在',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _changeAt = selected;
      _changeAtTouched = true;
      _validation = null;
    });
  }

  void _showCourse() {
    final entry = widget.ending;
    if (entry == null) return;
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: dark ? AppColors.darkSurface : AppColors.lightSurface,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.7,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  '这次经过',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: dark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                PainTimelineView(
                  startedAt: entry.startedAt,
                  moments: entry.timeline,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDoseUnit(int index) async {
    final draft = _medications[index];
    final units = [
      ...medicationDoseUnits,
      if (!medicationDoseUnits.contains(draft.unit)) draft.unit,
    ];
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showIosOptionMenu(
      context: context,
      anchorKey: draft.unitButtonKey,
      options: units,
      selected: draft.unit,
    );
    if (!mounted || selected == null || selected == draft.unit) return;
    setState(() {
      draft.unit = selected;
      _validation = null;
    });
  }

  Future<void> _afterPointerUp() {
    final done = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  DateTime _minute(DateTime value) {
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    );
  }

  /// Start used for this save. 「刚开始」is recorded as the current minute.
  DateTime _episodeStart() {
    if (_continuing || _timing != _PainTiming.justStarted) {
      return _minute(_startedAt);
    }
    return _minute(DateTime.now());
  }

  /// Null while the pain is still going.
  DateTime? _episodeEnd() {
    if (_continuing) {
      if (!_finishing) return null;
      if (_endJustNow == false) return _minute(_endedAt);
      return _minute(DateTime.now());
    }
    if (_timing == _PainTiming.ended) return _minute(_endedAt);
    return null;
  }

  DateTime _medicationLatest() {
    final now = _minute(DateTime.now());
    final end = _episodeEnd();
    if (end != null && end.isBefore(now)) return end;
    return now;
  }

  String? _medicationTimeError(DateTime takenAt) {
    if (isBeforeMinute(takenAt, _episodeStart())) {
      return '用药时间不能早于开始时间';
    }
    final end = _episodeEnd();
    if (end != null && isAfterMinute(takenAt, end)) {
      return '用药时间不能晚于结束时间';
    }
    if (isAfterMinute(takenAt, DateTime.now())) return '用药时间不能晚于现在';
    return null;
  }

  Future<void> _pickMedicationTime(int index) async {
    final earliest = _episodeStart();
    final latest = _medicationLatest();
    if (earliest.isAfter(latest)) {
      setState(() => _validation = '用药时间要在开始时间和结束时间之间');
      return;
    }
    final selected = await _pickDateTime(
      _medications[index].takenAt,
      futureMessage: '用药时间不能晚于现在',
      minimumDate: earliest,
      maximumDate: latest,
    );
    if (!mounted || selected == null) return;
    final error = _medicationTimeError(selected);
    if (error != null) {
      setState(() => _validation = error);
      return;
    }
    setState(() {
      _medications[index].takenAt = selected;
      _validation = null;
    });
  }

  List<MedicationRecord>? _readMedications() {
    final records = <MedicationRecord>[];
    for (final draft in _medications) {
      final name = draft.nameController.text.trim();
      final doseText = draft.doseController.text.trim();
      if (name.isEmpty && doseText.isEmpty) continue;
      if (name.isEmpty) {
        _rejectSave('请填写药品名称');
        return null;
      }
      final dose = double.tryParse(doseText);
      if (dose == null || dose <= 0) {
        _rejectSave('剂量请填一个大于 0 的数字');
        return null;
      }
      final timeError = _medicationTimeError(draft.takenAt);
      if (timeError != null) {
        _rejectSave(timeError);
        return null;
      }
      records.add(
        MedicationRecord(
          name: name,
          doseAmount: dose,
          doseUnit: draft.unit,
          takenAt: draft.takenAt,
        ),
      );
    }
    return records;
  }

  Widget _medicationCard(
    int index, {
    required bool dark,
    required Color muted,
    required double keyboard,
  }) {
    final draft = _medications[index];
    final takenText = DateFormat('yyyy年MM月dd日 HH:mm').format(draft.takenAt);
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_medications.length > 1)
            Row(
              children: [
                Text(
                  '第 ${index + 1} 种',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const Spacer(),
                ZtPressableScale(
                  pressEnabled: true,
                  tapScale: 0.94,
                  child: TextButton(
                    onPressed: () {
                      ztHaptic(context, ZtHaptic.heavy);
                      setState(() {
                        _medications.removeAt(index).dispose();
                        if (_medications.isEmpty) {
                          _medications.add(_MedicationDraft());
                        }
                        _validation = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('删除'),
                  ),
                ),
              ],
            ),
          if (_medications.length > 1) const SizedBox(height: 4),
          Text(
            '药品名称',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: draft.nameController,
            textInputAction: TextInputAction.next,
            maxLength: 40,
            scrollPadding: EdgeInsets.only(bottom: keyboard + 24),
            decoration: InputDecoration(
              hintText: '例如：布洛芬',
              counterText: '',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: _roundedInputBorder(dark),
              enabledBorder: _roundedInputBorder(dark),
              focusedBorder: _roundedInputBorder(dark, focused: true),
            ),
            onChanged: (_) {
              if (_validation != null) setState(() => _validation = null);
            },
          ),
          const SizedBox(height: 14),
          Text(
            '服药剂量',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DoseQuantityField(
                  controller: draft.doseController,
                  scrollPadding: EdgeInsets.only(bottom: keyboard + 24),
                  onChanged: (_) {
                    if (_validation != null) setState(() => _validation = null);
                  },
                ),
              ),
              const SizedBox(width: 8),
              DoseUnitButton(
                key: draft.unitButtonKey,
                unit: draft.unit,
                onTap: () => _pickDoseUnit(index),
              ),
            ],
          ),
          Divider(
            height: 22,
            color: dark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
          _FieldRow(
            label: '用药时间',
            value: takenText,
            onTap: () => _pickMedicationTime(index),
          ),
        ],
      ),
    );
  }

  void _selectEndChoice({required bool justNow}) {
    setState(() {
      _endJustNow = justNow;
      _validation = null;
      if (!justNow) _endedAt = DateTime.now();
    });
  }

  void _selectTiming(_PainTiming value) {
    final now = DateTime.now();
    setState(() {
      _timing = value;
      _validation = null;
      if (value == _PainTiming.justStarted) {
        _startedAt = now;
      } else if (value == _PainTiming.ongoingForAWhile &&
          !_startedAt.isBefore(now)) {
        _startedAt = now.subtract(const Duration(minutes: 30));
      } else if (value == _PainTiming.ended) {
        _endedAt = now;
        if (!_startedAt.isBefore(_endedAt)) {
          _startedAt = now.subtract(const Duration(minutes: 30));
        }
      }
    });
  }

  /// Save rules share the singleton toast, so a rejected save replaces the
  /// loading toast instead of leaving it on screen.
  ///
  /// [inline] keeps the red line above the save button. "没有新的变化" is only a
  /// toast, because nothing on the form is wrong.
  void _rejectSave(String message, {bool inline = true}) {
    if (!mounted) {
      ZtToast.dismiss();
      return;
    }
    if (inline) {
      setState(() => _validation = message);
    } else if (_validation != null) {
      setState(() => _validation = null);
    }
    ZtToast.failure(context, message);
  }

  Future<void> _save() async {
    if (_spots.isEmpty) {
      _rejectSave('请先添加一个痛点');
      return;
    }
    final medications = _readMedications();
    if (medications == null) return;
    if (_continuing) {
      await _saveContinuation(medications);
      return;
    }
    final now = DateTime.now();
    final startedAt = _timing == _PainTiming.justStarted ? now : _startedAt;
    final endedAt = _timing == _PainTiming.ended ? _endedAt : null;
    if (startedAt.isAfter(now)) {
      _rejectSave('开始时间不能晚于现在');
      return;
    }
    if (endedAt != null && !isAfterMinute(endedAt, startedAt)) {
      _rejectSave('结束时间要晚于开始时间');
      return;
    }
    final sensations = _sensations.toList(growable: false);
    final locations = [
      for (final spot in _spots)
        spot.toLocation(intensity0to10: _intensity, sensations: sensations),
    ];
    ZtToast.loading(context, '正在保存…');
    try {
      await context.read<PainRecordsController>().save(
        startedAt: startedAt,
        endedAt: endedAt,
        locations: locations,
        intensity0to10: _intensity,
        notes: _noteController.text,
        medications: medications,
      );
    } on PainRecordRejected catch (error) {
      _rejectSave(error.message);
      return;
    } catch (error, stackTrace) {
      debugPrint('保存疼痛记录失败: $error\n$stackTrace');
      if (!mounted) {
        ZtToast.dismiss();
        return;
      }
      ZtToast.failure(context, '暂时没有保存成功，请稍后再试');
      return;
    }
    if (!mounted) {
      ZtToast.dismiss();
      return;
    }
    ZtToast.success(context, '已经帮你记下来了。');
    Navigator.of(context).pop();
  }

  Future<void> _saveContinuation(List<MedicationRecord> added) async {
    final previous = widget.ending;
    if (previous == null) return;
    final now = DateTime.now();
    if (_finishing && _endJustNow == null) {
      _rejectSave('请先记下结束时间');
      return;
    }
    final sensations = _sensations.toList(growable: false);
    final locations = [
      for (final spot in _spots)
        spot.toLocation(intensity0to10: _intensity, sensations: sensations),
    ];
    final draft = PainMomentDraft(
      startedAt: _startedAt,
      changeAt: _changeAtTouched ? _changeAt : now,
      endedAt: _finishing ? (_endJustNow! ? now : _endedAt) : null,
      locations: locations,
      intensity0to10: _intensity,
      medications: [...previous.medications, ...added],
      supplement: _noteController.text,
    );
    final preview = applyPainUpdate(
      previous: previous,
      draft: draft,
      newId: () => 'preview',
    );
    if (!preview.saved) {
      _rejectSave(
        preview.message ?? '没有新的变化',
        inline: preview.message != null,
      );
      return;
    }
    ZtToast.loading(context, '正在保存…');
    late final PainUpdateOutcome outcome;
    try {
      outcome = await context.read<PainRecordsController>().revise(
        previous: previous,
        draft: draft,
      );
    } catch (error, stackTrace) {
      debugPrint('更新疼痛记录失败: $error\n$stackTrace');
      if (!mounted) {
        ZtToast.dismiss();
        return;
      }
      ZtToast.failure(context, '暂时没有保存成功，请稍后再试');
      return;
    }
    if (!mounted) {
      ZtToast.dismiss();
      return;
    }
    if (!outcome.saved) {
      _rejectSave(
        outcome.message ?? '没有新的变化',
        inline: outcome.message != null,
      );
      return;
    }
    ZtToast.success(context, _finishing ? '已经记下结束时间。' : '已经帮你记下来了。');
    Navigator.of(context).pop();
  }

  Widget _courseHeader(Color muted) {
    final entry = widget.ending;
    if (entry == null) return const SizedBox.shrink();
    final latest = entry.latestCourseMoment;
    final start = DateFormat('MM/dd HH:mm').format(_startedAt);
    final duration = ongoingDurationLabel(_startedAt, DateTime.now());
    final latestClock = latest == null
        ? ''
        : formatPainMomentClock(latest.moment.at, entry.startedAt);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '从 $start 开始 · $duration · 现在 ${entry.intensity0to10} 级',
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4),
            ),
            if (latest != null) ...[
              const SizedBox(height: 6),
              Text(
                '最近 $latestClock ${latest.caption}',
                style: TextStyle(color: muted, fontSize: 13, height: 1.4),
              ),
            ],
            _FieldRow(
              label: '开始时间',
              value: DateFormat('yyyy年MM月dd日 HH:mm').format(_startedAt),
              onTap: () => _pickTime(isEnd: false),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ZtPressableScale(
                pressEnabled: true,
                tapScale: 0.94,
                child: TextButton(
                  onPressed: () {
                    ztHaptic(context, ZtHaptic.light);
                    _showCourse();
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('查看经过'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final startText = DateFormat('yyyy年MM月dd日 HH:mm').format(_startedAt);
    final changeText = DateFormat('yyyy年MM月dd日 HH:mm').format(_changeAt);
    final endText = DateFormat('yyyy年MM月dd日 HH:mm').format(_endedAt);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return ZtSwipeBackPage(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: _unfocusInputs,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          appBar: AppBar(
            leading: (ModalRoute.of(context)?.canPop ?? false)
                ? const ZtBackButton()
                : null,
            title: Text(_continuing ? '这次疼痛' : '记一次疼痛'),
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 20 + keyboard),
            children: [
              Text(
                _continuing
                    ? '改现在的情况再保存，这次还会留在首页。不疼了再记结束。'
                    : '先记下哪里疼。感觉、程度和时间可以一起填，也可以之后再补。',
                style: TextStyle(color: muted, height: 1.45),
              ),
              const SizedBox(height: 18),
              if (_continuing) _courseHeader(muted),
              const _SectionTitle(index: '1', title: '疼在哪里？'),
              const SizedBox(height: 12),
              _AddActions(
                hasSpots: _spots.isNotEmpty,
                onQuick: _quickAdd,
                bodyAction: _bodyOpenContainer(
                  closedBuilder: (open) => _ActionTile(
                    icon: Icons.accessibility_new,
                    label: '人体模型标注',
                    onTap: open,
                  ),
                ),
              ),
              if (_spots.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '已添加的痛点',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _spots.length; i++) ...[
                  _SpotCard(
                    index: i + 1,
                    summary: _spots[i].summary,
                    editAction: _spots[i].quick
                        ? _SpotAction(
                            label: '编辑',
                            color: muted,
                            onTap: () => _quickAdd(index: i),
                          )
                        : _bodyOpenContainer(
                            index: i,
                            closedBorderRadius: BorderRadius.circular(10),
                            closedBuilder: (open) => _SpotAction(
                              label: '编辑',
                              color: muted,
                              onTap: open,
                            ),
                          ),
                    onDelete: () => setState(() => _spots.removeAt(i)),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 22),
              const _SectionTitle(index: '2', title: '疼起来是什么感觉？'),
              const SizedBox(height: 6),
              Text(
                _continuing
                    ? '改了会记成新的一条。暂时不确定也可以不改。'
                    : '整次记录共用。只选最接近的就可以，暂时不确定也可以跳过。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _chipWrap(
                title: '常见感觉',
                muted: muted,
                labels: painSensationOptions,
                expanded: _presetsExpanded,
                onToggle: () =>
                    setState(() => _presetsExpanded = !_presetsExpanded),
              ),
              if (_savedSensations.isNotEmpty) ...[
                const SizedBox(height: 14),
                _chipWrap(
                  title: '我记录过的',
                  muted: muted,
                  labels: _savedSensations,
                  expanded: _savedExpanded,
                  onToggle: () =>
                      setState(() => _savedExpanded = !_savedExpanded),
                  onDelete: _confirmForgetSensation,
                ),
              ],
              const SizedBox(height: 14),
              Text(
                '上面没有贴近的感觉，可以自己写一个',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: muted,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customSensationController,
                      maxLength: customPainSensationMaxLength,
                      textInputAction: TextInputAction.done,
                      scrollPadding: EdgeInsets.only(bottom: keyboard + 24),
                      decoration: InputDecoration(
                        hintText: '写一个自己的感觉',
                        counterText: '',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        border: _roundedInputBorder(dark),
                        enabledBorder: _roundedInputBorder(dark),
                        focusedBorder: _roundedInputBorder(dark, focused: true),
                      ),
                      onChanged: (_) {
                        if (_sensationError != null) {
                          setState(() => _sensationError = null);
                        }
                      },
                      onSubmitted: (_) => _rememberSensation(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 44,
                    child: ZtPressableScale(
                      pressEnabled: true,
                      child: FilledButton(
                        onPressed: () {
                          ztHaptic(context, ZtHaptic.medium);
                          _rememberSensation();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: dark
                              ? AppColors.darkPrimary
                              : AppColors.lightPrimary,
                          foregroundColor: dark
                              ? AppColors.darkOnPrimary
                              : AppColors.lightOnPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          '确认',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_sensationError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _sensationError!,
                  style: const TextStyle(
                    color: AppColors.painMarker,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const _SectionTitle(index: '3', title: '现在有多难受？'),
              const SizedBox(height: 12),
              _Panel(
                child: _IntensitySelector(
                  value: _intensity,
                  onChanged: (value) => setState(() => _intensity = value),
                ),
              ),
              const SizedBox(height: 24),
              _SectionTitle(
                index: '4',
                title: _continuing ? '这次变化发生在' : '这次疼痛的时间',
              ),
              const SizedBox(height: 12),
              if (_continuing) ...[
                Text(
                  '痛点、感觉和程度按这个时间记。吃药用各自的用药时间。',
                  style: TextStyle(color: muted, fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 12),
                _Panel(
                  child: _FieldRow(
                    label: '变化时间',
                    value: _changeAtTouched ? changeText : '现在',
                    onTap: _pickChangeTime,
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    for (final timing in _PainTiming.values)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _TimingCard(
                            label: timing.label,
                            selected: _timing == timing,
                            onTap: () => _selectTiming(timing),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_timing != _PainTiming.justStarted) ...[
                  const SizedBox(height: 12),
                  _Panel(
                    child: Column(
                      children: [
                        _FieldRow(
                          label: '开始时间',
                          value: startText,
                          onTap: () => _pickTime(isEnd: false),
                        ),
                        if (_timing == _PainTiming.ended) ...[
                          Divider(
                            color: dark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder,
                          ),
                          _FieldRow(
                            label: '结束时间',
                            value: endText,
                            onTap: () => _pickTime(isEnd: true),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              const _SectionTitle(index: '5', title: '用药记录'),
              const SizedBox(height: 6),
              Text(
                '吃了药就记一下，没吃可以留空。止痛没有错，按说明吃就好。如果疼一直压不住，或者你觉得越来越离不开药，可以找医生聊聊。',
                style: TextStyle(color: muted, fontSize: 12, height: 1.45),
              ),
              if (_continuing && widget.ending!.medications.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final medication in widget.ending!.medications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '已记下 ${medication.name} · ${medication.doseText} · ${DateFormat('MM/dd HH:mm').format(medication.takenAt)}',
                      style: TextStyle(
                        color: muted,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              for (var i = 0; i < _medications.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _medicationCard(
                  i,
                  dark: dark,
                  muted: muted,
                  keyboard: keyboard,
                ),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: ZtPressableScale(
                  pressEnabled: true,
                  tapScale: 0.94,
                  child: TextButton(
                    onPressed: () {
                      ztHaptic(context, ZtHaptic.light);
                      setState(() {
                        _medications.add(_MedicationDraft());
                        _validation = null;
                      });
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('再加一种'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SectionTitle(index: '6', title: _continuing ? '这次补充' : '补充记录'),
              const SizedBox(height: 6),
              Text(
                _continuing ? '这次想补充的话写在这里，以前写过的还留在经过里。' : '想再写一句也可以，不写直接保存就行。',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                maxLines: 3,
                maxLength: 200,
                scrollPadding: EdgeInsets.only(bottom: keyboard + 24),
                decoration: InputDecoration(
                  hintText: '例如：跳痛，压着会好一点……',
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: _roundedInputBorder(dark),
                  enabledBorder: _roundedInputBorder(dark),
                  focusedBorder: _roundedInputBorder(dark, focused: true),
                ),
              ),
            ],
          ),
          bottomNavigationBar: ColoredBox(
            color: dark ? AppColors.darkSurface : AppColors.lightPage,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: dark ? AppColors.darkSurface : AppColors.lightPage,
                  border: Border(
                    top: BorderSide(
                      color: dark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.46,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_validation != null) ...[
                          Text(
                            _validation!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.painMarker,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_continuing && _finishing) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  child: _TimingCard(
                                    label: '刚结束',
                                    selected: _endJustNow == true,
                                    onTap: () =>
                                        _selectEndChoice(justNow: true),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  child: _TimingCard(
                                    label: '自己选时间',
                                    selected: _endJustNow == false,
                                    onTap: () =>
                                        _selectEndChoice(justNow: false),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_endJustNow == false) ...[
                            const SizedBox(height: 8),
                            _FieldRow(
                              label: '结束时间',
                              value: endText,
                              onTap: () => _pickTime(isEnd: true),
                            ),
                          ],
                          const SizedBox(height: 10),
                        ],
                        ZtButton(
                          label: _continuing
                              ? (_finishing ? '结束并保存' : '保存，继续记录')
                              : '保存本次记录',
                          onPressed: _save,
                        ),
                        if (_continuing) ...[
                          ZtPressableScale(
                            pressEnabled: true,
                            tapScale: 0.94,
                            child: TextButton(
                              onPressed: () {
                                ztHaptic(context, ZtHaptic.selection);
                                setState(() {
                                  _finishing = !_finishing;
                                  _validation = null;
                                  if (_finishing) {
                                    _endJustNow = true;
                                    _endedAt = DateTime.now();
                                  } else {
                                    _endJustNow = null;
                                  }
                                });
                              },
                              child: Text(_finishing ? '还在疼，先不结束' : '这次不疼了'),
                            ),
                          ),
                        ],
                        Text(
                          _continuing
                              ? (_finishing ? '结束后会出现在历史里' : '保存后还会留在首页')
                              : '舒服一点后再补充也可以',
                          style: TextStyle(color: muted, fontSize: 12),
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
    );
  }

  void _unfocusInputs(PointerUpEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;
    final box = focus.context?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.inflate(8).contains(event.position)) return;
    }
    focus.unfocus();
  }

  Widget _chipWrap({
    required String title,
    required Color muted,
    required List<String> labels,
    required bool expanded,
    required VoidCallback onToggle,
    ValueChanged<String>? onDelete,
  }) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));
    final scaler = MediaQuery.textScalerOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fitted = _chipsWithinRows(
          labels: labels,
          maxWidth: constraints.maxWidth,
          style: style,
          scaler: scaler,
          extraWidth: onDelete == null ? 0 : ztChipDeleteExtraWidth,
        );
        final overflows = fitted < labels.length;
        final visible = expanded ? labels : labels.take(fitted).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
                const Spacer(),
                if (overflows)
                  ZtPressableScale(
                    pressEnabled: true,
                    tapScale: 0.94,
                    child: TextButton(
                      onPressed: () {
                        ztHaptic(context, ZtHaptic.light);
                        onToggle();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            expanded ? '收起' : '展开更多',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Icon(
                            expanded ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: _sensationChipGap,
              runSpacing: _sensationChipGap,
              children: [
                for (final sensation in visible)
                  _sensationChip(sensation, onDelete: onDelete),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _sensationChip(String sensation, {ValueChanged<String>? onDelete}) {
    return ZtChip(
      label: sensation,
      selected: _sensations.contains(sensation),
      onTap: () => setState(
        () => _sensations = togglePainSensation(_sensations, sensation),
      ),
      onDelete: onDelete == null ? null : () => onDelete(sensation),
    );
  }
}

const double _sensationChipGap = 8;

/// How many chips fit in two rows, using the same padding as [ZtChip].
int _chipsWithinRows({
  required List<String> labels,
  required double maxWidth,
  required TextStyle style,
  required TextScaler scaler,
  double extraWidth = 0,
  int maxRows = 2,
}) {
  if (labels.isEmpty || maxWidth <= 0 || maxRows < 1) return labels.length;
  var rows = 1;
  var used = 0.0;
  var count = 0;
  for (final label in labels) {
    var width = _sensationChipWidth(label, style, scaler) + extraWidth;
    if (width > maxWidth) width = maxWidth;
    final gap = used == 0 ? 0.0 : _sensationChipGap;
    if (used > 0 && used + gap + width > maxWidth) {
      rows++;
      if (rows > maxRows) return count;
      used = width;
    } else {
      used += gap + width;
    }
    count++;
  }
  return count;
}

OutlineInputBorder _roundedInputBorder(bool dark, {bool focused = false}) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(
      color: focused
          ? (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
          : (dark ? AppColors.darkBorder : AppColors.lightBorder),
    ),
  );
}

double _sensationChipWidth(String label, TextStyle style, TextScaler scaler) {
  final painter = TextPainter(
    text: TextSpan(text: label, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return painter.width + 32;
}

class _MedicationDraft {
  _MedicationDraft({String name = '', String dose = '', DateTime? takenAt})
    : nameController = TextEditingController(text: name),
      doseController = TextEditingController(text: dose),
      takenAt = takenAt ?? DateTime.now();

  final TextEditingController nameController;
  final TextEditingController doseController;
  final GlobalKey unitButtonKey = GlobalKey();
  String unit = '片';
  DateTime takenAt;

  void dispose() {
    nameController.dispose();
    doseController.dispose();
  }
}

class _AddActions extends StatelessWidget {
  const _AddActions({
    required this.hasSpots,
    required this.onQuick,
    required this.bodyAction,
  });

  final bool hasSpots;
  final VoidCallback onQuick;
  final Widget bodyAction;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasSpots)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '继续添加痛点',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: dark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _ActionTile(
                icon: Icons.bolt_outlined,
                label: '快速添加',
                onTap: onQuick,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: bodyAction),
          ],
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      child: Material(
        color: dark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: dark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotCard extends StatelessWidget {
  const _SpotCard({
    required this.index,
    required this.summary,
    required this.editAction,
    required this.onDelete,
  });

  final int index;
  final String summary;
  final Widget editAction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Container(
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(
          children: [
            _SpotIndex(index: index),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                summary,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 8),
            editAction,
            ZtPressableScale(
              pressEnabled: true,
              tapScale: 0.88,
              child: IconButton(
                onPressed: () {
                  ztHaptic(context, ZtHaptic.heavy);
                  onDelete();
                },
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 28,
                ),
                icon: Icon(Icons.close, size: 16, color: secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpotIndex extends StatelessWidget {
  const _SpotIndex({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppColors.darkElevated : AppColors.lightPrimarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$index',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: dark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
        ),
      ),
    );
  }
}

class _SpotAction extends StatelessWidget {
  const _SpotAction({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ZtPressableScale(
      pressEnabled: true,
      tapScale: 0.94,
      child: TextButton(
        onPressed: () {
          ztHaptic(context, ZtHaptic.light);
          onTap();
        },
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: Size.zero,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.index, required this.title});

  final String index;
  final String title;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: dark ? AppColors.darkPrimarySoft : AppColors.lightPrimary,
            shape: BoxShape.circle,
          ),
          child: Text(
            index,
            style: TextStyle(
              color: dark ? AppColors.darkPrimary : AppColors.lightOnPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _IntensitySelector extends StatelessWidget {
  const _IntensitySelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final step = value.clamp(1, 10);
    final color = intensityColor(step, dark: dark);
    final muted = dark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Column(
      children: [
        Text(
          '$step',
          style: TextStyle(
            color: color,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          intensityLabel(step),
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          intensityDetail(step),
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13, height: 1.35),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            inactiveTrackColor: dark
                ? AppColors.darkElevated
                : AppColors.lightSubtle,
            thumbColor: color,
            overlayColor: Colors.transparent,
            trackHeight: 6,
          ),
          child: Slider(
            value: step.toDouble(),
            min: 1,
            max: 10,
            divisions: 9,
            activeColor: color,
            onChanged: (next) {
              final rounded = next.round();
              if (rounded != step) ztHaptic(context, ZtHaptic.selection);
              onChanged(rounded);
            },
          ),
        ),
        Row(
          children: [
            Text('1', style: TextStyle(color: muted, fontSize: 12)),
            const Spacer(),
            Text('10', style: TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ],
    );
  }
}

class _TimingCard extends StatelessWidget {
  const _TimingCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      haptic: ZtHaptic.selection,
      child: Material(
        color: selected
            ? (dark ? AppColors.darkPrimarySoft : AppColors.lightPrimary)
            : (dark ? AppColors.darkElevated : AppColors.lightSurface),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          alignment: Alignment.center,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? (dark ? AppColors.darkPrimary : AppColors.lightPrimary)
                  : (dark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? (dark ? AppColors.darkPrimary : AppColors.lightOnPrimary)
                  : (dark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: dark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: child,
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ZtPressableScale(
      onTap: onTap,
      tapScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: dark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
            const Spacer(),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: dark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
