import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/study/study_learning.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/study/study_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

/// Title of the studies the user follows, see [StudyLearningScreen].
const kMyLearningTitle = 'My learning';

/// Title of the studies being learned.
const kContinueLearningTitle = 'Continue learning';

/// Title of the learned studies.
const kToReviseTitle = 'To revise';

/// All the studies the user marked as learning or learned.
class const StudyLearningScreen({super.key}) extends ConsumerWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const StudyLearningScreen());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learning = ref.watch(studyLearningProvider).value ?? StudyLearning.empty;
    final now = clock.now();

    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text(kMyLearningTitle)),
      body: learning.isEmpty
          ? const Center(
              child: Padding(
                padding: Styles.bodyPadding,
                child: Text(
                  'Mark a study as learning or learned from its menu, to find it here and go back '
                  'to the chapter you were on.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                if (learning.learning.isNotEmpty)
                  ListSection(
                    header: const SettingsSectionTitle(kContinueLearningTitle),
                    hasLeading: true,
                    children: [
                      for (final entry in learning.learning)
                        StudyLearningTile(entry: entry, now: now),
                    ],
                  ),
                if (learning.learned.isNotEmpty)
                  ListSection(
                    header: const SettingsSectionTitle(kToReviseTitle),
                    hasLeading: true,
                    children: [
                      for (final entry in learning.learned)
                        StudyLearningTile(entry: entry, now: now),
                    ],
                  ),
              ],
            ),
    );
  }
}

/// A study the user follows: tapping it opens the chapter they were last on, a long press lets
/// them change its status.
class const StudyLearningTile({
  required final StudyLearningEntry entry,
  required final DateTime now,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = ColorScheme.of(context);
    return ListTile(
      leading: Icon(
        entry.status == StudyLearningStatus.learning ? Icons.menu_book_outlined : Icons.task_alt,
      ),
      title: Text(entry.studyName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${entry.chapterName} • ${relativeDate(context.l10n, entry.lastOpenedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      // A learned study that has gone unopened for [kStudyRevisionInterval].
      trailing: entry.isDueForRevision(now)
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: const BorderRadius.all(Radius.circular(12)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Text(
                  'Revise',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : null,
      onTap: () => Navigator.of(
        context,
        rootNavigator: true,
      ).push(StudyScreen.buildRoute((id: entry.studyId, initialChapter: entry.chapterId))),
      onLongPress: () => showStudyLearningActions(context, ref, entry),
    );
  }
}

/// Lets the user change the status of [entry], or stop following it.
Future<void> showStudyLearningActions(
  BuildContext context,
  WidgetRef ref,
  StudyLearningEntry entry,
) {
  final notifier = ref.read(studyLearningProvider.notifier);
  return showAdaptiveActionSheet<void>(
    context: context,
    title: Text(entry.studyName, maxLines: 2, overflow: TextOverflow.ellipsis),
    actions: [
      if (entry.status != StudyLearningStatus.learning)
        BottomSheetAction(
          leading: const Icon(Icons.menu_book_outlined),
          makeLabel: (context) => const Text('Mark as learning'),
          onPressed: () => notifier.setStatus(entry.studyId, StudyLearningStatus.learning),
        ),
      if (entry.status != StudyLearningStatus.learned)
        BottomSheetAction(
          leading: const Icon(Icons.task_alt),
          makeLabel: (context) => const Text('Mark as learned'),
          onPressed: () => notifier.setStatus(entry.studyId, StudyLearningStatus.learned),
        ),
      BottomSheetAction(
        leading: const Icon(Icons.bookmark_remove_outlined),
        makeLabel: (context) => const Text('Remove from my learning'),
        onPressed: () => notifier.remove(entry.studyId),
      ),
    ],
  );
}
