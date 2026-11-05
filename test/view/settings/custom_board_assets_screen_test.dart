import 'dart:io';
import 'dart:typed_data';

import 'package:chessground/chessground.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets_import.dart';
import 'package:lichess_mobile/src/view/settings/custom_board_assets_screen.dart';
import 'package:lichess_mobile/src/widgets/platform.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../model/settings/custom_board_assets_fixtures.dart';
import '../../test_provider_scope.dart';

/// A [PlatformFile] backed by in-memory [chunks], avoiding the need for a real file in tests.
final class _FakePlatformFile({
  @override required final String name,
  required final List<Uint8List> chunks,
}) extends PlatformFile {
  int get _length => chunks.fold(0, (sum, chunk) => sum + chunk.length);

  @override
  Uri get uri => Uri.file(name);

  /// [Never] is used as the return type so that no `package:cross_file` import is needed: the
  /// screen only ever reads the file as a byte stream.
  @override
  Never get xFile => throw UnimplementedError();

  @override
  Future<int> length() async => _length;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([for (final c in chunks) ...c]);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.fromIterable(chunks);

  @override
  int? lengthSync() => _length;
}

PlatformFile platformFileOf(PickedFile file) {
  return _FakePlatformFile(name: file.name, chunks: [file.bytes]);
}

Future<Widget> makeApp(
  WidgetTester tester, {
  List<PlatformFile> pieceFilesPicked = const [],
  PlatformFile? boardFilePicked,
}) {
  return makeTestProviderScopeApp(
    tester,
    home: const CustomBoardAssetsScreen(),
    overrides: {
      pickCustomPieceSetFilesProvider: pickCustomPieceSetFilesProvider.overrideWithValue(
        () async => pieceFilesPicked,
      ),
      pickCustomBoardFileProvider: pickCustomBoardFileProvider.overrideWithValue(
        () async => boardFilePicked,
      ),
    },
  );
}

BoardPrefs boardPrefsOf(WidgetTester tester) {
  return ProviderScope.containerOf(tester.element(find.byType(CustomBoardAssetsScreen)))
      .read(boardPreferencesProvider);
}

/// Lets the import, which runs in another isolate and reads and writes files, go on until
/// [condition] holds.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 250 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  expect(condition(), isTrue, reason: 'The condition did not hold in time');
}

bool isImporting() => find.byType(PlatformAppBarLoadingIndicator).evaluate().isNotEmpty;

Future<void> tapImportPieces(WidgetTester tester) async {
  final button = find.text('Import pieces');
  await tester.scrollUntilVisible(button, 200);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('custom_board_assets_screen_test');
    CustomAssetsBundle.debugRootDirectory = root;
  });

  tearDown(() {
    CustomAssetsBundle.debugRootDirectory = null;
    ChessgroundImages.instance.clear();
    root.deleteSync(recursive: true);
  });

  testWidgets('describes the format of the board and of the pieces', (tester) async {
    await tester.pumpWidget(await makeApp(tester));

    expect(find.textContaining('One square image of the whole board'), findsOneWidget);
    expect(find.textContaining('a8 at the top left, h1 at the bottom right'), findsOneWidget);

    final rule = find.textContaining('All 12 pieces are required');
    await tester.scrollUntilVisible(rule, 200);
    expect(rule, findsOneWidget);
    expect(
      find.textContaining('named wK, wQ, wR, wB, wN, wP for white and bK, bQ, bR, bB, bN, bP'),
      findsOneWidget,
    );
  });

  testWidgets('imports a complete piece set and uses it', (tester) async {
    await tester.pumpWidget(
      await makeApp(tester, pieceFilesPicked: pieceFiles().map(platformFileOf).toList()),
    );

    await tapImportPieces(tester);
    await pumpUntil(tester, () => boardPrefsOf(tester).customPieceSet != null && !isImporting());

    final prefs = boardPrefsOf(tester);
    expect(prefs.useCustomPieceSet, isTrue);
    expect(find.byKey(const Key('custom-piece-set')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('custom-piece-set')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.text('Import other pieces'), findsOneWidget);
    final folder = Directory(p.join(root.path, prefs.customPieceSet!.folder));
    expect(folder.listSync(), hasLength(12));
  });

  testWidgets('imports a piece set from a zip file', (tester) async {
    final zip = (name: 'Glass.zip', bytes: zipOf(pieceFiles(prefix: 'glass/')));
    await tester.pumpWidget(await makeApp(tester, pieceFilesPicked: [platformFileOf(zip)]));

    await tapImportPieces(tester);
    await pumpUntil(tester, () => boardPrefsOf(tester).customPieceSet != null && !isImporting());

    expect(boardPrefsOf(tester).customPieceSet!.name, 'Glass');
    expect(find.text('Glass'), findsOneWidget);
  });

  testWidgets('refuses an incomplete piece set and says which pieces are missing', (tester) async {
    final files = pieceFiles(codes: codesWithout({'bP'})).map(platformFileOf).toList();
    await tester.pumpWidget(await makeApp(tester, pieceFilesPicked: files));

    await tapImportPieces(tester);
    await pumpUntil(tester, () => find.text('Could not import').evaluate().isNotEmpty);

    expect(find.text('Missing piece: bP. A piece set needs all 12 pieces.'), findsOneWidget);
    expect(boardPrefsOf(tester).customPieceSet, isNull);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Could not import'), findsNothing);
    expect(find.byKey(const Key('custom-piece-set')), findsNothing);
    expect(Directory(p.join(root.path, kCustomBoardAssetsFolder)).existsSync(), isFalse);
  });

  testWidgets('refuses a file too large to be a piece set without reading all of it', (
    tester,
  ) async {
    // 100 MB, in chunks of 1 MB.
    final hugeFile = _FakePlatformFile(
      name: 'huge.zip',
      chunks: List.filled(100, Uint8List(1024 * 1024)),
    );
    var chunksRead = 0;
    await tester.pumpWidget(
      await makeApp(
        tester,
        pieceFilesPicked: [_CountingPlatformFile(file: hugeFile, onChunk: () => chunksRead++)],
      ),
    );

    await tapImportPieces(tester);
    await pumpUntil(tester, () => find.text('Could not import').evaluate().isNotEmpty);

    expect(find.text('huge.zip is too large.'), findsOneWidget);
    expect(chunksRead, lessThan(100));
    expect(boardPrefsOf(tester).customPieceSet, isNull);
  });

  testWidgets('cancelling the file picker changes nothing', (tester) async {
    await tester.pumpWidget(await makeApp(tester));

    await tapImportPieces(tester);
    await pumpUntil(tester, () => !isImporting());

    expect(find.text('Could not import'), findsNothing);
    expect(boardPrefsOf(tester).customPieceSet, isNull);
  });

  testWidgets('removes the custom pieces once confirmed', (tester) async {
    await tester.pumpWidget(
      await makeApp(tester, pieceFilesPicked: pieceFiles().map(platformFileOf).toList()),
    );
    await tapImportPieces(tester);
    await pumpUntil(tester, () => boardPrefsOf(tester).customPieceSet != null && !isImporting());
    final folder = Directory(p.join(root.path, boardPrefsOf(tester).customPieceSet!.folder));

    final remove = find.text('Remove the custom pieces');
    await tester.scrollUntilVisible(remove, 200);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('Remove the custom pieces?'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextButton)).last,
    );
    await pumpUntil(tester, () => !folder.existsSync());

    expect(boardPrefsOf(tester).customPieceSet, isNull);
    expect(boardPrefsOf(tester).useCustomPieceSet, isFalse);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('custom-piece-set')), findsNothing);
    expect(find.text('Import pieces'), findsOneWidget);
  });

  testWidgets('imports a board image and uses it', (tester) async {
    final board = (name: 'Walnut.png', bytes: boardPng());
    await tester.pumpWidget(await makeApp(tester, boardFilePicked: platformFileOf(board)));

    await tester.tap(find.text('Import a board image'));
    await tester.pump();
    await pumpUntil(tester, () => boardPrefsOf(tester).customBoard != null && !isImporting());

    final prefs = boardPrefsOf(tester);
    expect(prefs.useCustomBoard, isTrue);
    expect(prefs.boardLabel, 'Walnut');
    expect(prefs.boardColors.lightSquare, const Color(kTestLightSquare));
    expect(find.byKey(const Key('custom-board')), findsOneWidget);
    expect(find.text('Import another board'), findsOneWidget);
  });

  testWidgets('refuses a board image that is not square', (tester) async {
    final board = (name: 'board.png', bytes: boardPng(width: 256, height: 384));
    await tester.pumpWidget(await makeApp(tester, boardFilePicked: platformFileOf(board)));

    await tester.tap(find.text('Import a board image'));
    await tester.pump();
    await pumpUntil(tester, () => find.text('Could not import').evaluate().isNotEmpty);

    expect(find.text('board.png must be square, it is 256×384 pixels.'), findsOneWidget);
    expect(boardPrefsOf(tester).customBoard, isNull);
  });
}

/// Wraps a [PlatformFile], calling [onChunk] for each chunk read from it.
final class _CountingPlatformFile({
  required final PlatformFile file,
  required final VoidCallback onChunk,
}) extends PlatformFile {
  @override
  String get name => file.name;

  @override
  Uri get uri => file.uri;

  @override
  Never get xFile => throw UnimplementedError();

  @override
  Future<int> length() => file.length();

  @override
  Future<Uint8List> readAsBytes() => file.readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => file.readAsByteStream().map((chunk) {
    onChunk();
    return chunk;
  });

  @override
  int? lengthSync() => file.lengthSync();
}
