import 'package:lichess_mobile/src/utils/oklch.dart';
import 'package:material_ui/material_ui.dart';

/// Default primary color of the app, as an ARGB value: the 'Neo' preset.
const kDefaultAccentColor = 0xFF5E6AD2;

/// Tint of the neutral greys: an OKLCH hue in degrees and a chroma.
typedef NeutralTint = ({double hue, double chroma});

/// Preset primary colors of the app.
///
/// These are the color themes of LichessNeo (MIT, Théophile Wallez), see `assets/neo/LICENSE`:
/// besides its accent, each theme tints the greys of the backgrounds, more in dark mode.
enum AccentColor(
  final Color color,
  final String label,
  final NeutralTint lightTint,
  final NeutralTint darkTint,
) {
  neo(Color(kDefaultAccentColor), 'Neo', (hue: 286, chroma: .006), (hue: 286, chroma: .004)),
  lichess(Color(0xFFD64F00), 'Lichess', (hue: 70, chroma: .008), (hue: 75, chroma: .008)),
  ocean(Color(0xFF2F9BEA), 'Ocean', (hue: 225, chroma: .012), (hue: 230, chroma: .025)),
  grove(Color(0xFF2A9F6D), 'Grove', (hue: 150, chroma: .011), (hue: 160, chroma: .02)),
  ember(Color(0xFFE2622A), 'Ember', (hue: 60, chroma: .012), (hue: 45, chroma: .02)),
  iris(Color(0xFF8467EC), 'Iris', (hue: 300, chroma: .014), (hue: 295, chroma: .03)),
  blossom(Color(0xFFDD4C89), 'Blossom', (hue: 355, chroma: .013), (hue: 350, chroma: .025)),
  midnight(Color(0xFF6D7CFF), 'Midnight', (hue: 255, chroma: .014), (hue: 265, chroma: .045)),
  ruby(Color(0xFFE04A63), 'Ruby', (hue: 15, chroma: .012), (hue: 12, chroma: .022)),
  dune(Color(0xFFC98326), 'Dune', (hue: 80, chroma: .016), (hue: 75, chroma: .018)),
  matcha(Color(0xFF6C9E2C), 'Matcha', (hue: 125, chroma: .014), (hue: 130, chroma: .02)),
  aurora(Color(0xFF16A294), 'Aurora', (hue: 185, chroma: .013), (hue: 185, chroma: .022)),
  fjord(Color(0xFF6688BD), 'Fjord', (hue: 235, chroma: .012), (hue: 240, chroma: .018)),
  mocha(Color(0xFFB07A52), 'Mocha', (hue: 55, chroma: .012), (hue: 50, chroma: .016)),
  plum(Color(0xFFC0509F), 'Plum', (hue: 330, chroma: .014), (hue: 325, chroma: .028)),
  twilight(Color(0xFFE66A33), 'Twilight', (hue: 295, chroma: .018), (hue: 290, chroma: .035));

  /// The preset matching [color], if any.
  static AccentColor? fromColor(Color color) =>
      values.where((preset) => preset.color.toARGB32() == color.toARGB32()).firstOrNull;

  /// The tint of the greys for the primary [color]: the preset's, or a light tint of the color's
  /// own hue for a custom color.
  static NeutralTint tintFor(Color color, Brightness brightness) {
    final preset = fromColor(color);
    if (preset != null) {
      return brightness == Brightness.dark ? preset.darkTint : preset.lightTint;
    }
    return (hue: colorToOklch(color).hue, chroma: brightness == Brightness.dark ? .014 : .01);
  }
}
