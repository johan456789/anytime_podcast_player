// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/ui/themes.dart';
import 'package:anytime/ui/podcast/transcript_row_layout.dart';
import 'package:anytime/ui/podcast/transcript_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'mini_player_test_harness.dart';

/// Tests for the transcript's pure logic and its exact row geometry: the
/// highlight index search, the speaker back-scan, and - critically - that
/// the measured row heights (which position every row in the list) match
/// what [SubtitleWidget] actually renders.
void main() {
  group('indexForPosition', () {
    final subtitles = <Subtitle>[
      for (var i = 0; i < 5; i++)
        Subtitle(
          index: i,
          start: Duration(seconds: i * 15),
          end: Duration(seconds: (i + 1) * 15),
          data: 'caption $i',
        ),
    ];

    test('empty list has no highlight', () {
      expect(indexForPosition(<Subtitle>[], const Duration(seconds: 30)), isNull);
    });

    test('before the first caption there is no highlight', () {
      expect(indexForPosition(subtitles, const Duration(seconds: -1)), isNull);
    });

    test('exactly at a caption start selects that caption', () {
      expect(indexForPosition(subtitles, const Duration(seconds: 30)), 2);
    });

    test('exactly at a boundary between contiguous captions selects the next one', () {
      // end(2) == start(3): position 45 must choose caption 3.
      expect(indexForPosition(subtitles, const Duration(seconds: 45)), 3);
    });

    test('inside a caption selects it', () {
      expect(indexForPosition(subtitles, const Duration(seconds: 37)), 2);
    });

    test('in a silence gap the caption before the gap stays highlighted', () {
      final gapped = <Subtitle>[
        Subtitle(index: 0, start: const Duration(seconds: 0), end: const Duration(seconds: 10), data: 'a'),
        Subtitle(index: 1, start: const Duration(seconds: 20), end: const Duration(seconds: 30), data: 'b'),
      ];

      expect(indexForPosition(gapped, const Duration(seconds: 15)), 0);
    });

    test('after the last caption the last caption stays highlighted', () {
      expect(indexForPosition(subtitles, const Duration(minutes: 5)), 4);
    });

    test('single caption matches from its start onwards', () {
      final single = <Subtitle>[
        Subtitle(index: 0, start: const Duration(seconds: 10), end: const Duration(seconds: 20), data: 'a'),
      ];

      expect(indexForPosition(single, const Duration(seconds: 9)), isNull);
      expect(indexForPosition(single, const Duration(seconds: 10)), 0);
      expect(indexForPosition(single, const Duration(minutes: 2)), 0);
    });
  });

  group('speakerForIndex', () {
    test('uses the explicit speaker field when present', () {
      final items = <Subtitle>[
        Subtitle(index: 0, start: const Duration(seconds: 0), end: const Duration(seconds: 10), data: 'hello'),
        Subtitle(
          index: 1,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
          data: 'hi',
          speaker: 'HAN',
        ),
      ];

      expect(speakerForIndex(items, 1), 'HAN');
    });

    test('back-scans caption bodies for a speaker prefix', () {
      final items = <Subtitle>[
        Subtitle(index: 0, start: const Duration(seconds: 0), data: '[HAN]: welcome back'),
        Subtitle(index: 1, start: const Duration(seconds: 10), data: 'thanks for listening'),
        Subtitle(index: 2, start: const Duration(seconds: 20), data: 'let us begin'),
      ];

      expect(speakerForIndex(items, 2), 'HAN');
      expect(speakerForIndex(items, 1), 'HAN');
      expect(speakerForIndex(items, 0), 'HAN');
    });

    test('stops scanning after 50 lines', () {
      final items = <Subtitle>[
        Subtitle(index: 0, start: const Duration(seconds: 0), data: '[HAN]: welcome'),
        for (var i = 1; i < 60; i++) Subtitle(index: i, start: Duration(seconds: i * 10), data: 'plain line $i'),
      ];

      // The speaker is 59 lines back, beyond the 50-line scan limit.
      expect(speakerForIndex(items, 59), '');
      expect(speakerForIndex(items, 40), 'HAN');
    });
  });

  group('sortedByStartIfNeeded', () {
    Subtitle s(int seconds) => Subtitle(index: seconds, start: Duration(seconds: seconds), data: 'x');

    test('returns the same list when already sorted', () {
      final items = <Subtitle>[s(0), s(5), s(10)];

      expect(identical(sortedByStartIfNeeded(items), items), isTrue);
    });

    test('returns a sorted copy when unsorted', () {
      final items = <Subtitle>[s(10), s(0), s(5)];
      final sorted = sortedByStartIfNeeded(items);

      expect(sorted.map((s) => s.start.inSeconds), [0, 5, 10]);
      expect(identical(sorted, items), isFalse);
    });
  });

  group('row geometry matches the render', () {
    /// Captions chosen to exercise every row-shape input: a short line, a
    /// long line wrapping to several lines, inline markup, an explicit
    /// speaker in the header, and an empty body.
    final captions = <Subtitle>[
      Subtitle(index: 0, start: const Duration(seconds: 0), data: 'Short line.'),
      Subtitle(
        index: 1,
        start: const Duration(seconds: 15),
        data: 'A much longer caption that will comfortably wrap onto four or more '
            'rendered lines at the narrowest width we test, because it just '
            'keeps going and going with plenty of ordinary words to lay out.',
      ),
      Subtitle(
        index: 2,
        start: const Duration(seconds: 30),
        data: 'A caption with <b>bold</b>, <i>italic</i> and <u>underline</u> '
            'markup spread across enough text to need more than one line.',
      ),
      Subtitle(
        index: 3,
        start: const Duration(seconds: 45),
        speaker: 'HAN',
        data: 'A caption with an explicit speaker in the header.',
      ),
      Subtitle(index: 4, start: const Duration(seconds: 60), data: ''),
    ];

    testWidgets('each rendered row height equals the measured extent within 0.5px', (tester) async {
      final audioPlayerService = _UnusedAudioPlayerService();
      final audioBloc = AudioBloc(audioPlayerService: audioPlayerService);

      addTearDown(() {
        audioBloc.dispose();
      });

      TranscriptRowSpec? spec;

      for (final theme in [Themes.lightTheme().themeData, Themes.darkTheme().themeData]) {
        for (final width in [320.0, 411.0, 800.0]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final caption in captions) {
              await tester.pumpWidget(
                Provider<AudioBloc>.value(
                  value: audioBloc,
                  child: MaterialApp(
                    theme: theme,
                    home: MediaQuery(
                      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                      child: Scaffold(
                        body: SingleChildScrollView(
                          child: SizedBox(
                            width: width,
                            child: Builder(
                              builder: (innerContext) {
                                spec = TranscriptRowSpec.of(innerContext);

                                return SubtitleWidget(
                                  key: const Key('row'),
                                  spec: spec!,
                                  subtitle: caption,
                                  highlight: true,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pump();

              // One layout over all captions; the row under test is index 0
              // of the single-caption list, but build the layout over every
              // caption to exercise the same prefix-sum code the list uses.
              final layout = TranscriptRowLayout.compute(
                subtitles: captions,
                spec: spec!,
                width: width,
              );

              final renderedHeight = tester.getSize(find.byKey(const Key('row'))).height;
              final measuredHeight = layout.extentOf(captions.indexOf(caption));

              expect(
                (renderedHeight - measuredHeight).abs(),
                lessThan(0.5),
                reason: 'caption ${caption.index} at width $width scale $scale '
                    '(${theme.brightness}): rendered $renderedHeight vs measured $measuredHeight',
              );
            }
          }
        }
      }
    });
  });

  group('row geometry with accessibility bold text', () {
    /// Text applies the bold-text override after merging the styles; the
    /// spec must mirror that order or headers can wrap on screen but not in
    /// the measurement (and the row gets clipped).
    testWidgets('measured extents match rendered rows with boldText on', (tester) async {
      final captions = <Subtitle>[
        Subtitle(
          index: 0,
          start: const Duration(seconds: 45),
          speaker: 'HAN',
          data: 'A caption with an explicit speaker in the header, long '
              'enough that its header has to make up its mind about wrapping.',
        ),
        Subtitle(
          index: 1,
          start: const Duration(seconds: 60),
          data: 'A body line that will wrap several times at the narrow '
              'width while the bold override is active.',
        ),
      ];

      final audioPlayerService = _UnusedAudioPlayerService();
      final audioBloc = AudioBloc(audioPlayerService: audioPlayerService);

      addTearDown(() {
        audioBloc.dispose();
      });

      TranscriptRowSpec? spec;

      for (final width in [320.0, 411.0]) {
        for (final scale in [1.0, 2.0]) {
          for (final caption in captions) {
            await tester.pumpWidget(
              Provider<AudioBloc>.value(
                value: audioBloc,
                child: MaterialApp(
                  theme: Themes.lightTheme().themeData,
                  home: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(scale),
                      boldText: true,
                    ),
                    child: Scaffold(
                      body: SingleChildScrollView(
                        child: SizedBox(
                          width: width,
                          child: Builder(
                            builder: (innerContext) {
                              spec = TranscriptRowSpec.of(innerContext);

                              return SubtitleWidget(
                                key: const Key('row'),
                                spec: spec!,
                                subtitle: caption,
                                highlight: true,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pump();

            // The bold override must actually be active in this tree, or
            // the test proves nothing.
            expect(MediaQuery.boldTextOf(tester.element(find.byKey(const Key('row')))), isTrue);

            final layout = TranscriptRowLayout.compute(
              subtitles: captions,
              spec: spec!,
              width: width,
            );

            final renderedHeight = tester.getSize(find.byKey(const Key('row'))).height;
            final measuredHeight = layout.extentOf(captions.indexOf(caption));

            expect(
              (renderedHeight - measuredHeight).abs(),
              lessThan(0.5),
              reason: 'caption ${caption.index} at width $width scale $scale with boldText: '
                  'rendered $renderedHeight vs measured $measuredHeight',
            );
          }
        }
      }
    });
  });

  group('list scroll extent', () {
    testWidgets('maxScrollExtent equals totalExtent minus the viewport dimension', (tester) async {
      late AudioBloc audioBloc;
      late MiniPlayerTestAudioPlayerService audioPlayerService;

      audioPlayerService = MiniPlayerTestAudioPlayerService();
      audioBloc = AudioBloc(audioPlayerService: audioPlayerService);

      addTearDown(() {
        audioBloc.dispose();
        audioPlayerService.disposeService();
      });

      await pumpScene(tester, audioBloc: audioBloc, theme: Themes.lightTheme().themeData, sceneBuilder: (context) {
        return nowPlayingScene(context);
      }, onMounted: () {
        audioPlayerService.emitPlayback(episode: fixtureEpisode());
      });

      final listFinder = find.byWidgetPredicate((w) => w is CustomScrollView && w.controller != null);

      expect(listFinder, findsOneWidget);

      final listSize = tester.getSize(listFinder);
      final spec = TranscriptRowSpec.of(tester.element(listFinder));
      final layout = TranscriptRowLayout.compute(
        subtitles: fixtureTranscript().subtitles,
        spec: spec,
        width: listSize.width,
      );

      final position = tester
          .state<ScrollableState>(find.descendant(of: listFinder, matching: find.byType(Scrollable)).first)
          .position;
      final expected = (layout.totalExtent - position.viewportDimension).clamp(0.0, double.infinity);

      expect(position.maxScrollExtent, closeTo(expected, 0.5));
    });
  });

  group('long transcript measurement', () {
    /// A ~3h, 5000 caption transcript with realistic, varied captions: 1-4
    /// rendered lines, some with speakers and inline markup.
    Transcript longTranscript() {
      const captionCount = 5000;
      const captionSeconds = 2; // 5000 * 2s = 10000s ≈ 2h47m
      final words = <String>[
        'so',
        'the',
        'first',
        'thing',
        'we',
        'need',
        'to',
        'do',
        'is',
        'understand',
        'how',
        'this',
        'actually',
        'works',
        'in',
        'practice',
        'and',
        'why',
        'it',
        'matters',
        'for',
        'everyone',
        'involved',
        'listen',
        'carefully',
        'because',
      ];
      final rnd = List<int>.generate(97, (i) => (i * 31 + 13) % 97);
      final subtitles = <Subtitle>[];

      for (var i = 0; i < captionCount; i++) {
        final start = Duration(seconds: i * captionSeconds);
        final end = Duration(seconds: (i + 1) * captionSeconds);
        final wordCount = 4 + rnd[i % rnd.length] % 28;
        final buf = StringBuffer();

        for (var w = 0; w < wordCount; w++) {
          buf.write(words[rnd[(i * 7 + w) % rnd.length] % words.length]);
          buf.write(' ');
        }

        final variant = i % 11;
        var text = buf.toString();
        if (variant == 2) {
          text = '<b>${text.trim()}</b>';
        } else if (variant == 5) {
          text = '<i>we ${text}today</i>';
        } else if (variant == 7) {
          text = '[HAN] \$text';
        }

        subtitles.add(Subtitle(
          index: i,
          start: start,
          end: end,
          data: text,
          speaker: variant == 9 ? 'HAN' : '',
        ));
      }

      return Transcript(subtitles: subtitles);
    }

    testWidgets('incremental measurement completes and produces exact geometry', (tester) async {
      TranscriptRowSpec? spec;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (innerContext) {
              spec = TranscriptRowSpec.of(innerContext);

              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );

      final transcript = longTranscript();
      final sw = Stopwatch()..start();
      final layout = TranscriptRowLayout.start(
        subtitles: transcript.subtitles,
        spec: spec!,
        width: 411.0,
      );

      // Drive the incremental job to completion the way the view does.
      var chunks = 0;

      while (!layout.complete) {
        layout.measureChunk();
        chunks++;
      }

      sw.stop();

      // ignore: avoid_print
      print('layout: 5000 captions measured in ${sw.elapsedMilliseconds} ms '
          'across $chunks chunks (${sw.elapsedMicroseconds / 5000} µs/caption)');

      // The geometry is exact once complete: prefix sums cover every row.
      var running = 0.0;

      for (var i = 0; i < layout.length; i++) {
        expect(layout.offsetOf(i), closeTo(running, 0.0001), reason: 'offset of row $i');
        running += layout.extentOf(i);
      }

      expect(layout.totalExtent, closeTo(running, 0.0001));
      expect(layout.totalExtent, greaterThan(0.0));
    });

    testWidgets('5000 caption transcript scrubs across the full range', (tester) async {
      late AudioBloc audioBloc;
      late MiniPlayerTestAudioPlayerService audioPlayerService;

      audioPlayerService = MiniPlayerTestAudioPlayerService();
      audioBloc = AudioBloc(audioPlayerService: audioPlayerService);

      addTearDown(() {
        audioBloc.dispose();
        audioPlayerService.disposeService();
      });

      await pumpScene(tester, audioBloc: audioBloc, theme: Themes.lightTheme().themeData, sceneBuilder: (context) {
        return nowPlayingScene(context);
      }, onMounted: () {
        // The episode must be as long as the transcript so the full sweep
        // reaches the last caption.
        audioPlayerService.emitPlayback(
          episode: fixtureEpisode(),
          length: const Duration(seconds: 10000),
        );
        audioPlayerService.emitTranscript(longTranscript());
      });

      // Let the incremental measurement job run to completion.
      final listFinder = find.byWidgetPredicate((w) => w is CustomScrollView && w.controller != null);
      final position = tester
          .state<ScrollableState>(find.descendant(of: listFinder, matching: find.byType(Scrollable)).first)
          .position;

      final spec = TranscriptRowSpec.of(tester.element(listFinder));
      final expectedLayout = TranscriptRowLayout.compute(
        subtitles: longTranscript().subtitles,
        spec: spec,
        width: tester.getSize(listFinder).width,
      );
      final exactMax = (expectedLayout.totalExtent - position.viewportDimension).clamp(0.0, double.infinity);

      // Drive the incremental measurement job to completion: each pump runs
      // a few idle-task chunks, and the exact maxScrollExtent only appears
      // once the final chunk's setState has laid the list out.
      var pumps = 0;

      while ((position.maxScrollExtent - exactMax).abs() > 0.5 && pumps < 200) {
        await tester.pump(const Duration(milliseconds: 16));
        pumps++;
      }

      // With measurement complete, the maxScrollExtent is exact and the list
      // can be driven across its whole range.
      expect(position.maxScrollExtent, closeTo(exactMax, 0.5));

      final barSize = tester.getSize(find.byType(MiniPlayerProgressBar));

      final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('miniplayer-playhead'))));
      await gesture.moveBy(Offset(barSize.width * 0.5, 0));
      await tester.pump();
      await gesture.moveBy(Offset(barSize.width * 0.5, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // The seek applied at 100%: the offset is the exact maxScrollExtent.
      expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    });
  });
}

/// Placeholder audio service for row-level tests that never trigger any
/// transport call; noSuchMethod satisfies the abstract members.
class _UnusedAudioPlayerService extends AudioPlayerService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
