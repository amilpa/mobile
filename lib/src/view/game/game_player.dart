import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/account/account_repository.dart';
import 'package:lichess_mobile/src/model/game/game.dart';
import 'package:lichess_mobile/src/model/game/material_diff.dart';
import 'package:lichess_mobile/src/model/settings/board_preferences.dart';
import 'package:lichess_mobile/src/network/socket.dart';
import 'package:lichess_mobile/src/service/sound_service.dart';
import 'package:lichess_mobile/src/styles/lichess_colors.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/lichess_assets.dart';
import 'package:lichess_mobile/src/utils/screen.dart';
import 'package:lichess_mobile/src/view/account/profile_picture.dart';
import 'package:lichess_mobile/src/view/account/rating_pref_aware.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/buttons.dart';
import 'package:lichess_mobile/src/widgets/clock.dart';
import 'package:lichess_mobile/src/widgets/material_diff.dart';
import 'package:lichess_mobile/src/widgets/neo_avatar.dart';
import 'package:lichess_mobile/src/widgets/network_image.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:material_ui/material_ui.dart';

/// A widget to display player information above/below the chess board.
class const GamePlayer({
  required final BaseGame game,
  required final Side side,
  final Uri? socketUri,
  final double? matchupScore,
  final Widget? clock,
  final MaterialDiffSide? materialDiff,
  final MaterialDifferenceFormat? materialDifferenceFormat,

  /// if confirm move preference is enabled, used to display confirmation buttons
  final ({VoidCallback confirm, VoidCallback cancel})? confirmMoveCallbacks,

  /// When the opponent has left the game, used to display the claim-win countdown
  /// and, once the opponent has been gone long enough, the claim choices.
  final ({
    (Duration, DateTime) countdown,
    bool canClaim,
    VoidCallback onClaimWin,
    VoidCallback onClaimDraw,
  })?
  opponentLeftCallbacks,

  /// Time left for the player to move at the start of the game.
  final Duration? timeToMove,
  final bool shouldLinkToUserProfile = true,
  final bool mePlaying = false,
  final bool canGoForward = false,
  final bool zenMode = false,
  final ClockPosition clockPosition = ClockPosition.right,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isShortScreen = isShortVerticalScreen(context);
    final playerFontSize = isShortScreen ? 15.0 : 16.0;
    final avatarRadius = isShortScreen ? 16.0 : 19.0;

    final player = game.playerOf(side);

    final tournament = game.meta.tournament;

    // With the clock on the left, the player block is mirrored so that it stays against the edge
    // of the screen, away from the clock.
    final isMirrored = clockPosition == ClockPosition.left;
    final colorScheme = ColorScheme.of(context);

    final hasAvatar = !zenMode && (player.user != null || player.isAI);

    final avatar = hasAvatar
        ? SizedBox.square(
            dimension: avatarRadius * 2,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                DecoratedBox(
                  // A thin ring that detaches the avatar from the page.
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.outlineVariant, width: 1.5),
                  ),
                  child: game.youAre == side
                      ? OwnAvatar(
                          radius: avatarRadius,
                          fallback: NeoAvatar(name: player.user?.name, radius: avatarRadius),
                        )
                      : NeoAvatar(name: player.user?.name, radius: avatarRadius),
                ),
                if (player.user != null)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Consumer(
                      builder: (context, ref, _) {
                        bool isPlayerConnected = player.onGame == true;
                        if (mePlaying && socketUri != null) {
                          final ping = ref.watch(socketPingProvider(socketUri));
                          if (ping.rating == 0) {
                            isPlayerConnected = false;
                          }
                        }
                        return Tooltip(
                          message: isPlayerConnected ? 'Joined the game' : 'Left the game',
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: avatarRadius * 0.6,
                            height: avatarRadius * 0.6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isPlayerConnected
                                  ? context.lichessColors.good
                                  : colorScheme.outline,
                              border: Border.all(color: colorScheme.surface, width: 2),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          )
        : null;

    final ratingStyle = TextStyle(
      fontSize: isShortScreen ? 12.0 : 13.0,
      fontWeight: FontWeight.w600,
      color: textShade(context, 0.6),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (tournament?.ranks != null)
          Text(
            '#${side == Side.white ? tournament?.ranks?.white : tournament?.ranks?.black} ',
            style: TextStyle(fontSize: playerFontSize, color: textShade(context, 0.6)),
          ),
        if (player.user?.isPatron == true) ...[
          PatronIcon(size: playerFontSize, color: player.user?.patronColor),
          const SizedBox(width: 4),
        ],
        if (player.user?.title != null) ...[
          Text(
            player.user!.title!,
            style: TextStyle(
              fontSize: playerFontSize,
              fontWeight: player.user?.title == 'BOT' ? FontWeight.w600 : FontWeight.w800,
              color: player.user?.title == 'BOT'
                  ? context.lichessColors.fancy
                  : context.lichessColors.brag,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Tooltip(
            message: player.displayName(context.l10n),
            child: Text(
              player.displayName(context.l10n),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: playerFontSize,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        if (player.user?.flair != null) ...[
          const SizedBox(width: 5),
          HttpNetworkImageWidget(
            lichessFlairSrc(player.user!.flair!),
            errorBuilder: (_, _, _) => kEmptyWidget,
            width: 16,
            height: 16,
          ),
        ],
        if (player.berserk == true) ...[
          const SizedBox(width: 5),
          Icon(
            LichessIcons.body_cut,
            color: LichessColors.brag,
            size: playerFontSize,
            semanticLabel: context.l10n.arenaBerserk,
          ),
        ],
        if (matchupScore != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
            decoration: ShapeDecoration(
              color: colorScheme.primaryContainer,
              shape: const StadiumBorder(),
            ),
            child: Text(
              _scoreDisplay(matchupScore!),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ],
    );

    final detailsRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!zenMode && player.rating != null) ...[
          RatingPrefAware(
            isActiveGameOfCurrentUser: game.me != null && !game.finished && !game.aborted,
            child: Text.rich(
              TextSpan(
                text: '${player.rating}${player.provisional == true ? '?' : ''}',
                children: [
                  if (player.ratingDiff != null)
                    TextSpan(
                      text: ' ${player.ratingDiff! > 0 ? '+' : ''}${player.ratingDiff}',
                      style: TextStyle(
                        color: player.ratingDiff! > 0
                            ? context.lichessColors.good
                            : player.ratingDiff! == 0
                            ? context.lichessColors.brag
                            : context.lichessColors.error,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              style: ratingStyle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: timeToMove != null
              ? MoveExpiration(timeToMove: timeToMove!, mePlaying: mePlaying)
              : MaterialDifferenceDisplay(
                  materialDiff: materialDiff,
                  materialDifferenceFormat: materialDifferenceFormat,
                ),
        ),
      ],
    );

    final playerInfo = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: isMirrored ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [if (!zenMode) nameRow, detailsRow],
    );

    final playerRowChildren = [
      if (avatar != null) ...[avatar, const SizedBox(width: 10)],
      Flexible(child: playerInfo),
    ];

    final playerWidget = Row(
      mainAxisAlignment: isMirrored ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: isMirrored ? playerRowChildren.reversed.toList() : playerRowChildren,
    );

    // When the opponent has left, the countdown / claim choices take the whole
    // table width (the clock is hidden) to leave enough room for the buttons.
    if (opponentLeftCallbacks != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: OpponentLeftCountdown(
          countdown: opponentLeftCallbacks!.countdown,
          canClaim: opponentLeftCallbacks!.canClaim,
          onClaimWin: opponentLeftCallbacks!.onClaimWin,
          onClaimDraw: opponentLeftCallbacks!.onClaimDraw,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (clock != null && clockPosition == ClockPosition.left) Flexible(flex: 3, child: clock!),
        if (mePlaying && confirmMoveCallbacks != null && canGoForward == false)
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: ConfirmMove(
                onConfirm: confirmMoveCallbacks!.confirm,
                onCancel: confirmMoveCallbacks!.cancel,
              ),
            ),
          )
        else
          Expanded(
            flex: 7,
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: shouldLinkToUserProfile
                  ? Consumer(
                      builder: (context, ref, _) {
                        return GestureDetector(
                          onTap: player.user != null
                              ? () {
                                  if (mePlaying) {
                                    ref.invalidate(accountProvider);
                                  }
                                  Navigator.of(context)
                                      .push(UserOrProfileScreen.buildRoute(player.user!));
                                }
                              : null,
                          child: playerWidget,
                        );
                      },
                    )
                  : playerWidget,
            ),
          ),
        if (clock != null && clockPosition == ClockPosition.right) Flexible(flex: 3, child: clock!),
      ],
    );
  }
}

class const ConfirmMove({
  required final VoidCallback onConfirm,
  required final VoidCallback onCancel,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        SemanticIconButton(
          icon: const Icon(CupertinoIcons.xmark_rectangle_fill),
          color: context.lichessColors.error,
          iconSize: 35,
          semanticsLabel: context.l10n.cancel,
          padding: const EdgeInsets.all(10),
          onPressed: onCancel,
        ),
        Flexible(
          child: Text(
            context.l10n.confirmMove,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
            textAlign: TextAlign.center,
          ),
        ),
        SemanticIconButton(
          icon: const Icon(CupertinoIcons.checkmark_rectangle_fill),
          color: context.lichessColors.good,
          iconSize: 35,
          semanticsLabel: context.l10n.accept,
          padding: const EdgeInsets.all(10),
          onPressed: onConfirm,
        ),
      ],
    );
  }
}

/// Shown in the player table when the opponent has left the game.
///
/// While the claim threshold has not been reached, displays a live countdown.
/// Once [canClaim] is true, displays the two claim choices inline (so there is
/// no dialog to dismiss). The player clock is hidden to leave enough room.
class const OpponentLeftCountdown({
  required final (Duration, DateTime) countdown,
  required final bool canClaim,
  required final VoidCallback onClaimWin,
  required final VoidCallback onClaimDraw,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!canClaim) {
      return CountdownClockBuilder(
        timeLeft: countdown.$1,
        clockUpdatedAt: countdown.$2,
        active: true,
        builder: (context, duration) => Text(
          context.l10n.opponentLeftCounter(duration.inSeconds),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    return Column(
      mainAxisSize: .max,
      mainAxisAlignment: .center,
      children: [
        // The buttons are the priority: they keep their full size and stay
        // visible even when vertical space is constrained.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Flexible(
              child: OpacityButton(
                semanticsLabel: context.l10n.forceResignation,
                onPressed: onClaimWin,
                child: Text(
                  context.l10n.forceResignation,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ColorScheme.of(context).secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            Flexible(
              child: OpacityButton(
                semanticsLabel: context.l10n.forceDraw,
                onPressed: onClaimDraw,
                child: Text(
                  context.l10n.forceDraw,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ColorScheme.of(context).secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
        // The explanatory text comes second and is dropped entirely on short
        // screens, where every pixel counts and the buttons take priority.
        if (!isShortVerticalScreen(context)) ...[
          const SizedBox(height: 8.0),
          Text(
            context.l10n.opponentLeftChoices,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

String _scoreDisplay(double score) {
  final integerPart = score.truncate();
  final decimalPart = score - integerPart;

  return integerPart == 0 && decimalPart == 0.5
      ? '½'
      : '$integerPart${decimalPart == 0.5 ? '½' : ''}';
}

class const MoveExpiration({
  required final Duration timeToMove,
  required final bool mePlaying,
  super.key,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<MoveExpiration> createState() => _MoveExpirationState();
}

class _MoveExpirationState() extends ConsumerState<MoveExpiration> {
  static const _period = Duration(milliseconds: 1000);
  Timer? _timer;
  Duration timeLeft = Duration.zero;
  bool playedEmergencySound = false;

  Timer startTimer() {
    return Timer.periodic(_period, (timer) {
      setState(() {
        timeLeft = timeLeft - _period;
        if (timeLeft <= Duration.zero) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void initState() {
    super.initState();
    timeLeft = widget.timeToMove;
    _timer = startTimer();
  }

  @override
  void didUpdateWidget(covariant MoveExpiration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeToMove != widget.timeToMove) {
      _timer?.cancel();
      timeLeft = widget.timeToMove;
      _timer = startTimer();
    }
  }

  @override
  void dispose() {
    super.dispose();
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final secs = timeLeft.inSeconds.remainder(60);
    final emerg = timeLeft <= const Duration(seconds: 8);

    if (emerg && widget.mePlaying && !playedEmergencySound) {
      ref.read(soundServiceProvider).play(Sound.lowTime);
      setState(() {
        playedEmergencySound = true;
      });
    }

    return secs <= 20
        ? Text(
            context.l10n.nbSecondsToPlayTheFirstMove(secs),
            style: TextStyle(color: widget.mePlaying && emerg ? context.lichessColors.error : null),
          )
        : const Text('');
  }
}
