import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/study/study_learning.dart';
import 'package:lichess_mobile/src/view/study/study_learning_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../test_provider_scope.dart';

/// Marks the study [id] with [status], as if it was last opened [ago].
Future<void> markStudy(
  WidgetTester tester,
  String id,
  StudyLearningStatus status, {
  Duration ago = Duration.zero,
}) async {
  final container = ProviderScope.containerOf(tester.element(find.byType(StudyLearningScreen)));
  await tester.runAsync(() async {
    await container.read(studyLearningProvider.future);
    await withClock(
      Clock.fixed(DateTime.now().subtract(ago)),
      () => container
          .read(studyLearningProvider.notifier)
          .mark(
            studyId: StudyId(id),
            studyName: 'Study $id',
            chapterId: StudyChapterId('chapter-$id'),
            chapterName: 'Chapter of $id',
            status: status,
          ),
    );
  });
  await tester.pumpAndSettle();
}

Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    await makeTestProviderScopeApp(tester, home: const StudyLearningScreen()),
  );
  await tester.runAsync(() async {
    final container = ProviderScope.containerOf(tester.element(find.byType(StudyLearningScreen)));
    await container.read(studyLearningProvider.future);
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('explains how to follow a study when none is followed', (tester) async {
    await pumpScreen(tester);

    expect(find.textContaining('Mark a study as learning or learned'), findsOneWidget);
  });

  testWidgets('lists the studies being learned and the learned ones apart', (tester) async {
    await pumpScreen(tester);
    await markStudy(tester, 'a', StudyLearningStatus.learning);
    await markStudy(tester, 'b', StudyLearningStatus.learned, ago: const Duration(days: 1));

    expect(find.text(kContinueLearningTitle), findsOneWidget);
    expect(find.text(kToReviseTitle), findsOneWidget);
    expect(find.text('Study a'), findsOneWidget);
    expect(find.text('Study b'), findsOneWidget);
    expect(find.textContaining('Chapter of a'), findsOneWidget);
    // Learned yesterday: not due for revision yet.
    expect(find.text('Revise'), findsNothing);
  });

  testWidgets('flags the learned studies due for revision', (tester) async {
    await pumpScreen(tester);
    await markStudy(
      tester,
      'old',
      StudyLearningStatus.learned,
      ago: kStudyRevisionInterval + const Duration(days: 1),
    );

    expect(find.text('Revise'), findsOneWidget);
  });

  testWidgets('a long press lets the user stop following a study', (tester) async {
    await pumpScreen(tester);
    await markStudy(tester, 'a', StudyLearningStatus.learning);

    await tester.longPress(find.text('Study a'));
    await tester.pumpAndSettle();
    expect(find.text('Mark as learned'), findsOneWidget);
    expect(find.text('Mark as learning'), findsNothing);

    await tester.tap(find.text('Remove from my learning'));
    await tester.pump();
    // Let the deletion reach the database.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.text('Study a'), findsNothing);
    expect(find.textContaining('Mark a study as learning or learned'), findsOneWidget);
  });
}
