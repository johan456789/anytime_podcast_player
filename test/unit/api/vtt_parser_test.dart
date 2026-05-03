// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/api/podcast/vtt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VttParserWithFormatting', () {
    late VttParserWithFormatting parser;

    setUp(() {
      parser = VttParserWithFormatting();
    });

    test('parses basic VTT without formatting', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
Hello, world!
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles.length, 1);
      expect(transcript.subtitles[0].data, 'Hello, world!');
    });

    test('preserves bold tag <b>', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <b>bold</b> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is <b>bold</b> text.');
    });

    test('preserves bold tag <strong>', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <strong>bold</strong> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is <strong>bold</strong> text.');
    });

    test('preserves italic tag <i>', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <i>italic</i> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is <i>italic</i> text.');
    });

    test('preserves italic tag <em>', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <em>emphasis</em> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is <em>emphasis</em> text.');
    });

    test('preserves underline tag <u>', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <u>underlined</u> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is <u>underlined</u> text.');
    });

    test('strips other HTML tags', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <span>span</span> and <div>div</div> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is span and div text.');
    });

    test('preserves multiple formatting tags', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
The word <i>normal</i> in Spanish is <b>normal</b>.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'The word <i>normal</i> in Spanish is <b>normal</b>.');
    });

    test('preserves nested formatting tags', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
This is <b><i>bold and italic</i></b> text.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'This is <b><i>bold and italic</i></b> text.');
    });

    test('strips HTML comments', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
Hello <!-- comment --> world!
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles[0].data, 'Hello  world!');
    });
  });
}
