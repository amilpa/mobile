import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';

/// Dialog asking for a personal API token, created at https://lichess.org/account/oauth/token.
///
/// Pops with the trimmed token, or with `null` if cancelled.
class const ApiTokenDialog({super.key}) extends StatefulWidget {
  @override
  State<ApiTokenDialog> createState() => _ApiTokenDialogState();
}

class _ApiTokenDialogState() extends State<ApiTokenDialog> {
  final TextEditingController controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final token = controller.text.trim();
    if (token.isEmpty) return;
    Navigator.of(context).pop(token);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign in with API token'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: const InputDecoration(hintText: 'lip_...'),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(context.l10n.cancel)),
        TextButton(onPressed: submit, child: Text(context.l10n.signIn)),
      ],
    );
  }
}
