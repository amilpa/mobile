import 'dart:ui' as ui;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';

// Boards and piece sets of LichessNeo (MIT, Théophile Wallez), see `assets/neo/LICENSE`.

/// Size at which a board texture is decoded in thumbnails.
///
/// The textures are bundled at 1024px, downscaled from LichessNeo's 2048px, which is plenty for
/// a phone board.
const _kThumbnailTextureSize = 512;

/// A LichessNeo material board: a grey relief texture blended over two square colors.
enum NeoBoard(final String label, final Color lightSquare, final Color darkSquare) {
  burlGloss('Glossy burl', Color(0xFFFBD19A), Color(0xFF6D3B25)),
  burl('Burl', Color(0xFFD9AA77), Color(0xFF603926)),
  vavona('Vavona', Color(0xFFD9AD7D), Color(0xFF803E28)),
  cocobolo('Cocobolo', Color(0xFFF9C88F), Color(0xFF680B02)),
  amboyna('Amboyna', Color(0xFFFCCE95), Color(0xFFB9440C)),
  olmo('Olmo', Color(0xFFECDAB1), Color(0xFF92401A)),
  padauk('Padauk', Color(0xFFF7CC97), Color(0xFFB81A03)),
  palisander('Palisander', Color(0xFFF2BE89), Color(0xFF4A2B22)),
  pomelle('Pomelle', Color(0xFFFCDCAC), Color(0xFFC54810)),
  portoro('Portoro', Color(0xFFEEF1EA), Color(0xFF37332B)),
  marble('Marble', Color(0xFFF7F5EF), Color(0xFF636B77)),
  terrazzo('Terrazzo', Color(0xFFEFEBE6), Color(0xFF3F49A7)),
  slate('Slate', Color(0xFFD0CCC1), Color(0xFF545F6C)),
  brushed('Brushed metal', Color(0xFFD4D7DD), Color(0xFF414B9F)),
  spun('Spun metal', Color(0xFFD9DADD), Color(0xFF977F4F)),
  zellige('Zellige', Color(0xFFE9E3D8), Color(0xFF2D7981)),
  felt('Felt', Color(0xFFE6DFCF), Color(0xFF275C4C)),
  leather('Leather', Color(0xFFCCB08C), Color(0xFF734635)),
  blueprint('Blueprint', Color(0xFF5B94E2), Color(0xFF1F468D)),
  halftone('Halftone', Color(0xFFF3EEE3), Color(0xFFB6B8DC)),
  cork('Cork', Color(0xFFD0A573), Color(0xFF60422D));

  /// File name of the texture, as named in LichessNeo.
  String get _fileName => switch (this) {
    NeoBoard.burlGloss => 'burl-gloss',
    _ => name,
  };

  AssetImage get _texture => AssetImage('assets/neo/boards/$_fileName.webp');

  ImageProvider get boardTexture => _texture;

  ImageProvider get thumbnailTexture => ResizeImage(_texture, width: _kThumbnailTextureSize);

  ChessboardColorScheme get colors => _colorSchemes[this] ??= ChessboardColorScheme(
    lightSquare: lightSquare,
    darkSquare: darkSquare,
    background: NeoBoardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      texture: boardTexture,
    ),
    whiteCoordBackground: NeoBoardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      texture: boardTexture,
      coordinates: true,
    ),
    blackCoordBackground: NeoBoardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      texture: boardTexture,
      coordinates: true,
      orientation: Side.black,
    ),
    lastMove: const HighlightDetails(solidColor: Color(0x809CC700)),
    selected: const HighlightDetails(solidColor: Color(0x6014551E)),
    validMoves: const Color(0x4014551E),
    validPremoves: const Color(0x40203085),
  );

  /// A strip of six squares of the board, for board pickers.
  Widget get thumbnail => SizedBox(
    height: 44,
    width: 44 * 6,
    child: NeoBoardBackground(
      lightSquare: lightSquare,
      darkSquare: darkSquare,
      texture: thumbnailTexture,
      files: 6,
      ranks: 1,
    ),
  );

  static final Map<NeoBoard, ChessboardColorScheme> _colorSchemes = {};
}

/// A LichessNeo piece set.
enum NeoPieceSet(final String label) {
  mochi('Mochi'),
  mellow('Mellow'),
  poppy('Poppy'),
  bop('Bop'),
  pebble('Pebble'),
  loop('Loop'),
  fold('Fold'),
  bitty('Bitty');

  PieceAssets get assets => _assets[this] ??= {
    for (final kind in PieceKind.values)
      kind: AssetImage('assets/neo/pieces/$name/${_code(kind)}.webp'),
  };

  static String _code(PieceKind kind) => switch (kind) {
    PieceKind.whitePawn => 'wP',
    PieceKind.whiteKnight => 'wN',
    PieceKind.whiteBishop => 'wB',
    PieceKind.whiteRook => 'wR',
    PieceKind.whiteQueen => 'wQ',
    PieceKind.whiteKing => 'wK',
    PieceKind.blackPawn => 'bP',
    PieceKind.blackKnight => 'bN',
    PieceKind.blackBishop => 'bB',
    PieceKind.blackRook => 'bR',
    PieceKind.blackQueen => 'bQ',
    PieceKind.blackKing => 'bK',
  };

  static final Map<NeoPieceSet, PieceAssets> _assets = {};
}

/// A board background made of two square colors with a relief texture over them, blended in
/// hard light: mid-grey leaves a square's color as it is, darker darkens it and lighter lightens
/// it.
class NeoBoardBackground extends ChessboardBackground {
  const NeoBoardBackground({
    super.key,
    super.coordinates,
    super.orientation,
    required super.lightSquare,
    required super.darkSquare,
    required this.texture,
    this.files = 8,
    this.ranks = 8,
  });

  final ImageProvider texture;

  /// Number of squares across and down.
  final int files;
  final int ranks;

  @override
  Widget build(BuildContext context) {
    return _TexturedChecker(background: this);
  }
}

class _TexturedChecker extends StatefulWidget {
  const _TexturedChecker({required this.background});

  final NeoBoardBackground background;

  @override
  State<_TexturedChecker> createState() => _TexturedCheckerState();
}

class _TexturedCheckerState extends State<_TexturedChecker> {
  ImageStream? _stream;
  ImageInfo? _imageInfo;
  late final ImageStreamListener _listener = ImageStreamListener((info, _) {
    if (!mounted) {
      info.dispose();
      return;
    }
    setState(() {
      _imageInfo?.dispose();
      _imageInfo = info;
    });
  });

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTexture();
  }

  @override
  void didUpdateWidget(_TexturedChecker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.background.texture != widget.background.texture) _resolveTexture();
  }

  void _resolveTexture() {
    final stream = widget.background.texture.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _stream = stream..addListener(_listener);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _imageInfo?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.background;
    return CustomPaint(
      size: Size.infinite,
      painter: _TexturedCheckerPainter(
        lightSquare: background.lightSquare,
        darkSquare: background.darkSquare,
        texture: _imageInfo?.image,
        files: background.files,
        ranks: background.ranks,
        coordinates: background.coordinates,
        orientation: background.orientation,
      ),
    );
  }
}

class _TexturedCheckerPainter extends CustomPainter {
  _TexturedCheckerPainter({
    required this.lightSquare,
    required this.darkSquare,
    required this.texture,
    required this.files,
    required this.ranks,
    required this.coordinates,
    required this.orientation,
  });

  final Color lightSquare;
  final Color darkSquare;
  final ui.Image? texture;
  final int files;
  final int ranks;
  final bool coordinates;
  final Side orientation;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final squareWidth = size.width / files;
    final squareHeight = size.height / ranks;

    // The texture is blended with the squares only, not with what is behind the board.
    canvas.saveLayer(rect, Paint());
    for (var rank = 0; rank < ranks; rank++) {
      for (var file = 0; file < files; file++) {
        canvas.drawRect(
          Rect.fromLTWH(file * squareWidth, rank * squareHeight, squareWidth, squareHeight),
          Paint()..color = (rank + file).isEven ? lightSquare : darkSquare,
        );
      }
    }
    if (texture != null) {
      // The texture is cut into the 8x8 squares of a board, each with its own shading: only as
      // many of its squares as painted are drawn, so that they line up with the painted ones.
      final image = texture!;
      final source = Rect.fromLTWH(
        0,
        0,
        image.width * files / 8,
        image.height * ranks / 8,
      );
      canvas.drawImageRect(
        image,
        source,
        rect,
        Paint()
          ..blendMode = BlendMode.hardLight
          ..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();

    if (coordinates) _paintCoordinates(canvas, squareWidth, squareHeight);
  }

  void _paintCoordinates(Canvas canvas, double squareWidth, double squareHeight) {
    const edgeOffset = 2.0;
    TextPainter coordinate(String text, Color color) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          inherit: false,
          fontWeight: FontWeight.bold,
          fontSize: 10.0,
          color: color,
          fontFamily: 'Roboto',
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    for (var rank = 0; rank < ranks; rank++) {
      final file = files - 1;
      final color = (rank + file).isEven ? darkSquare : lightSquare;
      final painter = coordinate(
        orientation == Side.white ? '${ranks - rank}' : '${rank + 1}',
        color,
      );
      painter.paint(
        canvas,
        Offset(
          file * squareWidth + squareWidth - painter.width - edgeOffset,
          rank * squareHeight + edgeOffset,
        ),
      );
    }
    for (var file = 0; file < files; file++) {
      final rank = ranks - 1;
      final color = (rank + file).isEven ? darkSquare : lightSquare;
      final painter = coordinate(
        String.fromCharCode(orientation == Side.white ? 97 + file : 97 + files - 1 - file),
        color,
      );
      painter.paint(
        canvas,
        Offset(
          file * squareWidth + edgeOffset,
          rank * squareHeight + squareHeight - painter.height - edgeOffset,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(_TexturedCheckerPainter oldDelegate) =>
      oldDelegate.texture != texture ||
      oldDelegate.lightSquare != lightSquare ||
      oldDelegate.darkSquare != darkSquare ||
      oldDelegate.coordinates != coordinates ||
      oldDelegate.orientation != orientation ||
      oldDelegate.files != files ||
      oldDelegate.ranks != ranks;
}
