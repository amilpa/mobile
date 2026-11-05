import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:lichess_mobile/src/model/settings/custom_board_assets.dart';
import 'package:lichess_mobile/src/model/settings/custom_board_assets_import.dart';

/// Colors of the light and dark squares of [boardPng].
const kTestLightSquare = 0xFFF0D9B5;
const kTestDarkSquare = 0xFFB58863;

/// A PNG image of a single color, with transparency.
Uint8List piecePng({int size = 128, int? height}) {
  final image = img.Image(width: size, height: height ?? size, numChannels: 4);
  image.clear(img.ColorRgba8(20, 40, 60, 255));
  return img.encodePng(image);
}

/// A JPEG image of a single color.
Uint8List plainJpg({int size = 128}) {
  final image = img.Image(width: size, height: size);
  image.clear(img.ColorRgb8(20, 40, 60));
  return img.encodeJpg(image);
}

/// A GIF image of a single color.
Uint8List plainGif({int size = 256}) {
  final image = img.Image(width: size, height: size);
  image.clear(img.ColorRgb8(20, 40, 60));
  return img.encodeGif(image);
}

/// A board image of [width]×[height] pixels: a checkerboard of [kTestLightSquare] and
/// [kTestDarkSquare], with a8 light at the top left.
img.Image boardImage({int width = 256, int? height}) {
  final imageHeight = height ?? width;
  final image = img.Image(width: width, height: imageHeight);
  final squareWidth = width / 8;
  final squareHeight = imageHeight / 8;
  for (var y = 0; y < imageHeight; y++) {
    for (var x = 0; x < width; x++) {
      final isLight = ((x ~/ squareWidth) + (y ~/ squareHeight)).isEven;
      final color = isLight ? kTestLightSquare : kTestDarkSquare;
      image.setPixelRgb(x, y, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF);
    }
  }
  return image;
}

Uint8List boardPng({int width = 256, int? height}) {
  return img.encodePng(boardImage(width: width, height: height));
}

Uint8List boardJpg() => img.encodeJpg(boardImage());

/// The 12 images of a complete piece set, named [prefix] + code + [extension].
List<PickedFile> pieceFiles({
  String prefix = '',
  String extension = '.png',
  Iterable<String>? codes,
  Uint8List? bytes,
}) {
  final image = bytes ?? piecePng();
  return [
    for (final code in codes ?? kCustomPieceCodes.values)
      (name: '$prefix$code$extension', bytes: image),
  ];
}

/// The piece codes, without the given ones.
Iterable<String> codesWithout(Set<String> left) {
  return kCustomPieceCodes.values.where((code) => !left.contains(code));
}

/// A zip file holding [files].
Uint8List zipOf(List<PickedFile> files) {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(ArchiveFile.bytes(file.name, file.bytes));
  }
  return ZipEncoder().encodeBytes(archive);
}
