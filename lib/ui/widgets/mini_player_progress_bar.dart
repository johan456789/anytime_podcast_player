// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A playback progress bar with a draggable playhead for the mini players.
///
/// The widget spans the full width of its parent and paints a dimmed track
/// with a filled portion representing the current playback position and a
/// round playhead centred on the track. It follows the theme's secondary
/// colour so it works in both the light and dark themes.
///
/// The playhead can be dragged to scrub through the episode. While dragging,
/// the bar freezes at the dragged position and a bubble above the playhead
/// shows the target timecode; the seek is applied when the drag ends via
/// [AudioBloc.transitionPosition]. The scrubbed position is also reported on
/// [AudioBloc.scrubPosition] while the drag is in progress so other views
/// (such as the transcript) can follow the drag live.
///
/// The full widget height is the touch target for the drag gesture, so the
/// widget is designed to be overlaid along the bottom edge of the mini player
/// (e.g. via [Positioned]) rather than added to a column. It only claims
/// horizontal drags; taps pass through so the buttons underneath remain
/// tappable.
class MiniPlayerProgressBar extends StatefulWidget {
  /// Height of the visible track.
  final double barHeight;

  /// Total height of the widget, which doubles as the drag touch target.
  final double height;

  const MiniPlayerProgressBar({
    super.key,
    this.height = 20.0,
    this.barHeight = 3.0,
  });

  @override
  State<MiniPlayerProgressBar> createState() => _MiniPlayerProgressBarState();
}

class _MiniPlayerProgressBarState extends State<MiniPlayerProgressBar> {
  /// Diameter of the playhead.
  static const playheadSize = 12.0;

  /// Gap between the parent's bottom edge and the track. The track is lifted
  /// by half the playhead size minus half the bar height so the playhead can
  /// sit centred on the track without spilling out of the mini player.
  static const trackBottomGap = 4.5;

  /// The position the user is currently dragging to, or null when not
  /// dragging. While set, it overrides the position from the stream so the
  /// bar does not fight with ongoing playback. It is computed once per drag
  /// event and is the single source for both the bubble text and the scrub
  /// event sent to the transcript, so the two can never disagree.
  Duration? _dragPosition;

  /// The most recent seek, held until the position stream catches up so the
  /// bar does not snap back to the pre-seek position in the gap between
  /// ending the drag and the next position event.
  Duration? _pendingSeek;

  /// Width of the progress strip, updated on every layout pass and used to
  /// convert drag positions into fractions.
  double _stripWidth = 0.0;

  bool _canSeek(AudioBloc audioBloc) {
    final length = audioBloc.playPosition?.valueOrNull?.length ?? Duration.zero;

    return length > Duration.zero;
  }

  /// Converts a drag x-coordinate into the absolute, millisecond-rounded
  /// position it represents on a strip of [width] within [length].
  Duration _scrubbedPosition(double dx, double width, Duration length) {
    final fraction = (dx / width).clamp(0.0, 1.0);

    return Duration(milliseconds: (fraction * length.inMilliseconds).round());
  }

  void _onDragStart(DragStartDetails details) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    if (!_canSeek(audioBloc)) {
      return;
    }

    final length = audioBloc.playPosition!.valueOrNull!.length;

    setState(() {
      _dragPosition = _scrubbedPosition(details.localPosition.dx, _stripWidth, length);
      _pendingSeek = null;
    });

    audioBloc.transitionScrubPosition(_dragPosition);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_dragPosition == null) {
      return;
    }

    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final length = audioBloc.playPosition?.valueOrNull?.length ?? Duration.zero;

    if (length <= Duration.zero) {
      return;
    }

    setState(() {
      _dragPosition = _scrubbedPosition(details.localPosition.dx, _stripWidth, length);
    });

    audioBloc.transitionScrubPosition(_dragPosition);
  }

  void _onDragEnd(DragEndDetails details) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final position = _dragPosition;

    if (position == null) {
      return;
    }

    setState(() {
      _dragPosition = null;
      _pendingSeek = position;
    });

    if (_canSeek(audioBloc)) {
      // The seek is applied before the scrub is cleared: the transcript
      // treats the last scrub value as the pending seek it waits for
      // playback to confirm.
      audioBloc.transitionPosition(position.inSeconds.toDouble());
      audioBloc.transitionScrubPosition(null);
    }
  }

  void _onDragCancel() {
    if (_dragPosition != null) {
      setState(() {
        _dragPosition = null;
      });

      Provider.of<AudioBloc>(context, listen: false).transitionScrubPosition(null);
    }
  }

  /// Accessibility actions: seek 10 seconds from the current position.
  void _nudge(AudioBloc audioBloc, Duration delta) {
    final state = audioBloc.playPosition?.valueOrNull;

    if (state == null || state.length <= Duration.zero) {
      return;
    }

    final targetMs = (state.position + delta).inMilliseconds.clamp(0, state.length.inMilliseconds);
    final target = Duration(milliseconds: targetMs);

    setState(() {
      _pendingSeek = target;
    });

    audioBloc.transitionPosition(target.inSeconds.toDouble());
  }

  /// The position a ±10s accessibility nudge from [position] would land on,
  /// clamped to [length].
  Duration _nudged(Duration position, Duration length, int seconds) {
    final ms = (position + Duration(seconds: seconds)).inMilliseconds.clamp(0, length.inMilliseconds);

    return Duration(milliseconds: ms);
  }

  /// Hours are only shown for episodes longer than an hour.
  String _formatDuration(Duration duration) {
    String twoDigits(int n) {
      if (n >= 10) return '$n';
      return '0$n';
    }

    var twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60).toInt());
    var twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60).toInt());

    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds';
    }

    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final accent = theme.colorScheme.secondary;
    final trackCentre = trackBottomGap + widget.barHeight / 2;

    return StreamBuilder<PositionState>(
        stream: audioBloc.playPosition,
        initialData: audioBloc.playPosition?.valueOrNull,
        builder: (context, snapshot) {
          var position = snapshot.hasData ? snapshot.data!.position : Duration.zero;

          // While dragging, the bar follows the finger; after a seek it holds
          // the requested position until playback confirms it.
          if (_dragPosition != null) {
            position = _dragPosition!;
          } else if (_pendingSeek != null) {
            if ((position.inMilliseconds - _pendingSeek!.inMilliseconds).abs() < 1000) {
              _pendingSeek = null;
            } else {
              position = _pendingSeek!;
            }
          }

          final length = snapshot.hasData ? snapshot.data!.length : Duration.zero;
          final progress =
              length > Duration.zero ? (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0) : 0.0;
          final canSeek = length > Duration.zero;

          return Semantics(
            slider: true,
            value: _formatDuration(position),
            onIncrease: canSeek ? () => _nudge(audioBloc, const Duration(seconds: 10)) : null,
            onDecrease: canSeek ? () => _nudge(audioBloc, const Duration(seconds: -10)) : null,
            // Both (or neither) of these are required whenever the
            // increase/decrease actions exist alongside a value.
            increasedValue: canSeek ? _formatDuration(_nudged(position, length, 10)) : null,
            decreasedValue: canSeek ? _formatDuration(_nudged(position, length, -10)) : null,
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              _stripWidth = width;
              final knobLeft = (progress * width - playheadSize / 2).clamp(0.0, width - playheadSize);
              final bubbleLeft = (progress * width - 36.0).clamp(0.0, width - 72.0);

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: SizedBox(
                  width: double.infinity,
                  height: widget.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0.0,
                        right: 0.0,
                        bottom: trackBottomGap,
                        height: widget.barHeight,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(color: accent.withValues(alpha: 0.3)),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Container(color: accent),
                            ),
                          ],
                        ),
                      ),
                      if (_dragPosition != null)
                        Positioned(
                          left: bubbleLeft,
                          bottom: trackCentre + playheadSize / 2 + 2.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                            decoration: BoxDecoration(
                              color: accent,
                              borderRadius: BorderRadius.circular(6.0),
                            ),
                            child: Text(
                              key: const Key('miniplayer-progress-bubble'),
                              _formatDuration(_dragPosition!),
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: theme.colorScheme.onSecondary,
                                fontWeight: FontWeight.bold,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        key: const Key('miniplayer-playhead'),
                        left: knobLeft,
                        bottom: trackCentre - playheadSize / 2,
                        width: playheadSize,
                        height: playheadSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          );
        });
  }
}
