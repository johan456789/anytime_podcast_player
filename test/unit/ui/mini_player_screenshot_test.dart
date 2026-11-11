// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/ui/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_player_test_harness.dart';

/// Renders the mini players with a mid-playback episode and captures review
/// screenshots (no golden comparison) to demo/screenshots/.
///
/// The file name tag comes from --dart-define=SHOT_TAG=<tag> and defaults to
/// 'after'; pass 'before' when capturing the pre-change baseline.
const String shotTag = String.fromEnvironment('SHOT_TAG', defaultValue: 'after');

void main() {
  late AudioBloc audioBloc;
  late MiniPlayerTestAudioPlayerService audioPlayerService;

  /// The mini player must render a full-width progress bar with a playhead
  /// flush with the bottom of the player, half-filled for the 08:36 / 17:12
  /// fixture. The check is skipped when capturing a pre-feature baseline
  /// (SHOT_TAG=before), which renders the pre-bar widgets.
  void expectProgressBar(WidgetTester tester, {required Type player}) {
    if (shotTag == 'before') {
      return;
    }

    final barFinder = find.descendant(of: find.byType(player), matching: find.byType(MiniPlayerProgressBar));

    expect(barFinder, findsOneWidget);

    final barRect = tester.getRect(barFinder);
    final playerRect = tester.getRect(find.byType(player));

    // The bar is a 20px touch target hugging the player's bottom edge and
    // spanning its full width.
    expect(barRect.height, 20.0);
    expect(barRect.bottom, playerRect.bottom);
    expect(barRect.left, playerRect.left);
    expect(barRect.right, playerRect.right);

    // The playhead is centred on the track (track centre sits 6px above the
    // player's bottom edge) at the current progress.
    final knobRect = tester.getRect(find.byKey(const Key('miniplayer-playhead')));

    expect(knobRect.height, 12.0);
    expect(knobRect.center.dx, closeTo(barRect.center.dx, 1.0));
    expect(knobRect.center.dy, closeTo(playerRect.bottom - 6.0, 0.5));
    expect(knobRect.bottom, lessThanOrEqualTo(playerRect.bottom));
  }

  setUp(() {
    audioPlayerService = MiniPlayerTestAudioPlayerService();
    audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
  });

  tearDown(() {
    audioBloc.dispose();
    audioPlayerService.disposeService();
  });

  testWidgets('main screen mini player, dark theme (screenshot)', (tester) async {
    await loadAppFonts();

    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.darkTheme().themeData, sceneBuilder: (context) {
      return mainScreenScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });

    expect(find.text('Complete Spanish 34'), findsOneWidget);
    expectProgressBar(tester, player: MiniPlayer);
    expect(tester.takeException(), isNull);

    await captureTo(tester, 'demo/screenshots/miniplayer-progress-$shotTag-main-dark.png');
  });

  testWidgets('main screen mini player, light theme (screenshot)', (tester) async {
    await loadAppFonts();

    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.lightTheme().themeData, sceneBuilder: (context) {
      return mainScreenScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });

    expect(find.text('Complete Spanish 34'), findsOneWidget);
    expectProgressBar(tester, player: MiniPlayer);
    expect(tester.takeException(), isNull);

    await captureTo(tester, 'demo/screenshots/miniplayer-progress-$shotTag-main-light.png');
  });

  testWidgets('now playing floating player, dark theme (screenshot)', (tester) async {
    await loadAppFonts();

    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.darkTheme().themeData, sceneBuilder: (context) {
      return nowPlayingScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });

    expect(find.text('Complete Spanish 34'), findsOneWidget);
    expectProgressBar(tester, player: FloatingPlayer);
    expect(tester.takeException(), isNull);

    await captureTo(tester, 'demo/screenshots/miniplayer-progress-$shotTag-nowplaying-dark.png');
  });
}
