import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/view/auth/api_token_dialog.dart';
import 'package:lichess_mobile/src/widgets/adaptive_action_sheet.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the user pick how to sign in, then starts the chosen flow.
///
/// The OAuth browser flow is the default. A personal API token can be pasted instead, which also
/// works where the browser flow is unreliable (some Android browsers and OEMs). The official app's
/// email login code is not offered: its tokens need the official app's `web:mobile` scope.
///
/// Failures of the browser flow are reported through [signInMutation], so callers are expected to
/// already listen to it with `showSignInErrorSnackBar`.
Future<void> showSignInOptions(BuildContext context, WidgetRef ref) {
  final navigator = Navigator.of(context, rootNavigator: true);

  return showAdaptiveActionSheet<void>(
    context: context,
    actions: [
      BottomSheetAction(
        makeLabel: (context) => Text(context.l10n.mobileSignInWithBrowser),
        leading: const Icon(Icons.open_in_browser),
        onPressed: () {
          // The error is surfaced by the caller's [ref.listen] on [signInMutation]; ignore the
          // rethrown future so it does not become an unhandled exception.
          signInMutation.run(ref, (tsx) async {
            await tsx.get(authControllerProvider.notifier).signIn();
          }).ignore();
        },
      ),
      BottomSheetAction(
        makeLabel: (context) => const Text('Sign in with API token'),
        leading: const Icon(Icons.key),
        onPressed: () async {
          final token = await showDialog<String>(
            context: navigator.context,
            builder: (_) => const ApiTokenDialog(),
          );
          if (token == null) return;
          // Same error handling as the browser flow, see above.
          signInMutation.run(ref, (tsx) async {
            await tsx.get(authControllerProvider.notifier).signInWithPersonalToken(token);
          }).ignore();
        },
      ),
    ],
  );
}
