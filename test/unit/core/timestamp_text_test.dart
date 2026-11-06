// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/core/timestamp_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseTimestampSegments', () {
    test('text without timestamps is a single plain segment', () {
      final segments = parseTimestampSegments('No timestamps here.');

      expect(segments.length, 1);
      expect(segments.first, isA<PlainTextSegment>());
      expect((segments.first as PlainTextSegment).text, 'No timestamps here.');
    });

    test('parses a single mm:ss timestamp', () {
      final segments = parseTimestampSegments('Discussed at [12:34] in depth.');

      expect(segments.length, 3);
      final timestamp = segments[1] as TimestampSegmentT;
      expect(timestamp.label, '12:34');
      expect(timestamp.seconds, 12 * 60 + 34);
    });

    test('parses a single m:ss timestamp', () {
      final segments = parseTimestampSegments('See [3:05]');

      expect(segments.length, 2);
      final timestamp = segments[1] as TimestampSegmentT;
      expect(timestamp.label, '3:05');
      expect(timestamp.seconds, 3 * 60 + 5);
    });

    test('parses an hh:mm:ss timestamp', () {
      final segments = parseTimestampSegments('Covered at [1:02:03]');

      expect(segments.length, 2);
      final timestamp = segments[1] as TimestampSegmentT;
      expect(timestamp.label, '1:02:03');
      expect(timestamp.seconds, 1 * 3600 + 2 * 60 + 3);
    });

    test('parses multiple timestamps and preserves surrounding text', () {
      final segments = parseTimestampSegments('At [0:30] and later at [45:10] again.');

      expect(segments.length, 5);
      expect((segments[0] as PlainTextSegment).text, 'At ');
      expect((segments[1] as TimestampSegmentT).seconds, 30);
      expect((segments[2] as PlainTextSegment).text, ' and later at ');
      expect((segments[3] as TimestampSegmentT).seconds, 45 * 60 + 10);
      expect((segments[4] as PlainTextSegment).text, ' again.');
    });

    test('does not treat non timestamp brackets as timestamps', () {
      final segments = parseTimestampSegments('An [array] of things.');

      expect(segments.length, 1);
      expect(segments.first, isA<PlainTextSegment>());
    });

    test('parses a range with an en dash and seeks to its start', () {
      final segments = parseTimestampSegments('me lo, then lo [0:45–0:57].');

      final timestamp = segments[1] as TimestampSegmentT;
      expect(timestamp.label, '0:45–0:57');
      expect(timestamp.seconds, 45);
    });

    test('parses a range with a plain hyphen', () {
      final segments = parseTimestampSegments('The endings vary [0:07-0:29].');

      final timestamp = segments[1] as TimestampSegmentT;
      expect(timestamp.label, '0:07-0:29');
      expect(timestamp.seconds, 7);
    });

    test('parses an hour range with surrounding spaces', () {
      final segments = parseTimestampSegments('He explains [1:02:03 - 1:02:10] here.');

      final timestamp = segments[1] as TimestampSegmentT;
      expect(timestamp.label, '1:02:03 - 1:02:10');
      expect(timestamp.seconds, 3723);
    });

    test('parses multiple singles and ranges mixed with text', () {
      final segments = parseTimestampSegments('dar + án = darán [0:22–0:25]. Also [0:08].');

      expect(segments.whereType<TimestampSegmentT>().map((s) => s.seconds), containsAll(<int>[22, 8]));
    });
  });

  group('formatTimestamp', () {
    test('formats sub hour positions as mm:ss', () {
      expect(formatTimestamp(const Duration(minutes: 12, seconds: 4)), '12:04');
      expect(formatTimestamp(const Duration(seconds: 5)), '0:05');
    });

    test('formats hour positions as hh:mm:ss', () {
      expect(formatTimestamp(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    });

    test('round trips with the parser', () {
      final position = const Duration(hours: 1, minutes: 23, seconds: 45);
      final parsed = parseTimestampSegments('[${formatTimestamp(position)}]');

      expect((parsed[0] as TimestampSegmentT).seconds, position.inSeconds);
    });
  });

  group('containsTimestamp', () {
    test('detects timestamps', () {
      expect(containsTimestamp('see [1:23] here'), isTrue);
    });

    test('rejects plain text', () {
      expect(containsTimestamp('no timecodes'), isFalse);
    });
  });
}
