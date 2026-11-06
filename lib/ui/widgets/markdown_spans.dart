// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/core/timestamp_text.dart';
import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

/// Builds a tappable timestamp chip for a `[mm:ss]` label found in assistant
/// text.
typedef TimestampChipBuilder = WidgetSpan Function(String label, int seconds);

/// Renders [text] as markdown into a flat list of [InlineSpan]s suitable for
/// [Text.rich], keeping the tappable `[mm:ss]` timestamp chips inline within
/// paragraphs, list items and headings.
///
/// Supported: paragraphs, headings, bullet/numbered lists, bold, italic,
/// inline code, links (rendered as underlined text), blockquotes, horizontal
/// rules and fenced code blocks. Anything unrecognised falls back to plain
/// text so a reply is never lost to a rendering gap.
List<InlineSpan> buildMarkdownSpans(
  String text, {
  required TextStyle baseStyle,
  required TimestampChipBuilder chipBuilder,
}) {
  final spans = <InlineSpan>[];

  if (text.trim().isEmpty) {
    return spans;
  }

  final nodes = md.Document().parse(text);

  for (final node in nodes) {
    _appendBlock(node, spans, baseStyle, chipBuilder);
  }

  return spans;
}

void _appendBlock(dynamic node, List<InlineSpan> spans, TextStyle baseStyle, TimestampChipBuilder chipBuilder) {
  if (node is md.Text) {
    spans.addAll(_inlineNode(node, baseStyle, chipBuilder));
    return;
  }

  if (node is! md.Element) {
    return;
  }

  switch (node.tag) {
    case 'h1':
    case 'h2':
    case 'h3':
    case 'h4':
    case 'h5':
    case 'h6':
      final level = int.parse(node.tag.substring(1));
      final style = baseStyle.copyWith(
        fontSize: baseStyle.fontSize == null ? null : baseStyle.fontSize! + (7 - level).clamp(0.0, 4.0),
        fontWeight: FontWeight.w700,
      );

      spans.addAll(_children(node, style, chipBuilder));
      spans.add(const TextSpan(text: '\n\n'));
      break;

    case 'ul':
    case 'ol':
      final ordered = node.tag == 'ol';
      var index = 1;

      for (final child in node.children ?? const <md.Node>[]) {
        if (child is md.Element && child.tag == 'li') {
          final marker = ordered ? '${index++}.  ' : '•  ';

          spans.add(TextSpan(text: marker, style: baseStyle.copyWith(fontWeight: FontWeight.w700)));
          spans.addAll(_children(child, baseStyle, chipBuilder));
          spans.add(const TextSpan(text: '\n'));
        } else {
          spans.addAll(_inlineNode(child, baseStyle, chipBuilder));
          spans.add(const TextSpan(text: '\n'));
        }
      }

      spans.add(const TextSpan(text: '\n'));
      break;

    case 'blockquote':
      spans.add(const TextSpan(text: '❝  '));
      spans.addAll(
        _children(
          node,
          baseStyle.copyWith(fontStyle: FontStyle.italic),
          chipBuilder,
        ),
      );
      spans.add(const TextSpan(text: '\n\n'));
      break;

    case 'pre':
      spans.add(
        TextSpan(
          text: '${node.textContent}\n\n',
          style: baseStyle.copyWith(fontFamily: 'monospace', fontSize: (baseStyle.fontSize ?? 14) - 1),
        ),
      );
      break;

    case 'hr':
      spans.add(const TextSpan(text: '──────────\n\n'));
      break;

    case 'p':
    default:
      spans.addAll(_children(node, baseStyle, chipBuilder));
      spans.add(const TextSpan(text: '\n\n'));
      break;
  }
}

/// The markdown package leaves HTML entities encoded in text nodes.
String _unescape(String text) => text
    .replaceAll('&quot;', '"')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

/// Flattens plain text into spans, splitting out timestamp chips.
List<InlineSpan> _inlineSpans(String text, TextStyle style, TimestampChipBuilder chipBuilder) {
  final spans = <InlineSpan>[];

  for (final segment in parseTimestampSegments(_unescape(text))) {
    switch (segment) {
      case PlainTextSegment():
        spans.add(TextSpan(text: segment.text, style: style));
        break;

      case TimestampSegmentT():
        spans.add(chipBuilder(segment.label, segment.seconds));
        break;
    }
  }

  return spans;
}

/// Walks an inline markdown node ([md.Text] or an inline [md.Element] such as
/// strong, em, code or a) into styled spans with timestamp chips inline.
List<InlineSpan> _inlineNode(dynamic node, TextStyle style, TimestampChipBuilder chipBuilder) {
  if (node is md.Text) {
    return _inlineSpans(node.text, style, chipBuilder);
  }

  if (node is! md.Element) {
    return const <InlineSpan>[];
  }

  switch (node.tag) {
    case 'strong':
      final bold = style.copyWith(fontWeight: FontWeight.w700);

      return [
        TextSpan(
          style: bold,
          children: _children(node, bold, chipBuilder),
        ),
      ];

    case 'em':
      final italic = style.copyWith(fontStyle: FontStyle.italic);

      return [
        TextSpan(
          style: italic,
          children: _children(node, italic, chipBuilder),
        ),
      ];

    case 'code':
      return [
        TextSpan(
          text: _unescape(node.textContent),
          style: style.copyWith(fontFamily: 'monospace'),
        ),
      ];

    case 'a':
      final link = style.copyWith(decoration: TextDecoration.underline);

      return [
        TextSpan(
          style: link,
          children: _children(node, link, chipBuilder),
        ),
      ];

    case 'br':
      return [const TextSpan(text: '\n')];

    default:
      return _children(node, style, chipBuilder);
  }
}

List<InlineSpan> _children(dynamic node, TextStyle style, TimestampChipBuilder chipBuilder) {
  final spans = <InlineSpan>[];

  for (final child in node.children ?? const <md.Node>[]) {
    spans.addAll(_inlineNode(child, style, chipBuilder));
  }

  return spans;
}
