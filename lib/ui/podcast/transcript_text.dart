// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parseFragment;

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
      final newStyle = _applyTagStyle(node.localName, style);
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
