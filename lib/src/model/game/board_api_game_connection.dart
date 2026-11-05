import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:deep_pick/deep_pick.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:http/http.dart' show Request;
import 'package:lichess_mobile/src/model/chat/chat_message.dart';
import 'package:lichess_mobile/src/model/common/chess.dart';
import 'package:lichess_mobile/src/model/common/id.dart';
import 'package:lichess_mobile/src/model/common/socket.dart';
import 'package:lichess_mobile/src/network/http.dart';
import 'package:logging/logging.dart';

final _logger = Logger('BoardApiGameConnection');

/// Delay before reopening the game stream after it was closed or failed.
const _kReconnectDelay = Duration(seconds: 2);

/// Connection to one of the user's games, played through the lichess Board API.
///
/// The game is streamed as ND-JSON from `/api/board/game/stream/{id}`, and actions are sent as HTTP
/// requests. This works with a personal API token holding the `board:play` scope, unlike the
/// `/play` socket which requires the `web:mobile` scope only the official app can use.
///
/// Board API events are translated into the events the `/play` socket used to emit (`full`,
/// `move`, `endData`, `drawOffer`, ...), so that the game controller can handle them unchanged.
/// The players' chat is relayed as `message` events, as on the socket. What the Board API does not
/// provide (more time, rematch, spectators and their chat) is unavailable.
class BoardApiGameConnection {
  BoardApiGameConnection({
    required LichessClient Function() client,
    required this.gameFullId,
    required this.myUserId,
  }) : _client = client;

  final LichessClient Function() _client;
  final GameFullId gameFullId;
  final UserId? myUserId;

  final StreamController<SocketEvent> _events = StreamController<SocketEvent>.broadcast();
  StreamSubscription<String>? _subscription;
  Timer? _reconnectTimer;

  bool _isDisposed = false;
  bool _isConnected = false;

  /// Increased on each [connect], to ignore the callbacks of a previous stream.
  int _connectionId = 0;

  /// Whether a `gameFull` event was ever received.
  bool _hasReceivedGame = false;

  /// The last `gameFull` event, holding the game data that never changes.
  Map<String, dynamic>? _gameFull;

  /// The last known game state.
  _BoardState? _state;

  /// The position after the moves of [_state].
  Position? _lastPosition;

  GameId get _gameId => gameFullId.gameId;

  /// Socket-like events of the game. The first one is always `full`.
  Stream<SocketEvent> get stream => _events.stream;

  bool get isDisposed => _isDisposed;

  /// Whether the game stream is currently open.
  bool get isConnected => _isConnected;

  bool get _isFinished =>
      _state != null && _state!.status != 'started' && _state!.status != 'created';

  /// Opens the game stream, closing the current one if any.
  ///
  /// The stream always starts with a `gameFull` event, so reconnecting also resyncs the game.
  void connect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _isConnected = false;
    final connectionId = ++_connectionId;
    _open(connectionId);
  }

  Future<void> _open(int connectionId) async {
    try {
      final response = await _client().send(
        Request('GET', lichessUri('/api/board/game/stream/${_gameId.value}')),
      );
      if (_isDisposed || connectionId != _connectionId) return;

      if (response.statusCode >= 400) {
        final error = ServerException(
          response.statusCode,
          'Could not open the game stream: ${response.statusCode}',
          lichessUri('/api/board/game/stream/${_gameId.value}'),
          null,
        );
        // Without a first game there is nothing to show: report it instead of retrying forever.
        if (!_hasReceivedGame) {
          _events.addError(error);
          return;
        }
        throw error;
      }

      _isConnected = true;
      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (Object e, StackTrace st) {
              if (connectionId != _connectionId) return;
              _logger.warning('Game stream error', e, st);
              _isConnected = false;
              _scheduleReconnect();
            },
            onDone: () {
              if (connectionId != _connectionId) return;
              _isConnected = false;
              // The server closes the stream once the game is over.
              if (!_isFinished) _scheduleReconnect();
            },
          );
    } catch (e, st) {
      if (_isDisposed || connectionId != _connectionId) return;
      _logger.warning('Could not open the game stream', e, st);
      _isConnected = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_kReconnectDelay, connect);
  }

  /// Closes the game stream until the next [connect].
  void close() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _isConnected = false;
    _connectionId++;
  }

  void dispose() {
    close();
    _isDisposed = true;
    _events.close();
  }

  void _emit(String topic, Object? data) {
    if (_isDisposed) return;
    _events.add(SocketEvent(topic: topic, data: data));
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return; // keep-alive
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(line) as Map<String, dynamic>;
    } catch (e, st) {
      _logger.warning('Could not decode game stream line: $line', e, st);
      return;
    }

    try {
      switch (json['type']) {
        case 'gameFull':
          _gameFull = json;
          _state = _BoardState.fromJson(json['state'] as Map<String, dynamic>);
          _lastPosition = _positionAfter(_state!.moves);
          _hasReceivedGame = true;
          _emit('full', _fullEventData());
        case 'gameState':
          _onGameState(_BoardState.fromJson(json));
        case 'opponentGone':
          _onOpponentGone(json);
        case 'chatLine':
          // Only the players' room: the spectators' one is not shown to the players.
          if (json['room'] == 'player') {
            _emit('message', {'u': json['username'], 't': json['text']});
          }
      }
    } catch (e, st) {
      _logger.severe('Could not handle game stream event: $line', e, st);
    }
  }

  void _onGameState(_BoardState next) {
    final prev = _state;
    if (prev == null || _gameFull == null) return;
    _state = next;

    final isNextMove =
        next.moves.length == prev.moves.length + 1 &&
        const ListEquality<String>().equals(
          next.moves.sublist(0, prev.moves.length),
          prev.moves,
        );

    if (isNextMove) {
      final uci = next.moves.last;
      final (newPos, san) = _lastPosition!.makeSan(Move.parse(uci)!);
      _lastPosition = newPos;
      _emit('move', {
        'uci': uci,
        'san': san,
        'ply': next.moves.length,
        'clock': {'white': next.wtime, 'black': next.btime},
        if (next.status != 'started') 'status': next.status,
        'winner': next.winner,
      });
    } else if (!const ListEquality<String>().equals(next.moves, prev.moves)) {
      // A takeback, or several moves missed: resync the whole game.
      _lastPosition = _positionAfter(next.moves);
      _emit('full', _fullEventData());
    }

    if (next.wdraw != prev.wdraw || next.bdraw != prev.bdraw) {
      _emit('drawOffer', next.wdraw ? 'white' : (next.bdraw ? 'black' : null));
    }

    if (next.wtakeback != prev.wtakeback || next.btakeback != prev.btakeback) {
      _emit('takebackOffers', {'white': next.wtakeback, 'black': next.btakeback});
    }

    final wasPlaying = prev.status == 'started' || prev.status == 'created';
    if (wasPlaying && _isFinished) {
      _emit('endData', {
        'status': next.status,
        'winner': next.winner,
        if (_gameFull!['clock'] != null)
          'clock': {
            'wc': next.wtime.inMilliseconds ~/ 10,
            'bc': next.btime.inMilliseconds ~/ 10,
          },
      });
    }
  }

  void _onOpponentGone(Map<String, dynamic> json) {
    final gone = json['gone'] as bool? ?? false;
    final opponent = _mySide == Side.white ? 'black' : 'white';
    _emit('crowd', {opponent: !gone});
    _emit('gone', gone);
    final claimWinInSeconds = json['claimWinInSeconds'] as int?;
    if (gone && claimWinInSeconds != null) {
      _emit('goneIn', claimWinInSeconds);
    }
  }

  Side get _mySide {
    final white = _gameFull?['white'] as Map<String, dynamic>?;
    return white?['id'] == myUserId?.value ? Side.white : Side.black;
  }

  Variant get _variant => pick(_gameFull, 'variant').asVariantOrThrow();

  String? get _initialFen {
    final fen = _gameFull?['initialFen'] as String?;
    return fen == null || fen == 'startpos' ? null : fen;
  }

  Position get _initialPosition {
    final variant = _variant;
    final fen = _initialFen;
    return (variant == Variant.fromPosition || variant == Variant.chess960) && fen != null
        ? Chess.fromSetup(Setup.parseFen(fen))
        : variant.initialPosition;
  }

  Position _positionAfter(List<String> moves) {
    Position pos = _initialPosition;
    for (final uci in moves) {
      pos = pos.playUnchecked(Move.parse(uci)!);
    }
    return pos;
  }

  List<String> _sanMoves(List<String> moves) {
    Position pos = _initialPosition;
    final sans = <String>[];
    for (final uci in moves) {
      final (newPos, san) = pos.makeSan(Move.parse(uci)!);
      pos = newPos;
      sans.add(san);
    }
    return sans;
  }

  /// Builds the data of a `/play` socket `full` event from the Board API game.
  Map<String, dynamic> _fullEventData() {
    final full = _gameFull!;
    final state = _state!;
    final speed = full['speed'] as String;
    final clock = full['clock'] as Map<String, dynamic>?;
    final white = full['white'] as Map<String, dynamic>;
    final black = full['black'] as Map<String, dynamic>;
    final isPlaying = state.status == 'started' || state.status == 'created';
    final hasAI = white['aiLevel'] != null || black['aiLevel'] != null;

    return {
      'socket': 0,
      'game': {
        'id': _gameId.value,
        'source': hasAI ? 'ai' : 'lobby',
        'status': state.status,
        'winner': state.winner,
        'initialFen': _initialFen,
        'pgn': _sanMoves(state.moves).join(' '),
        'createdAt': full['createdAt'],
        'rated': full['rated'],
        'speed': speed,
        'perf': pick(full, 'perf', 'name').asStringOrNull() ?? speed,
        'variant': _variant,
        // The Board API has no rematch.
        'rules': ['noRematch'],
      },
      'white': _playerData(white, offeringDraw: state.wdraw, proposingTakeback: state.wtakeback),
      'black': _playerData(black, offeringDraw: state.bdraw, proposingTakeback: state.btakeback),
      if (clock != null)
        'clock': {
          // The clock only starts once both players have moved.
          'running': isPlaying && state.moves.length >= 2,
          'white': state.wtime,
          'black': state.btime,
          'initial': Duration(milliseconds: clock['initial'] as int),
          'increment': Duration(milliseconds: clock['increment'] as int),
        },
      if (clock == null && speed == 'correspondence')
        'correspondence': {
          'daysPerTurn': full['daysPerTurn'] as int? ?? 1,
          'white': state.wtime,
          'black': state.btime,
        },
      'youAre': _mySide.name,
      'takebackable': !hasAI,
      'moretimeable': false,
    };
  }

  Map<String, dynamic> _playerData(
    Map<String, dynamic> player, {
    required bool offeringDraw,
    required bool proposingTakeback,
  }) {
    final id = player['id'] as String?;
    return {
      if (id != null) 'user': {'id': id, 'name': player['name'] ?? id, 'title': player['title']},
      'rating': player['rating'],
      'provisional': player['provisional'],
      'aiLevel': player['aiLevel'],
      'onGame': true,
      'offeringDraw': offeringDraw,
      'proposingTakeback': proposingTakeback,
    };
  }

  /// Plays [move] in the game.
  ///
  /// Resyncs the game if the server refuses it, so that the board does not keep a move that was
  /// never played.
  Future<void> sendMove(Move move) async {
    final ok = await _post('move/${move.uci}');
    if (!ok) connect();
  }

  /// Sends the action of a `/play` socket [topic], if the Board API supports it.
  void send(String topic) {
    final action = switch (topic) {
      'abort' => 'abort',
      'resign' => 'resign',
      'resign-force' => 'claim-victory',
      'draw-claim' || 'draw-force' => 'claim-draw',
      'draw-yes' => 'draw/yes',
      'draw-no' => 'draw/no',
      'takeback-yes' => 'takeback/yes',
      'takeback-no' => 'takeback/no',
      'berserk' => 'berserk',
      // Not supported by the Board API: the server flags players on its own, and there is no more
      // time or rematch.
      _ => null,
    };
    if (action == null) {
      _logger.info('Board API does not support $topic');
      return;
    }
    _post(action);
  }

  /// The messages of the players' chat so far, oldest first.
  Future<IList<ChatMessage>> fetchChat() {
    return _client().readJsonList(
      Uri(path: '/api/board/game/${_gameId.value}/chat'),
      mapper: (json) => ChatMessage(
        message: json['text'] as String,
        username: json['user'] as String?,
        troll: false,
        deleted: false,
      ),
    );
  }

  /// Posts [text] to the players' chat.
  ///
  /// The message is not added locally: the game stream sends it back as a `message` event, like
  /// the opponent's ones.
  Future<bool> sendChat(String text) {
    return _post('chat', body: {'room': 'player', 'text': text});
  }

  Future<bool> _post(String action, {Map<String, String>? body}) async {
    final uri = Uri(path: '/api/board/game/${_gameId.value}/$action');
    try {
      final response = await _client().post(uri, body: body);
      if (response.statusCode >= 400) {
        _logger.warning('$uri failed with ${response.statusCode}: ${response.body}');
        return false;
      }
      return true;
    } catch (e, st) {
      _logger.warning('$uri failed', e, st);
      return false;
    }
  }
}

/// The `state` of a Board API game.
class _BoardState {
  const _BoardState({
    required this.moves,
    required this.wtime,
    required this.btime,
    required this.status,
    required this.winner,
    required this.wdraw,
    required this.bdraw,
    required this.wtakeback,
    required this.btakeback,
  });

  factory _BoardState.fromJson(Map<String, dynamic> json) {
    final moves = (json['moves'] as String? ?? '').trim();
    return _BoardState(
      moves: moves.isEmpty ? const [] : moves.split(' '),
      wtime: Duration(milliseconds: json['wtime'] as int? ?? 0),
      btime: Duration(milliseconds: json['btime'] as int? ?? 0),
      status: json['status'] as String? ?? 'started',
      winner: json['winner'] as String?,
      wdraw: json['wdraw'] as bool? ?? false,
      bdraw: json['bdraw'] as bool? ?? false,
      wtakeback: json['wtakeback'] as bool? ?? false,
      btakeback: json['btakeback'] as bool? ?? false,
    );
  }

  final List<String> moves;
  final Duration wtime;
  final Duration btime;
  final String status;
  final String? winner;
  final bool wdraw;
  final bool bdraw;
  final bool wtakeback;
  final bool btakeback;
}
