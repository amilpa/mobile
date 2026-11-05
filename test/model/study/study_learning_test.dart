import 'package:clock/clock.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/db/database.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/study/study_learning.dart';

import '../../test_container.dart';

final _day0 = DateTime(2026, 3, 1, 12);

StudyLearningEntry entryOf(
  String id, {
  StudyLearningStatus status = StudyLearningStatus.learning,
  DateTime? lastOpenedAt,
}) {
  return StudyLearningEntry(
    studyId: StudyId(id),
    studyName: 'Study $id',
    status: status,
    chapterId: StudyChapterId('chapter$id'),
    chapterName: 'Chapter of $id',
    lastOpenedAt: lastOpenedAt ?? _day0,
  );
}

void main() {
  group('StudyLearningEntry', () {
    test('a learned study is due for revision once unopened for the revision interval', () {
      final entry = entryOf('a', status: StudyLearningStatus.learned);

      expect(entry.isDueForRevision(_day0.add(const Duration(days: 13))), isFalse);
      expect(entry.isDueForRevision(_day0.add(kStudyRevisionInterval)), isTrue);
      expect(entry.isDueForRevision(_day0.add(const Duration(days: 60))), isTrue);
    });

    test('a study being learned is never due for revision', () {
      final entry = entryOf('a');

      expect(entry.isDueForRevision(_day0.add(const Duration(days: 365))), isFalse);
    });
  });

  group('StudyLearning', () {
    test('lists the studies being learned, the most recently opened first', () {
      final learning = StudyLearning(
        {
          StudyId('old'): entryOf('old', lastOpenedAt: _day0),
          StudyId('new'): entryOf('new', lastOpenedAt: _day0.add(const Duration(days: 2))),
          StudyId('done'): entryOf('done', status: StudyLearningStatus.learned),
        }.lock,
      );

      expect(learning.learning.map((e) => e.studyId.value), ['new', 'old']);
    });

    test('lists the learned studies, the least recently opened first', () {
      final learning = StudyLearning(
        {
          StudyId('recent'): entryOf(
            'recent',
            status: StudyLearningStatus.learned,
            lastOpenedAt: _day0.add(const Duration(days: 20)),
          ),
          StudyId('stale'): entryOf('stale', status: StudyLearningStatus.learned),
          StudyId('ongoing'): entryOf('ongoing'),
        }.lock,
      );

      expect(learning.learned.map((e) => e.studyId.value), ['stale', 'recent']);
      expect(learning.length, 3);
    });
  });

  group('StudyLearningNotifier', () {
    Future<void> markA(StudyLearningNotifier notifier, StudyLearningStatus status) {
      return notifier.mark(
        studyId: const StudyId('a'),
        studyName: 'Study a',
        chapterId: const StudyChapterId('chapter1'),
        chapterName: 'Chapter 1',
        status: status,
      );
    }

    test('marking a study stores it, from the chapter the user is on', () async {
      final container = await makeContainer();
      await container.read(studyLearningProvider.future);
      final notifier = container.read(studyLearningProvider.notifier);

      await withClock(Clock.fixed(_day0), () => markA(notifier, StudyLearningStatus.learning));

      final expected = StudyLearningEntry(
        studyId: const StudyId('a'),
        studyName: 'Study a',
        status: StudyLearningStatus.learning,
        chapterId: const StudyChapterId('chapter1'),
        chapterName: 'Chapter 1',
        lastOpenedAt: _day0,
      );
      expect(container.read(studyLearningProvider).requireValue[const StudyId('a')], expected);
      final storage = await container.read(studyLearningStorageProvider.future);
      expect((await storage.fetch())[const StudyId('a')], expected);
    });

    test('opening a followed study records the chapter and the time', () async {
      final container = await makeContainer();
      await container.read(studyLearningProvider.future);
      final notifier = container.read(studyLearningProvider.notifier);
      await withClock(Clock.fixed(_day0), () => markA(notifier, StudyLearningStatus.learned));

      final later = _day0.add(const Duration(days: 20));
      await withClock(
        Clock.fixed(later),
        () => notifier.recordOpened(
          studyId: const StudyId('a'),
          studyName: 'Study a, renamed',
          chapterId: const StudyChapterId('chapter3'),
          chapterName: 'Chapter 3',
        ),
      );

      final storage = await container.read(studyLearningStorageProvider.future);
      final entry = (await storage.fetch())[const StudyId('a')]!;
      expect(entry.chapterId, const StudyChapterId('chapter3'));
      expect(entry.chapterName, 'Chapter 3');
      expect(entry.studyName, 'Study a, renamed');
      expect(entry.lastOpenedAt, later);
      expect(entry.status, StudyLearningStatus.learned);
      expect(entry.isDueForRevision(later), isFalse);
    });

    test('opening a study the user does not follow records nothing', () async {
      final container = await makeContainer();
      await container.read(studyLearningProvider.future);

      await container
          .read(studyLearningProvider.notifier)
          .recordOpened(
            studyId: const StudyId('b'),
            studyName: 'Study b',
            chapterId: const StudyChapterId('chapter1'),
            chapterName: 'Chapter 1',
          );

      expect(container.read(studyLearningProvider).requireValue.isEmpty, isTrue);
      final storage = await container.read(studyLearningStorageProvider.future);
      expect((await storage.fetch()).isEmpty, isTrue);
    });

    test('changing the status keeps the chapter and the time', () async {
      final container = await makeContainer();
      await container.read(studyLearningProvider.future);
      final notifier = container.read(studyLearningProvider.notifier);
      await withClock(Clock.fixed(_day0), () => markA(notifier, StudyLearningStatus.learning));

      await notifier.setStatus(const StudyId('a'), StudyLearningStatus.learned);

      final storage = await container.read(studyLearningStorageProvider.future);
      final entry = (await storage.fetch())[const StudyId('a')]!;
      expect(entry.status, StudyLearningStatus.learned);
      expect(entry.chapterId, const StudyChapterId('chapter1'));
      expect(entry.lastOpenedAt, _day0);
    });

    test('removing a study forgets it', () async {
      final container = await makeContainer();
      await container.read(studyLearningProvider.future);
      final notifier = container.read(studyLearningProvider.notifier);
      await markA(notifier, StudyLearningStatus.learning);

      await notifier.remove(const StudyId('a'));

      expect(container.read(studyLearningProvider).requireValue.isEmpty, isTrue);
      final storage = await container.read(studyLearningStorageProvider.future);
      expect((await storage.fetch()).isEmpty, isTrue);
    });

    test('unreadable rows are skipped', () async {
      final container = await makeContainer();
      final db = await container.read(databaseProvider.future);
      await db.insert('study_learning', {
        'studyId': 'future',
        'studyName': 'From a later version',
        'status': 'mastered',
        'chapterId': 'chapter1',
        'chapterName': 'Chapter 1',
        'lastOpened': _day0.toIso8601String(),
        'lastModified': _day0.toIso8601String(),
      });

      final learning = await container.read(studyLearningProvider.future);

      expect(learning.isEmpty, isTrue);
    });
  });
}
