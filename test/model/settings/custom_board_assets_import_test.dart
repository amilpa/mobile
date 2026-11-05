import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets_import.dart';
import 'package:lichess_mobile/src/model/settings/neo_board.dart';
import 'package:path/path.dart' as p;

import '../../test_container.dart';
import 'custom_board_assets_fixtures.dart';

/// The problems [validatePieceSet] reports for [files].
List<String> pieceSetProblems(List<PickedFile> files) {
  try {
    validatePieceSet(files);
  } on CustomAssetsImportException catch (e) {
    return e.problems.unlock;
  }
  fail('The piece set was accepted');
}

/// The problems [validateBoard] reports for [file].
List<String> boardProblems(PickedFile file) {
  try {
    validateBoard(file);
  } on CustomAssetsImportException catch (e) {
    return e.problems.unlock;
  }
  fail('The board was accepted');
}

void main() {
  group('validatePieceSet', () {
    test('accepts the 12 piece images picked together', () {
      final files = pieceFiles();
      final pieces = validatePieceSet(files);

      expect(pieces.keys.toSet(), PieceKind.values.toSet());
      expect(pieces[PieceKind.whiteKing], files.first.bytes);
    });

    test('does not mind the case of the names', () {
      final pieces = validatePieceSet([
        for (final code in kCustomPieceCodes.values)
          (name: '${code.toUpperCase()}.PNG', bytes: piecePng()),
      ]);

      expect(pieces.length, 12);
    });

    test('accepts a zip file, with the images in a folder and other files ignored', () {
      final zip = zipOf([
        ...pieceFiles(prefix: 'my-set/'),
        (name: 'my-set/LICENSE.txt', bytes: utf8.encode('MIT')),
        (name: 'my-set/.DS_Store', bytes: Uint8List(8)),
        (name: '__MACOSX/my-set/._wK.png', bytes: Uint8List(8)),
      ]);

      final pieces = validatePieceSet([(name: 'my-set.zip', bytes: zip)]);

      expect(pieces.keys.toSet(), PieceKind.values.toSet());
    });

    test('recognizes a zip file without its extension', () {
      final zip = zipOf(pieceFiles());

      expect(validatePieceSet([(name: 'download', bytes: zip)]).length, 12);
    });

    test('refuses a set missing a piece', () {
      expect(pieceSetProblems(pieceFiles(codes: codesWithout({'bQ'}))), [
        'Missing piece: bQ. A piece set needs all 12 pieces.',
      ]);
    });

    test('refuses a set missing several pieces, listing all of them', () {
      expect(pieceSetProblems(pieceFiles(codes: ['wK', 'wQ', 'wR', 'wB', 'wN', 'wP'])), [
        'Missing pieces: bK, bQ, bR, bB, bN, bP. A piece set needs all 12 pieces.',
      ]);
    });

    test('refuses a zip file missing a piece', () {
      final zip = zipOf(pieceFiles(codes: codesWithout({'wN'})));

      expect(pieceSetProblems([(name: 'set.zip', bytes: zip)]), [
        'Missing piece: wN. A piece set needs all 12 pieces.',
      ]);
    });

    test('refuses an empty selection', () {
      expect(pieceSetProblems([]), [
        'No piece images were found. A piece set needs 12 images, one per piece.',
      ]);
    });

    test('refuses a zip file holding no images', () {
      final zip = zipOf([(name: 'readme.md', bytes: utf8.encode('hello'))]);

      expect(pieceSetProblems([(name: 'set.zip', bytes: zip)]), [
        'No piece images were found. A piece set needs 12 images, one per piece.',
      ]);
    });

    test('refuses images not named after a piece', () {
      final problems = pieceSetProblems([...pieceFiles(), (name: 'knight.png', bytes: piecePng())]);

      expect(problems, [
        'Not named after a piece: knight.png. '
            'Name the images wK, wQ, wR, wB, wN, wP, bK, bQ, bR, bB, bN, bP.',
      ]);
    });

    test('refuses two images for the same piece', () {
      final problems = pieceSetProblems([...pieceFiles(), (name: 'wk.png', bytes: piecePng())]);

      expect(problems, ['Several images for wK: wK.png, wk.png.']);
    });

    test('refuses two images for the same piece in different folders of a zip file', () {
      final zip = zipOf([...pieceFiles(prefix: 'a/'), (name: 'b/bP.png', bytes: piecePng())]);

      expect(pieceSetProblems([(name: 'set.zip', bytes: zip)]), [
        'Several images for bP: bP.png, bP.png.',
      ]);
    });

    test('refuses a zip file picked with other files', () {
      final zip = zipOf(pieceFiles());

      expect(pieceSetProblems([(name: 'set.zip', bytes: zip), ...pieceFiles()]), [
        'Pick either a single .zip file, or the 12 piece images, not both.',
      ]);
    });

    test('refuses a damaged zip file', () {
      expect(pieceSetProblems([(name: 'set.zip', bytes: utf8.encode('not a zip file'))]), [
        'set.zip is not a valid .zip file.',
      ]);
    });

    test('refuses a zip file holding too many files', () {
      final zip = zipOf([
        ...pieceFiles(),
        for (var i = 0; i < 100; i++) (name: 'notes/$i.txt', bytes: utf8.encode('$i')),
      ]);

      expect(pieceSetProblems([(name: 'set.zip', bytes: zip)]), [
        'set.zip holds too many files: a piece set needs only 12 images.',
      ]);
    });

    test('refuses a piece image that is not square', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'wQ'})),
        (name: 'wQ.png', bytes: piecePng(size: 128, height: 100)),
      ];

      expect(pieceSetProblems(files), ['wQ.png must be square, it is 128×100 pixels.']);
    });

    test('refuses a piece image that is too small', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'bK'})),
        (name: 'bK.png', bytes: piecePng(size: 32)),
      ];

      expect(pieceSetProblems(files), [
        'bK.png is 32×32 pixels: it must be from 64×64 to 1024×1024 pixels.',
      ]);
    });

    test('refuses a piece image that is too large', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'bK'})),
        (name: 'bK.png', bytes: piecePng(size: 1032)),
      ];

      expect(pieceSetProblems(files), [
        'bK.png is 1032×1032 pixels: it must be from 64×64 to 1024×1024 pixels.',
      ]);
    });

    test('refuses JPEG pieces, whatever their name', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'wP', 'bP'})),
        (name: 'wP.jpg', bytes: plainJpg()),
        (name: 'bP.png', bytes: plainJpg()),
      ];

      expect(pieceSetProblems(files), [
        'wP.jpg is not a PNG or WebP image.',
        'bP.png is not a PNG or WebP image.',
      ]);
    });

    test('refuses a file that is not an image', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'wB'})),
        (name: 'wB.png', bytes: utf8.encode('this is not an image')),
      ];

      final problems = pieceSetProblems(files);

      expect(problems, hasLength(1));
      expect(problems.single, startsWith('wB.png '));
    });

    test('refuses a damaged image', () {
      // Only the PNG signature is left: the image itself is gone.
      final files = [
        ...pieceFiles(codes: codesWithout({'wR'})),
        (name: 'wR.png', bytes: Uint8List.sublistView(piecePng(), 0, 8)),
      ];

      final problems = pieceSetProblems(files);

      expect(problems, hasLength(1));
      expect(problems.single, startsWith('wR.png '));
    });

    test('refuses an image file that is too large', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'bN'})),
        (name: 'bN.png', bytes: Uint8List(kCustomImageMaxBytes + 1)),
      ];

      expect(pieceSetProblems(files), ['bN.png is too large: an image must be at most 8 MB.']);
    });

    test('reports every problem at once', () {
      final files = [
        ...pieceFiles(codes: codesWithout({'wK', 'wQ'})),
        (name: 'wQ.png', bytes: piecePng(size: 128, height: 64)),
        (name: 'king.png', bytes: piecePng()),
      ];

      expect(pieceSetProblems(files), [
        'Missing piece: wK. A piece set needs all 12 pieces.',
        'Not named after a piece: king.png. '
            'Name the images wK, wQ, wR, wB, wN, wP, bK, bQ, bR, bB, bN, bP.',
        'wQ.png must be square, it is 128×64 pixels.',
      ]);
    });
  });

  group('validateBoard', () {
    test('accepts a square PNG image and takes the square colors from a1 and h1', () {
      final bytes = boardPng();
      final board = validateBoard((name: 'board.png', bytes: bytes));

      expect(board.bytes, bytes);
      expect(board.lightSquareArgb, kTestLightSquare);
      expect(board.darkSquareArgb, kTestDarkSquare);
    });

    test('accepts a JPEG image', () {
      final board = validateBoard((name: 'board.jpg', bytes: boardJpg()));

      /// The largest difference between the red, green and blue channels of [a] and [b].
      int channelDistance(int a, int b) {
        var distance = 0;
        for (final shift in [16, 8, 0]) {
          final difference = (((a >> shift) & 0xFF) - ((b >> shift) & 0xFF)).abs();
          if (difference > distance) distance = difference;
        }
        return distance;
      }

      // JPEG is lossy: the colors are close to the original ones.
      expect(channelDistance(board.lightSquareArgb, kTestLightSquare), lessThan(8));
      expect(channelDistance(board.darkSquareArgb, kTestDarkSquare), lessThan(8));
    });

    test('refuses an image that is not square', () {
      expect(boardProblems((name: 'board.png', bytes: boardPng(width: 256, height: 320))), [
        'board.png must be square, it is 256×320 pixels.',
      ]);
    });

    test('refuses an image that is too small', () {
      expect(boardProblems((name: 'board.png', bytes: piecePng(size: 128))), [
        'board.png is 128×128 pixels: it must be from 256×256 to 2048×2048 pixels.',
      ]);
    });

    test('refuses an image that is too large', () {
      expect(boardProblems((name: 'board.png', bytes: piecePng(size: 2056))), [
        'board.png is 2056×2056 pixels: it must be from 256×256 to 2048×2048 pixels.',
      ]);
    });

    test('refuses an image of another format', () {
      expect(boardProblems((name: 'board.gif', bytes: plainGif())), [
        'board.gif is not a PNG, JPEG or WebP image.',
      ]);
    });

    test('refuses a zip file', () {
      expect(boardProblems((name: 'board.zip', bytes: zipOf(pieceFiles()))), [
        'Pick a single image of the whole board, not a .zip file.',
      ]);
    });
  });

  group('CustomBoardAssetsImporter', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('custom_board_assets_test');
      CustomAssetsBundle.debugRootDirectory = root;
    });

    tearDown(() {
      CustomAssetsBundle.debugRootDirectory = null;
      root.deleteSync(recursive: true);
    });

    Directory piecesFolder() => Directory(p.join(root.path, kCustomBoardAssetsFolder, 'pieces'));
    Directory boardsFolder() => Directory(p.join(root.path, kCustomBoardAssetsFolder, 'boards'));
    List<String> namesIn(Directory directory) =>
        directory.listSync().map((entity) => p.basename(entity.path)).toList();

    test('imports a piece set, stores its 12 images and uses it', () async {
      final container = await makeContainer();
      final files = pieceFiles();

      final pieceSet = await container
          .read(customBoardAssetsImporterProvider)
          .importPieceSet(files);

      final prefs = container.read(boardPreferencesProvider);
      expect(prefs.customPieceSet, pieceSet);
      expect(prefs.useCustomPieceSet, isTrue);
      expect(prefs.pieceAssets, pieceSet.assets);
      expect(prefs.pieceSetLabel, 'Custom pieces');
      expect(namesIn(piecesFolder()), [pieceSet.id]);
      expect(namesIn(Directory(p.join(piecesFolder().path, pieceSet.id))).toSet(), {
        ...kCustomPieceCodes.values,
      });
      for (final asset in pieceSet.assets.values) {
        final data = await CustomAssetsBundle.instance.load(asset.assetName);
        expect(Uint8List.sublistView(data), files.first.bytes);
      }
    });

    test('names a piece set imported from a zip file after the file', () async {
      final container = await makeContainer();

      final pieceSet = await container.read(customBoardAssetsImporterProvider).importPieceSet([
        (name: 'Glass pieces.zip', bytes: zipOf(pieceFiles())),
      ]);

      expect(pieceSet.name, 'Glass pieces');
      expect(container.read(boardPreferencesProvider).pieceSetLabel, 'Glass pieces');
    });

    test('an incomplete piece set changes nothing', () async {
      final container = await makeContainer();
      final importer = container.read(customBoardAssetsImporterProvider);
      final previous = await importer.importPieceSet(pieceFiles());

      await expectLater(
        importer.importPieceSet(pieceFiles(codes: codesWithout({'bK'}))),
        throwsA(isA<CustomAssetsImportException>()),
      );

      final prefs = container.read(boardPreferencesProvider);
      expect(prefs.customPieceSet, previous);
      expect(prefs.useCustomPieceSet, isTrue);
      expect(namesIn(piecesFolder()), [previous.id]);
      expect(namesIn(Directory(p.join(piecesFolder().path, previous.id))), hasLength(12));
    });

    test('an incomplete first piece set leaves the chosen piece set and writes nothing', () async {
      final container = await makeContainer();
      await container.read(boardPreferencesProvider.notifier).setPieceSet(PieceSet.alpha);

      await expectLater(
        container
            .read(customBoardAssetsImporterProvider)
            .importPieceSet(pieceFiles(codes: codesWithout({'wP'}))),
        throwsA(isA<CustomAssetsImportException>()),
      );

      final prefs = container.read(boardPreferencesProvider);
      expect(prefs.customPieceSet, isNull);
      expect(prefs.pieceAssets, PieceSet.alpha.assets);
      expect(piecesFolder().existsSync(), isFalse);
    });

    test('a new piece set replaces the previous one and deletes its images', () async {
      final container = await makeContainer();
      final importer = container.read(customBoardAssetsImporterProvider);
      final first = await importer.importPieceSet(pieceFiles());

      final second = await importer.importPieceSet(pieceFiles());

      expect(second.id, isNot(first.id));
      expect(container.read(boardPreferencesProvider).customPieceSet, second);
      expect(namesIn(piecesFolder()), [second.id]);
    });

    test('an import deletes the leftovers of an interrupted import', () async {
      final leftover = Directory(p.join(piecesFolder().path, 'interrupted'))
        ..createSync(recursive: true);
      final container = await makeContainer();

      final pieceSet = await container
          .read(customBoardAssetsImporterProvider)
          .importPieceSet(pieceFiles());

      expect(leftover.existsSync(), isFalse);
      expect(namesIn(piecesFolder()), [pieceSet.id]);
    });

    test('choosing another piece set keeps the custom one, which can be used again', () async {
      final container = await makeContainer();
      final notifier = container.read(boardPreferencesProvider.notifier);
      final pieceSet = await container
          .read(customBoardAssetsImporterProvider)
          .importPieceSet(pieceFiles());

      await notifier.setNeoPieceSet(NeoPieceSet.mochi);
      expect(container.read(boardPreferencesProvider).pieceAssets, NeoPieceSet.mochi.assets);
      expect(container.read(boardPreferencesProvider).customPieceSet, pieceSet);

      await notifier.useCustomPieceSet();
      expect(container.read(boardPreferencesProvider).pieceAssets, pieceSet.assets);
    });

    test('removing the piece set deletes its images and goes back to the previous set', () async {
      final container = await makeContainer();
      await container.read(boardPreferencesProvider.notifier).setNeoPieceSet(NeoPieceSet.poppy);
      final importer = container.read(customBoardAssetsImporterProvider);
      await importer.importPieceSet(pieceFiles());

      await importer.removePieceSet();

      final prefs = container.read(boardPreferencesProvider);
      expect(prefs.customPieceSet, isNull);
      expect(prefs.useCustomPieceSet, isFalse);
      expect(prefs.pieceAssets, NeoPieceSet.poppy.assets);
      expect(namesIn(piecesFolder()), isEmpty);
    });

    test('imports a board, with the square colors of its image, and uses it', () async {
      final container = await makeContainer();
      final bytes = boardPng();

      final board = await container.read(customBoardAssetsImporterProvider).importBoard((
        name: 'Walnut.png',
        bytes: bytes,
      ));

      final prefs = container.read(boardPreferencesProvider);
      expect(prefs.customBoard, board);
      expect(prefs.useCustomBoard, isTrue);
      expect(prefs.boardLabel, 'Walnut');
      expect(prefs.boardColors.lightSquare, const Color(kTestLightSquare));
      expect(prefs.boardColors.darkSquare, const Color(kTestDarkSquare));
      expect(prefs.boardColors.background, isA<ImageChessboardBackground>());
      expect(namesIn(boardsFolder()), [board.id]);
      final data = await CustomAssetsBundle.instance.load(board.image.assetName);
      expect(Uint8List.sublistView(data), bytes);
    });

    test('an invalid board changes nothing', () async {
      final container = await makeContainer();
      final importer = container.read(customBoardAssetsImporterProvider);
      final previous = await importer.importBoard((name: 'board.png', bytes: boardPng()));

      await expectLater(
        importer.importBoard((name: 'board.png', bytes: boardPng(width: 256, height: 512))),
        throwsA(isA<CustomAssetsImportException>()),
      );

      expect(container.read(boardPreferencesProvider).customBoard, previous);
      expect(namesIn(boardsFolder()), [previous.id]);
    });

    test('removing the board deletes its image and goes back to the previous board', () async {
      final container = await makeContainer();
      await container.read(boardPreferencesProvider.notifier).setBoardTheme(BoardTheme.blue);
      final importer = container.read(customBoardAssetsImporterProvider);
      await importer.importBoard((name: 'board.png', bytes: boardPng()));

      await importer.removeBoard();

      final prefs = container.read(boardPreferencesProvider);
      expect(prefs.customBoard, isNull);
      expect(prefs.boardColors, BoardTheme.blue.colors);
      expect(namesIn(boardsFolder()), isEmpty);
    });

    test('choosing another board keeps the custom one, which can be used again', () async {
      final container = await makeContainer();
      final notifier = container.read(boardPreferencesProvider.notifier);
      final board = await container.read(customBoardAssetsImporterProvider).importBoard((
        name: 'board.png',
        bytes: boardPng(),
      ));

      await notifier.setNeoBoard(NeoBoard.marble);
      expect(container.read(boardPreferencesProvider).boardColors, NeoBoard.marble.colors);

      await notifier.useCustomBoard();
      expect(container.read(boardPreferencesProvider).boardColors, board.colors);
    });
  });

  group('BoardPrefs', () {
    test('keeps the custom board and piece set through JSON', () {
      final prefs = BoardPrefs.defaults.copyWith(
        customPieceSet: const CustomPieceSet(id: '1', name: 'Glass'),
        useCustomPieceSet: true,
        customBoard: const CustomBoard(
          id: '2',
          name: 'Walnut',
          lightSquare: Color(kTestLightSquare),
          darkSquare: Color(kTestDarkSquare),
        ),
        useCustomBoard: true,
      );

      final decoded = BoardPrefs.fromJson(
        jsonDecode(jsonEncode(prefs.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, prefs);
      expect(decoded.pieceSetLabel, 'Glass');
      expect(decoded.boardLabel, 'Walnut');
    });

    test('reads preferences stored before custom boards and piece sets existed', () {
      final json = BoardPrefs.defaults.toJson()
        ..remove('customPieceSet')
        ..remove('useCustomPieceSet')
        ..remove('customBoard')
        ..remove('useCustomBoard');

      final decoded = BoardPrefs.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>);

      expect(decoded, BoardPrefs.defaults);
    });
  });
}
