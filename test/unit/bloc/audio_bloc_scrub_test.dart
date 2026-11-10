// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/entities/sleep.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal audio service: the scrub stream under test does not touch the
/// audio backend at all.
class _StubAudioPlayerService extends AudioPlayerService {
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

void main() {
  late AudioBloc audioBloc;

  setUp(() {
    audioBloc = AudioBloc(audioPlayerService: _StubAudioPlayerService());
  });

  tearDown(() {
    audioBloc.dispose();
  });

  test('scrub position is seeded with null', () {
    expect(audioBloc.scrubPosition.valueOrNull, isNull);
  });

  test('scrub position emits the values it is given', () {
    final events = <Duration?>[];
    final subscription = audioBloc.scrubPosition.listen(events.add);

    audioBloc.transitionScrubPosition(const Duration(seconds: 10));
    audioBloc.transitionScrubPosition(const Duration(seconds: 20));

    expect(events, [
      isNull,
      const Duration(seconds: 10),
      const Duration(seconds: 20),
    ]);

    subscription.cancel();
  });

  test('scrub position de-duplicates equal consecutive values', () {
    final events = <Duration?>[];
    final subscription = audioBloc.scrubPosition.listen(events.add);
    const ten = Duration(seconds: 10);

    audioBloc.transitionScrubPosition(ten);
    audioBloc.transitionScrubPosition(const Duration(milliseconds: 10000)); // == ten
    audioBloc.transitionScrubPosition(null);
    audioBloc.transitionScrubPosition(null);

    expect(events, [isNull, ten, isNull]);

    subscription.cancel();
  });

  test('a listener added first receives the value synchronously within the same call', () {
    final events = <Duration?>[];
    final subscription = audioBloc.scrubPosition.listen(events.add);

    audioBloc.transitionScrubPosition(const Duration(seconds: 45));

    // No microtask or pump in between: synchronous delivery is what keeps the
    // progress bar bubble and the transcript from drifting a frame apart.
    expect(events, [isNull, const Duration(seconds: 45)]);

    subscription.cancel();
  });

  test('a late subscriber receives the current value immediately', () {
    audioBloc.transitionScrubPosition(const Duration(seconds: 45));

    final events = <Duration?>[];
    final subscription = audioBloc.scrubPosition.listen(events.add);

    expect(events, [const Duration(seconds: 45)]);

    subscription.cancel();
  });
}
