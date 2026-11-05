import 'dart:async';
import 'dart:io';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show PieceKind, Side;
import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' show getApplicationSupportDirectory;

/// Folder, in the app support directory, holding the custom board and piece set of the user.
const kCustomBoardAssetsFolder = 'custom_board_assets';

/// File names, without extension, of the images of a custom piece set: `w` or `b` for the side,
/// followed by the letter of the piece. These are the names used by lichess and by most piece
/// set sources.
const kCustomPieceCodes = <PieceKind, String>{
  PieceKind.whiteKing: 'wK',
  PieceKind.whiteQueen: 'wQ',
  PieceKind.whiteRook: 'wR',
  PieceKind.whiteBishop: 'wB',
  PieceKind.whiteKnight: 'wN',
  PieceKind.whitePawn: 'wP',
  PieceKind.blackKing: 'bK',
  PieceKind.blackQueen: 'bQ',
  PieceKind.blackRook: 'bR',
  PieceKind.blackBishop: 'bB',
  PieceKind.blackKnight: 'bN',
  PieceKind.blackPawn: 'bP',
};

/// A piece set imported by the user, see `custom_board_assets_import.dart`.
///
/// Its images are stored in the app support directory, in a folder named after [id]. Only that
/// [id] is kept in the preferences, not the full path: on iOS the path of the app directories
/// changes across app updates.
@immutable
class const CustomPieceSet({required final String id, required final String name}) {
  factory fromJson(Map<String, dynamic> json) {
    return CustomPieceSet(id: json['id'] as String, name: json['name'] as String);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  /// Path of the folder of the images, relative to the app support directory.
  String get folder => '$kCustomBoardAssetsFolder/pieces/$id';

  /// The images of the set, read from the disk by [CustomAssetsBundle].
  ///
  /// Each import gets a new [id], so the image caches, which are keyed by path, never show the
  /// images of a previous import.
  PieceAssets get assets => _assets[id] ??= {
    for (final MapEntry(key: kind, value: code) in kCustomPieceCodes.entries)
      kind: AssetImage('$folder/$code', bundle: CustomAssetsBundle.instance),
  };

  static final Map<String, PieceAssets> _assets = {};

  @override
  bool operator ==(Object other) => other is CustomPieceSet && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

/// A board imported by the user: a square image of the whole board, see
/// `custom_board_assets_import.dart`.
///
/// The square colors are taken from the image when it is imported. They are used for the
/// coordinates and the border drawn over the board.
@immutable
class const CustomBoard({
  required final String id,
  required final String name,
  required final Color lightSquare,
  required final Color darkSquare,
}) {
  factory fromJson(Map<String, dynamic> json) {
    return CustomBoard(
      id: json['id'] as String,
      name: json['name'] as String,
      lightSquare: Color(json['lightSquare'] as int),
      darkSquare: Color(json['darkSquare'] as int),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lightSquare': lightSquare.toARGB32(),
    'darkSquare': darkSquare.toARGB32(),
  };

  /// Path of the image, relative to the app support directory.
  String get file => '$kCustomBoardAssetsFolder/boards/$id';

  AssetImage get image => AssetImage(file, bundle: CustomAssetsBundle.instance);

  ChessboardColorScheme get colors => _colorSchemes[id] ??= ChessboardColorScheme(
    lightSquare: lightSquare,
    darkSquare: darkSquare,
    background: ImageChessboardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      image: image,
    ),
    whiteCoordBackground: ImageChessboardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      image: image,
      coordinates: true,
    ),
    blackCoordBackground: ImageChessboardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      image: image,
      coordinates: true,
      orientation: Side.black,
    ),
    lastMove: const HighlightDetails(solidColor: Color(0x809CC700)),
    selected: const HighlightDetails(solidColor: Color(0x6014551E)),
    validMoves: const Color(0x4014551E),
    validPremoves: const Color(0x40203085),
  );

  /// The first six squares of the top rank of the board, for board pickers.
  Widget get thumbnail => SizedBox(
    height: 44,
    width: 44 * 6,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: 44 * 8,
        maxWidth: 44 * 8,
        minHeight: 44 * 8,
        maxHeight: 44 * 8,
        child: Image(
          image: ResizeImage(image, width: 512),
          fit: BoxFit.fill,
          errorBuilder: (context, error, stackTrace) => ColoredBox(color: darkSquare),
        ),
      ),
    ),
  );

  static final Map<String, ChessboardColorScheme> _colorSchemes = {};

  @override
  bool operator ==(Object other) =>
      other is CustomBoard &&
      other.id == id &&
      other.name == name &&
      other.lightSquare == lightSquare &&
      other.darkSquare == darkSquare;

  @override
  int get hashCode => Object.hash(id, name, lightSquare, darkSquare);
}

/// An [AssetBundle] reading the images of the custom board and piece set from the disk.
///
/// chessground only takes [AssetImage]s, which are loaded from an [AssetBundle]: this bundle lets
/// [AssetImage]s point at files of the app support directory. Its keys are paths relative to that
/// directory, with `/` separators.
class CustomAssetsBundle extends AssetBundle {
  CustomAssetsBundle._();

  static final instance = CustomAssetsBundle._();

  /// Directory used instead of the app support directory, for tests.
  @visibleForTesting
  static Directory? debugRootDirectory;

  Future<Directory>? _supportDirectory;

  /// The directory the keys of this bundle are relative to.
  Future<Directory> rootDirectory() {
    final debugDirectory = debugRootDirectory;
    if (debugDirectory != null) return Future.value(debugDirectory);
    return _supportDirectory ??= getApplicationSupportDirectory();
  }

  /// The file of the [key] of this bundle.
  Future<File> fileFor(String key) async {
    final root = await rootDirectory();
    return File(p.joinAll([root.path, ...key.split('/')]));
  }

  @override
  Future<ByteData> load(String key) async {
    final bytes = await (await fileFor(key)).readAsBytes();
    return ByteData.sublistView(bytes);
  }

  @override
  Future<T> loadStructuredBinaryData<T>(String key, FutureOr<T> Function(ByteData data) parser) {
    // [AssetImage] reads the manifest of its bundle to look for resolution variants of the
    // image. The files of this bundle have none: an empty manifest makes [AssetImage] load the
    // key as it is. Answered synchronously, so that images don't wait a frame for it.
    if (key == _kAssetManifest) {
      final manifest = parser(_emptyManifest);
      return manifest is Future<T> ? manifest : SynchronousFuture<T>(manifest);
    }
    return load(key).then(parser);
  }

  static const _kAssetManifest = 'AssetManifest.bin';

  static final ByteData _emptyManifest = const StandardMessageCodec().encodeMessage(
    <Object?, Object?>{},
  )!;
}
