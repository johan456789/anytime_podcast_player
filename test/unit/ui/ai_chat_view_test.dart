// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/ai/ai_chat_bloc.dart';
import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/entities/sleep.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/state/transcript_state_event.dart';
import 'package:anytime/ui/podcast/ai_chat_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

/// Minimal audio service: the view only renders once the transcript stream
/// reports an available transcript, and never plays anything in this test.
class _FakeAudioPlayerService extends AudioPlayerService {
  final _transcript = BehaviorSubject<TranscriptState>();

  @override
  Stream<TranscriptState>? get transcriptEvent => _transcript;

  void emitTranscript(TranscriptState state) => _transcript.add(state);

  void disposeService() => _transcript.close();

  @override
  Future<void> playEpisode({required Episode episode, bool resume = true}) async {}

  @override
  Future<void> playLatestEpisode({required Podcast podcast, bool resume = true}) async {}

  @override
  Future<void> playNextUnplayedEpisode({required Podcast podcast, bool resume = true}) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> rewind() async {}

  @override
  Future<void> fastForward() async {}

  @override
  Future<void> seek({required int position}) async {}

  @override
  Future<Episode?> resume() async => null;

  @override
  Future<void> addUpNextLatestEpisode({required Podcast podcast}) async {}

  @override
  Future<void> addUpNextUnplayedEpisode({required Podcast podcast}) async {}

  @override
  Future<void> addUpNextEpisode(Episode episode) async {}

  @override
  Future<bool> removeUpNextEpisode(Episode episode) async => true;

  @override
  Future<bool> moveUpNextEpisode(Episode episode, int oldIndex, int newIndex) async => true;

  @override
  Future<void> clearUpNext() async {}

  @override
  Future<void> suspend() async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> trimSilence(bool trim) async {}

  @override
  Future<void> volumeBoost(bool boost) async {}

  @override
  Future<void> searchTranscript(String search) async {}

  @override
  Future<void> clearTranscript() async {}

  @override
  void sleep(Sleep sleep) {}
}

class _FakeChatService extends AiChatService {
  @override
  Stream<String> send(AiChatRequest request) async* {
    yield 'Here is a long reply so the conversation grows tall enough to scroll:\n\n';

    for (final point in ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight']) {
      yield '- point $point with some wrapping text to take up vertical space\n';
    }
  }
}

class _FakePlaybackSource extends AiChatPlaybackSource {
  @override
  Episode? get currentEpisode => Episode(
        guid: 'episode-1',
        podcast: 'podcast',
        title: 'Episode 1',
      )..transcript = Transcript(subtitles: [
          Subtitle(
              index: 0,
              start: const Duration(minutes: 1),
              end: const Duration(minutes: 1, seconds: 5),
              data: 'Hello world'),
        ]);

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Stream<Episode?>? get episodeEvents => const Stream<Episode?>.empty();
}

void main() {
  late AudioBloc audioBloc;
  late AiChatBloc aiChatBloc;
  late _FakeAudioPlayerService audioPlayerService;

  Future<void> pumpChat(WidgetTester tester,
      {EdgeInsets viewInsets = EdgeInsets.zero, EdgeInsets padding = EdgeInsets.zero}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AudioBloc>.value(value: audioBloc),
          Provider<AiChatBloc>.value(value: aiChatBloc),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AnytimeLocalisationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
          ],
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360.0, 720.0),
              devicePixelRatio: 2.0,
              viewInsets: viewInsets,
              padding: padding,
            ),
            child: const Scaffold(
              // The real sheet is not a Scaffold, so it does not resize
              // itself; this mirrors the layout the chat actually lives in.
              resizeToAvoidBottomInset: false,
              body: AiChatView(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    audioPlayerService = _FakeAudioPlayerService();
    audioPlayerService.emitTranscript(TranscriptUpdateState(
      transcript: Transcript(subtitles: [
        Subtitle(
            index: 0,
            start: const Duration(minutes: 1),
            end: const Duration(minutes: 1, seconds: 5),
            data: 'Hello world'),
      ]),
    ));
    audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
    aiChatBloc = AiChatBloc(aiChatService: _FakeChatService(), playbackSource: _FakePlaybackSource());
  });

  tearDown(() {
    aiChatBloc.dispose();
    audioBloc.dispose();
    audioPlayerService.disposeService();
  });

  group('AiChatView input visibility', () {
    testWidgets('input sits above the keyboard inset', (tester) async {
      const keyboardHeight = 300.0;

      await pumpChat(tester, viewInsets: const EdgeInsets.only(bottom: keyboardHeight));

      final inputBottom = tester.getBottomRight(find.byType(TextField)).dy;

      // The test surface is 600 logical pixels high; the input must sit
      // above the keyboard, which covers the bottom 300.
      expect(inputBottom, lessThanOrEqualTo(600.0 - keyboardHeight));
    });

    testWidgets('input sits above the display padding when the keyboard is closed', (tester) async {
      await pumpChat(tester, padding: const EdgeInsets.only(bottom: 24.0));

      final inputBottom = tester.getBottomRight(find.byType(TextField)).dy;

      expect(inputBottom, lessThanOrEqualTo(600.0 - 24.0));
    });

    testWidgets('input fills the pane when no insets are present', (tester) async {
      await pumpChat(tester);

      final inputBottom = tester.getBottomRight(find.byType(TextField)).dy;

      expect(inputBottom, lessThanOrEqualTo(600.0));
      expect(inputBottom, greaterThan(500.0));
    });
  });

  group('AiChatView scroll position across keyboard changes', () {
    ScrollPosition listPosition(WidgetTester tester) {
      return tester
          .state<ScrollableState>(find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first)
          .position;
    }

    Future<void> exchange(WidgetTester tester, String question) async {
      aiChatBloc.ask(question);
      await tester.pumpAndSettle();
    }

    void usePhoneSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(720.0, 1440.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('preserves the reading position when the keyboard opens', (tester) async {
      usePhoneSurface(tester);

      await pumpChat(tester);

      for (var i = 0; i < 4; i++) {
        await exchange(tester, 'Question $i');
      }

      // Scroll up into the older part of the conversation, well away from
      // the newest message.
      await tester.drag(find.byType(ListView), const Offset(0.0, 400.0));
      await tester.pumpAndSettle();

      final position = listPosition(tester);
      expect(position.maxScrollExtent - position.pixels, greaterThanOrEqualTo(240.0),
          reason: 'precondition: the user is scrolled away from the end');

      await pumpChat(tester, viewInsets: const EdgeInsets.only(bottom: 300.0));
      await tester.pumpAndSettle();

      // The user was reading above the end, so the keyboard must not yank
      // the list back down to the newest message.
      expect(position.maxScrollExtent - position.pixels, greaterThanOrEqualTo(240.0));
    });

    testWidgets('pins back to the newest message when reading near the end', (tester) async {
      usePhoneSurface(tester);

      await pumpChat(tester, viewInsets: const EdgeInsets.only(bottom: 300.0));

      // The scroll controller has no clients until the first message batch
      // lays out, so pinning starts from the second exchange on.
      await exchange(tester, 'Question 1');
      await exchange(tester, 'Question 2');

      final position = listPosition(tester);
      expect(position.pixels, position.maxScrollExtent);

      // Still reading the latest message when the keyboard closes, so the
      // list follows the inset change and stays pinned to the end.
      await pumpChat(tester);
      await tester.pumpAndSettle();

      expect(position.pixels, position.maxScrollExtent);
    });
  });
}
