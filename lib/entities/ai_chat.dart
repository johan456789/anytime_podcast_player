// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/transcript.dart';

/// A single message within an AI chat conversation about the playing episode.
class AiChatMessage {
  /// True if the message was sent by the user; false if from the assistant.
  final bool fromUser;

  /// The message body. Assistant replies may contain `[mm:ss]` timestamps
  /// which the UI renders as tappable seek chips.
  final String text;

  /// True while the assistant is still streaming this message.
  final bool pending;

  /// True if the assistant failed to produce this message.
  final bool error;

  const AiChatMessage({
    required this.fromUser,
    required this.text,
    this.pending = false,
    this.error = false,
  });

  AiChatMessage copyWith({
    String? text,
    bool? pending,
    bool? error,
  }) =>
      AiChatMessage(
        fromUser: fromUser,
        text: text ?? this.text,
        pending: pending ?? this.pending,
        error: error ?? this.error,
      );
}

/// The request sent to an [AiChatService] when the user asks a question.
///
/// The transcript is passed with its timestamps intact so that replies can
/// cite timecodes which the user can tap to seek. [history] carries the prior
/// turns of the conversation so follow-up questions keep their context.
class AiChatRequest {
  /// The user's question.
  final String question;

  /// The title of the episode the chat is about.
  final String episodeTitle;

  /// The current playback position when the question was asked.
  final Duration currentPosition;

  /// The full transcript, one [Subtitle] per line.
  final List<Subtitle> lines;

  /// The recent portion of the transcript: the lines leading up to and
  /// including [currentPosition]. This gives the assistant grounding for
  /// questions about what is being said right now without requiring it to
  /// search the full transcript.
  final List<Subtitle> recentLines;

  /// The prior conversation turns, oldest first, excluding the current
  /// question.
  final List<AiChatMessage> history;

  const AiChatRequest({
    required this.question,
    required this.episodeTitle,
    required this.currentPosition,
    required this.lines,
    required this.recentLines,
    this.history = const <AiChatMessage>[],
  });
}
