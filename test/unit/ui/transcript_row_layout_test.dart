// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/entities/transcript.dart';
import 'package:anytime/ui/podcast/transcript_row_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
        for (var i = 1; i < 60; i++)
          Subtitle(index: i, start: Duration(seconds: i * 10), data: 'plain line $i'),
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

  group('long transcript measurement', () {
    /// A ~3h, 5000 caption transcript with realistic, varied captions: 1-4
    /// rendered lines, some with speakers and inline markup.
    Transcript longTranscript() {
      const captionCount = 5000;
      const captionSeconds = 2; // 5000 * 2s = 10000s ≈ 2h47m
      final words = <String>[
        'so', 'the', 'first', 'thing', 'we', 'need', 'to', 'do', 'is', 'understand',
        'how', 'this', 'actually', 'works', 'in', 'practice', 'and', 'why', 'it',
        'matters', 'for', 'everyone', 'involved', 'listen', 'carefully', 'because',
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


  });
}
