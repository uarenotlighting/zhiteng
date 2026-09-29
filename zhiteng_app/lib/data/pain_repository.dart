import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/models/pain_models.dart';

class PainRepository {
  PainRepository();

  Database? _db;
  final _uuid = const Uuid();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'zhiteng_pain.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE pain_entries (
  id TEXT PRIMARY KEY NOT NULL,
  started_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  ended_at TEXT,
  status TEXT NOT NULL,
  intensity INTEGER NOT NULL,
  notes TEXT NOT NULL,
  payload TEXT NOT NULL,
  sync_version INTEGER NOT NULL
)
''');
      },
    );
    return _db!;
  }

  Future<List<PainEntry>> listEntries() async {
    final db = await _database;
    final rows = await db.query('pain_entries', orderBy: 'started_at DESC');
    return rows
        .map((row) => PainEntry.decode(row['payload'] as String))
        .toList();
  }

  Future<PainEntry> saveEntry({
    required DateTime startedAt,
    DateTime? endedAt,
    required List<PainLocation> locations,
    required int intensity0to10,
    required String notes,
    List<MedicationRecord> medications = const [],
  }) async {
    final outcome = applyPainUpdate(
      previous: null,
      draft: PainMomentDraft(
        startedAt: startedAt,
        changeAt: startedAt,
        endedAt: endedAt,
        locations: locations,
        intensity0to10: intensity0to10,
        medications: medications,
        supplement: notes,
      ),
      newId: () => _uuid.v4(),
    );
    final update = outcome.update;
    if (update == null) {
      throw PainRecordRejected(outcome.message ?? '没有记下来');
    }
    final entry = _entryFromUpdate(
      id: _uuid.v4(),
      createdAt: DateTime.now(),
      update: update,
    );
    await _write(entry, insert: true);
    return entry;
  }

  /// Appends moments onto an open pain. An unchanged draft is not written.
  Future<PainUpdateOutcome> reviseEntry({
    required PainEntry previous,
    required PainMomentDraft draft,
  }) async {
    final outcome = applyPainUpdate(
      previous: previous,
      draft: draft,
      newId: () => _uuid.v4(),
    );
    final update = outcome.update;
    if (update == null) return outcome;
    final entry = _entryFromUpdate(
      id: previous.id,
      createdAt: previous.createdAt,
      update: update,
      sourcePlatform: previous.sourcePlatform,
      syncVersion: previous.syncVersion + 1,
    );
    await _write(entry, insert: false);
    return outcome;
  }

  PainEntry _entryFromUpdate({
    required String id,
    required DateTime createdAt,
    required PainTimelineUpdate update,
    String sourcePlatform = 'app',
    int syncVersion = 1,
  }) {
    final detailed = update.notes.isNotEmpty || update.medications.isNotEmpty;
    return PainEntry(
      id: id,
      createdAt: createdAt,
      startedAt: update.startedAt,
      endedAt: update.endedAt,
      locations: update.locations,
      intensity0to10: update.intensity0to10,
      notes: update.notes,
      medications: update.medications,
      moments: update.moments,
      sourcePlatform: sourcePlatform,
      status: update.endedAt == null ? 'ongoing' : 'completed',
      completionState: detailed ? 'detailed' : 'minimal',
      syncVersion: syncVersion,
    );
  }

  Future<void> _write(PainEntry entry, {required bool insert}) async {
    final db = await _database;
    final row = {
      'id': entry.id,
      'started_at': entry.startedAt.toIso8601String(),
      'created_at': entry.createdAt.toIso8601String(),
      'ended_at': entry.endedAt?.toIso8601String(),
      'status': entry.status,
      'intensity': entry.intensity0to10,
      'notes': entry.notes,
      'payload': entry.encode(),
      'sync_version': entry.syncVersion,
    };
    if (insert) {
      await db.insert('pain_entries', row);
      return;
    }
    final updated = await db.update(
      'pain_entries',
      row,
      where: 'id = ?',
      whereArgs: [entry.id],
    );
    if (updated == 0) {
      throw StateError('Pain entry ${entry.id} was not found.');
    }
  }

  Future<void> deleteAll() async {
    final db = await _database;
    await db.delete('pain_entries');
  }

  Future<String> exportJson() async {
    final entries = await listEntries();
    return const JsonEncoder.withIndent('  ').convert({
      'exportedAt': DateTime.now().toIso8601String(),
      'bodyModelVersion': bodyModelVersion,
      'entries': entries.map((e) => e.toJson()).toList(),
      'disclaimer': '知疼记录仅供个人回顾与就医沟通，不构成诊断或治疗建议。',
    });
  }
}
