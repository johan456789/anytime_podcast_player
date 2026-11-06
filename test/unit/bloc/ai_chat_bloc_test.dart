// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/ai/ai_chat_bloc.dart';
import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rxdart/rxdart.dart';

class _FakeChatService extends AiChatService {
  final List<String> chunks;
  final Duration delay;
  final requests = <AiChatRequest>[];
  int cancelCount = 0;

  _FakeChatService(this.chunks, {this.delay = Duration.zero});

  @override
  Stream<String> send(AiChatRequest request) async* {
    requests.add(request);

    for (final chunk in chunks) {
      await Future<void>.delayed(delay);

      yield chunk;
    }
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }
}

/// Streams one chunk then fails, simulating a mid-reply network error.
class _FailingAfterChunkService extends AiChatService {
  @override
  Stream<String> send(AiChatRequest request) async* {
    yield 'partial answer ';

    throw Exception('network error');
  }
}

class _FakePlaybackSource extends AiChatPlaybackSource {
  final BehaviorSubject<Episode?> episodes = BehaviorSubject<Episode?>();
  Duration position = Duration.zero;

  @override
  Episode? get currentEpisode => episodes.valueOrNull;

  @override
  Duration get currentPosition => position;

  @override
  Stream<Episode?>? get episodeEvents => episodes.stream;
}

Episode _episode(String guid, {List<Subtitle> subtitles = const <Subtitle>[]}) {
  return Episode(
    guid: guid,
    podcast: 'podcast',
    title: 'Episode $guid',
  )..transcript = Transcript(subtitles: subtitles);
}

void main() {
  final subtitles = <Subtitle>[
    Subtitle(index: 0, start: const Duration(minutes: 1), end: const Duration(minutes: 1, seconds: 5), data: 'Hello world'),
    Subtitle(index: 1, start: const Duration(minutes: 2), end: const Duration(minutes: 2, seconds: 5), data: 'Second line'),
  ];

  test('ask adds messages and streams the reply into state', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: _FakeChatService(['Hello ', 'there']), playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('What is this about?');

    expect(bloc.currentState.messages.length, 2);
    expect(bloc.currentState.messages.first.fromUser, isTrue);
    expect(bloc.currentState.messages.first.text, 'What is this about?');
    expect(bloc.currentState.busy, isTrue);

    // Allow the reply stream to complete.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.currentState.busy, isFalse);
    expect(bloc.currentState.messages.last.text, 'Hello there');
    expect(bloc.currentState.messages.last.pending, isFalse);

    bloc.dispose();
  });

  test('asking without a transcript does nothing', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: _FakeChatService(['nope']), playbackSource: source);

    source.episodes.add(_episode('ep1'));

    bloc.ask('What is this about?');

    expect(bloc.currentState.messages, isEmpty);
    expect(bloc.currentState.busy, isFalse);

    bloc.dispose();
  });

  test('changing episode clears the conversation', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: _FakeChatService(['reply']), playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('First question');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.currentState.messages, isNotEmpty);

    source.episodes.add(_episode('ep2', subtitles: subtitles));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.currentState.messages, isEmpty);

    bloc.dispose();
  });

  test('stop ends the reply early', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(
      aiChatService: _FakeChatService(['one ', 'two ', 'three'], delay: const Duration(milliseconds: 100)),
      playbackSource: source,
    );

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('Go');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    bloc.stop();

    expect(bloc.currentState.busy, isFalse);
    expect(bloc.currentState.messages.last.text, contains('one'));
    expect(bloc.currentState.messages.last.text, isNot(contains('three')));

    bloc.dispose();
  });

  test('clear resets the conversation', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: _FakeChatService(['reply']), playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('Question');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    bloc.clear();

    expect(bloc.currentState.messages, isEmpty);

    bloc.dispose();
  });

  test('follow-up questions carry the prior conversation as history', () async {
    final service = _FakeChatService(['first reply']);
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: service, playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('First question');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    bloc.ask('Second question');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.requests, hasLength(2));
    expect(service.requests.first.history, isEmpty);

    final history = service.requests.last.history;
    expect(history, hasLength(2));
    expect(history[0].fromUser, isTrue);
    expect(history[0].text, 'First question');
    expect(history[1].fromUser, isFalse);
    expect(history[1].text, 'first reply');

    /// The current question must not be duplicated inside the history.
    expect(history.where((m) => m.text == 'Second question'), isEmpty);

    bloc.dispose();
  });

  test('a failure after partial text keeps the reply marked as failed', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: _FailingAfterChunkService(), playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('Go');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(bloc.currentState.busy, isFalse);
    expect(bloc.currentState.messages.last.text, 'partial answer ');
    expect(bloc.currentState.messages.last.pending, isFalse);
    expect(bloc.currentState.messages.last.error, isTrue);

    bloc.dispose();
  });

  test('stop aborts the in-flight provider request', () async {
    final service = _FakeChatService(['one ', 'two ', 'three'], delay: const Duration(milliseconds: 100));
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: service, playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('Go');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(service.cancelCount, 0);

    bloc.stop();

    expect(service.cancelCount, 1);

    bloc.dispose();
  });

  test('clear aborts the in-flight provider request', () async {
    final service = _FakeChatService(['one ', 'two ', 'three'], delay: const Duration(milliseconds: 100));
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: service, playbackSource: source);

    source.episodes.add(_episode('ep1', subtitles: subtitles));

    bloc.ask('Go');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    bloc.clear();

    expect(service.cancelCount, 1);

    bloc.dispose();
  });

  test('recent context window covers the lines before the current position', () async {
    final source = _FakePlaybackSource();
    final bloc = AiChatBloc(aiChatService: _FakeChatService(["x"]), playbackSource: source);

    final lines = <Subtitle>[
      for (var i = 0; i < 10; i++)
        Subtitle(
          index: i,
          start: Duration(minutes: i),
          end: Duration(minutes: i, seconds: 30),
          data: 'Line $i',
        ),
    ];

    source.position = const Duration(minutes: 8);
    final recent = bloc.recentLinesForTest(lines);

    expect(recent.first.start, const Duration(minutes: 3));
    expect(recent.last.start, const Duration(minutes: 8));

    bloc.dispose();
  });
}
