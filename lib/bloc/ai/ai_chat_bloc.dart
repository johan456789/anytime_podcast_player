// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/bloc.dart';
import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

/// The window of transcript leading up to the current play position which is
/// passed to the assistant as recent context.
const recentContextWindow = Duration(minutes: 5);

/// Supplies the AI chat with just enough playback context: the playing
/// episode, the current position and a stream of episode changes so the
/// conversation can be reset when a new episode starts.
abstract class AiChatPlaybackSource {
  Episode? get currentEpisode;

  Duration get currentPosition;

  Stream<Episode?>? get episodeEvents;
}

/// Production [AiChatPlaybackSource] backed by the app's [AudioPlayerService].
class AudioPlayerChatSource extends AiChatPlaybackSource {
  final AudioPlayerService audioPlayerService;

  AudioPlayerChatSource(this.audioPlayerService);

  @override
  Episode? get currentEpisode => audioPlayerService.episodeEvent?.valueOrNull;

  @override
  Duration get currentPosition => audioPlayerService.playPosition?.value.position ?? Duration.zero;

  @override
  Stream<Episode?>? get episodeEvents => audioPlayerService.episodeEvent;
}

/// The state of the AI chat conversation for the playing episode.
class AiChatState {
  final List<AiChatMessage> messages;

  /// True while the assistant is generating a reply.
  final bool busy;

  const AiChatState({
    this.messages = const <AiChatMessage>[],
    this.busy = false,
  });

  AiChatState.initial() : this();

  AiChatState copyWith({
    List<AiChatMessage>? messages,
    bool? busy,
  }) =>
      AiChatState(
        messages: messages ?? this.messages,
        busy: busy ?? this.busy,
      );
}

/// A BLoC which manages an AI conversation about the currently playing
/// episode.
///
/// The conversation lives in memory for the app session and is cleared
/// whenever the playing episode changes. Questions are sent to the
/// [AiChatService] with layered transcript context: the full transcript plus
/// a [recentContextWindow] window leading up to the current play position.
class AiChatBloc extends Bloc {
  final log = Logger('AiChatBloc');
  final AiChatService aiChatService;
  final AiChatPlaybackSource playbackSource;

  final BehaviorSubject<AiChatState> _state = BehaviorSubject<AiChatState>.seeded(AiChatState.initial());
  StreamSubscription<Episode?>? _episodeSubscription;
  StreamSubscription<String>? _replySubscription;

  /// GUID of the episode the current conversation belongs to; [_unset] until
  /// the playing episode is first observed.
  static const _unset = '__unset__';
  String? _episodeGuid = _unset;

  AiChatBloc({
    required this.aiChatService,
    required this.playbackSource,
  }) {
    /// Start a fresh conversation whenever the playing episode changes.
    _episodeSubscription = playbackSource.episodeEvents?.listen((episode) {
      final guid = episode?.guid;

      if (_episodeGuid != guid) {
        final wasUnset = _episodeGuid == _unset;
        _episodeGuid = guid;

        /// Establishing the first known episode must not wipe a conversation
        /// which may already have started (episode events can be delivered
        /// asynchronously).
        if (!wasUnset) {
          clear();
        }
      }
    });
  }

  /// Sends the user's question to the assistant and streams the reply.
  /// Returns false when the question was not accepted (empty input, no
  /// transcript or a reply already in progress) so callers can keep the
  /// user's typed text.
  bool ask(String question) {
    final text = question.trim();
    final episode = playbackSource.currentEpisode;
    final lines = episode?.transcript?.subtitles ?? const <Subtitle>[];

    if (text.isEmpty || lines.isEmpty || _state.value.busy) {
      return false;
    }

    final position = playbackSource.currentPosition;
    final recentLines = _recentLines(lines, position);

    /// Snapshot the completed conversation before this question is appended;
    /// it becomes the provider's context so follow-ups keep their meaning.
    /// Failed or empty assistant turns are dropped (together with the
    /// question they answered) so the provider never receives empty or
    /// error placeholder content.
    final history = _cleanHistory(_state.value.messages);

    _state.add(_state.value.copyWith(
      messages: [
        ...history,
        AiChatMessage(fromUser: true, text: text),
        const AiChatMessage(fromUser: false, text: '', pending: true),
      ],
      busy: true,
    ));

    _replySubscription?.cancel();
    _replySubscription = aiChatService
        .send(AiChatRequest(
          question: text,
          episodeTitle: episode?.title ?? '',
          currentPosition: position,
          lines: lines,
          recentLines: recentLines,
          history: history,
        ))
        .listen(
          (chunk) => _appendChunk(chunk),
          onError: (error) {
            log.fine('AI chat error: $error');
            _finishReply(error: true);
          },
          onDone: () => _finishReply(),
        );

    return true;
  }

  /// Stops the assistant generating the current reply.
  void stop() {
    _replySubscription?.cancel();
    _replySubscription = null;

    /// Also abort the in-flight provider request, if the service supports
    /// it, so generation (and usage) actually stops.
    unawaited(aiChatService.cancel());

    if (_state.value.busy) {
      _finishReply();
    }
  }

  /// Clears the conversation.
  void clear() {
    _replySubscription?.cancel();
    _replySubscription = null;

    unawaited(aiChatService.cancel());

    _state.add(AiChatState.initial());
  }

  /// Removes assistant turns which would confuse the provider: error
  /// placeholders, empty replies (e.g. a stop before any text arrived) and
  /// the questions they belong to.
  List<AiChatMessage> _cleanHistory(List<AiChatMessage> messages) {
    final cleaned = <AiChatMessage>[];

    for (final message in messages) {
      if (message.fromUser) {
        cleaned.add(message);
      } else if (!message.error && !message.pending && message.text.trim().isNotEmpty) {
        cleaned.add(message);
      } else if (cleaned.isNotEmpty && cleaned.last.fromUser) {
        /// The reply was invalid (failed or empty), so drop the question it
        /// belongs to as well to keep the turns paired.
        cleaned.removeLast();
      }
    }

    return cleaned;
  }

  /// The transcript lines leading up to, and including, [position].
  @visibleForTesting
  List<Subtitle> recentLinesForTest(List<Subtitle> lines, [Duration? position]) =>
      _recentLines(lines, position ?? playbackSource.currentPosition);

  List<Subtitle> _recentLines(List<Subtitle> lines, Duration position) {
    final cutoff = position - recentContextWindow;
    final recent = <Subtitle>[];

    for (final line in lines) {
      if (line.start >= cutoff && line.start <= position) {
        recent.add(line);
      }

      if (line.start > position) {
        break;
      }
    }

    /// At the very start of an episode there may be no lines within the
    /// window; fall back to the opening lines.
    if (recent.isEmpty && lines.isNotEmpty) {
      recent.addAll(lines.take(3));
    }

    return recent;
  }

  void _appendChunk(String chunk) {
    final messages = List<AiChatMessage>.from(_state.value.messages);

    if (messages.isEmpty || messages.last.fromUser) {
      return;
    }

    messages[messages.length - 1] = messages.last.copyWith(text: messages.last.text + chunk);
    _state.add(_state.value.copyWith(messages: messages));
  }

  void _finishReply({bool error = false}) {
    final messages = List<AiChatMessage>.from(_state.value.messages);

    if (messages.isEmpty || messages.last.fromUser) {
      _state.add(_state.value.copyWith(busy: false));
      return;
    }

    if (error && messages.last.text.isEmpty) {
      /// Leave the text empty; the view renders the localized error label
      /// for messages flagged as errors.
      messages[messages.length - 1] = messages.last.copyWith(
        pending: false,
        error: true,
      );
    } else if (error) {
      /// A partial reply already reached the UI; keep it visible but mark it
      /// as failed so the user knows it was interrupted, not completed.
      messages[messages.length - 1] = messages.last.copyWith(
        pending: false,
        error: true,
      );
    } else {
      messages[messages.length - 1] = messages.last.copyWith(pending: false);
    }

    _state.add(AiChatState(messages: messages, busy: false));
  }

  Stream<AiChatState> get state => _state.stream;

  AiChatState get currentState => _state.value;

  @override
  void dispose() {
    _episodeSubscription?.cancel();
    _replySubscription?.cancel();
    _state.close();

    super.dispose();
  }
}
