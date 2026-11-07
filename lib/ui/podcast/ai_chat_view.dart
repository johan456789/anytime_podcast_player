import 'package:anytime/bloc/ai/ai_chat_bloc.dart';
import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/state/transcript_state_event.dart';
import 'package:anytime/ui/widgets/decorated_icon_button.dart';
import 'package:anytime/ui/widgets/markdown_spans.dart';
import 'package:anytime/ui/widgets/platform_progress_indicator.dart';
import 'package:anytime/ui/widgets/timestamp_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:provider/provider.dart';

/// AI chat about the currently playing episode.
///
/// Replies are grounded in the episode transcript and may contain `[mm:ss]`
/// timestamps which are rendered as tappable chips that seek playback.
class AiChatView extends StatefulWidget {
  const AiChatView({super.key});

  @override
  State<AiChatView> createState() => _AiChatViewState();
}

class _AiChatViewState extends State<AiChatView> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  int _lastMessageCount = 0;
  int _lastTextLength = 0;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _textController.text).trim();

    if (text.isEmpty) {
      return;
    }

    final accepted = Provider.of<AiChatBloc>(context, listen: false).ask(text);

    if (accepted) {
      _textController.clear();
    }
  }

  /// Keeps the message list pinned to the bottom while the assistant is
  /// streaming, unless the user has scrolled away to read.
  void _scheduleAutoScroll(int messageCount, int textLength) {
    final newMessage = messageCount != _lastMessageCount;
    final grew = textLength != _lastTextLength;
    _lastMessageCount = messageCount;
    _lastTextLength = textLength;

    if (!newMessage && !grew || !_scrollController.hasClients) {
      return;
    }

    final position = _scrollController.position;
    final nearBottom = position.maxScrollExtent - position.pixels < 240;

    if (newMessage || nearBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    return StreamBuilder<TranscriptState>(
        stream: audioBloc.nowPlayingTranscript,
        builder: (context, transcriptSnapshot) {
          if (transcriptSnapshot.hasData) {
            if (transcriptSnapshot.data is TranscriptLoadingState) {
              return const Align(
                alignment: Alignment.center,
                child: PlatformProgressIndicator(),
              );
            } else if (transcriptSnapshot.data is TranscriptUnavailableState ||
                !transcriptSnapshot.data!.transcript!.transcriptAvailable) {
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    L.of(context)!.no_transcript_available_label,
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            } else {
              return _buildChat(context);
            }
          } else {
            return Container();
          }
        });
  }

  Widget _buildChat(BuildContext context) {
    final aiChatBloc = Provider.of<AiChatBloc>(context);

    return StreamBuilder<AiChatState>(
        stream: aiChatBloc.state,
        builder: (context, snapshot) {
          final state = snapshot.data ?? aiChatBloc.currentState;

          _scheduleAutoScroll(state.messages.length, state.messages.isEmpty ? 0 : state.messages.last.text.length);

          return Column(
            children: [
              Expanded(
                child: state.messages.isEmpty ? _buildSuggestions(context) : _buildMessages(context, state),
              ),
              _buildContextRow(context, state),
              _buildInputRow(context, state),
            ],
          );
        });
  }

  Widget _buildSuggestions(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context)!;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.auto_awesome,
            size: 40.0,
            color: theme.colorScheme.secondary,
          ),
          const Padding(padding: EdgeInsets.only(top: 12.0)),
          Text(
            l.ask_ai_empty_title,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const Padding(padding: EdgeInsets.only(top: 8.0)),
          Text(
            l.ask_ai_empty_subtitle,
            style: theme.textTheme.titleSmall!.copyWith(color: theme.disabledColor),
            textAlign: TextAlign.center,
          ),
          const Padding(padding: EdgeInsets.only(top: 24.0)),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            alignment: WrapAlignment.center,
            children: [
              ActionChip(
                label: Text(l.ask_ai_suggestion_summarize),
                onPressed: () => _send(l.ask_ai_suggestion_summarize),
              ),
              ActionChip(
                label: Text(l.ask_ai_suggestion_takeaways),
                onPressed: () => _send(l.ask_ai_suggestion_takeaways),
              ),
              ActionChip(
                label: Text(l.ask_ai_suggestion_topics),
                onPressed: () => _send(l.ask_ai_suggestion_topics),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(BuildContext context, AiChatState state) {
    final theme = Theme.of(context);
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16.0, 4.0, 16.0, 4.0),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[index];

        if (message.fromUser) {
          return _UserMessageBubble(message: message);
        } else {
          return _AssistantMessageBubble(
            message: message,
            baseStyle: message.error
                ? theme.textTheme.titleMedium!.copyWith(color: theme.colorScheme.error)
                : theme.textTheme.titleMedium,
            onSeek: (seconds) => audioBloc.transitionPosition(seconds.toDouble()),
          );
        }
      },
    );
  }

  Widget _buildContextRow(BuildContext context, AiChatState state) {
    final l = L.of(context)!;
    final aiChatBloc = Provider.of<AiChatBloc>(context, listen: false);

    if (state.messages.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.restart_alt),
            iconSize: 20.0,
            color: Theme.of(context).disabledColor,
            tooltip: l.ask_ai_clear_conversation_label,
            onPressed: aiChatBloc.clear,
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, AiChatState state) {
    final theme = Theme.of(context);
    final l = L.of(context)!;
    final aiChatBloc = Provider.of<AiChatBloc>(context, listen: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !state.busy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                isDense: true,
                filled: true,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24.0)),
                  borderSide: BorderSide.none,
                  gapPadding: 0.0,
                ),
                hintText: l.ask_ai_input_hint,
              ),
            ),
          ),
          const Padding(padding: EdgeInsets.only(left: 8.0)),
          Semantics(
            label: state.busy ? l.ask_ai_stop_label : l.ask_ai_send_message_label,
            button: true,
            child: DecoratedIconButton(
              icon: state.busy ? Icons.stop_rounded : Icons.send_rounded,
              decorationColour: state.busy ? theme.disabledColor : theme.colorScheme.secondary,
              iconColour: theme.colorScheme.onSecondary,
              onPressed: () {
                if (state.busy) {
                  aiChatBloc.stop();
                } else {
                  _send();
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UserMessageBubble extends StatelessWidget {
  final AiChatMessage message;

  const _UserMessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondary.withValues(alpha: 0.18),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14.0),
            topRight: Radius.circular(14.0),
            bottomLeft: Radius.circular(14.0),
            bottomRight: Radius.circular(4.0),
          ),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  final AiChatMessage message;
  final TextStyle? baseStyle;
  final void Function(int seconds) onSeek;

  const _AssistantMessageBubble({
    required this.message,
    this.baseStyle,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = L.of(context)!;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 8.0),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.85),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.cardColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14.0),
            topRight: Radius.circular(14.0),
            bottomLeft: Radius.circular(4.0),
            bottomRight: Radius.circular(14.0),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: _buildSpans(message.text.isEmpty && message.error ? l.ask_ai_error_label : message.text, baseStyle),
              ),
              style: baseStyle,
            ),
            if (message.pending)
              Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: SpinKitThreeBounce(
                  color: theme.colorScheme.secondary,
                  size: 12.0,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _buildSpans(String text, TextStyle? baseStyle) {
    return buildMarkdownSpans(
      text,
      baseStyle: baseStyle ?? const TextStyle(),
      chipBuilder: (label, seconds) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: TimestampChip(
          label: label,
          seconds: seconds,
          onSeek: onSeek,
        ),
      ),
    );
  }
}
