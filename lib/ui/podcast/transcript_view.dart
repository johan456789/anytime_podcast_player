// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/bloc/podcast/queue_bloc.dart';
import 'package:anytime/entities/person.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/state/queue_event_state.dart';
import 'package:anytime/state/transcript_state_event.dart';
import 'package:anytime/ui/podcast/person_avatar.dart';
import 'package:anytime/ui/podcast/transcript_row_layout.dart';
import 'package:anytime/ui/podcast/transcript_text.dart';
import 'package:anytime/ui/widgets/platform_progress_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/scheduler.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// This class handles the rendering of the podcast transcript (where available).
///
/// The list is a plain [ListView.builder] whose row heights come from a
/// pre-measured [TranscriptRowLayout] via `itemExtentBuilder`, which makes
/// every scroll target exact from the first frame: the highlighted row can
/// be centred (with natural clamps at the list's edges) with a single
/// `jumpTo` while the user scrubs, and a gentle `animateTo` keeps following
/// playback without any measure-and-correct passes.
// ignore: must_be_immutable
class TranscriptView extends StatefulWidget {
  const TranscriptView({
    super.key,
  });

  @override
  State<TranscriptView> createState() => _TranscriptViewState();
}

class _TranscriptViewState extends State<TranscriptView> {
  final log = Logger('TranscriptView');
  final ScrollController _scrollController = ScrollController();
  final _transcriptSearchController = TextEditingController();
  late StreamSubscription<PositionState> _positionSubscription;
  late StreamSubscription<Duration?> _scrubSubscription;

  /// Timer that clears an unconfirmed pending seek (a failed seek) so stale
  /// playback positions do not freeze the transcript forever.
  Timer? _pendingSeekTimer;

  /// The transcript captions the list renders and the highlight searches.
  /// This is the transcript state's list (or a sorted copy of it), never the
  /// episode's own transcript, so a search filter cannot desync the two.
  List<Subtitle> _items = const <Subtitle>[];
  List<Subtitle> _rawItems = const <Subtitle>[];

  /// The resolved row recipe and its measured geometry, recomputed when the
  /// captions, the width, the text scale or the theme change.
  TranscriptRowSpec? _spec;
  TranscriptRowLayout? _layout;
  double _layoutWidth = 0.0;

  /// An incremental measurement job still in progress (long transcripts).
  TranscriptRowLayout? _layoutJob;

  /// Index of the caption to highlight, or null when there is none (before
  /// the first caption, or no transcript yet).
  int? _highlightIndex;

  /// True while the user is scrubbing with the mini player's playhead;
  /// playback position updates are ignored until the scrub ends.
  bool _scrubbing = false;

  /// The scrubbed position, held until playback reports a position within
  /// the confirmation window of it, so the release stays motionless.
  Duration? _pendingSeek;

  /// The most recent position accepted from either a scrub or playback.
  Duration? _lastPosition;

  /// Whether the transcript should follow the playhead (dragging the list
  /// turns it off; programmatic scrolls never do).
  bool _follow = true;

  /// Master's behaviour: the follow switch is disabled while a search filter
  /// is active.
  bool _autoScrollEnabled = true;

  /// The speaker of the highlighted caption, for the avatar row highlight.
  String _speaker = '';

  /// Set when the list should re-anchor the highlighted row (first attach or
  /// a layout recompute); consumed by a single post-frame callback.
  bool _needsAnchor = false;

  /// The viewport dimension seen by the last anchor, to detect viewport
  /// height changes (rotation, keyboard) and re-anchor.
  double? _lastViewportDimension;

  @override
  void initState() {
    super.initState();
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    // Seed the highlight from the current playback position (if any) so the
    // first frame can anchor to the right row.
    final current = audioBloc.playPosition?.valueOrNull;

    if (current != null) {
      _lastPosition = current.position;
    }

    // While the user is scrubbing with the mini player's playhead, follow
    // the dragged position live; when the scrub ends, hold position until
    // playback confirms the seek.
    _scrubSubscription = audioBloc.scrubPosition.listen(_onScrubPosition);

    // Listen to playback position updates and follow the highlighted caption
    // if follow is enabled.
    _positionSubscription = audioBloc.playPosition!.listen(_onPlaybackPosition);
  }

  @override
  void dispose() {
    _scrubSubscription.cancel();
    _positionSubscription.cancel();
    _pendingSeekTimer?.cancel();
    _layoutJob = null;
    _scrollController.dispose();
    _transcriptSearchController.dispose();

    super.dispose();
  }

  /// A scrub event from the mini player's progress bar. A non-null position
  /// means the user is dragging; null means the drag ended (the seek was
  /// applied by the bar just before this event).
  void _onScrubPosition(Duration? p) {
    if (!mounted) {
      return;
    }

    if (p != null) {
      _scrubbing = true;
      _pendingSeekTimer?.cancel();
      _pendingSeek = p;
      _lastPosition = p;

      final index = indexForPosition(_items, p);
      final changed = index != _highlightIndex;

      if (changed) {
        setState(() {
          _highlightIndex = index;
          _speaker = index != null ? speakerForIndex(_items, index) : '';
        });
      }

      // Follow the drag live: jump synchronously within the listener so the
      // scroll lands in the same frame as the bar's bubble. Between caption
      // boundaries the target is constant, so this is a cheap no-op.
      if (_follow && _scrollController.hasClients) {
        _scrollController.jumpTo(_targetOffsetForIndex(index));
      }
    } else {
      // The scrub ended. Do nothing else: the highlight and the scroll stay
      // exactly where the drag left them. The bar has already applied the
      // seek; hold the scrubbed position as a pending seek until playback
      // reports a position near it, which normally lands in the same caption
      // so nothing moves at all.
      _scrubbing = false;

      if (_pendingSeek != null) {
        _pendingSeekTimer?.cancel();
        _pendingSeekTimer = Timer(pendingSeekTimeout, () {
          // The seek never confirmed (e.g. it failed); accept positions again.
          _pendingSeek = null;
        });
      }
    }
  }

  /// A playback position event. While scrubbing, events are ignored. Right
  /// after a scrub, stale pre-seek positions are skipped until one arrives
  /// that confirms the pending seek.
  void _onPlaybackPosition(PositionState event) {
    if (!mounted || _scrubbing) {
      return;
    }

    final p = event.position;
    final pending = _pendingSeek;

    if (pending != null) {
      if ((p.inMilliseconds - pending.inMilliseconds).abs() <= pendingSeekConfirmationWindow.inMilliseconds) {
        _pendingSeek = null;
        _pendingSeekTimer?.cancel();
      } else {
        // A stale position from before the seek landed.
        return;
      }
    }

    _lastPosition = p;

    final index = indexForPosition(_items, p);

    if (index == _highlightIndex) {
      // Same caption: keep the scroll exactly where it is. This is what
      // makes the release of a scrub motionless.
      return;
    }

    setState(() {
      _highlightIndex = index;
      _speaker = index != null ? speakerForIndex(_items, index) : '';
    });

    if (_follow && _scrollController.hasClients) {
      // A new animateTo replaces any running one (Flutter's behaviour), so
      // rapid position updates never queue animations.
      unawaited(_scrollController.animateTo(
        _targetOffsetForIndex(index),
        duration: playbackFollowDuration,
        curve: Curves.easeOutCubic,
      ));
    }
  }

  /// The scroll offset that centres the row [index] in the viewport, with
  /// natural clamps: the start of the list cannot scroll past 0 and the end
  /// clamps at maxScrollExtent, leaving the last row flush with the
  /// viewport's bottom and no trailing gap.
  double _targetOffsetForIndex(int? index) {
    if (index == null || _layout == null || !_scrollController.hasClients) {
      return 0.0;
    }

    final layout = _layout!;
    final viewport = _scrollController.position.viewportDimension;
    final centre = layout.offsetOf(index) + layout.extentOf(index) / 2;

    return (centre - viewport / 2).clamp(0.0, _scrollController.position.maxScrollExtent);
  }

  /// Schedules the single post-frame callback that re-anchors the list.
  void _scheduleAnchor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        // No clients yet (the list is not laid out): keep the request so the
        // next layout anchors.
        return;
      }

      final dimension = _scrollController.position.viewportDimension;
      final dimensionChanged = _lastViewportDimension != dimension;
      _lastViewportDimension = dimension;

      if (!_needsAnchor && !dimensionChanged) {
        return;
      }

      _needsAnchor = false;

      if (_follow) {
        _scrollController.jumpTo(_targetOffsetForIndex(_highlightIndex));
      }
    });
  }

  /// Recomputes the row geometry when its cache key changes (captions,
  /// width, text scale, theme). Short transcripts are measured in one pass;
  /// long ones are measured incrementally (see [TranscriptRowLayout]) and
  /// re-anchored once complete.
  void _rebuildLayoutIfNeeded(List<Subtitle> items, TranscriptRowSpec spec, double width) {
    if (identical(items, _rawItems) && spec == _spec && width == _layoutWidth && _layout != null) {
      return;
    }

    _rawItems = items;
    _spec = spec;
    _layoutWidth = width;
    _items = sortedByStartIfNeeded(items);
    _layoutJob = null;
    _needsAnchor = true;

    final reference = _pendingSeek ?? _lastPosition;
    final index = reference == null ? null : indexForPosition(_items, reference);

    if (index != _highlightIndex) {
      _highlightIndex = index;
      _speaker = index != null ? speakerForIndex(_items, index) : '';
    }

    if (_items.length <= TranscriptRowLayout.syncComputeMaxRows) {
      _layout = TranscriptRowLayout.compute(
        subtitles: _items,
        spec: spec,
        width: width,
      );
    } else {
      final job = TranscriptRowLayout.start(
        subtitles: _items,
        spec: spec,
        width: width,
      );

      _layout = job;
      _layoutJob = job;
      _scheduleMeasureChunks(job);
    }
  }

  /// Drives an incremental measurement job with an idle task per chunk.
  void _scheduleMeasureChunks(TranscriptRowLayout job) {
    SchedulerBinding.instance.scheduleTask(() {
      if (!mounted || !identical(job, _layoutJob) || job.complete) {
        return false;
      }

      final done = job.measureChunk();

      if (done && identical(job, _layoutJob)) {
        _layoutJob = null;
        _needsAnchor = true;

        // Rebuild so the list picks up the exact extents, then re-anchor so
        // the highlighted row keeps its centre.
        setState(() {});
      } else {
        _scheduleMeasureChunks(job);
      }

      return false;
    }, Priority.idle, debugLabel: 'TranscriptRowLayout.measure');
  }

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);
    final queueBloc = Provider.of<QueueBloc>(context, listen: false);

    return StreamBuilder<QueueState>(
        initialData: QueueEmptyState(),
        stream: queueBloc.queue,
        builder: (context, queueSnapshot) {
          return StreamBuilder<TranscriptState>(
              stream: audioBloc.nowPlayingTranscript,
              builder: (context, transcriptSnapshot) {
                if (transcriptSnapshot.hasData) {
                  if (transcriptSnapshot.data is TranscriptLoadingState) {
                    return const Align(
                      alignment: Alignment.center,
                      child: PlatformProgressIndicator(),
                    );
                  } else if (transcriptSnapshot.data is TranscriptUnavailableState ||
                      !transcriptSnapshot.data!.transcript!.transcriptAvailable) {
                    return Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Align(
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              L.of(context)!.no_transcript_available_label,
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 32.0, bottom: 32.0),
                              child: OutlinedButton(
                                  onPressed: () {
                                    final uri = Uri.parse(L.of(context)!.transcript_why_not_url);

                                    unawaited(
                                      canLaunchUrl(uri).then((value) => launchUrl(uri)),
                                    );
                                  },
                                  child: Text(
                                    L.of(context)!.transcript_why_not_label,
                                    style: Theme.of(context).textTheme.titleSmall,
                                    textAlign: TextAlign.center,
                                  )),
                            ),
                          ],
                        ),
                      ),
                    );
                  } else {
                    final items = transcriptSnapshot.data!.transcript?.subtitles ?? const <Subtitle>[];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0, left: 16.0, right: 16.0),
                          child: TextField(
                            controller: _transcriptSearchController,
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.all(0.0),
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  Icons.close,
                                  semanticLabel: L.of(context)!.clear_search_button_label,
                                ),
                                onPressed: () {
                                  _transcriptSearchController.clear();
                                  audioBloc.filterTranscript(TranscriptClearEvent());
                                  setState(() {
                                    _autoScrollEnabled = true;
                                  });
                                },
                              ),
                              isDense: true,
                              filled: true,
                              border: const OutlineInputBorder(
                                borderRadius: BorderRadius.all(Radius.circular(8.0)),
                                borderSide: BorderSide.none,
                                gapPadding: 0.0,
                              ),
                              hintText: L.of(context)!.search_transcript_label,
                            ),
                            onSubmitted: ((search) {
                              if (search.isNotEmpty) {
                                setState(() {
                                  _autoScrollEnabled = false;
                                  _follow = false;
                                });
                                audioBloc.filterTranscript(TranscriptFilterEvent(search: search));
                              }
                            }),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(L.of(context)!.auto_scroll_transcript_label),
                              Switch(
                                value: _follow,
                                onChanged: _autoScrollEnabled
                                    ? (bool enableFollow) {
                                        setState(() {
                                          _follow = enableFollow;
                                        });

                                        // Turning follow back on re-anchors to
                                        // the current highlight.
                                        if (enableFollow && _scrollController.hasClients) {
                                          unawaited(_scrollController.animateTo(
                                            _targetOffsetForIndex(_highlightIndex),
                                            duration: playbackFollowDuration,
                                            curve: Curves.easeOutCubic,
                                          ));
                                        }
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        if (queueSnapshot.hasData &&
                            queueSnapshot.data?.playing != null &&
                            queueSnapshot.data!.playing!.persons.isNotEmpty)
                          _buildPersonRow(queueSnapshot.data!.playing!.persons),
                        Expanded(
                          /// A simple way to ensure the builder is visible before attempting to use it.
                          child: LayoutBuilder(builder: (context, constraints) {
                            if (constraints.minHeight <= 60.0) {
                              return Container();
                            }

                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: _buildList(context, items, constraints.maxWidth),
                            );
                          }),
                        ),
                      ],
                    );
                  }
                } else {
                  return Container();
                }
              });
        });
  }

  /// The horizontal avatar row, highlighting the current speaker.
  Widget _buildPersonRow(List<Person> persons) {
    return Container(
      padding: const EdgeInsets.only(left: 0.0),
      width: double.infinity,
      height: 72.0,
      child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: persons.length,
          itemBuilder: (BuildContext context, int index) {
            final person = persons[index];

            // Some speakers are - delimited so won't match.
            final speaker = _speaker.replaceAll('-', ' ');
            final selected = speaker.isNotEmpty && person.name.toLowerCase().startsWith(speaker.toLowerCase());

            return PersonAvatar(
              padding: const EdgeInsets.all(4.0),
              person: person,
              width: 80,
              radius: 28,
              showName: false,
              highlight: selected,
            );
          }),
    );
  }

  /// The transcript list. Rows are laid out from the measured
  /// [TranscriptRowLayout] via `itemExtentBuilder`, so the scroll offset of
  /// any row is exact even while that row has never been built.
  Widget _buildList(BuildContext context, List<Subtitle> items, double width) {
    final spec = TranscriptRowSpec.of(context);

    _rebuildLayoutIfNeeded(items, spec, width);

    final layout = _layout!;
    final highlightIndex = _highlightIndex;

    _scheduleAnchor();

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Only real user drags carry dragDetails; programmatic jumps and
        // animations must not disable follow-transcript.
        final dragDetails = switch (notification) {
          ScrollStartNotification() => notification.dragDetails,
          ScrollUpdateNotification() => notification.dragDetails,
          _ => null,
        };

        if (dragDetails != null && _follow) {
          setState(() {
            _follow = false;
          });
        }

        return false;
      },
      // A CustomScrollView + SliverVariedExtentList rather than
      // ListView.builder so the child delegate can report the exact scroll
      // extent: the default extrapolates it from the children that happen
      // to be laid out, which is inexact for transcripts with varied row
      // heights until the end of the list has been reached. With the exact
      // extent, maxScrollExtent is correct from the first frame, so the
      // centre-anchoring clamps hold at the list's natural bounds.
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverVariedExtentList(
            delegate: _TranscriptChildBuilderDelegate(
              (BuildContext context, int index) {
                return SubtitleWidget(
                  spec: spec,
                  subtitle: _items[index],
                  highlight: index == highlightIndex,
                );
              },
              childCount: _items.length,
              layout: layout,
            ),
            itemExtentBuilder: (index, dimensions) => index < layout.length ? layout.extentOf(index) : null,
          ),
        ],
      ),
    );
  }
}

/// The transcript list's child delegate: exactly as [SliverChildBuilderDelegate]
/// builds rows, but reporting the measured [TranscriptRowLayout] extent as the
/// max scroll extent instead of an extrapolation from laid-out children.
class _TranscriptChildBuilderDelegate extends SliverChildBuilderDelegate {
  final TranscriptRowLayout layout;

  _TranscriptChildBuilderDelegate(
    super.builder, {
    required this.layout,
    super.childCount,
  });

  @override
  double? estimateMaxScrollOffset(
      int firstIndex, int lastIndex, double leadingScrollOffset, double trailingScrollOffset) {
    return layout.totalExtent;
  }

  // Like SliverChildBuilderDelegate: always rebuild. The builder closures
  // capture the current highlight and spec, so cached rows must be rebuilt
  // on every pass for highlight updates to reach the tree.
  @override
  bool shouldRebuild(covariant SliverChildBuilderDelegate oldDelegate) => true;
}

/// Each transcript is made up of one or more subtitles. Each [Subtitle] represents one
/// line of the transcript. This widget handles rendering the passed line.
///
/// The row builds itself from the [TranscriptRowSpec] it is given - the same
/// instance the row geometry was measured with - so the rendered height and
/// the measured height cannot diverge. The highlight changes only the
/// background colour, never the size.
class SubtitleWidget extends StatelessWidget {
  final TranscriptRowSpec spec;
  final Subtitle subtitle;
  final bool highlight;
  static const margin = Duration(milliseconds: 1000);

  const SubtitleWidget({
    super.key,
    required this.spec,
    required this.subtitle,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final audioBloc = Provider.of<AudioBloc>(context, listen: false);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        final p = subtitle.start + margin;

        audioBloc.transitionPosition(p.inSeconds.toDouble());
      },
      child: Container(
        width: double.infinity,
        padding: spec.paddingFor(subtitle),
        color: highlight ? Theme.of(context).cardTheme.color : Colors.transparent,
        // While a long transcript is still being measured, a row's slot can
        // briefly be smaller than its content (the estimate for unmeasured
        // rows is only an estimate). The content lays out at its natural
        // height regardless and is clipped to its slot for that window;
        // once measurement completes every slot is exact.
        child: ClipRect(
          child: OverflowBox(
            fit: OverflowBoxFit.deferToChild,
            alignment: Alignment.topLeft,
            minHeight: 0.0,
            maxHeight: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spec.headerText(subtitle),
                  style: spec.headerStyle,
                ),
                Builder(
                  builder: (context) {
                    final parsed = parseTranscriptText(
                      rawText: subtitle.data ?? '',
                      baseStyle: spec.bodyBaseStyle,
                    );
                    // Wrap with Semantics so screen readers get plain text,
                    // not raw markup tags.
                    return Semantics(
                      label: parsed.plainText,
                      child: ExcludeSemantics(
                        child: Text.rich(parsed.textSpan),
                      ),
                    );
                  },
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, spec.bottomGap),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
