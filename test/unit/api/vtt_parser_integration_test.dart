// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/api/podcast/vtt_parser.dart';
import 'package:anytime/ui/podcast/transcript_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VTT to TextSpan integration', () {
    late VttParserWithFormatting parser;

    setUp(() {
      parser = VttParserWithFormatting();
    });

    test('parses real Language Transfer VTT with formatting and renders styled spans', () {
      // This is actual content from the Language Transfer Spanish VTT file
      const vtt = '''WEBVTT

00:00:56.717 --> 00:01:02.223
<v Teacher>So to give you an example, <i>normal</i> in Spanish is <b>normal</b>.

00:01:03.335 --> 00:01:03.960
<v Student><b>Normal</b>.
''';
      final transcript = parser.parse(vtt);

      expect(transcript.subtitles.length, 2);

      // First subtitle should have both italic and bold formatting preserved
      expect(
        transcript.subtitles[0].data,
        'So to give you an example, <i>normal</i> in Spanish is <b>normal</b>.',
      );

      // Second subtitle should have bold formatting
      expect(transcript.subtitles[0].speaker, 'Teacher');
      expect(transcript.subtitles[1].data, '<b>Normal</b>.');
      expect(transcript.subtitles[1].speaker, 'Student');
    });

    test('formatting-preserved VTT data renders correctly with buildTranscriptTextSpan', () {
      const vtt = '''WEBVTT

00:00:00.000 --> 00:00:05.000
<v Teacher>The word <i>normal</i> in Spanish is <b>normal</b>.
''';
      final transcript = parser.parse(vtt);
      final subtitleData = transcript.subtitles[0].data!;

      // Verify the formatting tags are preserved
      expect(subtitleData, 'The word <i>normal</i> in Spanish is <b>normal</b>.');

      // Now verify buildTranscriptTextSpan correctly processes the formatted text
      const baseStyle = TextStyle(fontSize: 16, color: Colors.black);
      final span = buildTranscriptTextSpan(text: subtitleData, baseStyle: baseStyle);

      // The span should have children for the mixed content
      expect(span.children, isNotNull);
      expect(span.children!.length, greaterThan(1));

      // Find the italic span (for "normal")
      final italicSpan = span.children!.firstWhere(
        (child) => child.style?.fontStyle == FontStyle.italic,
      ) as TextSpan;
      expect(italicSpan.text, 'normal');

      // Find the bold span (for "normal")
      final boldSpan = span.children!.firstWhere(
        (child) => child.style?.fontWeight == FontWeight.bold,
      ) as TextSpan;
      expect(boldSpan.text, 'normal');
    });

    test('words ending in -al rule example renders with italic and bold', () {
      const vtt = '''WEBVTT

00:00:48.430 --> 00:00:56.717
<v Teacher>So for example, one of these rules is that words ending in -<i>al</i> tend to come from Latin.
''';
      final transcript = parser.parse(vtt);
      final subtitleData = transcript.subtitles[0].data!;

      // The -al suffix should be in italics
      expect(subtitleData, contains('<i>al</i>'));

      const baseStyle = TextStyle(fontSize: 16);
      final span = buildTranscriptTextSpan(text: subtitleData, baseStyle: baseStyle);

      // Find the italic span for "al"
      final italicSpan = span.children!.firstWhere(
        (child) => child.style?.fontStyle == FontStyle.italic,
      ) as TextSpan;
      expect(italicSpan.text, 'al');
    });

    test('nested bold tags render correctly', () {
      const vtt = '''WEBVTT

00:01:04.122 --> 00:01:04.741
<v Teacher><b>Normal</b>,
''';
      final transcript = parser.parse(vtt);
      final subtitleData = transcript.subtitles[0].data!;

      expect(subtitleData, '<b>Normal</b>,');

      const baseStyle = TextStyle(fontSize: 16);
      final span = buildTranscriptTextSpan(text: subtitleData, baseStyle: baseStyle);

      // The span should contain bold "Normal" and plain ","
      expect(span.children, isNotNull);

      final boldSpan = span.children!.firstWhere(
        (child) => child.style?.fontWeight == FontWeight.bold,
      ) as TextSpan;
      expect(boldSpan.text, 'Normal');
    });

    test('speaker tags (voice cues) are correctly extracted and stripped', () {
      const vtt = '''WEBVTT

00:01:03.335 --> 00:01:03.960
<v Student><b>Normal</b>.
''';
      final transcript = parser.parse(vtt);

      // Speaker should be extracted
      expect(transcript.subtitles[0].speaker, 'Student');

      // Voice cue should be stripped but formatting preserved
      expect(transcript.subtitles[0].data, '<b>Normal</b>.');
    });
  });
}
