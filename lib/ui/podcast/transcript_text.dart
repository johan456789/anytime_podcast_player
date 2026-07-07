// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/core/transcript_text.dart' as core;
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parseFragment;

/// Parsed transcript text containing both plain text and styled representation.
///
/// Use [plainText] for search and accessibility.
/// Use [textSpan] for rich text rendering.
class ParsedTranscriptText {
  final String plainText;
  final TextSpan textSpan;

  const ParsedTranscriptText({
    required this.plainText,
    required this.textSpan,
  });
}

/// Parses transcript text and returns both plain text and styled TextSpan.
///
/// This is the primary API for transcript text handling in the UI layer.
/// It combines plain text extraction (for search/accessibility) with
/// rich text building (for display).
ParsedTranscriptText parseTranscriptText({
  required String rawText,
  required TextStyle? baseStyle,
}) {
  final plainText = core.extractPlainText(rawText);
  final textSpan = buildTranscriptTextSpan(text: rawText, baseStyle: baseStyle);

  return ParsedTranscriptText(
    plainText: plainText,
    textSpan: textSpan,
  );
}

/// Builds a [TextSpan] tree from raw transcript text that may contain
/// basic inline HTML formatting tags.
///
/// Supported tags:
/// - `<b>` and `<strong>` => bold
/// - `<i>` and `<em>` => italic
/// - `<u>` => underline
///
/// Unknown tags render their text content with inherited style.
/// Malformed markup degrades to readable plain text.
/// Script and style tags are stripped entirely (including their content).
TextSpan buildTranscriptTextSpan({
  required String text,
  required TextStyle? baseStyle,
}) {
  if (text.isEmpty) {
    return TextSpan(text: '', style: baseStyle);
  }

  try {
    final fragment = parseFragment(text);
    final children = _buildSpansFromNodes(fragment.nodes, baseStyle);

    if (children.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    if (children.length == 1) {
      return children.first;
    }

    return TextSpan(children: children, style: baseStyle);
  } catch (_) {
    return TextSpan(text: text, style: baseStyle);
  }
}

List<TextSpan> _buildSpansFromNodes(List<dom.Node> nodes, TextStyle? style) {
  final spans = <TextSpan>[];

  for (final node in nodes) {
    if (node is dom.Text) {
      final text = node.text;
      if (text.isNotEmpty) {
        spans.add(TextSpan(text: text, style: style));
      }
    } else if (node is dom.Element) {
      final tagName = node.localName?.toLowerCase();

      // Skip script and style content entirely
      if (tagName == 'script' || tagName == 'style') {
        continue;
      }

      final newStyle = _applyTagStyle(tagName, style);
      final childSpans = _buildSpansFromNodes(node.nodes, newStyle);

      if (childSpans.isNotEmpty) {
        spans.addAll(childSpans);
      }
    }
  }

  return spans;
}

TextStyle? _applyTagStyle(String? tagName, TextStyle? baseStyle) {
  if (tagName == null) return baseStyle;

  final effectiveStyle = baseStyle ?? const TextStyle();

  switch (tagName.toLowerCase()) {
    case 'b':
    case 'strong':
      return effectiveStyle.copyWith(fontWeight: FontWeight.bold);
    case 'i':
    case 'em':
      return effectiveStyle.copyWith(fontStyle: FontStyle.italic);
    case 'u':
      return effectiveStyle.copyWith(decoration: TextDecoration.underline);
    default:
      return baseStyle;
  }
}
