// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' show parseFragment;

/// Allowed inline formatting tags for transcript text.
const _allowedTags = {'b', 'strong', 'i', 'em', 'u'};

/// Extracts plain visible text from transcript markup, stripping all HTML tags.
///
/// Use this for:
/// - Search matching (search should find "bold word" in "<b>bold</b> word")
/// - Accessibility labels (screen readers should not read markup)
/// - Any comparison that needs visible text only
///
/// HTML entities are decoded. Unsupported tags are stripped but their text
/// content is preserved.
String extractPlainText(String rawText) {
  if (rawText.isEmpty) return '';

  try {
    final fragment = parseFragment(rawText);
    return _extractTextFromNodes(fragment.nodes);
  } catch (_) {
    return rawText;
  }
}

String _extractTextFromNodes(List<dom.Node> nodes) {
  final buffer = StringBuffer();

  for (final node in nodes) {
    if (node is dom.Text) {
      buffer.write(node.text);
    } else if (node is dom.Element) {
      final tagName = node.localName?.toLowerCase();
      // Skip script and style content entirely
      if (tagName == 'script' || tagName == 'style') {
        continue;
      }
      buffer.write(_extractTextFromNodes(node.nodes));
    }
  }

  return buffer.toString();
}

/// Sanitizes transcript text by:
/// - Keeping only allowed formatting tags (b, strong, i, em, u)
/// - Stripping all other tags while preserving their text content
/// - Removing all tag attributes (no onclick, href, style, etc.)
/// - Removing script and style element content entirely
///
/// Use this to ensure transcript markup is safe for display while
/// preserving intended formatting.
String sanitizeTranscriptMarkup(String rawText) {
  if (rawText.isEmpty) return '';

  try {
    final fragment = parseFragment(rawText);
    return _sanitizeNodes(fragment.nodes);
  } catch (_) {
    return rawText;
  }
}

String _sanitizeNodes(List<dom.Node> nodes) {
  final buffer = StringBuffer();

  for (final node in nodes) {
    if (node is dom.Text) {
      buffer.write(node.text);
    } else if (node is dom.Element) {
      final tagName = node.localName?.toLowerCase();

      // Skip script and style content entirely
      if (tagName == 'script' || tagName == 'style') {
        continue;
      }

      final childContent = _sanitizeNodes(node.nodes);

      if (tagName != null && _allowedTags.contains(tagName)) {
        // Keep allowed tags but strip all attributes
        buffer.write('<$tagName>$childContent</$tagName>');
      } else {
        // Strip other tags but keep their text content
        buffer.write(childContent);
      }
    }
  }

  return buffer.toString();
}

/// Checks if the given text contains any HTML formatting tags.
///
/// Use this to determine if text needs special handling for formatted display.
bool containsFormattingTags(String text) {
  if (text.isEmpty) return false;

  // Quick check for any tag-like content
  if (!text.contains('<')) return false;

  try {
    final fragment = parseFragment(text);
    return _hasFormattingElements(fragment.nodes);
  } catch (_) {
    return false;
  }
}

bool _hasFormattingElements(List<dom.Node> nodes) {
  for (final node in nodes) {
    if (node is dom.Element) {
      final tagName = node.localName?.toLowerCase();
      if (tagName != null && _allowedTags.contains(tagName)) {
        return true;
      }
      if (_hasFormattingElements(node.nodes)) {
        return true;
      }
    }
  }
  return false;
}

/// Checks if concatenating two text fragments would result in broken markup.
///
/// Returns true if either fragment has unclosed or unopened formatting tags
/// that would be split across the join boundary.
///
/// Use this during transcript grouping to decide whether to preserve
/// or strip formatting when combining fragments.
bool hasUnbalancedTags(String text) {
  if (text.isEmpty || !text.contains('<')) return false;

  var openTags = 0;

  // Simple tag counting - not a full parser, but sufficient for our allowed tags
  final tagPattern = RegExp(r'<(/?)([a-zA-Z]+)[^>]*>');
  for (final match in tagPattern.allMatches(text)) {
    final isClosing = match.group(1) == '/';
    final tagName = match.group(2)?.toLowerCase();

    if (tagName != null && _allowedTags.contains(tagName)) {
      if (isClosing) {
        openTags--;
      } else {
        openTags++;
      }
    }
  }

  return openTags != 0;
}

/// Merges two transcript text fragments, handling formatting safely.
///
/// If both fragments have balanced markup, they are concatenated directly.
/// If either has unbalanced tags, formatting is stripped to prevent broken markup.
///
/// The [addSpace] parameter controls whether to add a space between fragments
/// when neither ends/starts with whitespace.
String mergeTranscriptFragments(String first, String second, {bool addSpace = true}) {
  if (first.isEmpty) return second;
  if (second.isEmpty) return first;

  // If either fragment has unbalanced tags, strip formatting from both
  if (hasUnbalancedTags(first) || hasUnbalancedTags(second)) {
    final plainFirst = extractPlainText(first);
    final plainSecond = extractPlainText(second);

    if (addSpace && !plainFirst.endsWith(' ') && !plainSecond.startsWith(' ')) {
      return '$plainFirst $plainSecond';
    }
    return '$plainFirst$plainSecond';
  }

  // Both are balanced, safe to concatenate
  if (addSpace && !first.endsWith(' ') && !second.startsWith(' ')) {
    return '$first $second';
  }
  return '$first$second';
}
