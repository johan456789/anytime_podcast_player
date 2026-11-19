// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/ui/themes.dart';
import 'package:anytime/ui/widgets/podcast_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_player_test_harness.dart';

/// Geometry tests for the mini players' progress bar placement.
///
/// Both mini players sit flush above another surface: the floating player
/// above the now playing options sheet when it is fully expanded, and the
/// main screen mini player above the bottom navigation bar. The progress
/// bar must stay clear of both neighbours: the playhead must not touch the
/// player's bottom edge (where the next surface starts) and must not
/// collide with the artwork above it. Before the spacing fix the playhead's
/// bottom edge sat exactly on the player's bottom edge, visually
/// overlapping the surface below.
void main() {
  late AudioBloc audioBloc;
  late MiniPlayerTestAudioPlayerService audioPlayerService;

  setUp(() {
    audioPlayerService = MiniPlayerTestAudioPlayerService();
    audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
  });

  tearDown(() {
    audioBloc.dispose();
    audioPlayerService.disposeService();
  });

  /// Minimum breathing room, in logical pixels, between the playhead and
  /// whatever starts directly below the player's bottom edge.
  const sheetClearance = 4.0;

  testWidgets('the expanded floating player keeps the playhead clear of the sheet below it',
      (tester) async {
    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.darkTheme().themeData, sceneBuilder: (context) {
      return nowPlayingScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });

    final playerRect = tester.getRect(find.byType(FloatingPlayer));
    final playheadRect = tester.getRect(find.byKey(const Key('miniplayer-playhead')));
    final barRect = tester.getRect(find.byType(MiniPlayerProgressBar));

    // The playhead (the lowest element of the bar) must sit above the
    // player's bottom edge, which is where the options sheet begins.
    expect(playerRect.bottom - playheadRect.bottom, greaterThanOrEqualTo(sheetClearance));
    expect(playerRect.bottom - barRect.bottom, greaterThanOrEqualTo(sheetClearance));

    // And it must not reach into the content row above.
    final artworkRect = tester.getRect(find.byType(PodcastImage).first);

    expect(playheadRect.top - artworkRect.bottom, greaterThanOrEqualTo(sheetClearance));
  });

  testWidgets('the main screen mini player keeps the playhead clear of the navigation bar below it',
      (tester) async {
    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.darkTheme().themeData, sceneBuilder: (context) {
      return mainScreenScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });

    final playerRect = tester.getRect(find.byType(MiniPlayer));
    final playheadRect = tester.getRect(find.byKey(const Key('miniplayer-playhead')));

    // The navigation bar starts flush against the mini player's bottom
    // edge; the playhead must stop short of it.
    expect(playerRect.bottom - playheadRect.bottom, greaterThanOrEqualTo(sheetClearance));

    // And it must not reach into the content row above.
    final artworkRect = tester.getRect(find.byType(PodcastImage).first);

    expect(playheadRect.top - artworkRect.bottom, greaterThanOrEqualTo(0.0));
  });
}
