// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/core/transcript_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractPlainText', () {
    test('returns empty string for empty input', () {
      expect(extractPlainText(''), '');
    });

    test('returns plain text unchanged', () {
      expect(extractPlainText('Hello world'), 'Hello world');
    });

    test('strips bold tags', () {
      expect(extractPlainText('<b>bold</b>'), 'bold');
    });

    test('strips strong tags', () {
      expect(extractPlainText('<strong>bold</strong>'), 'bold');
    });

    test('strips italic tags', () {
      expect(extractPlainText('<i>italic</i>'), 'italic');
    });

    test('strips em tags', () {
      expect(extractPlainText('<em>emphasis</em>'), 'emphasis');
    });

    test('strips underline tags', () {
      expect(extractPlainText('<u>underline</u>'), 'underline');
    });

    test('strips nested tags', () {
      expect(extractPlainText('<b><i>bold italic</i></b>'), 'bold italic');
    });

    test('strips all tags from mixed content', () {
      expect(
        extractPlainText('Hello <b>bold</b> and <i>italic</i> world'),
        'Hello bold and italic world',
      );
    });

    test('strips unsupported tags preserving text', () {
      expect(extractPlainText('<span>hello</span>'), 'hello');
      expect(extractPlainText('<a href="http://example.com">link</a>'), 'link');
      expect(extractPlainText('<div>content</div>'), 'content');
    });

    test('strips script tags and their content', () {
      expect(extractPlainText('<script>alert(1)</script>Hello'), 'Hello');
    });

    test('strips style tags and their content', () {
      expect(extractPlainText('<style>body{color:red}</style>Hello'), 'Hello');
    });

    test('decodes HTML entities', () {
      expect(extractPlainText('Rock &amp; Roll'), 'Rock & Roll');
      expect(extractPlainText('&lt;tag&gt;'), '<tag>');
      expect(extractPlainText('&quot;quoted&quot;'), '"quoted"');
    });

    test('handles malformed markup gracefully', () {
      expect(extractPlainText('<b>unclosed'), 'unclosed');
      expect(extractPlainText('unopened</b>'), 'unopened');
    });
  });

  group('sanitizeTranscriptMarkup', () {
    test('returns empty string for empty input', () {
      expect(sanitizeTranscriptMarkup(''), '');
    });

    test('preserves plain text', () {
      expect(sanitizeTranscriptMarkup('Hello world'), 'Hello world');
    });

    test('preserves allowed tags', () {
      expect(sanitizeTranscriptMarkup('<b>bold</b>'), '<b>bold</b>');
      expect(sanitizeTranscriptMarkup('<strong>bold</strong>'), '<strong>bold</strong>');
      expect(sanitizeTranscriptMarkup('<i>italic</i>'), '<i>italic</i>');
      expect(sanitizeTranscriptMarkup('<em>emphasis</em>'), '<em>emphasis</em>');
      expect(sanitizeTranscriptMarkup('<u>underline</u>'), '<u>underline</u>');
    });

    test('preserves nested allowed tags', () {
      expect(
        sanitizeTranscriptMarkup('<b><i>bold italic</i></b>'),
        '<b><i>bold italic</i></b>',
      );
    });

    test('strips attributes from allowed tags', () {
      expect(
        sanitizeTranscriptMarkup('<b onclick="alert(1)">bold</b>'),
        '<b>bold</b>',
      );
      expect(
        sanitizeTranscriptMarkup('<i style="color:red">italic</i>'),
        '<i>italic</i>',
      );
    });

    test('strips unsupported tags but preserves text', () {
      expect(sanitizeTranscriptMarkup('<span>hello</span>'), 'hello');
      expect(sanitizeTranscriptMarkup('<a href="http://example.com">link</a>'), 'link');
      expect(sanitizeTranscriptMarkup('<div>content</div>'), 'content');
    });

    test('removes script tags and their content', () {
      expect(sanitizeTranscriptMarkup('<script>alert(1)</script>Hello'), 'Hello');
    });

    test('removes style tags and their content', () {
      expect(sanitizeTranscriptMarkup('<style>body{color:red}</style>Hello'), 'Hello');
    });

    test('handles mixed allowed and unsupported tags', () {
      expect(
        sanitizeTranscriptMarkup('<b>bold</b> and <a href="#">link</a> text'),
        '<b>bold</b> and link text',
      );
    });
  });

  group('containsFormattingTags', () {
    test('returns false for empty string', () {
      expect(containsFormattingTags(''), false);
    });

    test('returns false for plain text', () {
      expect(containsFormattingTags('Hello world'), false);
    });

    test('returns true for bold tags', () {
      expect(containsFormattingTags('<b>bold</b>'), true);
      expect(containsFormattingTags('<strong>bold</strong>'), true);
    });

    test('returns true for italic tags', () {
      expect(containsFormattingTags('<i>italic</i>'), true);
      expect(containsFormattingTags('<em>emphasis</em>'), true);
    });

    test('returns true for underline tags', () {
      expect(containsFormattingTags('<u>underline</u>'), true);
    });

    test('returns false for unsupported tags only', () {
      expect(containsFormattingTags('<span>text</span>'), false);
      expect(containsFormattingTags('<a href="#">link</a>'), false);
    });

    test('returns true for mixed content with formatting', () {
      expect(containsFormattingTags('Hello <b>world</b>'), true);
    });

    test('returns false for text with angle brackets that are not tags', () {
      expect(containsFormattingTags('5 < 10 > 3'), false);
    });
  });

  group('hasUnbalancedTags', () {
    test('returns false for empty string', () {
      expect(hasUnbalancedTags(''), false);
    });

    test('returns false for plain text', () {
      expect(hasUnbalancedTags('Hello world'), false);
    });

    test('returns false for balanced tags', () {
      expect(hasUnbalancedTags('<b>bold</b>'), false);
      expect(hasUnbalancedTags('<b><i>nested</i></b>'), false);
    });

    test('returns true for unclosed opening tag', () {
      expect(hasUnbalancedTags('<b>unclosed'), true);
    });

    test('returns true for unopened closing tag', () {
      expect(hasUnbalancedTags('unopened</b>'), true);
    });

    test('returns false for unsupported tags', () {
      expect(hasUnbalancedTags('<span>text</span>'), false);
      expect(hasUnbalancedTags('<span>unclosed'), false);
    });
  });

  group('mergeTranscriptFragments', () {
    test('returns second fragment when first is empty', () {
      expect(mergeTranscriptFragments('', 'hello'), 'hello');
    });

    test('returns first fragment when second is empty', () {
      expect(mergeTranscriptFragments('hello', ''), 'hello');
    });

    test('merges plain text with space', () {
      expect(mergeTranscriptFragments('hello', 'world'), 'hello world');
    });

    test('does not add extra space when first ends with space', () {
      expect(mergeTranscriptFragments('hello ', 'world'), 'hello world');
    });

    test('does not add extra space when second starts with space', () {
      expect(mergeTranscriptFragments('hello', ' world'), 'hello world');
    });

    test('merges balanced formatted fragments', () {
      expect(
        mergeTranscriptFragments('<b>bold</b>', '<i>italic</i>'),
        '<b>bold</b> <i>italic</i>',
      );
    });

    test('strips formatting when first has unbalanced tags', () {
      expect(
        mergeTranscriptFragments('<b>unclosed', 'text'),
        'unclosed text',
      );
    });

    test('strips formatting when second has unbalanced tags', () {
      expect(
        mergeTranscriptFragments('text', 'unopened</b>'),
        'text unopened',
      );
    });

    test('strips formatting when both have unbalanced tags', () {
      expect(
        mergeTranscriptFragments('<b>unclosed', 'unopened</i>'),
        'unclosed unopened',
      );
    });

    test('respects addSpace parameter', () {
      expect(
        mergeTranscriptFragments('hello', 'world', addSpace: false),
        'helloworld',
      );
    });
  });
}
