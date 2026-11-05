import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:lichess_mobile/src/widgets/neo_avatar.dart';
import 'package:material_ui/material_ui.dart';

/// Time for the radar to make a full turn, and for each wave to cross it.
const _kRadarPeriod = Duration(milliseconds: 2400);

/// Time each avatar stays in the middle of the radar while looking for an opponent.
const _kAvatarShuffleInterval = Duration(milliseconds: 900);

/// Animated scene shown while waiting for an opponent: a radar sweeping the lobby, with waves
/// spreading from the avatar in its center, and a pill counting the time spent waiting.
///
/// When [opponentName] is null the avatars of LichessNeo shuffle in the center, as if the lobby was
/// being scanned for a player; otherwise the avatar of that opponent is shown.
class const MatchmakingAnimation({
  final String? opponentName,
  final bool showElapsedTime = true,
  super.key,
}) extends StatefulWidget {
  @override
  State<MatchmakingAnimation> createState() => _MatchmakingAnimationState();
}

class _MatchmakingAnimationState() extends State<MatchmakingAnimation>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;

  /// Progress of the radar through its turn, from 0 to 1.
  final ValueNotifier<double> _phase = ValueNotifier(0.0);

  int _avatarIndex = 0;
  int _elapsedSeconds = 0;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    // A ticker rather than a timer, so that the elapsed time follows the frames, which tests fake.
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  void _onTick(Duration elapsed) {
    if (!_reduceMotion) {
      _phase.value =
          (elapsed.inMicroseconds % _kRadarPeriod.inMicroseconds) / _kRadarPeriod.inMicroseconds;
    }
    final avatarIndex = elapsed.inMilliseconds ~/ _kAvatarShuffleInterval.inMilliseconds;
    final elapsedSeconds = elapsed.inSeconds;
    if (avatarIndex != _avatarIndex || elapsedSeconds != _elapsedSeconds) {
      setState(() {
        _avatarIndex = avatarIndex;
        _elapsedSeconds = elapsedSeconds;
      });
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final size = (MediaQuery.sizeOf(context).shortestSide * 0.3).clamp(88.0, 132.0);
    final avatarRadius = size * 0.2;
    final minutes = _elapsedSeconds ~/ 60;
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _RadarPainter(
                  phase: _phase,
                  color: colorScheme.primary,
                  innerRadius: avatarRadius,
                ),
              ),
            ),
          ),
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: colorScheme.primary, width: 2.5),
            ),
            child: AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: animation, child: child),
              ),
              child: NeoAvatar(
                key: ValueKey(widget.opponentName ?? _avatarIndex),
                name: widget.opponentName ?? 'lobby-seek-$_avatarIndex',
                radius: avatarRadius,
              ),
            ),
          ),
          if (widget.showElapsedTime)
            Positioned(
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                decoration: ShapeDecoration(
                  color: colorScheme.primary,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  '$minutes:$seconds',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints the radar: guide circles, a rotating sweep lighting up blips as it passes over them, and
/// waves spreading from the avatar.
class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.phase, required this.color, required this.innerRadius})
    : super(repaint: phase);

  final ValueListenable<double> phase;
  final Color color;
  final double innerRadius;

  /// Position of the blips, as an angle in radians and a fraction of the radius.
  static const _blips = [(0.7, 0.8), (2.5, 0.55), (4.2, 0.9), (5.4, 0.62)];

  /// Angle over which a blip fades out once the sweep has passed it.
  static const _blipAfterglow = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    final t = phase.value;
    final sweepAngle = t * 2 * math.pi;

    // Faint fill and guide circles.
    canvas.drawCircle(center, maxRadius, Paint()..color = color.withValues(alpha: 0.06));
    final guidePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withValues(alpha: 0.18);
    canvas.drawCircle(center, maxRadius, guidePaint);
    canvas.drawCircle(center, innerRadius + (maxRadius - innerRadius) * 0.5, guidePaint);

    // The sweep: its leading edge is bright, its tail fades away behind it.
    final sweepRect = Rect.fromCircle(center: center, radius: maxRadius);
    canvas.drawCircle(
      center,
      maxRadius,
      Paint()
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0.0), color.withValues(alpha: 0.35)],
          stops: const [0.72, 1.0],
          transform: GradientRotation(sweepAngle),
        ).createShader(sweepRect),
    );

    // Blips, lit when the sweep passes over them.
    for (final (angle, distance) in _blips) {
      final behind = (sweepAngle - angle) % (2 * math.pi);
      final intensity = behind < _blipAfterglow ? 1.0 - behind / _blipAfterglow : 0.0;
      if (intensity <= 0) continue;
      final position = center + Offset(math.cos(angle), math.sin(angle)) * (maxRadius * distance);
      canvas.drawCircle(
        position,
        3.5 + 2.0 * intensity,
        Paint()..color = color.withValues(alpha: 0.25 * intensity),
      );
      canvas.drawCircle(position, 2.5, Paint()..color = color.withValues(alpha: 0.9 * intensity));
    }

    // Waves spreading from the avatar, three at a time.
    for (var i = 0; i < 3; i++) {
      final progress = (t + i / 3) % 1.0;
      final radius = innerRadius + (maxRadius - innerRadius) * Curves.easeOut.transform(progress);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1.0 - progress) + 0.5
          ..color = color.withValues(alpha: 0.55 * (1.0 - progress)),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.color != color ||
      oldDelegate.innerRadius != innerRadius;
}
