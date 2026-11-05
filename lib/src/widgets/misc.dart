import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/gestures.dart';
import 'package:lichess_mobile/src/styles/lichess_icons.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

class const AppBarLichessTitle({super.key, final double iconSize = 24}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          WidgetSpan(
            alignment: .bottom,
            child: Icon(LichessIcons.logo_lichess, size: iconSize),
          ),
          const TextSpan(text: ' lichess'),
        ],
      ),
      maxLines: 1,
    );
  }
}

/// An app bar title made of an illustration followed by a text, as used by the bottom tabs.
///
/// The illustration is sized from the app bar's title text style, so that it matches the text on
/// both platforms.
class const AppBarImageTitle(final String imageAsset, final String title, {super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final fontSize = DefaultTextStyle.of(context).style.fontSize ?? 20;
    final imageSize = (fontSize * 1.3).roundToDouble();
    return Row(
      mainAxisSize: .min,
      children: [
        Image.asset(imageAsset, width: imageSize, height: imageSize, filterQuality: .medium),
        SizedBox(width: (fontSize * 0.45).roundToDouble()),
        Flexible(child: Text(title, maxLines: 1, overflow: .ellipsis)),
      ],
    );
  }
}

/// A widget that displays a title in the app bar with auto-sizing text.
class const AppBarTitleText(
  final String text, {
  super.key,
  final double? minFontSize,
  final double? maxFontSize,
  final int maxLines = 1,
}) extends StatelessWidget {
  this : assert(maxLines > 0 && maxLines <= 2);

  @override
  Widget build(BuildContext context) {
    return AutoSizeText(
      text,
      maxLines: maxLines,
      style: maxLines > 1 ? const TextStyle(height: 1) : null,
      minFontSize: minFontSize ?? 15.0,
      maxFontSize:
          maxFontSize ??
          (maxLines > 1 ? 18 : AppBarTheme.of(context).titleTextStyle?.fontSize ?? 20.0),
      overflow: TextOverflow.ellipsis,
    );
  }
}

class const LichessMessage({
  super.key,
  final TextStyle? style,
  final TextAlign textAlign = TextAlign.start,
}) extends StatefulWidget {
  @override
  State<LichessMessage> createState() => _LichessMessageState();
}

class _LichessMessageState() extends State<LichessMessage> {
  late TapGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = TapGestureRecognizer()..onTap = _handleTap;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _handleTap() {
    launchUrl(Uri.parse('https://lichess.org/features'));
  }

  @override
  Widget build(BuildContext context) {
    final trans = context.l10n.xIsAFreeYLibreOpenSourceChessServer('Lichess', context.l10n.really);
    final regexp = RegExp(r'''^([^(]*\()([^)]*)(\).*)$''');
    final match = regexp.firstMatch(trans);
    final List<TextSpan> spans = [];
    if (match != null) {
      for (var i = 1; i <= match.groupCount; i++) {
        spans.add(
          TextSpan(
            text: match[i],
            style: i == 2 ? TextStyle(color: ColorScheme.of(context).primary) : null,
            recognizer: i == 2 ? _recognizer : null,
          ),
        );
      }
    } else {
      spans.add(TextSpan(text: trans));
    }

    return MergeSemantics(
      child: Text.rich(
        TextSpan(style: widget.style, children: spans),
        textAlign: widget.textAlign,
      ),
    );
  }
}

/// An icon that represents opening a button or a link in a external application.
class const OpenInNewIcon() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.open_in_new, size: 18);
  }
}
