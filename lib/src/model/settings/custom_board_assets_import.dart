import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:archive/archive.dart';
import 'package:chessground/chessground.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

// The format of the custom boards and piece sets. It is described to the user on the custom
// board and pieces screen: keep that description in sync.

/// Smallest and largest side, in pixels, of a piece image.
const kCustomPieceMinSize = 64;
const kCustomPieceMaxSize = 1024;

/// Smallest and largest side, in pixels, of a board image.
const kCustomBoardMinSize = 256;
const kCustomBoardMaxSize = 2048;

/// Largest size of an image file.
const kCustomImageMaxBytes = 8 * 1024 * 1024;

/// Largest size of a picked file, and of the files of a zip file once extracted.
const kCustomImportMaxBytes = 40 * 1024 * 1024;

/// Largest number of entries of a zip file: a piece set needs 12 of them, the rest leaves room
/// for folders and files such as a license.
const _kMaxArchiveEntries = 100;

/// Extensions of the files looked at in a zip file, and accepted when picking images. Other files
/// of a zip file, such as a license or a readme, are ignored.
const _kImageExtensions = {'.png', '.webp', '.jpg', '.jpeg', '.gif', '.bmp', '.svg', '.heic'};

final _logger = Logger('CustomBoardAssetsImport');

/// A file picked by the user to import a custom board or piece set.
typedef PickedFile = ({String name, Uint8List bytes});

/// The reasons a board or a piece set could not be imported, as messages for the user.
class CustomAssetsImportException implements Exception {
  const CustomAssetsImportException(this.problems);

  final IList<String> problems;

  @override
  String toString() => 'CustomAssetsImportException: ${problems.join(' ')}';
}

/// A valid board image, with the square colors found in it.
typedef ValidBoard = ({Uint8List bytes, int lightSquareArgb, int darkSquareArgb});

/// Checks that [files] make a complete piece set and returns its images.
///
/// [files] is either a single zip file holding the images, or the images themselves. There must
/// be exactly one image per piece, named after [kCustomPieceCodes] (case does not matter), each a
/// square PNG or WebP image whose side is from [kCustomPieceMinSize] to [kCustomPieceMaxSize]
/// pixels. In a zip file the images can be in a folder, and files that are not images are
/// ignored.
///
/// Throws a [CustomAssetsImportException] listing every problem found, so that the user can fix
/// them all at once: a piece set is either imported whole or not at all.
IMap<PieceKind, Uint8List> validatePieceSet(List<PickedFile> files) {
  final problems = <String>[];
  final images = <PickedFile>[];

  final zips = files.where(_isZip).toList();
  if (zips.isNotEmpty) {
    if (files.length > 1) {
      throw const CustomAssetsImportException(
        IListConst(['Pick either a single .zip file, or the 12 piece images, not both.']),
      );
    }
    images.addAll(_readZip(zips.single));
  } else {
    images.addAll(files);
  }

  final found = <PieceKind, PickedFile>{};
  final duplicates = <PieceKind, List<String>>{};
  final unknown = <String>[];
  for (final file in images) {
    final baseName = p.posix.basename(file.name);
    if (!_kImageExtensions.contains(p.posix.extension(baseName).toLowerCase())) continue;
    final kind = _pieceKindOf(p.posix.basenameWithoutExtension(baseName));
    if (kind == null) {
      unknown.add(baseName);
    } else if (found[kind] case final previous?) {
      (duplicates[kind] ??= [p.posix.basename(previous.name)]).add(baseName);
    } else {
      found[kind] = file;
    }
  }

  if (found.isEmpty && unknown.isEmpty) {
    throw const CustomAssetsImportException(
      IListConst(['No piece images were found. A piece set needs 12 images, one per piece.']),
    );
  }

  final missing = [
    for (final MapEntry(key: kind, value: code) in kCustomPieceCodes.entries)
      if (!found.containsKey(kind)) code,
  ];
  if (missing.isNotEmpty) {
    problems.add(
      'Missing ${missing.length == 1 ? 'piece' : 'pieces'}: ${missing.join(', ')}. '
      'A piece set needs all 12 pieces.',
    );
  }
  for (final MapEntry(key: kind, value: names) in duplicates.entries) {
    problems.add('Several images for ${kCustomPieceCodes[kind]}: ${names.join(', ')}.');
  }
  if (unknown.isNotEmpty) {
    problems.add(
      'Not named after a piece: ${unknown.join(', ')}. '
      'Name the images ${kCustomPieceCodes.values.join(', ')}.',
    );
  }

  final pieces = <PieceKind, Uint8List>{};
  for (final MapEntry(key: kind, value: file) in found.entries) {
    final problem = _checkImage(
      file,
      formats: const {img.ImageFormat.png, img.ImageFormat.webp},
      formatsLabel: 'PNG or WebP',
      minSize: kCustomPieceMinSize,
      maxSize: kCustomPieceMaxSize,
    ).problem;
    if (problem != null) {
      problems.add(problem);
    } else {
      pieces[kind] = file.bytes;
    }
  }

  if (problems.isNotEmpty) throw CustomAssetsImportException(problems.lock);
  return pieces.lock;
}

/// Checks that [file] is a board image and returns it, with its square colors.
///
/// The image must be a square PNG, JPEG or WebP image of the whole board, whose side is from
/// [kCustomBoardMinSize] to [kCustomBoardMaxSize] pixels, with a8 at the top left. The light and
/// dark square colors are taken from the middle of h1 and a1.
///
/// Throws a [CustomAssetsImportException] if it is not.
ValidBoard validateBoard(PickedFile file) {
  if (_isZip(file)) {
    throw const CustomAssetsImportException(
      IListConst(['Pick a single image of the whole board, not a .zip file.']),
    );
  }
  final (:problem, :image) = _checkImage(
    file,
    formats: const {img.ImageFormat.png, img.ImageFormat.jpg, img.ImageFormat.webp},
    formatsLabel: 'PNG, JPEG or WebP',
    minSize: kCustomBoardMinSize,
    maxSize: kCustomBoardMaxSize,
  );
  if (problem != null) throw CustomAssetsImportException(IList([problem]));

  final squareSize = image!.width / 8;
  return (
    bytes: file.bytes,
    lightSquareArgb: _averageColor(image, file: 7, rank: 0, squareSize: squareSize),
    darkSquareArgb: _averageColor(image, file: 0, rank: 0, squareSize: squareSize),
  );
}

bool _isZip(PickedFile file) {
  if (p.posix.extension(file.name).toLowerCase() == '.zip') return true;
  // Zip files start with the "PK\x03\x04" signature.
  final bytes = file.bytes;
  return bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4B &&
      bytes[2] == 0x03 &&
      bytes[3] == 0x04;
}

/// The files of the [zip] file, leaving out folders and the hidden files added by macOS.
List<PickedFile> _readZip(PickedFile zip) {
  final invalid = CustomAssetsImportException(IList(['${zip.name} is not a valid .zip file.']));
  // Every zip file, even an empty one, starts with "PK": without it the decoder would find no
  // files rather than fail, which would hide that the file is not a zip file.
  final bytes = zip.bytes;
  if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) throw invalid;
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw invalid;
  }
  if (archive.length > _kMaxArchiveEntries) {
    throw CustomAssetsImportException(
      IList(['${zip.name} holds too many files: a piece set needs only 12 images.']),
    );
  }

  final files = <PickedFile>[];
  var totalBytes = 0;
  for (final entry in archive) {
    if (!entry.isFile || entry.isSymbolicLink) continue;
    final name = entry.name.replaceAll(r'\', '/');
    final isHidden = name
        .split('/')
        .any((segment) => segment.startsWith('.') || segment == '__MACOSX');
    if (isHidden) continue;
    if (!_kImageExtensions.contains(p.posix.extension(name).toLowerCase())) continue;

    // Checked before extracting, so that a zip bomb is never extracted, and again after, as the
    // declared size can't be trusted.
    totalBytes += entry.size;
    if (entry.size > kCustomImageMaxBytes || totalBytes > kCustomImportMaxBytes) {
      throw CustomAssetsImportException(IList(['${zip.name} holds images that are too large.']));
    }
    final Uint8List? entryBytes;
    try {
      entryBytes = entry.readBytes();
    } catch (e) {
      throw invalid;
    }
    if (entryBytes == null || entryBytes.length > kCustomImageMaxBytes) {
      throw CustomAssetsImportException(IList(['${zip.name} holds images that are too large.']));
    }
    files.add((name: name, bytes: entryBytes));
  }
  return files;
}

PieceKind? _pieceKindOf(String name) {
  final lowerName = name.toLowerCase();
  for (final MapEntry(key: kind, value: code) in kCustomPieceCodes.entries) {
    if (code.toLowerCase() == lowerName) return kind;
  }
  return null;
}

/// Checks that [file] is a square image of one of the [formats], whose side is from [minSize] to
/// [maxSize] pixels, and decodes it.
({String? problem, img.Image? image}) _checkImage(
  PickedFile file, {
  required Set<img.ImageFormat> formats,
  required String formatsLabel,
  required int minSize,
  required int maxSize,
}) {
  final name = p.posix.basename(file.name);
  ({String? problem, img.Image? image}) fail(String problem) => (problem: problem, image: null);

  final damaged = fail('$name could not be read: the image is damaged.');

  if (file.bytes.length > kCustomImageMaxBytes) {
    return fail('$name is too large: an image must be at most 8 MB.');
  }
  final img.Decoder? decoder;
  try {
    decoder = img.findDecoderForData(file.bytes);
  } catch (e) {
    return damaged;
  }
  if (decoder == null || !formats.contains(decoder.format)) {
    return fail('$name is not a $formatsLabel image.');
  }
  final img.DecodeInfo? info;
  try {
    info = decoder.startDecode(file.bytes);
  } catch (e) {
    return damaged;
  }
  if (info == null) return damaged;
  if (info.width != info.height) {
    return fail('$name must be square, it is ${info.width}×${info.height} pixels.');
  }
  if (info.width < minSize || info.width > maxSize) {
    return fail(
      '$name is ${info.width}×${info.height} pixels: it must be from $minSize×$minSize to '
      '$maxSize×$maxSize pixels.',
    );
  }
  final img.Image? image;
  try {
    image = decoder.decode(file.bytes);
  } catch (e) {
    return damaged;
  }
  if (image == null) return damaged;
  return (problem: null, image: image);
}

/// The average color, as ARGB, of the middle of a square of a board [image]. [file] and [rank]
/// count from a1, at the bottom left of the image.
int _averageColor(
  img.Image image, {
  required int file,
  required int rank,
  required double squareSize,
}) {
  final centerX = ((file + 0.5) * squareSize).floor();
  final centerY = ((7 - rank + 0.5) * squareSize).floor();
  final radius = (squareSize / 8).floor();
  var red = 0.0;
  var green = 0.0;
  var blue = 0.0;
  var count = 0;
  for (var y = centerY - radius; y <= centerY + radius; y++) {
    for (var x = centerX - radius; x <= centerX + radius; x++) {
      final pixel = image.getPixel(x, y);
      red += pixel.rNormalized.toDouble();
      green += pixel.gNormalized.toDouble();
      blue += pixel.bNormalized.toDouble();
      count++;
    }
  }
  int channel(double sum) => (sum / count * 255).round().clamp(0, 255);
  return 0xFF000000 | (channel(red) << 16) | (channel(green) << 8) | channel(blue);
}

/// Imports and removes the custom board and piece set of the user.
final customBoardAssetsImporterProvider = Provider<CustomBoardAssetsImporter>(
  CustomBoardAssetsImporter.new,
  name: 'CustomBoardAssetsImporterProvider',
);

/// Imports and removes the custom board and piece set of the user.
///
/// An import is all or nothing: the files are checked first, then written to a new folder, and
/// only once they are all written is the new board or piece set saved in the preferences. The
/// previous one is deleted last. If anything fails along the way, the preferences and the
/// previous board or piece set are left as they were.
class CustomBoardAssetsImporter {
  CustomBoardAssetsImporter(this._ref);

  final Ref _ref;

  BoardPreferences get _preferences => _ref.read(boardPreferencesProvider.notifier);

  /// Imports the piece set made of [files] and selects it, see [validatePieceSet].
  ///
  /// Throws a [CustomAssetsImportException] if [files] are not a complete piece set.
  Future<CustomPieceSet> importPieceSet(List<PickedFile> files) async {
    final pieces = await _validatePieceSetInIsolate(files);
    final pieceSet = CustomPieceSet(id: _newId(), name: _nameOf(files, 'Custom pieces'));

    final folder = await _directoryOf(pieceSet.folder);
    try {
      await folder.create(recursive: true);
      for (final MapEntry(key: kind, value: bytes) in pieces.entries) {
        await File(p.join(folder.path, kCustomPieceCodes[kind])).writeAsBytes(bytes, flush: true);
      }
      await _preferences.setCustomPieceSet(pieceSet);
    } catch (_) {
      await _deleteQuietly(folder);
      rethrow;
    }
    await _deleteOthers(folder);
    return pieceSet;
  }

  /// Imports the board image [file] and selects it, see [validateBoard].
  ///
  /// Throws a [CustomAssetsImportException] if [file] is not a board image.
  Future<CustomBoard> importBoard(PickedFile file) async {
    final valid = await _validateBoardInIsolate(file);
    final board = CustomBoard(
      id: _newId(),
      name: _nameOf([file], 'Custom board'),
      lightSquare: Color(valid.lightSquareArgb),
      darkSquare: Color(valid.darkSquareArgb),
    );

    final imageFile = await _fileOf(board.file);
    try {
      await imageFile.parent.create(recursive: true);
      await imageFile.writeAsBytes(valid.bytes, flush: true);
      await _preferences.setCustomBoard(board);
    } catch (_) {
      await _deleteQuietly(imageFile);
      rethrow;
    }
    await _deleteOthers(imageFile);
    return board;
  }

  /// Removes the custom piece set, going back to the piece set chosen before it was used.
  Future<void> removePieceSet() async {
    final pieceSet = _ref.read(boardPreferencesProvider).customPieceSet;
    await _preferences.setCustomPieceSet(null);
    if (pieceSet != null) await _deleteQuietly(await _directoryOf(pieceSet.folder));
  }

  /// Removes the custom board, going back to the board chosen before it was used.
  Future<void> removeBoard() async {
    final board = _ref.read(boardPreferencesProvider).customBoard;
    await _preferences.setCustomBoard(null);
    if (board != null) await _deleteQuietly(await _fileOf(board.file));
  }

  Future<File> _fileOf(String relativePath) => CustomAssetsBundle.instance.fileFor(relativePath);

  Future<Directory> _directoryOf(String relativePath) async {
    return Directory((await _fileOf(relativePath)).path);
  }

  /// Deletes the siblings of [kept]: the previous import, and any import interrupted before it
  /// was saved in the preferences.
  Future<void> _deleteOthers(FileSystemEntity kept) async {
    try {
      await for (final entity in kept.parent.list(followLinks: false)) {
        if (entity.path != kept.path) await _deleteQuietly(entity);
      }
    } catch (e, st) {
      _logger.warning('Could not clean up custom board assets', e, st);
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (await entity.exists()) await entity.delete(recursive: true);
    } catch (e, st) {
      _logger.warning('Could not delete ${entity.path}', e, st);
    }
  }
}

// The checks decode every image, which takes a while: they run in another isolate, so as not to
// freeze the app. These are top-level functions so that the closures sent to the isolate only
// capture the files.

Future<IMap<PieceKind, Uint8List>> _validatePieceSetInIsolate(List<PickedFile> files) {
  return Isolate.run(() => validatePieceSet(files));
}

Future<ValidBoard> _validateBoardInIsolate(PickedFile file) {
  return Isolate.run(() => validateBoard(file));
}

var _lastId = 0;

/// A new id for an import, which also names its files: the time of the import, made unique even
/// if the clock is too coarse to tell two imports apart.
String _newId() {
  final now = DateTime.now().microsecondsSinceEpoch;
  _lastId = now > _lastId ? now : _lastId + 1;
  return '$_lastId';
}

/// A name for an import: the name of the zip file or of the single image, else [fallback].
String _nameOf(List<PickedFile> files, String fallback) {
  if (files.length != 1) return fallback;
  final name = p.posix.basenameWithoutExtension(files.single.name.replaceAll(r'\', '/')).trim();
  return name.isEmpty ? fallback : name;
}
