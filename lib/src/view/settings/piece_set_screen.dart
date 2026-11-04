import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/neo_board.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/chessboard.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';

class const PieceSetScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const PieceSetScreen());
  }

  @override
  ConsumerState<PieceSetScreen> createState() => _PieceSetScreenState();
}

class _PieceSetScreenState() extends ConsumerState<PieceSetScreen> {
  bool isLoading = false;

  /// Saves the choice with [save], then loads the images of the new set.
  Future<void> onChanged(Future<void> Function() save, PieceAssets assets) async {
    save();
    setState(() {
      isLoading = true;
    });
    try {
      await precachePieceImages(assets);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final notifier = ref.read(boardPreferencesProvider.notifier);

    Widget tile({
      required String label,
      required PieceAssets assets,
      required bool selected,
      required Future<void> Function() save,
    }) {
      return ListTile(
        trailing: selected ? const Icon(Icons.check) : null,
        title: Text(label),
        subtitle: _PieceSetPreview(assets: assets, boardPrefs: boardPrefs),
        onTap: isLoading ? null : () => onChanged(save, assets),
        selected: selected,
      );
    }

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(context.l10n.pieceSet),
        actions: [if (isLoading) const PlatformAppBarLoadingIndicator()],
      ),
      body: SafeArea(
        child: ListView(
          children: [
            const _SectionHeader('LichessNeo'),
            for (final pieceSet in NeoPieceSet.values)
              tile(
                label: pieceSet.label,
                assets: pieceSet.assets,
                selected: boardPrefs.neoPieceSet == pieceSet,
                save: () => notifier.setNeoPieceSet(pieceSet),
              ),
            const _SectionHeader('Lichess'),
            for (final pieceSet in PieceSet.values)
              tile(
                label: pieceSet.label,
                assets: pieceSet.assets,
                selected: boardPrefs.neoPieceSet == null && boardPrefs.pieceSet == pieceSet,
                save: () => notifier.setPieceSet(pieceSet),
              ),
          ],
        ),
      ),
    );
  }
}

class const _PieceSetPreview({
  required final PieceAssets assets,
  required final BoardPrefs boardPrefs,
}) extends StatelessWidget {
  static const _previewPieces = [
    PieceKind.whiteKing,
    PieceKind.blackQueen,
    PieceKind.whiteRook,
    PieceKind.blackBishop,
    PieceKind.whiteKnight,
    PieceKind.blackPawn,
  ];

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 264),
      child: Stack(
        children: [
          BrightnessHueFilter(
            brightness: boardPrefs.brightness,
            hue: boardPrefs.hue,
            child: boardPrefs.neoBoard?.thumbnail ?? boardPrefs.boardTheme.thumbnail,
          ),
          Row(
            children: [
              for (final kind in _previewPieces) Image(image: assets[kind]!, height: 44),
            ],
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
