import 'package:material_ui/material_ui.dart';

// Avatars of LichessNeo (MIT, Théophile Wallez), see `assets/neo/LICENSE`: lichess has no profile
// pictures, so each user gets one of its mascots on a gradient, picked from their name. The
// picking is the same as LichessNeo's, so a user has the same avatar here as on its website.

/// Number of mascots, `assets/neo/coaches/mascot-<n>.webp`.
const _kMascotCount = 26;

/// The robot mascot, kept for the computer.
const _kRobotMascot = 8;

/// The gradients of the avatars.
enum _AvatarColor(final Color from, final Color to) {
  blue(Color(0xFF4F8DFF), Color(0xFF7A5CFF)),
  purple(Color(0xFFA46CFF), Color(0xFFE35BD0)),
  pink(Color(0xFFFF6FAE), Color(0xFFFF9A72)),
  red(Color(0xFFFF6161), Color(0xFFE8336F)),
  orange(Color(0xFFFFAD4D), Color(0xFFFF6B3D)),
  green(Color(0xFF2FD68F), Color(0xFF12A8A0)),
  cyan(Color(0xFF3FD2EE), Color(0xFF3D7DFF)),
}

/// Colors a mascot would melt into, which it never gets.
const _kClashes = <int, List<_AvatarColor>>{
  2: [.orange],
  3: [.green],
  4: [.pink, .red],
  5: [.green],
  6: [.orange],
  7: [.cyan],
  9: [.red],
  10: [.orange],
  12: [.green],
  13: [.orange],
  14: [.blue],
  15: [.purple],
  16: [.green],
  17: [.orange],
  18: [.purple],
  21: [.purple],
  23: [.orange],
  25: [.green, .cyan],
  26: [.orange],
};

/// Every avatar a name may get, in LichessNeo's order.
final List<({int mascot, _AvatarColor color})> _kAvatars = [
  for (var mascot = 1; mascot <= _kMascotCount; mascot++)
    if (mascot != _kRobotMascot)
      for (final color in _AvatarColor.values)
        if (!(_kClashes[mascot]?.contains(color) ?? false)) (mascot: mascot, color: color),
];

/// FNV-1a, then murmur3's finalizer, on 32 bits: names one letter apart land far apart.
int _nameHash(String name) {
  const mask = 0xFFFFFFFF;
  var hash = 0x811c9dc5;
  for (final unit in name.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & mask;
  }
  hash ^= hash >> 16;
  hash = (hash * 0x85ebca6b) & mask;
  hash ^= hash >> 13;
  hash = (hash * 0xc2b2ae35) & mask;
  hash ^= hash >> 16;
  return hash;
}

/// A LichessNeo avatar: the one of the user [name], or the robot's for the computer.
class const NeoAvatar({required final String? name, required final double radius, super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final avatar = name != null
        ? _kAvatars[_nameHash(name!.trim().toLowerCase()) % _kAvatars.length]
        : (mascot: _kRobotMascot, color: _AvatarColor.blue);
    final size = radius * 2;

    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              // CSS's 145deg: from the top left towards the bottom right.
              begin: const Alignment(-0.57, -0.82),
              end: const Alignment(0.57, 0.82),
              colors: [avatar.color.from, avatar.color.to],
            ),
          ),
          child: DecoratedBox(
            // A glint at the top.
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.56, -0.76),
                radius: 0.58,
                colors: [Color(0x47FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: OverflowBox(
              maxWidth: size * 1.5,
              maxHeight: size * 1.5,
              alignment: Alignment.bottomCenter,
              child: Image.asset(
                'assets/neo/coaches/mascot-${avatar.mascot}.webp',
                width: size * 1.5,
                fit: BoxFit.fitWidth,
                alignment: Alignment.bottomCenter,
                cacheWidth: (size * 1.5 * MediaQuery.devicePixelRatioOf(context)).round(),
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
