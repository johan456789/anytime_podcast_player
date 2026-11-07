/// A segment of text which either contains plain text or a playback timestamp
/// reference in the form `[mm:ss]`, `[hh:mm:ss]` or a range
/// `[mm:ss–mm:ss]` (with a hyphen, en dash or em dash).
///
/// Used to render AI chat replies where timestamp references are displayed as
/// tappable chips which seek the player to that position.
sealed class TimestampSegment {
  const TimestampSegment();
}

class PlainTextSegment extends TimestampSegment {
  final String text;

  const PlainTextSegment(this.text);
}

class TimestampSegmentT extends TimestampSegment {
  /// The original text of the timestamp, e.g. `12:34` or `0:45–0:57`.
  final String label;

  /// The position this timestamp refers to, in seconds. For a range this is
  /// the start of the range.
  final int seconds;

  const TimestampSegmentT({required this.label, required this.seconds});
}

final RegExp _timestampPattern = RegExp(
    r'\[ ?(\d{1,2}:\d{2}(?::\d{2})?)(?:\s*[–—-]\s*(\d{1,2}:\d{2}(?::\d{2})?))? ?\]');

/// Splits [text] into [TimestampSegment]s. Anything which looks like a
/// `[mm:ss]`, `[hh:mm:ss]` or `[mm:ss–mm:ss]` reference becomes a
/// [TimestampSegmentT]; all other text is returned as [PlainTextSegment]s.
///
/// The [seconds] of a timestamp are calculated as follows: a two-part
/// timestamp is minutes and seconds; a three-part timestamp is hours, minutes
/// and seconds. A range cites its start position.
List<TimestampSegment> parseTimestampSegments(String text) {
  final segments = <TimestampSegment>[];
  var cursor = 0;

  for (final match in _timestampPattern.allMatches(text)) {
    if (match.start > cursor) {
      segments.add(PlainTextSegment(text.substring(cursor, match.start)));
    }

    final inner = match.group(0)!.substring(1, match.group(0)!.length - 1).trim();

    segments.add(TimestampSegmentT(label: inner, seconds: parseClockSeconds(match.group(1)!)));

    cursor = match.end;
  }

  if (cursor < text.length) {
    segments.add(PlainTextSegment(text.substring(cursor)));
  }

  return segments;
}

/// Parses a `mm:ss`, `hh:mm:ss` clock string into seconds.
int parseClockSeconds(String clock) {
  final parts = clock.split(':');

  if (parts.length == 3) {
    return int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2]);
  }

  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// True if the given text contains at least one tappable timestamp.
bool containsTimestamp(String text) => _timestampPattern.hasMatch(text);

/// Formats a [Duration] as a chat timestamp: `mm:ss`, or `hh:mm:ss` for
/// positions of an hour or longer. This is the format parsed by
/// [parseTimestampSegments].
String formatTimestamp(Duration position) {
  final hh = position.inHours;
  final mm = position.inMinutes % 60;
  final ss = position.inSeconds % 60;

  return hh > 0
      ? '$hh:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}'
      : '$mm:${ss.toString().padLeft(2, '0')}';
}
