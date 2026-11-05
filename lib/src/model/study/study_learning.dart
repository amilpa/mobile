import 'package:clock/clock.dart';
import 'package:collection/collection.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/db/database.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:meta/meta.dart';
import 'package:sqflite/sqflite.dart';

// Lichess has no notion of studies being learned: the user's marks are only kept on this device,
// in the app database.

/// How long a learned study can go unopened before it is suggested for revision.
const kStudyRevisionInterval = Duration(days: 14);

/// Where the user is with a study they follow.
enum StudyLearningStatus() {
  /// The user is going through the study, and will come back to continue it.
  learning,

  /// The user went through the study, and will come back to revise it.
  learned,
}

/// A study the user marked as [StudyLearningStatus.learning] or [StudyLearningStatus.learned], with
/// the chapter they were last on, so that they can go back to it.
@immutable
class const StudyLearningEntry({
  required final StudyId studyId,

  /// The name of the study, kept so that the entry can be listed without fetching the study.
  required final String studyName,
  required final StudyLearningStatus status,
  required final StudyChapterId chapterId,
  required final String chapterName,

  /// When the study was last opened, or marked.
  required final DateTime lastOpenedAt,
}) {
  /// Whether a learned study has gone unopened long enough to be revised.
  bool isDueForRevision(DateTime now) =>
      status == StudyLearningStatus.learned &&
      now.difference(lastOpenedAt) >= kStudyRevisionInterval;

  StudyLearningEntry copyWith({
    String? studyName,
    StudyLearningStatus? status,
    StudyChapterId? chapterId,
    String? chapterName,
    DateTime? lastOpenedAt,
  }) {
    return StudyLearningEntry(
      studyId: studyId,
      studyName: studyName ?? this.studyName,
      status: status ?? this.status,
      chapterId: chapterId ?? this.chapterId,
      chapterName: chapterName ?? this.chapterName,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StudyLearningEntry &&
      other.studyId == studyId &&
      other.studyName == studyName &&
      other.status == status &&
      other.chapterId == chapterId &&
      other.chapterName == chapterName &&
      other.lastOpenedAt == lastOpenedAt;

  @override
  int get hashCode => Object.hash(studyId, studyName, status, chapterId, chapterName, lastOpenedAt);
}

/// The studies the user follows.
@immutable
class const StudyLearning(final IMap<StudyId, StudyLearningEntry> _entries) {
  static const empty = StudyLearning(IMapConst({}));

  bool get isEmpty => _entries.isEmpty;

  /// The number of studies the user follows.
  int get length => _entries.length;

  StudyLearningEntry? operator [](StudyId studyId) => _entries[studyId];

  /// The studies being learned, the most recently opened first.
  IList<StudyLearningEntry> get learning => _entries.values
      .where((entry) => entry.status == StudyLearningStatus.learning)
      .sortedBy((entry) => entry.lastOpenedAt)
      .reversed
      .toIList();

  /// The learned studies, the least recently opened first: the ones due for revision come first.
  IList<StudyLearningEntry> get learned => _entries.values
      .where((entry) => entry.status == StudyLearningStatus.learned)
      .sortedBy((entry) => entry.lastOpenedAt)
      .toIList();

  StudyLearning withEntry(StudyLearningEntry entry) =>
      StudyLearning(_entries.add(entry.studyId, entry));

  StudyLearning without(StudyId studyId) => StudyLearning(_entries.remove(studyId));
}

/// A provider for [StudyLearningStorage].
final studyLearningStorageProvider = FutureProvider<StudyLearningStorage>((Ref ref) async {
  final db = await ref.watch(databaseProvider.future);
  return StudyLearningStorage(db);
}, name: 'StudyLearningStorageProvider');

const _tableName = 'study_learning';

/// Local storage of the studies the user follows.
class const StudyLearningStorage(final Database _db) {
  Future<StudyLearning> fetch() async {
    final rows = await _db.query(_tableName);
    return StudyLearning(
      {
        for (final row in rows)
          if (_entryOf(row) case final entry?) entry.studyId: entry,
      }.lock,
    );
  }

  Future<void> save(StudyLearningEntry entry) async {
    await _db.insert(_tableName, {
      'studyId': entry.studyId.value,
      'studyName': entry.studyName,
      'status': entry.status.name,
      'chapterId': entry.chapterId.value,
      'chapterName': entry.chapterName,
      'lastOpened': entry.lastOpenedAt.toIso8601String(),
      'lastModified': clock.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> delete(StudyId studyId) async {
    await _db.delete(_tableName, where: 'studyId = ?', whereArgs: [studyId.value]);
  }

  /// The entry of [row], or null if it can't be read, e.g. a status written by a later version.
  static StudyLearningEntry? _entryOf(Map<String, Object?> row) {
    final status = StudyLearningStatus.values.firstWhereOrNull((s) => s.name == row['status']);
    final lastOpenedAt = DateTime.tryParse(row['lastOpened'] as String? ?? '');
    if (status == null || lastOpenedAt == null) return null;
    return StudyLearningEntry(
      studyId: StudyId(row['studyId']! as String),
      studyName: row['studyName']! as String,
      status: status,
      chapterId: StudyChapterId(row['chapterId']! as String),
      chapterName: row['chapterName']! as String,
      lastOpenedAt: lastOpenedAt,
    );
  }
}

/// The studies the user follows, loaded from local storage.
final studyLearningProvider = AsyncNotifierProvider<StudyLearningNotifier, StudyLearning>(
  StudyLearningNotifier.new,
  name: 'StudyLearningProvider',
);

class StudyLearningNotifier() extends AsyncNotifier<StudyLearning> {
  @override
  Future<StudyLearning> build() async {
    final storage = await ref.watch(studyLearningStorageProvider.future);
    return await storage.fetch();
  }

  /// Marks the study [studyId] with [status], keeping the chapter the user is on to go back to.
  Future<void> mark({
    required StudyId studyId,
    required String studyName,
    required StudyChapterId chapterId,
    required String chapterName,
    required StudyLearningStatus status,
  }) {
    return _save(
      StudyLearningEntry(
        studyId: studyId,
        studyName: studyName,
        status: status,
        chapterId: chapterId,
        chapterName: chapterName,
        lastOpenedAt: clock.now(),
      ),
    );
  }

  /// Changes the status of a followed study, leaving the rest of its entry as it is.
  Future<void> setStatus(StudyId studyId, StudyLearningStatus status) async {
    final entry = (await future)[studyId];
    if (entry == null || entry.status == status) return;
    await _save(entry.copyWith(status: status));
  }

  /// Records that the user opened [chapterId] of the study [studyId], if they follow it, so that
  /// they get back to it and so that a learned study is not suggested for revision.
  ///
  /// Studies the user doesn't follow are not recorded.
  Future<void> recordOpened({
    required StudyId studyId,
    required String studyName,
    required StudyChapterId chapterId,
    required String chapterName,
  }) async {
    final entry = (await future)[studyId];
    if (entry == null) return;
    await _save(
      entry.copyWith(
        studyName: studyName,
        chapterId: chapterId,
        chapterName: chapterName,
        lastOpenedAt: clock.now(),
      ),
    );
  }

  /// Stops following the study [studyId].
  Future<void> remove(StudyId studyId) async {
    final current = await future;
    state = AsyncData(current.without(studyId));
    final storage = await ref.read(studyLearningStorageProvider.future);
    await storage.delete(studyId);
  }

  Future<void> _save(StudyLearningEntry entry) async {
    final current = await future;
    state = AsyncData(current.withEntry(entry));
    final storage = await ref.read(studyLearningStorageProvider.future);
    await storage.save(entry);
  }
}
