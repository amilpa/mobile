import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/model/settings/accent_color.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/oklch.dart';
import 'package:material_ui/material_ui.dart';

const kSliderTheme = SliderThemeData(
  // ignore: deprecated_member_use
  year2023: false,
);

ThemeData makeAppTheme(
  BuildContext context, {
  required BackgroundThemeMode themeMode,
  required (BackgroundColor, bool)? backgroundColor,
  required BackgroundImage? backgroundImage,
  required Color accentColor,
}) {
  final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
  final isForcedDarkMode = backgroundColor != null || backgroundImage != null;
  final brightness = isForcedDarkMode
      ? Brightness.dark
      : switch (themeMode) {
          BackgroundThemeMode.light => Brightness.light,
          BackgroundThemeMode.dark || BackgroundThemeMode.amoled => Brightness.dark,
          BackgroundThemeMode.system => MediaQuery.platformBrightnessOf(context),
        };

  if (backgroundColor == null && backgroundImage == null) {
    return _withAppFont(
      _makeDefaultTheme(brightness, themeMode: themeMode, accentColor: accentColor, isIOS: isIOS),
    );
  } else {
    return _withAppFont(
      _makeBackgroundImageTheme(
        baseTheme: backgroundImage?.baseTheme ?? backgroundColor!.$1.baseTheme,
        seedColor:
            backgroundImage?.seedColor ??
            (backgroundColor!.$2 ? backgroundColor.$1.darker : backgroundColor.$1.color),
        isIOS: isIOS,
        isBackgroundImage: backgroundImage != null,
      ),
    );
  }
}

/// The text font of the app, bundled in `assets/fonts/PlusJakartaSans/`.
///
/// Scripts it does not cover (Cyrillic, Greek, CJK, ...) fall back to the system font.
const kAppFontFamily = 'PlusJakartaSans';

/// Font size of the app bar titles on Android, Material's `titleLarge`.
///
/// It must be written out: the text theme of a [ThemeData] gets its sizes only once [MaterialApp]
/// localizes it, so it has none here.
const kAppBarTitleFontSize = 22.0;

/// Sets [kAppFontFamily] on every text style of [theme], and gives the app bar titles a heavier
/// weight that suits the font.
ThemeData _withAppFont(ThemeData theme) {
  final appBarTitleStyle =
      theme.appBarTheme.titleTextStyle ??
      TextStyle(
        fontSize: kAppBarTitleFontSize,
        height: 28 / kAppBarTitleFontSize,
        color: theme.colorScheme.onSurface,
      );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: kAppFontFamily),
    primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: kAppFontFamily),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: appBarTitleStyle.copyWith(
        fontFamily: kAppFontFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    ),
  );
}

/// A custom theme extension that adds lichess custom properties to the theme.
@immutable
class const CustomTheme({required final Color rowEven, required final Color rowOdd})
    extends ThemeExtension<CustomTheme> {
  @override
  CustomTheme copyWith({Color? rowEven, Color? rowOdd}) {
    return CustomTheme(rowEven: rowEven ?? this.rowEven, rowOdd: rowOdd ?? this.rowOdd);
  }

  @override
  CustomTheme lerp(ThemeExtension<CustomTheme>? other, double t) {
    if (other is! CustomTheme) {
      return this;
    }
    return CustomTheme(
      rowEven: Color.lerp(rowEven, other.rowEven, t) ?? rowEven,
      rowOdd: Color.lerp(rowOdd, other.rowOdd, t) ?? rowOdd,
    );
  }
}

/// A [BuildContext] extension that provides the [lichessTheme] property.
extension CustomThemeBuildContext on BuildContext {
  CustomTheme get _defaultLichessTheme => CustomTheme(
    rowEven: ColorScheme.of(this).surfaceContainer,
    rowOdd: ColorScheme.of(this).surfaceContainerLow,
  );

  CustomTheme get lichessTheme => Theme.of(this).extension<CustomTheme>() ?? _defaultLichessTheme;
}

// --

/// Lightness of the 14 neutral greys of LichessNeo in dark mode, in percent, from darkest.
const _kDarkNeutralLightness = [
  14.0, 15.5, 17.3, 19.2, 21.4, 24.0, 26.9, 30.2, 38.1, 49.1, 64.9, 77.6, 87.9, 97.8, //
];

/// Lightness of the 14 neutral greys of LichessNeo in light mode, in percent, from lightest.
const _kLightNeutralLightness = [
  100.0, 99.3, 98.5, 96.8, 95.4, 93.4, 91.2, 88.6, 80.0, 63.0, 53.0, 44.0, 30.0, 18.0, //
];

/// The 14 neutral greys of LichessNeo, tinted with the hue of the theme: `neutrals[0]` is
/// LichessNeo's `neutral-1`.
List<Color> _neutrals(Brightness brightness, NeutralTint tint) {
  final lightness = brightness == Brightness.dark
      ? _kDarkNeutralLightness
      : _kLightNeutralLightness;
  return [
    for (final (index, l) in lightness.indexed)
      // The last two steps, used for text, are half as tinted.
      oklchToColor(l / 100, index >= 12 ? tint.chroma / 2 : tint.chroma, tint.hue),
  ];
}

/// Builds the color scheme of the app from its [accentColor], the way LichessNeo does: the
/// accent colors buttons, links and selections, while backgrounds are greys tinted towards the
/// theme's hue.
ColorScheme _makeColorScheme(
  Color accentColor,
  Brightness brightness,
  BackgroundThemeMode themeMode,
) {
  final accentScheme = ColorScheme.fromSeed(
    seedColor: accentColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final n = _neutrals(brightness, AccentColor.tintFor(accentColor, brightness));
  final onAccent = ThemeData.estimateBrightnessForColor(accentColor) == Brightness.dark
      ? Colors.white
      : const Color(0xFF0C0C0D);

  final scheme = accentScheme.copyWith(
    // Buttons use the accent exactly, as LichessNeo's primary buttons.
    primary: accentColor,
    onPrimary: onAccent,
    surfaceTint: Colors.transparent,
  );

  if (brightness == Brightness.light) {
    return scheme.copyWith(
      // Page on neutral-5, panels and cards on neutral-1.
      surface: n[4],
      surfaceDim: n[5],
      surfaceBright: n[0],
      surfaceContainerLowest: n[0],
      surfaceContainerLow: n[1],
      surfaceContainer: n[0],
      surfaceContainerHigh: n[5],
      surfaceContainerHighest: n[6],
      onSurface: n[13],
      onSurfaceVariant: n[10],
      outline: n[8],
      outlineVariant: n[6],
      inverseSurface: n[12],
      onInverseSurface: n[0],
    );
  }

  final isAmoled = themeMode == BackgroundThemeMode.amoled;
  const black = Color(0xFF000000);
  return scheme.copyWith(
    // Page on neutral-4, panels on neutral-3, raised elements and borders on neutral-6.
    surface: isAmoled ? black : n[3],
    surfaceDim: isAmoled ? black : n[1],
    surfaceBright: n[6],
    surfaceContainerLowest: isAmoled ? black : n[1],
    surfaceContainerLow: isAmoled ? n[0] : n[2],
    surfaceContainer: isAmoled ? n[1] : n[4],
    surfaceContainerHigh: isAmoled ? n[3] : n[5],
    surfaceContainerHighest: isAmoled ? n[5] : n[6],
    // Text is neutral-14 at 88%, dim text neutral-11.
    onSurface: Color.alphaBlend(n[13].withValues(alpha: 0.88), isAmoled ? black : n[3]),
    onSurfaceVariant: n[10],
    outline: n[7],
    outlineVariant: isAmoled ? n[3] : n[5],
    inverseSurface: n[12],
    onInverseSurface: n[1],
  );
}

ThemeData _makeDefaultTheme(
  Brightness brightness, {
  required BackgroundThemeMode themeMode,
  required Color accentColor,
  required bool isIOS,
}) {
  final colorScheme = _makeColorScheme(accentColor, brightness, themeMode);
  final textTheme = isIOS ? kCupertinoDefaultTextTheme : null;
  final theme = ThemeData.from(colorScheme: colorScheme, textTheme: textTheme);
  final isDark = brightness == Brightness.dark;
  final barColor = isDark
      ? theme.colorScheme.surfaceContainerHigh
      : theme.colorScheme.surfaceContainer;

  final finalTheme = theme.copyWith(
    cupertinoOverrideTheme: _makeCupertinoThemeData(theme.colorScheme, brightness),
    splashFactory: isIOS ? NoSplash.splashFactory : null,
    appBarTheme: _appBarTheme.copyWith(
      // The same color as the bottom navigation bar (see FloatingNavBar), so that the header
      // stands out from the page.
      backgroundColor: isIOS
          ? theme.colorScheme.surface.withValues(alpha: kCupertinoBarOpacity)
          : barColor,
      surfaceTintColor: isIOS ? null : Colors.transparent,
      // Full width, with only its bottom corners rounded.
      shape: isIOS
          ? null
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(Styles.materialPopupRadius),
              ),
            ),
      scrolledUnderElevation: 0,
      titleTextStyle: isIOS
          ? const CupertinoTextThemeData().navTitleTextStyle.copyWith(
              color: theme.colorScheme.onSurface,
            )
          : null,
    ),
    navigationBarTheme: isIOS
        ? NavigationBarThemeData(
            backgroundColor: theme.colorScheme.surface.withValues(alpha: kCupertinoBarOpacity),
          )
        : null,
    bottomAppBarTheme: BottomAppBarThemeData(
      color: theme.colorScheme.surface,
      elevation: isIOS ? 0 : null,
    ),
    searchBarTheme: isIOS ? _kCupertinoSearchBarTheme : null,
    iconTheme: IconThemeData(color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
    listTileTheme: _makeListTileTheme(theme.colorScheme, isIOS),
    cardTheme: isIOS
        ? _kCupertinoCardTheme.copyWith(color: theme.colorScheme.surfaceContainerHigh)
        : CardThemeData(
            elevation: 0,
            color: theme.colorScheme.surfaceContainer,
            shape: RoundedRectangleBorder(
              borderRadius: Styles.materialCardBorderRadius,
              side: isDark ? BorderSide(color: theme.colorScheme.outlineVariant) : BorderSide.none,
            ),
          ),
    inputDecorationTheme: isIOS ? _makeCupertinoInputDecorationTheme(theme.colorScheme) : null,
    floatingActionButtonTheme: isIOS
        ? FloatingActionButtonThemeData(
            backgroundColor: theme.colorScheme.secondaryFixedDim,
            foregroundColor: theme.colorScheme.onSecondaryFixedVariant,
          )
        : const FloatingActionButtonThemeData(shape: StadiumBorder()),
    // Popups float over the page, so they are rounder than the cards in it.
    dialogTheme: isIOS
        ? _kCupertinoDialogTheme
        : const DialogThemeData(shape: _kMaterialPopupShape),
    filledButtonTheme: isIOS ? _kCupertinoFilledButtonTheme : _kNeoFilledButtonTheme,
    outlinedButtonTheme: isIOS ? _kCupertinoOutlinedButtonTheme : _kNeoOutlinedButtonTheme,
    textButtonTheme: isIOS ? null : _kNeoTextButtonTheme,
    menuTheme: isIOS ? _kCupertinoMenuThemeData : const MenuThemeData(style: _kMaterialMenuStyle),
    popupMenuTheme: isIOS ? null : const PopupMenuThemeData(shape: _kMaterialCardShape),
    chipTheme: isIOS ? null : const ChipThemeData(shape: StadiumBorder()),
    bottomSheetTheme: isIOS
        ? _kCupertinoBottomSheetTheme
        : const BottomSheetThemeData(shape: _kMaterialSheetShape),
    sliderTheme: kSliderTheme,
    extensions: [lichessCustomColors.harmonized(theme.colorScheme)],
  );

  if (!isDark) return finalTheme;

  // Flat background with no tint when scrolling, as LichessNeo's pages.
  return finalTheme.copyWith(
    scaffoldBackgroundColor: theme.colorScheme.surface,
    appBarTheme: finalTheme.appBarTheme.copyWith(surfaceTintColor: Colors.transparent),
    bottomAppBarTheme: finalTheme.bottomAppBarTheme.copyWith(color: theme.colorScheme.surface),
    dividerTheme: DividerThemeData(color: theme.colorScheme.outlineVariant, thickness: 0.5),
  );
}

ThemeData _makeBackgroundImageTheme({
  required ThemeData baseTheme,
  required Color seedColor,
  required bool isIOS,
  required bool isBackgroundImage,
}) {
  final baseSurfaceAlpha = isBackgroundImage ? 0.5 : 0.3;

  return baseTheme.copyWith(
    colorScheme: baseTheme.colorScheme.copyWith(
      surface: baseTheme.colorScheme.surface.withValues(alpha: baseSurfaceAlpha),
      surfaceContainerLowest: baseTheme.colorScheme.surfaceContainerLowest.withValues(
        alpha: baseSurfaceAlpha,
      ),
      surfaceContainerLow: baseTheme.colorScheme.surfaceContainerLow.withValues(
        alpha: baseSurfaceAlpha,
      ),
      surfaceContainer: baseTheme.colorScheme.surfaceContainer.withValues(alpha: baseSurfaceAlpha),
      surfaceContainerHigh: baseTheme.colorScheme.surfaceContainerHigh.withValues(
        alpha: baseSurfaceAlpha,
      ),
      surfaceContainerHighest: baseTheme.colorScheme.surfaceContainerHighest.withValues(
        alpha: baseSurfaceAlpha,
      ),
      surfaceDim: baseTheme.colorScheme.surfaceDim.withValues(alpha: baseSurfaceAlpha + 1),
      surfaceBright: baseTheme.colorScheme.surfaceBright.withValues(alpha: baseSurfaceAlpha - 2),
    ),
    cupertinoOverrideTheme: _makeCupertinoThemeData(baseTheme.colorScheme, baseTheme.brightness),
    listTileTheme: _makeListTileTheme(baseTheme.colorScheme, isIOS),
    cardTheme: isIOS ? _kCupertinoCardTheme : const CardThemeData(shape: _kMaterialCardShape),
    inputDecorationTheme: isIOS ? _makeCupertinoInputDecorationTheme(baseTheme.colorScheme) : null,
    bottomSheetTheme:
        (isIOS
                ? _kCupertinoBottomSheetTheme
                : const BottomSheetThemeData(shape: _kMaterialSheetShape))
            .copyWith(
              backgroundColor: isIOS
                  ? lighten(baseTheme.colorScheme.surface, 0.1).withValues(alpha: 0.9)
                  : baseTheme.colorScheme.surface.withValues(alpha: 0.9),
            ),
    drawerTheme: DrawerThemeData(
      backgroundColor: baseTheme.colorScheme.surfaceContainerLow.withValues(alpha: 0.9),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: baseTheme.colorScheme.secondaryFixedDim,
      foregroundColor: baseTheme.colorScheme.onSecondaryFixedVariant,
      shape: isIOS ? null : const StadiumBorder(),
    ),
    popupMenuTheme: isIOS ? null : const PopupMenuThemeData(shape: _kMaterialCardShape),
    chipTheme: isIOS ? null : const ChipThemeData(shape: StadiumBorder()),
    dialogTheme:
        (isIOS ? _kCupertinoDialogTheme : const DialogThemeData(shape: _kMaterialPopupShape))
            .copyWith(backgroundColor: baseTheme.colorScheme.surface.withValues(alpha: 0.9)),
    filledButtonTheme: isIOS ? _kCupertinoFilledButtonTheme : null,
    outlinedButtonTheme: isIOS ? _kCupertinoOutlinedButtonTheme : null,
    menuTheme: isIOS
        ? MenuThemeData(
            style: MenuStyle(
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: WidgetStatePropertyAll(
                baseTheme.colorScheme.surfaceContainer.withValues(alpha: 0.8),
              ),
            ),
          )
        : MenuThemeData(
            style: _kMaterialMenuStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(
                baseTheme.colorScheme.surfaceContainerLow.withValues(alpha: 0.8),
              ),
            ),
          ),
    scaffoldBackgroundColor: seedColor.withValues(alpha: 0),
    appBarTheme: _appBarTheme.copyWith(
      backgroundColor: isBackgroundImage ? null : seedColor.withValues(alpha: kCupertinoBarOpacity),
      scrolledUnderElevation: isIOS ? 0 : null,
      titleTextStyle: isIOS
          ? const CupertinoTextThemeData().navTitleTextStyle.copyWith(
              color: baseTheme.colorScheme.onSurface,
            )
          : null,
    ),
    navigationBarTheme: isIOS
        ? NavigationBarThemeData(
            backgroundColor: isBackgroundImage
                ? baseTheme.colorScheme.surface.withValues(alpha: baseSurfaceAlpha)
                : seedColor.withValues(alpha: kCupertinoBarOpacity),
          )
        : null,
    bottomAppBarTheme: BottomAppBarThemeData(
      color: isBackgroundImage
          ? baseTheme.colorScheme.surface.withValues(alpha: baseSurfaceAlpha)
          : seedColor,
      elevation: isIOS ? 0 : null,
    ),
    searchBarTheme: isIOS ? _kCupertinoSearchBarTheme : null,
    splashFactory: isIOS ? NoSplash.splashFactory : null,
    sliderTheme: kSliderTheme,
    extensions: [lichessCustomColors.harmonized(baseTheme.colorScheme)],
  );
}

/// The buttons are pills, as the bottom navigation bar (see the corner scale in [Styles]).
const WidgetStatePropertyAll<OutlinedBorder> _kNeoButtonShape = WidgetStatePropertyAll(
  StadiumBorder(),
);

// The shapes of the Android components, after the corner scale in [Styles].

const _kMaterialCardShape = RoundedRectangleBorder(borderRadius: Styles.materialCardBorderRadius);

const _kMaterialPopupShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(Styles.materialPopupRadius)),
);

const _kMaterialSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(Styles.materialPopupRadius)),
);

/// Menus are small popups attached to their button: they take the corners of the cards.
const _kMaterialMenuStyle = MenuStyle(shape: WidgetStatePropertyAll(_kMaterialCardShape));

const _kNeoFilledButtonTheme = FilledButtonThemeData(
  style: ButtonStyle(
    shape: _kNeoButtonShape,
    textStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w800)),
  ),
);

const _kNeoOutlinedButtonTheme = OutlinedButtonThemeData(
  style: ButtonStyle(
    shape: _kNeoButtonShape,
    textStyle: WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700)),
  ),
);

const _kNeoTextButtonTheme = TextButtonThemeData(style: ButtonStyle(shape: _kNeoButtonShape));

const _kCupertinoFilledButtonTheme = FilledButtonThemeData(
  style: ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
  ),
);

const _kCupertinoOutlinedButtonTheme = OutlinedButtonThemeData(
  style: ButtonStyle(
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
    ),
  ),
);

const MenuThemeData _kCupertinoMenuThemeData = MenuThemeData(
  style: MenuStyle(elevation: WidgetStatePropertyAll(0)),
);

ListTileThemeData _makeListTileTheme(ColorScheme colorScheme, bool isIOS) {
  return ListTileThemeData(
    iconColor: colorScheme.onSurface.withValues(alpha: 0.7),
    titleTextStyle: isIOS
        ? TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.w500, fontSize: 16)
        : null,
    subtitleTextStyle: TextStyle(
      color: colorScheme.onSurface.withValues(alpha: Styles.subtitleOpacity),
    ),
    contentPadding: isIOS ? const EdgeInsets.symmetric(horizontal: 16) : null,
    minTileHeight: isIOS ? 48.0 : null,
  );
}

const _appBarTheme = AppBarTheme(actionsPadding: EdgeInsets.only(right: 8.0));

const _kCupertinoBottomSheetTheme = BottomSheetThemeData(
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
);

const _kCupertinoDialogTheme = DialogThemeData(
  elevation: 0,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14))),
);

const _kCupertinoCardTheme = CardThemeData(
  elevation: 0,
  margin: EdgeInsets.zero,
  shape: RoundedRectangleBorder(borderRadius: Styles.cardBorderRadius),
);

const _kCupertinoSearchBarTheme = SearchBarThemeData(
  elevation: WidgetStatePropertyAll(0),
  shape: WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8.0))),
  ),
  constraints: BoxConstraints(minHeight: 40, maxHeight: 40),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 7)),
);

InputDecorationTheme _makeCupertinoInputDecorationTheme(ColorScheme colorScheme) {
  return InputDecorationTheme(
    filled: true,
    fillColor: colorScheme.surfaceContainer.withValues(alpha: 0.7),
    border: const OutlineInputBorder(),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.outline),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
    ),
    disabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: colorScheme.error),
      borderRadius: const BorderRadius.all(Radius.circular(8)),
    ),
  );
}

CupertinoThemeData _makeCupertinoThemeData(ColorScheme colorScheme, Brightness brightness) {
  return CupertinoThemeData(
    applyThemeToAll: true,
    primaryColor: colorScheme.primary,
    primaryContrastingColor: colorScheme.onPrimary,
    textTheme: const CupertinoThemeData().textTheme.copyWith(
      primaryColor: colorScheme.primary,
      textStyle: const CupertinoThemeData().textTheme.textStyle.copyWith(
        color: colorScheme.onSurface,
        fontFamily: kAppFontFamily,
      ),
      actionTextStyle: const CupertinoThemeData().textTheme.actionTextStyle.copyWith(
        fontFamily: kAppFontFamily,
      ),
      tabLabelTextStyle: const CupertinoThemeData().textTheme.tabLabelTextStyle.copyWith(
        fontFamily: kAppFontFamily,
      ),
      navTitleTextStyle: const CupertinoThemeData().textTheme.navTitleTextStyle.copyWith(
        color: colorScheme.onSurface,
        fontFamily: kAppFontFamily,
        fontWeight: FontWeight.w700,
      ),
      navLargeTitleTextStyle: const CupertinoThemeData().textTheme.navLargeTitleTextStyle.copyWith(
        color: colorScheme.onSurface,
        fontFamily: kAppFontFamily,
        fontWeight: FontWeight.w800,
      ),
    ),
    brightness: brightness,
  );
}

// Letter spacing value taken from:
// https://github.com/flutter/flutter/blob/ea121f8859e4b13e47a8f845e4586164519588bc/packages/flutter/lib/src/cupertino/text_theme.dart#L106
const TextStyle _kCupertinoDefaultTextStyle = TextStyle(letterSpacing: -0.41);

const TextTheme kCupertinoDefaultTextTheme = TextTheme(
  // titleLarge: _kCupertinoDefaultTextStyle,
  titleMedium: _kCupertinoDefaultTextStyle,
  titleSmall: _kCupertinoDefaultTextStyle,
  bodyLarge: _kCupertinoDefaultTextStyle,
  bodyMedium: _kCupertinoDefaultTextStyle,
  bodySmall: _kCupertinoDefaultTextStyle,
  labelLarge: _kCupertinoDefaultTextStyle,
  labelMedium: _kCupertinoDefaultTextStyle,
  labelSmall: _kCupertinoDefaultTextStyle,
);
