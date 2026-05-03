// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/ui/podcast/transcript_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseStyle = TextStyle(fontSize: 16.0);

  group('buildTranscriptTextSpan', () {
    test('plain text renders as a single normal span', () {
      final span = buildTranscriptTextSpan(
        text: 'Hello world',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'Hello world');
      expect(span.style, baseStyle);
    });

    test('empty text renders as empty span', () {
      final span = buildTranscriptTextSpan(
        text: '',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), '');
    });

    test('<b> applies bold', () {
      final span = buildTranscriptTextSpan(
        text: '<b>bold</b>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'bold');
      final children = _flattenSpans(span);
      expect(children.any((s) => s.style?.fontWeight == FontWeight.bold), true);
    });

    test('<strong> applies bold', () {
      final span = buildTranscriptTextSpan(
        text: '<strong>bold</strong>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'bold');
      final children = _flattenSpans(span);
      expect(children.any((s) => s.style?.fontWeight == FontWeight.bold), true);
    });

    test('<i> applies italic', () {
      final span = buildTranscriptTextSpan(
        text: '<i>italic</i>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'italic');
      final children = _flattenSpans(span);
      expect(children.any((s) => s.style?.fontStyle == FontStyle.italic), true);
    });

    test('<em> applies italic', () {
      final span = buildTranscriptTextSpan(
        text: '<em>italic</em>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'italic');
      final children = _flattenSpans(span);
      expect(children.any((s) => s.style?.fontStyle == FontStyle.italic), true);
    });

    test('<u> applies underline', () {
      final span = buildTranscriptTextSpan(
        text: '<u>underline</u>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'underline');
      final children = _flattenSpans(span);
      expect(
        children.any((s) => s.style?.decoration == TextDecoration.underline),
        true,
      );
    });

    test('nested tags combine styles', () {
      final span = buildTranscriptTextSpan(
        text: '<b><i>bold and italic</i></b>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'bold and italic');
      final children = _flattenSpans(span);
      expect(
        children.any((s) => s.style?.fontWeight == FontWeight.bold && s.style?.fontStyle == FontStyle.italic),
        true,
      );
    });

    test('unknown tags do not apply style but keep text', () {
      final span = buildTranscriptTextSpan(
        text: '<span>hello</span> <div>world</div>',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'hello world');
    });

    test('malformed markup does not throw', () {
      final span = buildTranscriptTextSpan(
        text: '<b>unclosed tag',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'unclosed tag');
    });

    test('mixed plain text and tags render correctly', () {
      final span = buildTranscriptTextSpan(
        text: 'Hello <b>bold</b> and <i>italic</i> world',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'Hello bold and italic world');
    });

    test('HTML entities decode correctly', () {
      final span = buildTranscriptTextSpan(
        text: 'Rock &amp; Roll &lt;3',
        baseStyle: baseStyle,
      );

      expect(span.toPlainText(), 'Rock & Roll <3');
    });

    test('null baseStyle is handled', () {
      final span = buildTranscriptTextSpan(
        text: '<b>bold</b>',
        baseStyle: null,
      );

      expect(span.toPlainText(), 'bold');
      final children = _flattenSpans(span);
      expect(children.any((s) => s.style?.fontWeight == FontWeight.bold), true);
    });
  });
}

List<TextSpan> _flattenSpans(TextSpan span) {
  final result = <TextSpan>[];

  void visit(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) {
        result.add(s);
      }
      s.children?.forEach(visit);
    }
  }

  visit(span);
  return result;
}
