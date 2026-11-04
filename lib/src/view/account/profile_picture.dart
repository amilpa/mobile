import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lichess_mobile/src/model/account/local_profile_picture.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Size of the picture, in pixels: twice the largest avatar, for sharp rendering.
const _kPictureSize = 384.0;

/// Lets the user choose or remove their [localProfilePictureProvider].
Future<void> showProfilePictureOptions(BuildContext context, WidgetRef ref) {
  final hasPicture = ref.read(localProfilePictureProvider).value != null;
  return showAdaptiveActionSheet<void>(
    context: context,
    actions: [
      BottomSheetAction(
        makeLabel: (_) => const Text('Choose a picture'),
        leading: const Icon(Icons.photo_library_outlined),
        onPressed: () async {
          final image = await ImagePicker().pickImage(
            source: ImageSource.gallery,
            maxWidth: _kPictureSize,
            maxHeight: _kPictureSize,
            imageQuality: 90,
            // Only the pixels are needed: skipping the metadata avoids the photo library
            // permission prompt on iOS.
            requestFullMetadata: false,
          );
          if (image == null) return;
          await ref
              .read(localProfilePictureProvider.notifier)
              .setPicture(await image.readAsBytes());
        },
      ),
      if (hasPicture)
        BottomSheetAction(
          makeLabel: (_) => const Text('Remove picture'),
          leading: const Icon(Icons.delete_outline),
          isDestructiveAction: true,
          onPressed: () => ref.read(localProfilePictureProvider.notifier).remove(),
        ),
    ],
  );
}

/// The user's own avatar: their [localProfilePictureProvider] if they chose one, [fallback]
/// otherwise.
class const OwnAvatar({
  required final double radius,
  required final Widget fallback,

  /// Space around the picture, not applied to [fallback].
  final EdgeInsetsGeometry padding = EdgeInsets.zero,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picture = ref.watch(localProfilePictureProvider).value;
    if (picture == null) return fallback;
    return Padding(
      padding: padding,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: ColorScheme.of(context).surfaceContainerHighest,
        // The picture is center cropped into the circle.
        foregroundImage: ResizeImage(FileImage(picture), width: _kPictureSize.toInt()),
      ),
    );
  }
}
