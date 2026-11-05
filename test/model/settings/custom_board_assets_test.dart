import 'dart:io';
import 'dart:typed_data';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets.dart';
import 'package:path/path.dart' as p;

import 'custom_board_assets_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('custom_board_assets_bundle_test');
    CustomAssetsBundle.debugRootDirectory = root;
  });

  tearDown(() {
    CustomAssetsBundle.debugRootDirectory = null;
    root.deleteSync(recursive: true);
  });

  /// Writes [bytes] at the [key] of the bundle.
  void writeFile(String key, Uint8List bytes) {
    File(p.joinAll([root.path, ...key.split('/')]))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  }

  test('a custom piece set has one image per piece, all read from the bundle', () {
    const pieceSet = CustomPieceSet(id: '42', name: 'Glass');

    expect(pieceSet.assets.keys.toSet(), PieceKind.values.toSet());
    expect(
      pieceSet.assets[PieceKind.blackKnight]!.assetName,
      '$kCustomBoardAssetsFolder/pieces/42/bN',
    );
    for (final asset in pieceSet.assets.values) {
      expect(asset.bundle, same(CustomAssetsBundle.instance));
    }
  });

  test('loads the files of the app support directory', () async {
    final bytes = piecePng();
    writeFile('$kCustomBoardAssetsFolder/pieces/1/wK', bytes);

    final data = await CustomAssetsBundle.instance.load('$kCustomBoardAssetsFolder/pieces/1/wK');

    expect(Uint8List.sublistView(data), bytes);
  });

  test('fails to load a missing file', () async {
    await expectLater(
      CustomAssetsBundle.instance.load('$kCustomBoardAssetsFolder/pieces/1/wK'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('an AssetImage of the bundle resolves to its file, at its natural resolution', () async {
    const pieceSet = CustomPieceSet(id: '1', name: 'Glass');
    final asset = pieceSet.assets[PieceKind.whiteQueen]!;

    final key = await asset.obtainKey(const ImageConfiguration(devicePixelRatio: 3));

    expect(key.bundle, same(CustomAssetsBundle.instance));
    expect(key.name, '$kCustomBoardAssetsFolder/pieces/1/wQ');
    expect(key.scale, 1.0);
  });

  testWidgets('chessground loads the custom piece images', (tester) async {
    const pieceSet = CustomPieceSet(id: '7', name: 'Glass');
    final asset = pieceSet.assets[PieceKind.whiteKing]!;
    writeFile(asset.assetName, piecePng(size: 96));
    addTearDown(() => ChessgroundImages.instance.evict(asset));

    final image = await tester.runAsync(() => ChessgroundImages.instance.load(asset));

    expect(image!.width, 96);
    expect(image.height, 96);
  });
}
