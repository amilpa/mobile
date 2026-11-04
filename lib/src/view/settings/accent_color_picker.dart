import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/settings/accent_color.dart';
import 'package:lichess_mobile/src/model/settings/general_preferences.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Lightness of the custom colors: bright enough to stand out on the dark backgrounds, dark
/// enough to carry white text.
const _kCustomLightness = 0.56;

/// Shows a bottom sheet to choose the primary color of the app.
Future<void> showAccentColorPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _AccentColorPicker(),
  );
}

class const _AccentColorPicker() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AccentColorPicker> createState() => _AccentColorPickerState();
}

class _AccentColorPickerState() extends ConsumerState<_AccentColorPicker> {
  late double hue;
  late double saturation;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(ref.read(generalPreferencesProvider).accent);
    hue = hsl.hue;
    saturation = hsl.saturation.clamp(0.3, 1.0);
  }

  Color get customColor =>
      HSLColor.fromAHSL(1.0, hue, saturation, _kCustomLightness).toColor();

  void select(Color color) {
    HapticFeedback.selectionClick();
    ref.read(generalPreferencesProvider.notifier).setAccentColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(generalPreferencesProvider.select((p) => p.accent));
    final isCustom = AccentColor.fromColor(accent) == null;

    return BottomSheetScrollableContainer(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        const Text('Primary color', style: Styles.sectionTitle),
        const SizedBox(height: 4),
        Text(
          'Buttons, highlights and selections use this color.',
          style: TextStyle(color: textShade(context, Styles.subtitleOpacity)),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 16,
          children: [
            for (final preset in AccentColor.values)
              _Swatch(
                color: preset.color,
                label: preset.label,
                selected: preset.color.toARGB32() == accent.toARGB32(),
                onTap: () => select(preset.color),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            const Expanded(child: Text('Custom', style: Styles.subtitle)),
            _Swatch(color: customColor, selected: isCustom, onTap: () => select(customColor)),
          ],
        ),
        const SizedBox(height: 8),
        Text('Hue', style: TextStyle(color: textShade(context, Styles.subtitleOpacity))),
        Slider(
          value: hue,
          max: 360,
          activeColor: customColor,
          onChanged: (value) => setState(() => hue = value),
          onChangeEnd: (_) => select(customColor),
        ),
        Text('Saturation', style: TextStyle(color: textShade(context, Styles.subtitleOpacity))),
        Slider(
          value: saturation,
          min: 0.3,
          activeColor: customColor,
          onChanged: (value) => setState(() => saturation = value),
          onChangeEnd: (_) => select(customColor),
        ),
      ],
    );
  }
}

/// A round color choice, with its optional [label] below it.
class const _Swatch({
  required final Color color,
  required final bool selected,
  required final VoidCallback onTap,
  final String? label,
}) extends StatelessWidget {
  static const _size = 48.0;

  @override
  Widget build(BuildContext context) {
    final onColor = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? ColorScheme.of(context).onSurface : Colors.transparent,
                    width: 2.5,
                  ),
                ),
                child: selected ? Icon(Icons.check, color: onColor, size: 22) : null,
              ),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(
                  label!,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
