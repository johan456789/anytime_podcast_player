// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/ui/podcast/selection_action_bar.dart';
import 'package:anytime/ui/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'podcast_details_test_harness.dart'
    show captureRootTo, captureTo, fixtureEpisodes, fixturePodcast, loadAppFonts, pumpPodcastDetails;

/// Scrolls the episode list back to the top.
Future<void> scrollToTop(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 800));
    await tester.pump(const Duration(milliseconds: 100));
  }

  await tester.pump(const Duration(milliseconds: 300));
}

/// Scrolls down until the episode with the given title is visible.
Future<void> scrollUntilText(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200.0, scrollable: find.byType(Scrollable).first);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Dismisses any visible snack bar; the auto-hide timer plus exit animation
/// are flaky to drive with the test clock between flows. The page has its own
/// [ScaffoldMessenger] (nested inside MaterialApp's), which is the one that
/// hosts these snack bars.
Future<void> dismissSnackBars(WidgetTester tester) async {
  tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger).last).clearSnackBars();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Captures review screenshots of the episode multi-selection flows (no
/// golden comparison) to demo/screenshots/.
///
/// The fixtures cover the common flows: long-press to enter selection,
/// tapping to grow the selection, select all, and each bulk action with its
/// snackbar (mark played with undo, download, queue and delete downloads).
void main() {
  testWidgets('multi-select flows, dark theme (screenshot)', (tester) async {
    await loadAppFonts();

    final podcast = fixturePodcast(fixtureEpisodes(count: 10));

    await pumpPodcastDetails(tester, theme: Themes.darkTheme().themeData, podcast: podcast);

    expect(find.text('The Long Dark'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await captureTo(tester, 'demo/screenshots/multiselect-1-list-dark.png');

    /// 1. Long-press an episode to enter selection mode with it selected.
    await tester.longPress(find.text('The Long Dark'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.descendant(of: find.byType(SliverAppBar), matching: find.byIcon(Icons.close)), findsOneWidget);

    await captureTo(tester, 'demo/screenshots/multiselect-2-enter-dark.png');

    /// 2. Tap two more episodes to grow the selection.
    await tester.tap(find.text('Static Bloom'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Embers'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('3 selected'), findsOneWidget);

    // One more timed pump so the selection count animation has finished
    // before the capture.
    await tester.pump(const Duration(milliseconds: 200));

    await captureTo(tester, 'demo/screenshots/multiselect-3-partial-dark.png');

    /// 3. Select everything in the list.
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('10 selected'), findsOneWidget);
    expect(find.byIcon(Icons.deselect), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));

    await captureTo(tester, 'demo/screenshots/multiselect-4-all-dark.png');

    /// 4. Mark every selected episode as played; the snackbar offers undo.
    await tester.tap(find.text('Played'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Marked 8 episodes as played'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('1 selected'), findsNothing);

    // Timed pump so the snack bar entrance animation renders before capture.
    await tester.pump(const Duration(milliseconds: 300));

    await captureTo(tester, 'demo/screenshots/multiselect-5-marked-played-dark.png');

    /// 5. Undo restores the previous played state.
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pump(const Duration(milliseconds: 300));

    await captureTo(tester, 'demo/screenshots/multiselect-6-undo-dark.png');

    await dismissSnackBars(tester);

    /// 6. Queue two episodes; they are queued in selection order.
    await tester.longPress(find.text('The Long Dark'));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Static Bloom'));
    await tester.pump(const Duration(milliseconds: 250));

    // The selection with the action bar before the queue action.
    await tester.pump(const Duration(milliseconds: 200));

    await captureTo(tester, 'demo/screenshots/multiselect-7-queue-select-dark.png');

    await tester.tap(find.text('Queue'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Added 2 episodes to Up Next'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));

    await captureTo(tester, 'demo/screenshots/multiselect-8-queued-dark.png');

    await dismissSnackBars(tester);

    /// 7. Download two episodes; scroll down to reach them first.
    await scrollUntilText(tester, 'Neon Rain');

    await tester.longPress(find.text('Neon Rain'));
    await tester.pump(const Duration(milliseconds: 250));
    await scrollUntilText(tester, 'Dead Air');
    await tester.tap(find.text('Dead Air'));
    await tester.pump(const Duration(milliseconds: 250));

    // The selection before the download action, scrolled to the episodes.
    await tester.pump(const Duration(milliseconds: 200));

    await captureTo(tester, 'demo/screenshots/multiselect-9-download-select-dark.png');

    await tester.tap(find.text('Download'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Downloading 2 episodes'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));

    await captureTo(tester, 'demo/screenshots/multiselect-10-downloading-dark.png');

    await dismissSnackBars(tester);

    /// 8. Delete the downloads of two downloaded episodes; the destructive
    /// action is confirmed first.
    await scrollToTop(tester);
    await tester.longPress(find.text('Ferry Tales'));
    await tester.pump(const Duration(milliseconds: 250));
    await scrollUntilText(tester, 'Night Lines');
    await tester.tap(find.text('Night Lines'));
    await tester.pump(const Duration(milliseconds: 250));

    // The selection before the delete action; Delete is enabled, Download disabled.
    await tester.pump(const Duration(milliseconds: 200));

    await captureTo(tester, 'demo/screenshots/multiselect-11-delete-select-dark.png');

    await tester.tap(find.descendant(of: find.byType(SelectionActionBar), matching: find.byIcon(Icons.delete_outline)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Delete downloads'), findsOneWidget);

    // Timed pump so the dialog fade-in has rendered before capture; the
    // dialog lives in the root overlay, so capture the whole view.
    await tester.pump(const Duration(milliseconds: 200));

    await captureRootTo(tester, 'demo/screenshots/multiselect-12-delete-confirm-dark.png');

    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Deleted 2 downloads'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));

    await captureTo(tester, 'demo/screenshots/multiselect-13-deleted-dark.png');

    await dismissSnackBars(tester);
  });

  testWidgets('multi-select key states, light theme (screenshot)', (tester) async {
    await loadAppFonts();

    final podcast = fixturePodcast(fixtureEpisodes(count: 10));

    await pumpPodcastDetails(tester, theme: Themes.lightTheme().themeData, podcast: podcast);

    expect(find.text('The Long Dark'), findsOneWidget);

    await captureTo(tester, 'demo/screenshots/multiselect-1-list-light.png');

    /// Long-press, then tap another episode.
    await tester.longPress(find.text('The Long Dark'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Static Bloom'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('2 selected'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));

    await captureTo(tester, 'demo/screenshots/multiselect-2-enter-light.png');

    /// Select all and mark played.
    await tester.tap(find.byIcon(Icons.select_all));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Played'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Marked 8 episodes as played'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));

    await captureTo(tester, 'demo/screenshots/multiselect-3-marked-played-light.png');

    await dismissSnackBars(tester);
  });
}
