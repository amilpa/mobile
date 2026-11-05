import 'dart:math';

import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lichess_mobile/src/constants.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';

/// Space between the edge of the Material action sheet and its buttons.
const _kActionSheetPadding = 12.0;

/// Corners of the buttons of the Material action sheet: the corners of the dialog less the
/// [_kActionSheetPadding], so that the corners of the buttons follow those of the dialog.
const _kActionButtonBorderRadius = BorderRadius.all(
  Radius.circular(Styles.materialPopupRadius - _kActionSheetPadding),
);

/// A action bottom sheet that adapts to the platform (Android/iOS).
///
/// [actions] The Actions list that will appear on the ActionSheet. (required)
///
/// [title] The optional title widget that show above the actions.
///
/// The optional [isDismissible] can be passed to set barrierDismissible of showCupertinoModalPopup
/// and isDismissible of showModalBottomSheet (Default true as for both implementations)
Future<T?> showAdaptiveActionSheet<T>({
  required BuildContext context,
  Widget? title,
  required List<BottomSheetAction> actions,
  bool isDismissible = true,
}) {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return showCupertinoActionSheet(
      context: context,
      title: title,
      actions: actions,
      isDismissible: isDismissible,
    );
  } else {
    return showMaterialActionSheet(
      context: context,
      title: title,
      actions: actions,
      isDismissible: isDismissible,
    );
  }
}

Future<T?> showConfirmDialog<T>(
  BuildContext context, {
  required Widget title,
  required VoidCallback onConfirm,

  /// Only for iOS
  bool isDestructiveAction = false,
}) {
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return showCupertinoActionSheet(
      context: context,
      actions: [
        BottomSheetAction(
          makeLabel: (_) => title,
          isDestructiveAction: isDestructiveAction,
          onPressed: onConfirm,
        ),
      ],
    );
  } else {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: title,
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(textStyle: TextTheme.of(context).labelLarge),
              child: Text(context.l10n.cancel),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              style: TextButton.styleFrom(textStyle: TextTheme.of(context).labelLarge),
              child: Text(context.l10n.mobileOkButton),
              onPressed: () {
                Navigator.of(context).pop();
                onConfirm();
              },
            ),
          ],
        );
      },
    );
  }
}

Future<T?> showCupertinoActionSheet<T>({
  required BuildContext context,
  Widget? title,
  required List<BottomSheetAction> actions,
  bool isDismissible = true,
}) {
  return showCupertinoModalPopup(
    context: context,
    barrierDismissible: isDismissible,
    builder: (BuildContext context) {
      return CupertinoActionSheet(
        title: title,
        actions: actions
            .map(
              // Builder is used to retrieve the context immediately surrounding the button
              // This is necessary to get the correct context for the iPad share dialog
              // which needs the position of the action to display the share dialog
              (action) => Builder(
                builder: (context) {
                  return CupertinoActionSheetAction(
                    onPressed: () {
                      if (action.dismissOnPress) {
                        Navigator.of(context).pop();
                      }
                      action.onPressed();
                    },
                    isDestructiveAction: action.isDestructiveAction,
                    isDefaultAction: action.isDefaultAction,
                    child: action.makeLabel(context),
                  );
                },
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: Text(context.l10n.cancel),
        ),
      );
    },
  );
}

Future<T?> showMaterialActionSheet<T>({
  required BuildContext context,
  Widget? title,
  required List<BottomSheetAction> actions,
  bool isDismissible = true,
}) {
  final colorScheme = ColorScheme.of(context);
  final actionTextStyle = (TextTheme.of(context).titleMedium ?? const TextStyle(fontSize: 18))
      .copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w500);

  final screenWidth = MediaQuery.widthOf(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (BuildContext context) {
      // A panel of rounded buttons: the panel is a raised surface (grey in the dark themes) and
      // each action sits on the deepest surface (near black), so that it reads as a button.
      return Dialog(
        backgroundColor: colorScheme.surfaceContainerHigh,
        // Narrower margins than a dialog's, so that the labels of the actions fit on one line.
        insetPadding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: SizedBox(
          width: min(screenWidth, kMaterialPopupMenuMaxWidth),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(_kActionSheetPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                    child: Center(child: title),
                  ),
                ...actions.mapIndexed<Widget>((index, action) {
                  return Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                    child: Material(
                      color: colorScheme.surfaceContainerLowest,
                      shape: const RoundedRectangleBorder(borderRadius: _kActionButtonBorderRadius),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          if (action.dismissOnPress) {
                            Navigator.of(context).pop();
                          }
                          action.onPressed();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          child: Row(
                            children: [
                              if (action.leading != null) ...[
                                action.leading!,
                                const SizedBox(width: 14),
                              ],
                              Expanded(
                                child: DefaultTextStyle(
                                  style: actionTextStyle,
                                  textAlign: action.leading != null
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  child: action.makeLabel(context),
                                ),
                              ),
                              if (action.trailing != null) ...[
                                const SizedBox(width: 10),
                                action.trailing!,
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// The Actions model that will use on the ActionSheet.
class BottomSheetAction({
  /// A function that returns the label widget. (required)
  ///
  /// Typically a [Text] widget.
  ///
  /// This should not wrap. To enforce the single line limit, use
  /// [Text.maxLines].
  required final Widget Function(BuildContext context) makeLabel,

  /// The callback that is called when the action item is tapped. (required)
  required final VoidCallback onPressed,

  /// Whether the modal should be dismissed when an action is pressed.
  ///
  /// Default to true.
  final bool dismissOnPress = true,

  /// A widget to display after the label.
  ///
  /// Typically an [Icon] widget. (Android only).
  final Widget? trailing,

  /// A widget to display before the label.
  ///
  /// Typically an [Icon] or a [CircleAvatar] widget. (Android only).
  final Widget? leading,

  /// Whether the action is destructive. (iOS only).
  final bool isDestructiveAction = false,

  /// Whether the action is the default action. (iOS only).
  final bool isDefaultAction = false,
});
