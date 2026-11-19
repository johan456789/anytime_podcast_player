// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/ui/podcast/mini_player.dart';
import 'package:anytime/ui/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_player_test_harness.dart' show fixtureEpisode, loadAppFonts;
import 'podcast_details_test_harness.dart' show captureTo, fixtureEpisodes, fixturePodcast, pumpPodcastDetails;

/// Verifies the podcast details page keeps the app chrome in place.
///
/// The page must show the mini player (when something is playing) and the
/// app's bottom navigation bar beneath the episode list, and the podcast
/// title must fade into the toolbar once the compact header has scrolled
/// away. Captures review screenshots (no golden comparison) to
/// demo/screenshots/.
void main() {
  testWidgets('mini player and bottom navigation stay visible on the details page, dark theme (screenshot)',
      (tester) async {
    await loadAppFonts();

    final podcast = fixturePodcast(fixtureEpisodes(count: 10));

    await pumpPodcastDetails(
      tester,
      theme: Themes.darkTheme().themeData,
      podcast: podcast,
      onReady: (audioPlayerService) {
        audioPlayerService.emitPlayback(episode: fixtureEpisode());
      },
    );

    // With playback active, the mini player and the app's bottom navigation
    // bar are both rendered below the episode list, stacked without a gap.
    final playerRect = tester.getRect(find.byType(MiniPlayer));
    final navigationRect = tester.getRect(find.byType(BottomNavigationBar));

    expect(find.text('Complete Spanish 34'), findsOneWidget);
    expect(playerRect.height, greaterThan(0.0));
    expect(playerRect.bottom, navigationRect.top);
    expect(tester.takeException(), isNull);

    await captureTo(tester, 'demo/screenshots/details-player-bar-dark.png');

    // Scrolling collapses the compact header; the toolbar title fades in.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(tester.getRect(find.byType(MiniPlayer)).bottom, navigationRect.top);

    await captureTo(tester, 'demo/screenshots/details-player-bar-scrolled-dark.png');
  });

  testWidgets(
      'without playback the mini player collapses and only the navigation bar remains, light theme (screenshot)',
      (tester) async {
    await loadAppFonts();

    final podcast = fixturePodcast(fixtureEpisodes(count: 10));

    await pumpPodcastDetails(
      tester,
      theme: Themes.lightTheme().themeData,
      podcast: podcast,
    );

    final playerRect = tester.getRect(find.byType(MiniPlayer));
    final navigationRect = tester.getRect(find.byType(BottomNavigationBar));

    expect(playerRect.height, 0.0);
    expect(playerRect.bottom, navigationRect.top);
    expect(tester.takeException(), isNull);

    await captureTo(tester, 'demo/screenshots/details-player-bar-stopped-light.png');
  });
}
