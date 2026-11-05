import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lichess_mobile/src/model/auth/auth_controller.dart';
import 'package:lichess_mobile/src/model/chat/chat.dart';
import 'package:lichess_mobile/src/model/chat/chat_providers.dart';
import 'package:lichess_mobile/src/service/app_links_service.dart';
import 'package:lichess_mobile/src/styles/styles.dart';
import 'package:lichess_mobile/src/tab_navigation.dart';
import 'package:lichess_mobile/src/utils/focus_detector.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:lichess_mobile/src/utils/navigation.dart';
import 'package:lichess_mobile/src/view/chat/chat_context_menu.dart';
import 'package:lichess_mobile/src/view/user/user_or_profile_screen.dart';
import 'package:lichess_mobile/src/widgets/adaptive_bottom_sheet.dart';
import 'package:lichess_mobile/src/widgets/bottom_bar.dart';
import 'package:lichess_mobile/src/widgets/neo_avatar.dart';
import 'package:lichess_mobile/src/widgets/rich_link_text.dart';
import 'package:lichess_mobile/src/widgets/user.dart';
import 'package:lichess_mobile/src/widgets/yes_no_dialog.dart';
import 'package:material_ui/material_ui.dart';

class const ChatBottomBarButton({
  required final ChatOptions options,
  final bool showLabel = false,
  super.key,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatUnread = ref.watch(chatUnreadProvider(options));

    return BottomBarButton(
      label: context.l10n.chatRoom,
      showLabel: showLabel,
      onTap: () => Navigator.of(context).push(ChatScreen.buildRoute(options: options)),
      icon: Icons.chat_bubble_outline,
      badgeLabel: switch (chatUnread) {
        AsyncData(:final value) =>
          value > 0
              ? value < 10
                    ? value.toString()
                    : '9+'
              : null,
        _ => null,
      },
    );
  }
}

class const ChatScreen({required final ChatOptions options}) extends ConsumerStatefulWidget {
  static Route<dynamic> buildRoute({required ChatOptions options}) {
    return buildScreenRoute(screen: ChatScreen(options: options));
  }

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ChatScreenState();
}

class _ChatScreenState() extends ConsumerState<ChatScreen> with RouteAware {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route is PageRoute) {
      rootNavPageRouteObserver.subscribe(this, route);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatNotifierProvider(widget.options)).onFocusRegained();
    });
  }

  @override
  void dispose() {
    rootNavPageRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPop() {
    ref.read(chatNotifierProvider(widget.options)).markMessagesAsRead();
    super.didPop();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider);
    final chatState = ref.watch(chatProvider(widget.options));
    return FocusDetector(
      onFocusRegained: () {
        if (context.mounted) {
          ref.read(chatNotifierProvider(widget.options)).onFocusRegained();
        }
      },
      onForegroundLost: () {
        if (context.mounted) {
          ref.read(chatNotifierProvider(widget.options)).onForegroundLost();
        }
      },
      child: switch (chatState) {
        AsyncValue(:final value?, hasValue: true) => Scaffold(
          appBar: AppBar(
            title: widget.options is TvChatOptions
                ? Text(context.l10n.spectatorRoom)
                : widget.options.isPublic
                ? Text(context.l10n.chatRoom)
                : widget.options.opponent == null
                ? Text(context.l10n.chatRoom)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      NeoAvatar(name: widget.options.opponent!.name, radius: 16),
                      const SizedBox(width: 10),
                      Flexible(
                        child: UserFullNameWidget(
                          user: widget.options.opponent,
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                  ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              // Display error if there is one, but still show the messages if they are available
              if (chatState.hasError)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      chatState.error.toString(),
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              Expanded(
                child: GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: value.messages.isEmpty
                      ? _EmptyChat(options: widget.options)
                      : ListView.builder(
                          padding: MediaQuery.paddingOf(context).copyWith(top: 12, bottom: 12),
                          reverse: true,
                          itemCount: value.messages.length,
                          itemBuilder: (context, index) {
                            final messages = value.messages;
                            final position = messages.length - index - 1;
                            final message = messages[position];
                            if (message.username == 'lichess') {
                              return _MessageAction(message: message.message);
                            }
                            // Consecutive messages of a same sender are grouped together.
                            bool isSameSender(int otherPosition) =>
                                otherPosition >= 0 &&
                                otherPosition < messages.length &&
                                messages[otherPosition].username != 'lichess' &&
                                messages[otherPosition].username == message.username;
                            final isFirstOfGroup = !isSameSender(position - 1);
                            final isLastOfGroup = !isSameSender(position + 1);
                            final you =
                                authUser != null &&
                                message.username?.toLowerCase() == authUser.user.id.value;
                            return _MessageBubble(
                              options: widget.options,
                              you: you,
                              message: message,
                              isFirstOfGroup: isFirstOfGroup,
                              isLastOfGroup: isLastOfGroup,
                              showUsername: !you && widget.options.isPublic && isFirstOfGroup,
                            );
                          },
                        ),
                ),
              ),
              if (widget.options.writeable) _ChatBottomBar(options: widget.options),
            ],
          ),
        ),
        AsyncValue(:final error?) => Scaffold(body: Center(child: Text(error.toString()))),
        _ => const Scaffold(body: Center(child: CircularProgressIndicator.adaptive())),
      },
    );
  }
}

/// Radius of the corners of the bubbles, except where a bubble joins the others of its group.
const _kBubbleRadius = Radius.circular(20.0);

/// Radius of the corners where a bubble joins the others of its group, on its sender's side.
const _kBubbleJoinRadius = Radius.circular(6.0);

/// Radius of the avatars next to the opponent's messages.
const _kAvatarRadius = 13.0;

class const _MessageBubble({
  required final ChatOptions options,
  required final bool you,
  required final ChatMessage message,
  final bool isFirstOfGroup = true,
  final bool isLastOfGroup = true,
  final bool showUsername = false,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = ColorScheme.of(context);
    // Your messages take the accent color, as the buttons of the app.
    final bubbleColor = you ? colorScheme.primary : colorScheme.surfaceContainerHighest;
    final textColor = you ? colorScheme.onPrimary : colorScheme.onSurface;

    // The corners on the sender's side are tighter inside a group, so that its bubbles read as one
    // block, with a small tail on the last one.
    final senderTop = isFirstOfGroup ? _kBubbleRadius : _kBubbleJoinRadius;
    final senderBottom = isLastOfGroup ? const Radius.circular(4.0) : _kBubbleJoinRadius;
    final borderRadius = you
        ? BorderRadius.only(
            topLeft: _kBubbleRadius,
            bottomLeft: _kBubbleRadius,
            topRight: senderTop,
            bottomRight: senderBottom,
          )
        : BorderRadius.only(
            topRight: _kBubbleRadius,
            bottomRight: _kBubbleRadius,
            topLeft: senderTop,
            bottomLeft: senderBottom,
          );

    // The opponent's avatar is shown next to the last message of each of their groups.
    final showAvatar = !you && !options.isPublic && message.user != null;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 14.0),
      decoration: BoxDecoration(borderRadius: borderRadius, color: bubbleColor),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showUsername && message.user != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: UserFullNameWidget(
                user: message.user,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: you ? textColor : colorScheme.primary,
                ),
                onTap: () =>
                    Navigator.of(context).push(UserOrProfileScreen.buildRoute(message.user!)),
              ),
            ),
          RichLinkText(
            onOpen: (link) async =>
                await ref.read(appLinksServiceProvider).onLinkifyOpen(context, link),
            linkifiers: AppLinksService.kLichessLinkifiers,
            text: message.message,
            style: TextStyle(color: textColor, fontSize: 15, height: 1.3),
            // The usual blue links would not read on the accent color.
            linkStyle: you
                ? TextStyle(color: textColor, decoration: TextDecoration.underline)
                : Styles.linkStyle,
          ),
        ],
      ),
    );

    return ChatBubbleContextMenu(
      message: message.message,
      actions: [
        if (you == false && message.user != null)
          BottomSheetContextMenuAction(
            onPressed: () async {
              final result = await showAdaptiveDialog<bool>(
                context: context,
                builder: (context) => YesNoDialog(
                  content: Text(context.l10n.reportXToModerators('"${message.message}"')),
                  onYes: () {
                    return Navigator.of(context).pop(true);
                  },
                  onNo: () => Navigator.of(context).pop(false),
                ),
              );
              if (result == true) {
                ref.read(chatNotifierProvider(options)).reportMessage(message);
              }
            },
            icon: Icons.report_problem_outlined,
            child: const Text('Report'),
          ),
      ],
      child: Padding(
        padding: EdgeInsets.only(
          left: 12.0,
          right: 12.0,
          // Groups are spaced apart, the bubbles of a group are close together.
          top: isFirstOfGroup ? 10.0 : 2.0,
        ),
        child: FractionallySizedBox(
          alignment: you ? Alignment.centerRight : Alignment.centerLeft,
          widthFactor: 0.82,
          child: Row(
            mainAxisAlignment: you ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showAvatar) ...[
                if (isLastOfGroup)
                  NeoAvatar(name: message.username, radius: _kAvatarRadius)
                else
                  const SizedBox(width: _kAvatarRadius * 2),
                const SizedBox(width: 8.0),
              ],
              Flexible(child: bubble),
            ],
          ),
        ),
      ),
    );
  }
}

/// A message from lichess itself, such as a draw offer, shown as a small pill between the bubbles.
class const _MessageAction({required final String message}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 32.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 14.0),
          decoration: ShapeDecoration(
            color: colorScheme.surfaceContainerHigh,
            shape: StadiumBorder(side: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the messages while there are none yet.
class const _EmptyChat({required final ChatOptions options}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final opponent = options.isPublic ? null : options.opponent;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NeoAvatar(name: opponent?.name ?? 'lichess-chat', radius: 36),
            const SizedBox(height: 16),
            const Text(
              'No messages yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              opponent != null ? 'Say hi to ${opponent.name}!' : 'Be the first to say something.',
              textAlign: TextAlign.center,
              style: TextStyle(color: textShade(context, Styles.subtitleOpacity)),
            ),
          ],
        ),
      ),
    );
  }
}

class const _ChatBottomBar({required final ChatOptions options}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _ChatBottomBarState();
}

class _ChatBottomBarState() extends ConsumerState<_ChatBottomBar> {
  final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _textController.text = ref.read(chatNotifierProvider(widget.options)).chatInputDraft;
    _textController.addListener(() {
      ref.read(chatNotifierProvider(widget.options)).chatInputDraft = _textController.text;
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authControllerProvider);
    final colorScheme = ColorScheme.of(context);
    final sendButton = ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textController,
      builder: (context, value, child) => IconButton.filled(
        onPressed: authUser != null && value.text.trim().isNotEmpty
            ? () {
                ref.read(chatNotifierProvider(widget.options)).postMessage(_textController.text);
                _textController.clear();
              }
            : null,
        icon: const Icon(Icons.send_rounded),
        tooltip: context.l10n.send,
      ),
    );
    final placeholder = authUser != null ? context.l10n.talkInChat : context.l10n.loginToChat;
    const pillBorder = OutlineInputBorder(
      borderSide: BorderSide.none,
      borderRadius: BorderRadius.all(Radius.circular(24.0)),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12.0, 6.0, 8.0, 10.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 18.0),
                  border: pillBorder,
                  enabledBorder: pillBorder,
                  disabledBorder: pillBorder,
                  focusedBorder: pillBorder.copyWith(
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  hintText: placeholder,
                ),
                controller: _textController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                enableSuggestions: true,
                readOnly: authUser == null,
              ),
            ),
            const SizedBox(width: 6.0),
            sendButton,
          ],
        ),
      ),
    );
  }
}
