import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

// Conversions between sRGB colors and OKLCH, the perceptual color space LichessNeo builds its
// palettes in. See https://bottosson.github.io/posts/oklab/.

/// The OKLCH coordinates of a color: lightness and chroma in 0..1, hue in degrees.
typedef Oklch = ({double lightness, double chroma, double hue});

/// Converts OKLCH coordinates to an sRGB color, clamping it into the sRGB gamut.
Color oklchToColor(double lightness, double chroma, double hue) {
  final h = hue * math.pi / 180;
  final a = chroma * math.cos(h);
  final b = chroma * math.sin(h);

  final l = math.pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3).toDouble();
  final m = math.pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3).toDouble();
  final s = math.pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3).toDouble();

  final red = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s;
  final green = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s;
  final blue = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s;

  return Color.from(
    alpha: 1.0,
    red: _gamma(red),
    green: _gamma(green),
    blue: _gamma(blue),
  );
}

/// Converts an sRGB color to its OKLCH coordinates.
Oklch colorToOklch(Color color) {
  final red = _linear(color.r);
  final green = _linear(color.g);
  final blue = _linear(color.b);

  final l = _cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue);
  final m = _cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue);
  final s = _cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue);

  final lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  final a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  final b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;

  final hue = math.atan2(b, a) * 180 / math.pi;
  return (lightness: lightness, chroma: math.sqrt(a * a + b * b), hue: hue < 0 ? hue + 360 : hue);
}

double _gamma(double linear) {
  final value = linear <= 0.0031308
      ? 12.92 * linear
      : 1.055 * math.pow(linear, 1 / 2.4).toDouble() - 0.055;
  return value.clamp(0.0, 1.0);
}

double _linear(double channel) => channel <= 0.04045
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

double _cbrt(double value) =>
    value < 0 ? -math.pow(-value, 1 / 3).toDouble() : math.pow(value, 1 / 3).toDouble();
