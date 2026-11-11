// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:anytime/entities/transcript.dart';
import 'package:anytime/ui/podcast/transcript_text.dart';
import 'package:flutter/material.dart';

/// The scroll offset window around a confirmed seek within which a playback
/// position event is considered to confirm the scrubbed position instead of
/// being a stale pre-seek position.
const Duration pendingSeekConfirmationWindow = Duration(milliseconds: 1500);

/// How long the transcript waits for playback to confirm a scrubbed seek
/// before accepting any playback position again (covers a failed seek).
const Duration pendingSeekTimeout = Duration(seconds: 3);

/// How long the playback follow animation runs when the highlighted row
/// changes during normal playback.
const Duration playbackFollowDuration = Duration(milliseconds: 250);

/// Formats the transcript row header time as `hh:mm:ss`.
String formatRowHeader(Duration duration) {
  final hh = (duration.inHours).toString().padLeft(2, '0');
  final mm = (duration.inMinutes % 60).toString().padLeft(2, '0');
  final ss = (duration.inSeconds % 60).toString().padLeft(2, '0');

  return '$hh:$mm:$ss';
}

/// Returns the index of the caption containing [p], found by binary search
/// over [items], which must be sorted by `start` - it is the *same list the
/// transcript list view renders*.
///
/// Rules (deliberate, to avoid flicker while playback advances):
/// - `p` before the first caption's start returns null (no highlight, the
///   list anchors to the top).
/// - Exactly at a boundary between contiguous captions (`p == end(i) ==
///   start(i+1)`) the next caption (i+1) is chosen.
/// - Inside a silence gap (`end(i) < p < start(i+1)`) the caption before the
///   gap stays highlighted instead of dropping the highlight.
/// - After the last caption's start, the last caption stays highlighted.
/// - An empty list returns null.
int? indexForPosition(List<Subtitle> items, Duration p) {
  if (items.isEmpty) {
    return null;
  }

  var low = 0;
  var high = items.length - 1;
  var candidate = -1;

  while (low <= high) {
    final mid = (low + high) >> 1;

    if (items[mid].start <= p) {
      candidate = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  return candidate == -1 ? null : candidate;
}

/// The speaker of the caption at [index]: the explicit `speaker` field if
/// present, otherwise a backwards scan of up to 50 caption bodies looking for
/// a `Speaker:` (or `[Speaker]:`) prefix, mirroring the historical behaviour.
String speakerForIndex(List<Subtitle> items, int index) {
  final subtitle = items[index];

  if (subtitle.speaker.isNotEmpty) {
    return subtitle.speaker;
  }

  const speakerPattern = r'(^)(\[?)(?<speaker>[A-Za-z0-9\s]+)(\]?)(\s?)(:)';
  final exp = RegExp(speakerPattern);

  var remaining = 50;
  var scanIndex = index;

  while (remaining-- > 0 && scanIndex >= 0) {
    final match = exp.firstMatch(items[scanIndex].data ?? '');

    if (match != null) {
      final speaker = match.namedGroup('speaker') ?? '';

      if (speaker.isNotEmpty) {
        return speaker;
      }
    }

    scanIndex--;
  }

  return '';
}

/// Everything that affects the rendered height of one transcript row.
///
/// The transcript rows must be measurable *before* they are built (the list
/// positions rows from their offsets), so all inputs to the row's height are
/// owned here and both the rendered [SubtitleWidget] and the pure
/// [TranscriptRowLayout] derive from one instance. The highlight only
/// changes the row's background colour - never its size.
///
/// Style resolution mirrors what the [Text] widget does internally
/// (see [Text.build]): a [Text] with an explicit style renders with
/// `DefaultTextStyle.style.merge(style)`, and the root span of `Text.rich`
/// is the bare `DefaultTextStyle.style` with the child span carrying the
/// theme style. The bold-text accessibility override is applied to the root.
/// Measurement feeds the very same spans to a [TextPainter], so render and
/// measurement cannot diverge.
class TranscriptRowSpec {
  /// Horizontal padding on both sides of a row.
  final double horizontalPadding;

  /// Top padding of a row.
  final double topPadding;

  /// Trailing gap at the bottom of a row (kept empty so consecutive rows
  /// never visually merge).
  final double bottomGap;

  /// The style the header [Text] renders with: the ambient default text
  /// style merged with the theme's `titleSmall`.
  final TextStyle headerStyle;

  /// The style passed to the transcript text parser for the caption body
  /// (the theme's `titleMedium`).
  final TextStyle bodyBaseStyle;

  /// The root style `Text.rich` wraps the body span in: the ambient default
  /// text style, with the bold-text accessibility override applied.
  final TextStyle bodyRootStyle;

  final TextScaler textScaler;
  final TextDirection textDirection;
  final TextAlign textAlign;
  final TextHeightBehavior? textHeightBehavior;
  final TextWidthBasis textWidthBasis;
  final int? maxLines;
  final bool softWrap;
  final TextOverflow overflow;

  const TranscriptRowSpec({
    required this.horizontalPadding,
    required this.topPadding,
    required this.bottomGap,
    required this.headerStyle,
    required this.bodyBaseStyle,
    required this.bodyRootStyle,
    required this.textScaler,
    required this.textDirection,
    required this.textAlign,
    required this.textHeightBehavior,
    required this.textWidthBasis,
    required this.maxLines,
    required this.softWrap,
    required this.overflow,
  });

  /// Resolves the spec from [context], matching what the rendered rows see.
  ///
  /// `MediaQuery` line-height/letter-spacing overrides are deliberately not
  /// replicated: no ancestor in the app sets them, and the plain
  /// accessibility settings (text scale, bold text) are covered.
  factory TranscriptRowSpec.of(BuildContext context) {
    final theme = Theme.of(context);
    final defaultTextStyle = DefaultTextStyle.of(context);
    final defaultStyle = defaultTextStyle.style;

    final rootStyle = MediaQuery.boldTextOf(context)
        ? defaultStyle.merge(const TextStyle(fontWeight: FontWeight.bold))
        : defaultStyle;

    return TranscriptRowSpec(
      horizontalPadding: 16.0,
      topPadding: 16.0,
      bottomGap: 16.0,
      headerStyle: rootStyle.merge(theme.textTheme.titleSmall),
      bodyBaseStyle: theme.textTheme.titleMedium ?? const TextStyle(),
      bodyRootStyle: rootStyle,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      textAlign: defaultTextStyle.textAlign ?? TextAlign.start,
      textHeightBehavior: defaultTextStyle.textHeightBehavior ?? DefaultTextHeightBehavior.maybeOf(context),
      textWidthBasis: defaultTextStyle.textWidthBasis,
      maxLines: defaultTextStyle.maxLines,
      softWrap: defaultTextStyle.softWrap,
      overflow: defaultTextStyle.overflow,
    );
  }

  /// The header string rendered above the caption body: the start timecode,
  /// optionally followed by the speaker.
  String headerText(Subtitle subtitle) {
    final header = formatRowHeader(subtitle.start);

    return subtitle.speaker.isEmpty ? header : '$header - ${subtitle.speaker}';
  }

  /// The parsed body [TextSpan] for [subtitle], exactly as the row renders it.
  TextSpan bodySpan(Subtitle subtitle) {
    return buildTranscriptTextSpan(text: subtitle.data ?? '', baseStyle: bodyBaseStyle);
  }

  /// The width the body text lays out within for a list of cross-axis
  /// extent [width] (the row's horizontal padding is subtracted).
  double bodyMaxWidth(double width) => width - horizontalPadding * 2;

  /// The row's padding, as rendered.
  EdgeInsetsGeometry paddingFor(Subtitle subtitle) {
    return EdgeInsets.fromLTRB(horizontalPadding, topPadding, horizontalPadding, 0.0);
  }

  /// The exact height of the row for [subtitle] when rendered at [width].
  ///
  /// Every [TextPainter] is laid out with the identical span structure,
  /// width, text scaler, height behaviour, width basis and overflow the
  /// rendered row receives, and is disposed immediately after use.
  double extentOf(Subtitle subtitle, double width) {
    final headerHeight = _measureHeight(
      TextSpan(text: headerText(subtitle), style: headerStyle),
      width,
    );
    final bodyHeight = _measureHeight(
      TextSpan(style: bodyRootStyle, children: <InlineSpan>[bodySpan(subtitle)]),
      width,
    );

    return topPadding + headerHeight + bodyHeight + bottomGap;
  }

  double _measureHeight(TextSpan span, double width) {
    final maxWidth = width - horizontalPadding * 2;
    final painter = TextPainter(
      text: span,
      textAlign: textAlign,
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
      textHeightBehavior: textHeightBehavior,
      textWidthBasis: textWidthBasis,
    );

    // softWrap == false lays the paragraph out on a single unbounded line,
    // exactly like RenderParagraph does.
    painter.layout(
      minWidth: 0.0,
      maxWidth: softWrap ? maxWidth : double.infinity,
    );

    final height = painter.height;
    painter.dispose();

    return height;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranscriptRowSpec &&
          runtimeType == other.runtimeType &&
          horizontalPadding == other.horizontalPadding &&
          topPadding == other.topPadding &&
          bottomGap == other.bottomGap &&
          headerStyle == other.headerStyle &&
          bodyBaseStyle == other.bodyBaseStyle &&
          bodyRootStyle == other.bodyRootStyle &&
          textScaler == other.textScaler &&
          textDirection == other.textDirection &&
          textAlign == other.textAlign &&
          textHeightBehavior == other.textHeightBehavior &&
          textWidthBasis == other.textWidthBasis &&
          maxLines == other.maxLines &&
          softWrap == other.softWrap &&
          overflow == other.overflow;

  @override
  int get hashCode => Object.hash(
        horizontalPadding,
        topPadding,
        bottomGap,
        headerStyle,
        bodyBaseStyle,
        bodyRootStyle,
        textScaler,
        textDirection,
        textAlign,
        textHeightBehavior,
        textWidthBasis,
        maxLines,
        softWrap,
        overflow,
      );
}

/// Exact row geometry for a transcript, measured up front with [TextPainter].
///
/// The offsets are prefix sums, so [offsetOf] and [extentOf] are O(1)
/// lookups and [totalExtent] is exact - there is no estimation in the scroll
/// maths, and a list built with `ListView.builder(itemExtentBuilder:)` gets
/// a correct `maxScrollExtent` from the first frame even for rows that have
/// never been built.
///
/// For long transcripts (measured at roughly 120µs per caption on the test
/// host; see `test/unit/ui/transcript_row_layout_test.dart`) measuring every
/// row in one go would stall the UI thread for a noticeable fraction of a
/// second, so rows above [syncComputeMaxRows] are measured incrementally
/// with [start] + [measureChunk]: while incomplete, unmeasured rows report
/// the running average of the measured rows, and the caller re-anchors the
/// list once [complete].
class TranscriptRowLayout {
  /// Above this caption count, rows are measured incrementally instead of
  /// synchronously in one build pass. Derived from the measured cost
  /// (~120µs/caption worst case) against a ~50ms budget.
  static const int syncComputeMaxRows = 400;

  /// Estimate used for rows not yet measured when nothing has been measured
  /// at all (the first chunk of an incremental job measures immediately, so
  /// this only matters between [start] and the first chunk).
  static const double initialRowEstimate = 110.0;

  final List<Subtitle> _subtitles;
  final TranscriptRowSpec _spec;
  final double _width;

  /// Prefix sums of the measured row extents: `_offsets[i]` is the exact
  /// offset of row `i` once rows `0..i-1` are all measured.
  final Float64List _offsets;

  double _measuredExtent = 0.0;
  int _measuredCount = 0;
  double _averageExtent = initialRowEstimate;

  /// The tallest row measured so far. The estimate for unmeasured rows is
  /// never allowed below this: forcing a built row into a slot smaller than
  /// its content produces a debug-mode RenderFlex overflow stripe (and a
  /// visible clip in release), which is worse than spacing rows a little
  /// too far apart during the brief measurement window. The re-anchor once
  /// the job completes corrects any over-estimate.
  double _maxMeasuredExtent = initialRowEstimate;

  TranscriptRowLayout._(this._subtitles, this._spec, this._width) : _offsets = Float64List(_subtitles.length + 1);

  /// Measures every row synchronously. Use only when
  /// `subtitles.length <= [syncComputeMaxRows]`.
  factory TranscriptRowLayout.compute({
    required List<Subtitle> subtitles,
    required TranscriptRowSpec spec,
    required double width,
  }) {
    final layout = TranscriptRowLayout._(subtitles, spec, width);

    while (!layout.complete) {
      layout._measureNextRow();
    }

    return layout;
  }

  /// Begins an incremental measurement job. Measures an initial chunk of
  /// rows synchronously (seeding the estimate used for the remaining rows);
  /// the caller drives the rest with [measureChunk].
  factory TranscriptRowLayout.start({
    required List<Subtitle> subtitles,
    required TranscriptRowSpec spec,
    required double width,
  }) {
    final layout = TranscriptRowLayout._(subtitles, spec, width);

    layout.measureChunk();

    return layout;
  }

  /// Number of rows (captions) in the transcript.
  int get length => _subtitles.length;

  /// True when every row has been measured and all geometry is exact.
  bool get complete => _measuredCount == _subtitles.length;

  /// Number of rows measured so far (incremental jobs only).
  int get measuredCount => _measuredCount;

  /// The estimate used for rows that have not been measured yet.
  double get _estimate => _averageExtent > _maxMeasuredExtent ? _averageExtent : _maxMeasuredExtent;

  /// The exact height of row [index] once it has been measured, or the
  /// estimate (running average, floored by the tallest measured row) while
  /// the job is incomplete.
  double extentOf(int index) {
    assert(index >= 0 && index < length, 'index out of range');

    if (index < _measuredCount) {
      return _offsets[index + 1] - _offsets[index];
    }

    return _estimate;
  }

  /// The top edge of row [index] within the list, relative to the list's
  /// top. Exact for measured prefixes; estimated beyond that while
  /// incomplete.
  double offsetOf(int index) {
    assert(index >= 0 && index <= length, 'index out of range');

    if (index <= _measuredCount) {
      return _offsets[index];
    }

    return _offsets[_measuredCount] + (index - _measuredCount) * _estimate;
  }

  /// The total scroll extent of all rows.
  double get totalExtent => offsetOf(length);

  /// Measures further rows until [budget] of wall time is used up or the
  /// layout is [complete]. Always measures at least one row per call so a
  /// slow row cannot starve the job.
  bool measureChunk({Duration budget = const Duration(milliseconds: 4)}) {
    final watch = Stopwatch()..start();

    while (!complete && (watch.elapsed < budget || _measuredCount == 0)) {
      _measureNextRow();
    }

    watch.stop();

    return complete;
  }

  void _measureNextRow() {
    final index = _measuredCount;
    final extent = _spec.extentOf(_subtitles[index], _width);

    _measuredCount++;
    _measuredExtent += extent;
    _offsets[_measuredCount] = _measuredExtent;
    _averageExtent = _measuredExtent / _measuredCount;

    if (extent > _maxMeasuredExtent) {
      _maxMeasuredExtent = extent;
    }
  }
}

/// Sorts [items] by `start` if they are not already sorted, returning
/// [items] itself when no sort is needed. The transcript list and the
/// highlight search must agree on one order; parsers and persisted
/// transcripts are not guaranteed to be sorted.
List<Subtitle> sortedByStartIfNeeded(List<Subtitle> items) {
  for (var i = 1; i < items.length; i++) {
    if (items[i].start < items[i - 1].start) {
      final sorted = List<Subtitle>.of(items)..sort((a, b) => a.start.compareTo(b.start));

      return sorted;
    }
  }

  return items;
}
