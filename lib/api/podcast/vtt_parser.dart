// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:podcast_search/podcast_search.dart' as podcast_search;

/// VTT parser that preserves basic inline formatting tags (b, strong, i, em, u).
/// Based on podcast_search's VttParser but does NOT strip allowed HTML tags.
class VttParserWithFormatting {
  final _vttMatcher = RegExp(
    r'((?<shour>\d{2})?(:)?(?<smin>\d{2}):(?<ssec>\d{2})[,|.](?<smili>\d{3})) +--> +((?<ehour>\d{2})?(:)?(?<emin>\d{2}):(?<esec>\d{2})[,|.](?<emili>\d{3})).*[\r\n]+\s*(?<lines>(?:(?!\r?\n\r?).)*(\r\n|\r|\n)(?:.*))',
    caseSensitive: false,
    multiLine: true,
  );

  final _newlineMatcher = RegExp(
    r'[\r\n]+',
    caseSensitive: false,
    multiLine: true,
  );

  final _prefixMatcher = RegExp(
    r'^<(?<prefix>[a-z.]*)\s(?<speaker>.*?)>(?<text>.*)',
    caseSensitive: false,
    multiLine: true,
  );

  // Only strip HTML tags that are NOT formatting tags we want to preserve
  final _stripTagsMatcher = RegExp(
    r'</?(?!b>|/b>|strong>|/strong>|i>|/i>|em>|/em>|u>|/u>)[a-z][a-z0-9]*[^<>]*>|<!--.*?-->',
    caseSensitive: false,
    multiLine: true,
  );

  podcast_search.Transcript parse(String srt) {
    final matches = _vttMatcher.allMatches(srt).toList();
    final subtitles = <podcast_search.Subtitle>[];
    var i = 0;

    for (final regExpMatch in matches) {
      i++;

      final startTimeHours = int.parse(regExpMatch.namedGroup('shour') ?? '0');
      final startTimeMinutes = int.parse(regExpMatch.namedGroup('smin') ?? '0');
      final startTimeSeconds = int.parse(regExpMatch.namedGroup('ssec') ?? '0');
      final startTimeMilliseconds = int.parse(
        regExpMatch.namedGroup('smili') ?? '0',
      );

      final endTimeHours = int.parse(regExpMatch.namedGroup('ehour') ?? '0');
      final endTimeMinutes = int.parse(regExpMatch.namedGroup('emin') ?? '0');
      final endTimeSeconds = int.parse(regExpMatch.namedGroup('esec') ?? '0');
      final endTimeMilliseconds = int.parse(
        regExpMatch.namedGroup('emili') ?? '0',
      );
      final textLines = regExpMatch.namedGroup('lines')?.split(_newlineMatcher);

      var text = '';
      var speaker = '';

      if (textLines != null) {
        for (var line in textLines) {
          if (text.isEmpty) {
            text = line;
          } else if (text.endsWith(' ') || line.startsWith(' ')) {
            text += line;
          } else {
            text += ' $line';
          }
        }
      }

      // VTT can contain speaker names at the start of the line
      final speakerMatcher = _prefixMatcher.firstMatch(text);

      if (speakerMatcher != null) {
        var prefix = speakerMatcher.namedGroup('prefix') ?? '';

        if (prefix.startsWith('v')) {
          speaker = speakerMatcher.namedGroup('speaker') ?? '';
        }

        text = speakerMatcher.namedGroup('text') ?? '';
      }

      // Strip HTML tags EXCEPT formatting tags (b, strong, i, em, u)
      text = text.replaceAll(_stripTagsMatcher, '');

      final startTime = Duration(
        hours: startTimeHours,
        minutes: startTimeMinutes,
        seconds: startTimeSeconds,
        milliseconds: startTimeMilliseconds,
      );

      final endTime = Duration(
        hours: endTimeHours,
        minutes: endTimeMinutes,
        seconds: endTimeSeconds,
        milliseconds: endTimeMilliseconds,
      );

      var subtitle = podcast_search.Subtitle(
        index: i,
        start: startTime,
        end: endTime,
        speaker: speaker,
        data: text.trim(),
      );

      subtitles.add(subtitle);
    }

    return podcast_search.Transcript(subtitles: subtitles);
  }
}
