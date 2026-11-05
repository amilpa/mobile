import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/neo_board.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/color_palette.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/settings/custom_board_assets_screen.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

class const BoardChoiceScreen({super.key}) extends StatelessWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const BoardChoiceScreen());
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(context.l10n.board)),
      body: const _Body(),
    );
  }
}

class const _Body() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (boardTheme, neoBoard, customBoard, useCustomBoard) = ref.watch(
      boardPreferencesProvider.select(
        (p) => (p.boardTheme, p.neoBoard, p.customBoard, p.useCustomBoard),
      ),
    );
    final notifier = ref.read(boardPreferencesProvider.notifier);

    final hasSystemColors = getSystemCorePalettes() != null;
    final lichessBoards = BoardTheme.values
        .where((t) => t != BoardTheme.system || hasSystemColors)
        .toList();

    const checkedIcon = Icon(Icons.check);

    Widget tile({
      required String label,
      required Widget thumbnail,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return ListTile(
        selected: selected,
        trailing: selected ? checkedIcon : null,
        title: Text(label),
        subtitle: Align(alignment: Alignment.topLeft, child: thumbnail),
        onTap: onTap,
      );
    }

    return SafeArea(
      child: ListView(
        children: [
          const _SectionHeader('Custom'),
          if (customBoard != null)
            tile(
              label: customBoard.name,
              thumbnail: customBoard.thumbnail,
              selected: useCustomBoard,
              onTap: notifier.useCustomBoard,
            ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: Text(customBoard == null ? 'Import your own board' : 'Manage custom board'),
            onTap: () => Navigator.of(context).push(CustomBoardAssetsScreen.buildRoute()),
          ),
          const _SectionHeader('LichessNeo'),
          for (final board in NeoBoard.values)
            tile(
              label: board.label,
              thumbnail: board.thumbnail,
              selected: !useCustomBoard && board == neoBoard,
              onTap: () => notifier.setNeoBoard(board),
            ),
          const _SectionHeader('Lichess'),
          for (final board in lichessBoards)
            tile(
              label: board.label,
              thumbnail: board.thumbnail,
              selected: !useCustomBoard && neoBoard == null && board == boardTheme,
              onTap: () => notifier.setBoardTheme(board),
            ),
        ],
      ),
    );
  }
}

/// Title of a group of choices.
class const _SectionHeader(final String title) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: Styles.sectionTitle),
    );
  }
}
