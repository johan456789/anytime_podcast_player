// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/core/timestamp_text.dart';
import 'package:anytime/entities/ai_chat.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/services/ai/ai_chat_service.dart';

/// A mock [AiChatService] which simulates an AI assistant grounded in the
/// episode transcript.
///
/// The mock performs simple keyword retrieval over the real transcript lines
/// so replies contain genuine timecodes which seek to the right spot, and
/// streams the answer back in small chunks to mimic token-by-token generation.
/// No network calls are made and no AI provider is required.
class MockAiChatService extends AiChatService {
  /// Delay between streamed chunks; kept configurable so tests run fast.
  final Duration chunkDelay;

  MockAiChatService({this.chunkDelay = const Duration(milliseconds: 24)});

  /// Words ignored when extracting search terms from a question.
  static const _stopwords = <String>{
    'the', 'and', 'for', 'are', 'but', 'not', 'you', 'all', 'any', 'can', 'her', 'was', 'one', 'our', 'out', 'day',
    'get', 'has', 'him', 'his', 'how', 'its', 'new', 'now', 'old', 'see', 'two', 'way', 'who', 'did', 'does', 'what',
    'when', 'where', 'which', 'this', 'that', 'with', 'they', 'them', 'there', 'their', 'from', 'have', 'about',
    'talk', 'talking', 'said', 'says', 'episode', 'podcast', 'please', 'tell', 'give', 'show', 'find', 'mention',
    'mentions', 'mentioning', 'discuss', 'discusses', 'discussed', 'covered', 'cover', 'time', 'timecode', 'timestamp',
    'were', 'will', 'would', 'could', 'should', 'into', 'than', 'then', 'also', 'just', 'like', 'some',
    'more', 'very', 'much', 'been', 'being', 'because', 'right',
  };

  @override
  Stream<String> send(AiChatRequest request) async* {
    final answer = _compose(request);

    /// Stream the reply in small word groups to simulate generation.
    final buffer = StringBuffer();

    for (final word in answer.split(' ')) {
      buffer.write(word);
      buffer.write(' ');

      if (buffer.length >= 12 || word.endsWith('\n')) {
        yield buffer.toString();
        buffer.clear();

        await Future<void>.delayed(chunkDelay);
      }
    }

    if (buffer.isNotEmpty) {
      yield buffer.toString();
    }
  }

  String _compose(AiChatRequest request) {
    final lines = _plainLines(request.lines);

    if (lines.isEmpty) {
      return 'There is no transcript loaded for this episode yet, so I can\'t answer questions about it.';
    }

    final question = request.question.toLowerCase();
    final normalisedQuestion = question.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');

    if (_matches(normalisedQuestion, const ['summar', 'recap', 'overview'])) {
      return _summary(request, lines);
    }

    if (_matches(normalisedQuestion, const ['takeaway', 'key point', 'learn'])) {
      return _takeaways(request, lines);
    }

    if (_matches(normalisedQuestion, const ['topic', 'segments', 'sections', 'agenda'])) {
      return _topics(lines);
    }

    if (_matches(normalisedQuestion, const ['right now', 'currently', 'this moment', 'where are we', 'just said'])) {
      return _aroundNow(request, lines);
    }

    return _findByKeywords(request, lines, _keywords(normalisedQuestion));
  }

  bool _matches(String question, List<String> terms) => terms.any(question.contains);

  List<_Line> _plainLines(List<Subtitle> subtitles) => <_Line>[
        for (final subtitle in subtitles)
          _Line(
            start: subtitle.start,
            speaker: subtitle.speaker.trim(),
            text: subtitle.data ?? '',
          ),
      ];

  Set<String> _keywords(String normalisedQuestion) => normalisedQuestion
      .split(RegExp(r'\s+'))
      .where((word) => word.length > 2 && !_stopwords.contains(word))
      .toSet();

  /// Finds the [count] best matching, well spaced lines for [keywords].
  List<_Line> _search(List<_Line> lines, Set<String> keywords, {int count = 3}) {
    if (keywords.isEmpty) {
      return const <_Line>[];
    }

    final scored = <MapEntry<_Line, int>>[];

    for (final line in lines) {
      final text = line.text.toLowerCase();
      var score = 0;

      for (final keyword in keywords) {
        if (text.contains(keyword)) {
          score += 1 + (text.split(keyword).length - 1);
        }
      }

      if (score > 0) {
        scored.add(MapEntry(line, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    final picked = <_Line>[];

    for (final entry in scored) {
      if (picked.every((line) => (line.start - entry.key.start).abs() > const Duration(seconds: 30))) {
        picked.add(entry.key);

        if (picked.length == count) {
          break;
        }
      }
    }

    return picked;
  }

  String _quote(_Line line, {int words = 16}) {
    final text = line.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    final split = text.split(' ');

    if (split.length <= words) {
      return text;
    }

    return '${split.take(words).join(' ')}…';
  }

  String _speaker(_Line line) => line.speaker.isEmpty ? 'They' : line.speaker;

  String _summary(AiChatRequest request, List<_Line> lines) {
    final buffer = StringBuffer('Here\'s a quick summary of **"${request.episodeTitle}"**:\n\n');

    final highlights = _spreadHighlights(lines, count: 4, maxGap: const Duration(minutes: 4));

    for (final line in highlights) {
      buffer.write('- [${formatTimestamp(line.start)}] **${_speaker(line)}:** "${_quote(line, words: 14)}"\n');
    }

    buffer.write('\nAsk me when something specific was covered and I\'ll take you straight to it.');

    return buffer.toString();
  }

  /// Picks up to [count] evenly spaced, representative lines across the whole
  /// transcript, with at most [maxGap] between highlights so that short
  /// episodes still get several highlights.
  List<_Line> _spreadHighlights(List<_Line> lines, {required int count, required Duration maxGap}) {
    if (lines.isEmpty) {
      return const <_Line>[];
    }

    final step = (lines.length / count).clamp(1.0, double.infinity).floor();
    final highlights = <_Line>[];

    for (var i = step ~/ 2; i < lines.length; i += step) {
      if (highlights.isEmpty || (lines[i].start - highlights.last.start) >= maxGap) {
        highlights.add(lines[i]);
      }

      if (highlights.length == count) {
        break;
      }
    }

    /// The gap requirement left us short (e.g. a short episode): fill with
    /// evenly spaced lines, ignoring the gap.
    if (highlights.length < count) {
      for (var i = step ~/ 2; i < lines.length && highlights.length < count; i += step) {
        if (highlights.every((line) => line.start != lines[i].start)) {
          highlights.add(lines[i]);
        }
      }
    }

    return highlights;
  }

  String _takeaways(AiChatRequest request, List<_Line> lines) {
    final buffer = StringBuffer('Key takeaways from **"${request.episodeTitle}"**:\n\n');

    final highlights = _spreadHighlights(lines, count: 3, maxGap: const Duration(minutes: 5));

    for (final line in highlights) {
      buffer.write('- [${formatTimestamp(line.start)}] "${_quote(line, words: 18)}"\n');
    }

    buffer.write('\nTap any timecode to hear the full context.');

    return buffer.toString();
  }

  String _topics(List<_Line> lines) {
    final buffer = StringBuffer('The conversation moves through roughly these segments:\n\n');

    final segments = <_Line>[];
    final step = (lines.length / 5).clamp(1.0, double.infinity).floor();

    for (var i = step ~/ 2; i < lines.length && segments.length < 5; i += step) {
      segments.add(lines[i]);
    }

    for (final line in segments) {
      final keywords = _keywords(line.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')).take(4).join(', ');

      buffer.write('• [${formatTimestamp(line.start)}]${keywords.isEmpty ? '' : ' — $keywords'}\n');
    }

    buffer.write('\nAsk about any of these and I\'ll find the exact moment.');

    return buffer.toString();
  }

  String _aroundNow(AiChatRequest request, List<_Line> lines) {
    final position = request.currentPosition;

    _Line? current;

    for (var i = 0; i < lines.length; i++) {
      final next = lines[i];

      if (next.start <= position) {
        current = next;
      } else {
        current ??= next;

        break;
      }
    }

    if (current == null) {
      return _summary(request, lines);
    }

    return 'Right now, around [${formatTimestamp(current.start)}], ${_speaker(current)} '
        '${current.speaker.isEmpty ? 'are' : 'is'} saying: "${_quote(current, words: 22)}"\n\n'
        'Ask me to summarize the episode or search for a specific topic to explore elsewhere.';
  }

  String _findByKeywords(AiChatRequest request, List<_Line> lines, Set<String> keywords) {
    final matches = _search(lines, keywords);

    if (matches.isEmpty) {
      final suggestions = _topicsHint(lines);

      return 'I couldn\'t find "${request.question.trim()}" in this episode\'s transcript.\n\n'
          'The conversation covers things like $suggestions. Try asking about one of those!';
    }

    final buffer = StringBuffer('**Found it** — that comes up ');

    if (matches.length == 1) {
      buffer.write('at [${formatTimestamp(matches.first.start)}]');
    } else {
      buffer.write('at ${matches.map((line) => '[${formatTimestamp(line.start)}]').join(' and ')}');
    }

    buffer.write('.\n\n');

    final first = matches.first;

    buffer.write('At [${formatTimestamp(first.start)}], ${_speaker(first)} says: "${_quote(first)}"\n\n');

    buffer.write('Tap a timecode to jump straight there.');

    return buffer.toString();
  }

  String _topicsHint(List<_Line> lines) {
    final seen = <String>{};
    final hints = <String>[];

    for (final line in lines.reversed) {
      for (final keyword in _keywords(line.text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' '))) {
        if (seen.add(keyword) && hints.length < 4) {
          hints.add(keyword);
        }
      }
    }

    return hints.join(', ');
  }
}

class _Line {
  final Duration start;
  final String speaker;
  final String text;

  const _Line({
    required this.start,
    required this.speaker,
    required this.text,
  });
}
