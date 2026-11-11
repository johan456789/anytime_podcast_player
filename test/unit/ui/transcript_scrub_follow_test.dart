// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/ui/themes.dart';
import 'package:anytime/ui/podcast/transcript_row_layout.dart';
import 'package:anytime/ui/podcast/transcript_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_player_test_harness.dart';

/// Behaviour tests for scrub-follow: the transcript highlights the caption at
/// the dragged timecode and follows the drag live with one frame, centre
/// anchoring clamps naturally at the list's bounds, and releasing the drag
/// applies the seek without any extra movement.
///
/// Each test asserts after a single pump; the absence of multi-frame
/// convergence is the point.
Finder transcriptList() =>
    find.byWidgetPredicate((w) => w is CustomScrollView && w.controller != null);

ScrollPosition scrollPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(of: transcriptList(), matching: find.byType(Scrollable)).first,
    )
    .position;

/// The fixture captions, which is the exact list the view renders.
List<Subtitle> get captions => fixtureTranscript().subtitles;

SubtitleWidget highlightedRow(WidgetTester tester) =>
    tester.widget<SubtitleWidget>(find.byWidgetPredicate((w) => w is SubtitleWidget && w.highlight));

int highlightedRowIndex(WidgetTester tester) => captions.indexOf(highlightedRow(tester).subtitle);

void main() {
  late AudioBloc audioBloc;
  late MiniPlayerTestAudioPlayerService audioPlayerService;
  late TranscriptRowLayout layout;

  setUp(() {
    audioPlayerService = MiniPlayerTestAudioPlayerService();
    audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
  });

  tearDown(() {
    audioBloc.dispose();
    audioPlayerService.disposeService();
  });

  /// Pumps the now-playing scene (floating player + transcript tab) with the
  /// fixture episode playing.
  Future<void> pumpTranscript(WidgetTester tester) async {
    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.lightTheme().themeData, sceneBuilder: (context) {
      return nowPlayingScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });
  }

  /// Drags the mini player's playhead from its current position to
  /// [fraction] of the bar (in one or more moves), keeping the gesture down.
  /// The caller owns releasing it.
  Future<TestGesture> scrubGesture(WidgetTester tester, double fraction, {int steps = 1}) async {
    final playhead = tester.getCenter(find.byKey(const Key('miniplayer-playhead')));
    final width = tester.getSize(find.byType(MiniPlayerProgressBar)).width;
    final gesture = await tester.startGesture(playhead);

    final dx = width * fraction - playhead.dx;

    for (var step = 1; step <= steps; step++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump();
    }

    return gesture;
  }

  /// Scrubs to [fraction] and releases.
  Future<void> scrubTo(WidgetTester tester, double fraction, {int steps = 1}) async {
    final gesture = await scrubGesture(tester, fraction, steps: steps);

    await gesture.up();
    await tester.pump();
  }

  /// Asserts the highlighted row is centred in the viewport, or - when the
  /// centre anchor falls outside the list - that the scroll clamps at the
  /// list's bounds with the first row flush at the top (last row flush at
  /// the bottom), as the natural clamps require.
  void expectCentreAnchoredOrClamped(WidgetTester tester) {
    final listRect = tester.getRect(transcriptList());
    final rowRect = tester.getRect(find.byWidgetPredicate((w) => w is SubtitleWidget && w.highlight));
    final rowExtent = layout.extentOf(captions.indexOf(highlightedRow(tester).subtitle));
    final index = highlightedRowIndex(tester);
    final idealTarget = layout.offsetOf(index) + rowExtent / 2 - listRect.height / 2;
    final maxExtent = scrollPosition(tester).maxScrollExtent;
    final clampedTop = idealTarget < 0;
    final clampedBottom = idealTarget > maxExtent;

    if (clampedTop) {
      expect(scrollPosition(tester).pixels, moreOrLessEquals(0.0, epsilon: 0.5),
          reason: 'scroll must clamp at 0');

      // The first row sits flush at the top; the highlighted row (which may
      // be a later row) sits naturally below it.
      final firstRowRect = tester.getRect(
        find.byWidgetPredicate((w) => w is SubtitleWidget && w.subtitle == captions[0]),
      );

      expect(firstRowRect.top, moreOrLessEquals(listRect.top, epsilon: 0.5));
    } else if (clampedBottom) {
      expect(scrollPosition(tester).pixels, moreOrLessEquals(maxExtent, epsilon: 0.5),
          reason: 'scroll must clamp at maxScrollExtent');

      // The last row sits flush at the bottom, with no trailing gap.
      final lastRowRect = tester.getRect(
        find.byWidgetPredicate((w) => w is SubtitleWidget && w.subtitle == captions[captions.length - 1]),
      );

      expect(lastRowRect.bottom, moreOrLessEquals(listRect.bottom, epsilon: 0.5));
    } else {
      expect(rowRect.center.dy, moreOrLessEquals(listRect.center.dy, epsilon: 0.5));
    }
  }

  testWidgets('scrubbing highlights the caption at the dragged time and centres it', (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    // 50% of the 17:12 fixture is 08:36, inside caption 34 (08:30 - 09:00).
    final gesture = await scrubGesture(tester, 0.5);
    await tester.pump();

    const dragged = Duration(seconds: 516);
    final expectedIndex = indexForPosition(captions, dragged);

    expect(expectedIndex, 34);
    expect(highlightedRowIndex(tester), expectedIndex);
    expectCentreAnchoredOrClamped(tester);

    // Release keeps everything where the drag left it: the confirmed seek
    // lands in the same caption, so no scroll and no highlight change.
    final offsetAtDrag = scrollPosition(tester).pixels;

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(audioPlayerService.positionSubject.valueOrNull!.position, dragged);
    expect(highlightedRowIndex(tester), expectedIndex);
    expect(scrollPosition(tester).pixels, offsetAtDrag);
  });

  testWidgets('sweeping 0-100% tracks the highlight and timecode bubble at every step', (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    const steps = 100;
    final lengthSeconds = fixtureLength.inSeconds;

    final width = tester.getSize(find.byType(MiniPlayerProgressBar)).width;
    final downPoint = tester.getCenter(find.byKey(const Key('miniplayer-playhead')));
    var currentFraction = downPoint.dx / width; // the fixture plays at 50%.

    final gesture = await tester.startGesture(downPoint);

    for (var step = 1; step <= steps; step++) {
      final fraction = step / steps;

      await gesture.moveBy(Offset(width * (fraction - currentFraction), 0));
      currentFraction = fraction;
      await tester.pump();

      final dragged = Duration(seconds: (fraction * lengthSeconds).round());
      final expectedIndex = indexForPosition(captions, dragged);

      // The highlighted row is the caption containing the dragged time...
      expect(highlightedRowIndex(tester), expectedIndex, reason: 'step $step ($dragged)');
      // ... the bubble shows the dragged timecode...
      expect(
        tester.widget<Text>(find.byKey(const Key('miniplayer-progress-bubble'))).data,
        _formatBubbleDuration(dragged),
        reason: 'step $step',
      );
      // ... and that timecode falls inside the highlighted caption's window.
      final highlighted = highlightedRow(tester).subtitle;
      expect(dragged, greaterThanOrEqualTo(highlighted.start), reason: 'step $step');
      expect(dragged, lessThan(highlighted.end!), reason: 'step $step');

      // At 0% the list is at the very top; at 100% the last row is flush at
      // the bottom. Otherwise the row is centred.
      expectCentreAnchoredOrClamped(tester);
    }

    // End of sweep: offset is the exact maxScrollExtent, row 0 sits at the
    // top when the drag returns to 0%.
    expect(scrollPosition(tester).pixels, moreOrLessEquals(scrollPosition(tester).maxScrollExtent, epsilon: 0.5));

    await gesture.up();
    await tester.pump();

    // Programmatic jumps never disable follow-transcript.
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });

  testWidgets('at 0% the first row sits at the top of the viewport', (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    await scrubTo(tester, 0.0);

    expect(scrollPosition(tester).pixels, moreOrLessEquals(0.0, epsilon: 0.5));
    expect(highlightedRowIndex(tester), 0);

    final listRect = tester.getRect(transcriptList());
    final rowRect = tester.getRect(find.byWidgetPredicate((w) => w is SubtitleWidget && w.highlight));

    expect(rowRect.top, moreOrLessEquals(listRect.top, epsilon: 0.5));
  });

  testWidgets('releasing a scrub at 63% is motionless through stale and confirmed positions',
      (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    // Hold the seek so the release's landing can be controlled, simulating
    // the audio service's seek latency.
    audioPlayerService.holdSeeks = true;

    await scrubTo(tester, 0.63);

    final offsetAfterRelease = scrollPosition(tester).pixels;
    final indexAfterRelease = highlightedRowIndex(tester);

    // 63% of 17:12 is 10:50:160ms; the seek is applied at whole seconds
    // (10:50) and confirms the scrubbed position.
    const pending = Duration(seconds: 650);

    // Stale pre-seek positions must be ignored while the seek is pending.
    audioPlayerService.emitPosition(const Duration(seconds: 516));
    await tester.pump();

    expect(scrollPosition(tester).pixels, offsetAfterRelease);
    expect(highlightedRowIndex(tester), indexAfterRelease);

    // The confirmed position lands in the same caption: nothing moves.
    audioPlayerService.holdSeeks = false;
    audioPlayerService.landHeldSeek();
    await tester.pump();

    // Normal playback ticks within the same caption (43 covers 10:45 up to
    // caption 44's start at 11:00): still motionless.
    for (var tick = 1; tick <= 5; tick++) {
      audioPlayerService.emitPosition(Duration(seconds: 650 + tick));
      await tester.pump(const Duration(milliseconds: 16));

      expect(scrollPosition(tester).pixels, offsetAfterRelease);
      expect(highlightedRowIndex(tester), indexAfterRelease);
    }

    // Two seconds of empty frames must not move anything either.
    final offsetBeforeIdle = scrollPosition(tester).pixels;

    for (var frame = 0; frame < 125; frame++) {
      await tester.pump(const Duration(milliseconds: 16));

      expect(scrollPosition(tester).pixels, offsetBeforeIdle);
      expect(highlightedRowIndex(tester), indexAfterRelease);
    }

    // Sanity: the scrubbed position really was in the same caption.
    expect(indexForPosition(captions, pending), indexAfterRelease);
  });

  testWidgets('releasing a scrub at 100% is motionless (the old backward-slide case)',
      (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    audioPlayerService.holdSeeks = true;

    await scrubTo(tester, 1.0);

    final offsetAfterRelease = scrollPosition(tester).pixels;
    final indexAfterRelease = highlightedRowIndex(tester);

    expect(indexAfterRelease, captions.length - 1);
    expect(scrollPosition(tester).pixels, moreOrLessEquals(scrollPosition(tester).maxScrollExtent, epsilon: 0.5));

    audioPlayerService.emitPosition(const Duration(seconds: 516));
    await tester.pump();

    expect(scrollPosition(tester).pixels, offsetAfterRelease);

    audioPlayerService.holdSeeks = false;
    audioPlayerService.landHeldSeek();
    await tester.pump();

    expect(scrollPosition(tester).pixels, offsetAfterRelease);
    expect(highlightedRowIndex(tester), indexAfterRelease);
  });

  testWidgets('a caption starting mid-second does not move the highlight on release', (tester) async {
    // Real VTT/SRT captions start at fractional seconds. The scrubbed
    // position is whole seconds end to end (bubble, scrub event, pending
    // seek and the seek itself), so the confirmed position is the exact
    // scrubbed value and the release can never shift the highlight back
    // into the previous caption - the regression the millisecond contract
    // had.
    final custom = <Subtitle>[
      Subtitle(
          index: 0,
          start: const Duration(seconds: 0),
          end: const Duration(milliseconds: 10400),
          data: 'caption A'),
      Subtitle(
          index: 1,
          start: const Duration(milliseconds: 10400),
          end: const Duration(milliseconds: 25000),
          data: 'caption B'),
      Subtitle(
          index: 2,
          start: const Duration(milliseconds: 25000),
          end: const Duration(milliseconds: 40000),
          data: 'caption C'),
    ];

    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: custom, spec: spec, width: tester.getSize(transcriptList()).width);

    audioPlayerService.emitTranscript(Transcript(subtitles: custom));
    await tester.pump();

    // 10.7s is inside caption B (10.4s .. 25s); its whole-second scrub is
    // 11s, which is inside the same caption.
    const scrubbed = Duration(seconds: 11);
    final fraction = 11 / fixtureLength.inSeconds;

    final gesture = await scrubGesture(tester, fraction);
    await tester.pump();

    final highlighted = find.byWidgetPredicate((w) => w is SubtitleWidget && w.highlight);
    final offsetAtDrag = scrollPosition(tester).pixels;

    expect(tester.widget<SubtitleWidget>(highlighted).subtitle, same(custom[1]));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // The seek confirmed at the scrubbed whole second, inside the same
    // caption: nothing moved.
    expect(audioPlayerService.positionSubject.valueOrNull!.position, scrubbed);
    expect(tester.widget<SubtitleWidget>(highlighted).subtitle, same(custom[1]));
    expect(scrollPosition(tester).pixels, offsetAtDrag);
  });

  testWidgets('a seek that never confirms resumes normal follow after the timeout', (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    audioPlayerService.holdSeeks = true;

    await scrubTo(tester, 0.63);

    final offsetAfterRelease = scrollPosition(tester).pixels;
    final indexAfterRelease = highlightedRowIndex(tester);

    // Stale positions only, for three seconds: the seek never confirms and
    // the transcript stays exactly where the scrub left it.
    for (var i = 0; i < 30; i++) {
      audioPlayerService.emitPosition(const Duration(seconds: 516));
      await tester.pump(const Duration(milliseconds: 100));

      expect(scrollPosition(tester).pixels, offsetAfterRelease);
      expect(highlightedRowIndex(tester), indexAfterRelease);
    }

    // Past the 3s safety timeout the stale hold must be lifted: the next
    // playback position is accepted and normal follow resumes (back to
    // 08:36, where playback actually is).
    audioPlayerService.emitPosition(const Duration(seconds: 516));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    final resumedIndex = indexForPosition(captions, const Duration(seconds: 516));

    expect(resumedIndex, 34);
    expect(highlightedRowIndex(tester), resumedIndex);
    expect(scrollPosition(tester).pixels,
        moreOrLessEquals(_targetFor(tester, layout, resumedIndex!), epsilon: 0.5));

    // And a further position is followed as normal.
    audioPlayerService.emitPosition(const Duration(seconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    final expectedIndex = indexForPosition(captions, const Duration(seconds: 200));

    expect(expectedIndex, 13);
    expect(highlightedRowIndex(tester), expectedIndex);
    expect(scrollPosition(tester).pixels,
        moreOrLessEquals(_targetFor(tester, layout, expectedIndex!), epsilon: 0.5));
  });

  testWidgets('playback follows gently across caption boundaries', (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    // Move to caption 32's window (08:00 - 08:30) and let the follow settle.
    audioPlayerService.emitPosition(const Duration(seconds: 490));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    var expectedIndex = indexForPosition(captions, const Duration(seconds: 490));

    expect(expectedIndex, 32);

    expect(highlightedRowIndex(tester), expectedIndex);
    expect(scrollPosition(tester).pixels, moreOrLessEquals(_targetFor(tester, layout, expectedIndex!), epsilon: 0.5));

    // Ticks inside the same caption (32 covers 08:00 up to caption 33's
    // start at 08:15) do not move the list.
    final offsetBefore = scrollPosition(tester).pixels;

    audioPlayerService.emitPosition(const Duration(seconds: 493));
    await tester.pump();

    expect(highlightedRowIndex(tester), expectedIndex);
    expect(scrollPosition(tester).pixels, offsetBefore);

    // Crossing into caption 33 animates to its centred target.
    audioPlayerService.emitPosition(const Duration(seconds: 505));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expectedIndex = indexForPosition(captions, const Duration(seconds: 505));

    expect(expectedIndex, 33);
    expect(highlightedRowIndex(tester), expectedIndex);
    expect(scrollPosition(tester).pixels, moreOrLessEquals(_targetFor(tester, layout, expectedIndex!), epsilon: 0.5));
  });

  testWidgets('dragging the list disables follow; a scrub then highlights without scrolling',
      (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    // A real user drag on the list turns follow off.
    await tester.drag(transcriptList(), const Offset(0, -200));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    final offsetAfterDrag = scrollPosition(tester).pixels;

    // Scrub to a caption that is visible after the drag: the highlight
    // moves to it but the list must not scroll.
    final visibleIndices = tester
        .widgetList<SubtitleWidget>(find.byType(SubtitleWidget))
        .map((w) => captions.indexOf(w.subtitle))
        .toList();
    final targetIndex = visibleIndices.first;
    final targetTime = captions[targetIndex].start + const Duration(seconds: 1);

    await scrubTo(tester, targetTime.inMilliseconds / fixtureLength.inMilliseconds);

    expect(highlightedRowIndex(tester), targetIndex);
    expect(scrollPosition(tester).pixels, offsetAfterDrag);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    // Follow back on: the switch re-anchors and stays on while the scrub
    // jumps and playback animates.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await scrubTo(tester, 0.5);

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    audioPlayerService.emitPosition(const Duration(seconds: 200));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpAndSettle(const Duration(milliseconds: 16));

    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(highlightedRowIndex(tester), indexForPosition(captions, const Duration(seconds: 200)));
  });

  testWidgets('with a search filter active the highlight is computed against the filtered list',
      (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    // 'timecode 00' keeps only the captions that start in the first minute
    // (00:00, 00:15, 00:30, 00:45).
    await tester.enterText(find.byType(TextField), 'timecode 00');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump();

    // The exact filtered list the view renders comes from the service.
    final filtered = audioPlayerService.transcriptSubject.valueOrNull!.transcript!.subtitles;

    expect(filtered.length, 4);

    // Scrub to 100s: the full list would highlight caption 6, which was
    // filtered out; the filtered list highlights caption 3 (the last one
    // starting at or before 100s).
    await scrubTo(tester, const Duration(seconds: 100).inMilliseconds / fixtureLength.inMilliseconds);

    final expectedFilteredIndex = indexForPosition(filtered, const Duration(seconds: 100));

    expect(expectedFilteredIndex, 3);
    expect(highlightedRowIndex(tester), 3);
    expect(
      highlightedRow(tester).subtitle,
      same(filtered[3]),
    );

    // And nothing rendered out of range: only the four filtered rows exist.
    expect(tester.widgetList<SubtitleWidget>(find.byType(SubtitleWidget)).length, lessThan(5));
  });

  testWidgets('resizing the viewport and changing the text scale re-anchors the highlighted row',
      (tester) async {
    await pumpTranscript(tester);

    final spec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(subtitles: captions, spec: spec, width: tester.getSize(transcriptList()).width);

    await scrubTo(tester, 0.5);

    final index = highlightedRowIndex(tester);

    expect(index, 34);
    expectCentreAnchoredOrClamped(tester);

    // Resize the window: narrower width changes the measured layout, and the
    // highlighted row is re-centred in the new viewport.
    tester.view.physicalSize = const Size(780 * 3.0, 1200 * 3.0);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();

    final resizedSpec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(
      subtitles: captions,
      spec: resizedSpec,
      width: tester.getSize(transcriptList()).width,
    );

    expect(highlightedRowIndex(tester), index);
    expectCentreAnchoredOrClamped(tester);

    // Change the system text scale: the layout is recomputed again and the
    // row is re-centred.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump();

    final scaledSpec = TranscriptRowSpec.of(tester.element(transcriptList()));
    layout = TranscriptRowLayout.compute(
      subtitles: captions,
      spec: scaledSpec,
      width: tester.getSize(transcriptList()).width,
    );

    expect(highlightedRowIndex(tester), index);
    expectCentreAnchoredOrClamped(tester);
  });
}

/// Formats a dragged timecode exactly like the progress bar's bubble does
/// (hours only shown past one hour; the fixture is under an hour).
String _formatBubbleDuration(Duration duration) {
  String twoDigits(int n) => n >= 10 ? '$n' : '0$n';
  final minutes = twoDigits(duration.inMinutes.remainder(60).toInt());
  final seconds = twoDigits(duration.inSeconds.remainder(60).toInt());

  if (duration.inHours > 0) {
    return '${twoDigits(duration.inHours)}:$minutes:$seconds';
  }

  return '$minutes:$seconds';
}

/// The centred (and clamped) scroll target for [index], as the view computes it.
double _targetFor(WidgetTester tester, TranscriptRowLayout layout, int index) {
  final viewport = tester.getRect(transcriptList()).height;
  final centre = layout.offsetOf(index) + layout.extentOf(index) / 2;

  return (centre - viewport / 2).clamp(0.0, double.infinity);
}
