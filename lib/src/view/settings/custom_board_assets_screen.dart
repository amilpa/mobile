import 'dart:typed_data';

import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets_import.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/chessboard.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/settings/piece_set_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:lichess_mobile/src/widgets/feedback.dart';
import 'package:lichess_mobile/src/widgets/list.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:lichess_mobile/src/widgets/platform_alert_dialog.dart';
import 'package:lichess_mobile/src/widgets/settings.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the user pick the files of a custom piece set: a zip file, or the piece images. Can be
/// overridden in tests.
final pickCustomPieceSetFilesProvider = Provider<Future<List<PlatformFile>> Function()>((ref) {
  return () => FilePicker.pickFiles(type: .custom, allowedExtensions: ['zip', 'png', 'webp']);
}, name: 'PickCustomPieceSetFilesProvider');

/// Lets the user pick the image of a custom board. Can be overridden in tests.
final pickCustomBoardFileProvider = Provider<Future<PlatformFile?> Function()>((ref) {
  return () =>
      FilePicker.pickFile(type: .custom, allowedExtensions: ['png', 'jpg', 'jpeg', 'webp']);
}, name: 'PickCustomBoardFileProvider');

/// Reads the picked [file], refusing files too large to be a board or a piece set, before they
/// fill the memory.
Future<PickedFile> _readPickedFile(PlatformFile file) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.readAsByteStream()) {
    builder.add(chunk);
    if (builder.length > kCustomImportMaxBytes) {
      throw CustomAssetsImportException(IList(['${file.name} is too large.']));
    }
  }
  return (name: file.name, bytes: builder.takeBytes());
}

/// Which custom assets are in use, as the value of the settings tile opening
/// [CustomBoardAssetsScreen].
String customBoardAssetsInUse(BoardPrefs prefs) {
  return switch ((prefs.selectedCustomBoard != null, prefs.selectedCustomPieceSet != null)) {
    (true, true) => 'Board & pieces',
    (true, false) => 'Board',
    (false, true) => 'Pieces',
    (false, false) => 'None',
  };
}

/// Lets the user import their own board and piece set, in a set format which this screen
/// describes.
class const CustomBoardAssetsScreen({super.key}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute() {
    return buildScreenRoute(screen: const CustomBoardAssetsScreen());
  }

  @override
  ConsumerState<CustomBoardAssetsScreen> createState() => _CustomBoardAssetsScreenState();
}

class _CustomBoardAssetsScreenState() extends ConsumerState<CustomBoardAssetsScreen> {
  bool isImporting = false;

  CustomBoardAssetsImporter get _importer => ref.read(customBoardAssetsImporterProvider);

  BoardPreferences get _preferences => ref.read(boardPreferencesProvider.notifier);

  /// Runs the import [run], showing the user why it failed if it does.
  Future<void> _import(Future<void> Function() run) async {
    setState(() {
      isImporting = true;
    });
    try {
      await run();
    } on CustomAssetsImportException catch (e) {
      if (mounted) await _showProblems(e.problems);
    } catch (e, st) {
      debugPrint('SEVERE: [CustomBoardAssetsScreen] could not import; $e\n$st');
      if (mounted) showSnackBar(context, 'Could not import the files.', type: .error);
    } finally {
      if (mounted) {
        setState(() {
          isImporting = false;
        });
      }
    }
  }

  Future<void> _importPieceSet() => _import(() async {
    final files = await ref.read(pickCustomPieceSetFilesProvider)();
    if (files.isEmpty) return;
    final pieceSet = await _importer.importPieceSet([
      for (final file in files) await _readPickedFile(file),
    ]);
    await precachePieceImages(pieceSet.assets);
  });

  Future<void> _importBoard() => _import(() async {
    final file = await ref.read(pickCustomBoardFileProvider)();
    if (file == null) return;
    await _importer.importBoard(await _readPickedFile(file));
  });

  Future<void> _usePieceSet(CustomPieceSet pieceSet) async {
    await _preferences.useCustomPieceSet();
    await precachePieceImages(pieceSet.assets);
  }

  Future<void> _removePieceSet() async {
    await _importer.removePieceSet();
    await precachePieceImages(ref.read(boardPreferencesProvider).pieceAssets);
  }

  Future<void> _showProblems(IList<String> problems) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Could not import'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              for (final problem in problems)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(problem)),
            ],
          ),
        ),
        actions: [
          PlatformDialogAction(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.mobileOkButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardPrefs = ref.watch(boardPreferencesProvider);
    final customBoard = boardPrefs.customBoard;
    final customPieceSet = boardPrefs.customPieceSet;

    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: const Text('Custom board & pieces'),
        actions: [if (isImporting) const PlatformAppBarLoadingIndicator()],
      ),
      body: ListView(
        children: [
          ListSection(
            header: const SettingsSectionTitle('Board'),
            hasLeading: true,
            footer: const _FormatDescription([
              'One square image of the whole board: PNG, JPEG or WebP, from '
                  '$kCustomBoardMinSize×$kCustomBoardMinSize to '
                  '$kCustomBoardMaxSize×$kCustomBoardMaxSize pixels.',
              'Seen from white: a8 at the top left, h1 at the bottom right.',
              'The colors of the coordinates are taken from the a1 and h1 squares.',
            ]),
            children: [
              if (customBoard != null) ...[
                ListTile(
                  key: const Key('custom-board'),
                  selected: boardPrefs.useCustomBoard,
                  trailing: boardPrefs.useCustomBoard ? const Icon(Icons.check) : null,
                  title: Text(customBoard.name),
                  subtitle: Align(alignment: .topLeft, child: customBoard.thumbnail),
                  onTap: isImporting ? null : _preferences.useCustomBoard,
                ),
                _RemoveTile(
                  label: 'Remove the custom board',
                  onConfirm: isImporting ? null : _importer.removeBoard,
                ),
              ],
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: Text(customBoard == null ? 'Import a board image' : 'Import another board'),
                onTap: isImporting ? null : _importBoard,
              ),
            ],
          ),
          ListSection(
            header: const SettingsSectionTitle('Pieces'),
            hasLeading: true,
            footer: _FormatDescription([
              'A .zip file holding the 12 piece images, or the 12 images picked together.',
              'One image per piece, named ${kCustomPieceCodes.values.take(6).join(', ')} for '
                  'white and ${kCustomPieceCodes.values.skip(6).join(', ')} for black.',
              'PNG or WebP, square, from $kCustomPieceMinSize×$kCustomPieceMinSize to '
                  '$kCustomPieceMaxSize×$kCustomPieceMaxSize pixels, ideally with a transparent '
                  'background.',
              'All 12 pieces are required: an incomplete set is not imported.',
            ]),
            children: [
              if (customPieceSet != null) ...[
                ListTile(
                  key: const Key('custom-piece-set'),
                  selected: boardPrefs.useCustomPieceSet,
                  trailing: boardPrefs.useCustomPieceSet ? const Icon(Icons.check) : null,
                  title: Text(customPieceSet.name),
                  subtitle: PieceSetPreview(assets: customPieceSet.assets, boardPrefs: boardPrefs),
                  onTap: isImporting ? null : () => _usePieceSet(customPieceSet),
                ),
                _RemoveTile(
                  label: 'Remove the custom pieces',
                  onConfirm: isImporting ? null : _removePieceSet,
                ),
              ],
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: Text(customPieceSet == null ? 'Import pieces' : 'Import other pieces'),
                onTap: isImporting ? null : _importPieceSet,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A tile removing a custom board or piece set, once the user confirms.
class const _RemoveTile({
  required final String label,
  required final Future<void> Function()? onConfirm,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final onConfirm = this.onConfirm;
    return ListTile(
      leading: const Icon(Icons.delete_outline),
      title: Text(label),
      onTap: onConfirm == null
          ? null
          : () => showConfirmDialog<void>(
              context,
              title: Text('$label?'),
              isDestructiveAction: true,
              onConfirm: onConfirm,
            ),
    );
  }
}

/// The format a custom board or piece set must follow, as a list of [rules].
class const _FormatDescription(final List<String> rules) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 13, color: textShade(context, Styles.subtitleOpacity));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('•  $rule', style: style),
            ),
        ],
      ),
    );
  }
}
