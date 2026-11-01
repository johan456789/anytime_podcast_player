// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:anytime/bloc/podcast/queue_bloc.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/state/queue_event_state.dart';
import 'package:anytime/ui/podcast/transcript_view.dart';
import 'package:anytime/ui/podcast/up_next_view.dart';
import 'package:anytime/ui/widgets/slider_handle.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// This class gives us options that can be dragged up from the bottom of the main player
/// window.
///
/// Currently these options are Up Next & Transcript.
///
/// This class is an initial version and should by much simpler than it is; however,
/// a [NestedScrollView] is the widget we need to implement this UI, there is a current
/// issue whereby the scroll view and [DraggableScrollableSheet] clash and therefore cannot
/// be used together.
///
/// See issues [64157](https://github.com/flutter/flutter/issues/64157)
///            [67219](https://github.com/flutter/flutter/issues/67219)
///
/// If anyone can come up with a more elegant solution (and one that does not throw
/// an overflow error in debug) please raise and issue/submit a PR.
///
class NowPlayingOptionsSelector extends StatefulWidget {
  final double? scrollPos;

  /// Height reserved on the now playing screen for the collapsed sheet.
  ///
  /// Note that the actual collapsed height of the sheet is derived from its
  /// content - see [collapsedSheetHeight] - and not from this value.
  static const baseSize = 68.0;

  /// Padding either side of each tab label, matching [TabBar.labelPadding].
  static const double _tabLabelHorizontalPadding = 16.0;

  /// Height of the [SliderHandle]: 8.0 padding above and below a 4.0 high handle.
  static const double _handleHeight = 20.0;

  /// Padding above and below each tab label.
  static const double _tabLabelVerticalPadding = 8.0;

  /// Height the [TabBar] adds below each tab for the selection indicator.
  static const double _tabIndicatorWeight = 2.0;

  /// Space between the tab bar and the tab content.
  static const double _tabContentTopPadding = 12.0;

  const NowPlayingOptionsSelector({super.key, this.scrollPos});

  /// The height the sheet requires when fully collapsed: the drag handle, the
  /// tab bar and the gap above the tab content.
  ///
  /// The tab labels are measured with the current [TextScaler] and laid out
  /// within the width a tab actually has - [tabBarWidth] split between the two
  /// tabs - so that the collapsed sheet is always tall enough to display its
  /// content without a bottom overflow, whatever font size the user has
  /// selected and however many lines the labels need.
  static double collapsedSheetHeight(BuildContext context, {required double tabBarWidth}) {
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = Theme.of(context).textTheme.labelLarge;
    final labelWidth = math.max(0.0, tabBarWidth / 2 - _tabLabelHorizontalPadding * 2);

    final labelHeight = [
      L.of(context)!.up_next_queue_label.toUpperCase(),
      L.of(context)!.transcript_label.toUpperCase(),
    ].map((label) {
      final textPainter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: labelWidth);

      final height = textPainter.height;
      textPainter.dispose();

      return height;
    }).reduce(math.max);

    return _handleHeight + _tabLabelVerticalPadding + labelHeight + _tabLabelVerticalPadding + _tabIndicatorWeight + _tabContentTopPadding;
  }

  @override
  State<NowPlayingOptionsSelector> createState() => _NowPlayingOptionsSelectorState();
}

class _NowPlayingOptionsSelectorState extends State<NowPlayingOptionsSelector> {
  DraggableScrollableController? draggableController;

  @override
  Widget build(BuildContext context) {
    final queueBloc = Provider.of<QueueBloc>(context, listen: false);
    final theme = Theme.of(context);

    /// A [DraggableScrollableSheet] sizes its child as a fraction of the height
    /// available to it, which is less than the window height once safe area
    /// insets and the floating player above this widget are taken into account.
    /// Sizing the collapsed sheet against a [LayoutBuilder] ensures the handle,
    /// tab bar and padding always fit without overflowing; previously both the
    /// collapsed height and the fraction were hardcoded against the window
    /// height, which could leave the sheet shorter than its own content.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return _buildDraggableSheet(context, queueBloc, theme, constraints);
      },
    );
  }

  DraggableScrollableSheet _buildDraggableSheet(BuildContext context, QueueBloc queueBloc, ThemeData theme, BoxConstraints constraints) {
    final collapsedHeight = NowPlayingOptionsSelector.collapsedSheetHeight(context, tabBarWidth: constraints.maxWidth);
    final minSize = constraints.maxHeight > 0.0 ? (collapsedHeight / constraints.maxHeight).clamp(0.0, 1.0) : 0.0;

    return DraggableScrollableSheet(
      initialChildSize: minSize,
      minChildSize: minSize,
      maxChildSize: 1.0,
      controller: draggableController,
      // Snap doesn't work as the sheet and scroll controller just don't get along
      // snap: true,
      // snapSizes: [minSize, maxSize],
      builder: (BuildContext context, ScrollController scrollController) {
        return DefaultTabController(
          animationDuration: !draggableController!.isAttached || draggableController!.size <= minSize
              ? const Duration(seconds: 0)
              : kTabScrollDuration,
          length: 2,
          child: LayoutBuilder(builder: (BuildContext ctx, BoxConstraints constraints) {
            return SingleChildScrollView(
              controller: scrollController,
              child: ConstrainedBox(
                constraints: BoxConstraints.expand(
                  height: constraints.maxHeight,
                ),
                child: Material(
                  color: theme.secondaryHeaderColor,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(
                      color: theme.highlightColor,
                      width: 0.0,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18.0),
                      topRight: Radius.circular(18.0),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      SliderHandle(
                        label: optionsSliderOpen()
                            ? L.of(context)!.semantic_playing_options_collapse_label
                            : L.of(context)!.semantic_playing_options_expand_label,
                        onTap: () {
                          if (draggableController != null) {
                            if (draggableController!.size < 1.0) {
                              draggableController!.animateTo(
                                1.0,
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeInOut,
                              );
                            } else {
                              draggableController!.animateTo(
                                0.0,
                                duration: const Duration(milliseconds: 150),
                                curve: Curves.easeInOut,
                              );
                            }
                          }
                        },
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.0),
                          border: Border(
                            bottom: draggableController != null &&
                                    (!draggableController!.isAttached || draggableController!.size <= minSize)
                                ? BorderSide.none
                                : BorderSide(color: Colors.grey[800]!, width: 1.0),
                          ),
                        ),
                        child: StreamBuilder<QueueState>(
                            initialData: QueueEmptyState(),
                            stream: queueBloc.queue,
                            builder: (context, snapshot) {
                              return TabBar(
                                onTap: (index) {
                                  DefaultTabController.of(ctx).animateTo(index);

                                  if (draggableController != null && draggableController!.size < 1.0) {
                                    draggableController!.animateTo(
                                      1.0,
                                      duration: const Duration(milliseconds: 150),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                },
                                automaticIndicatorColorAdjustment: false,
                                indicatorPadding: EdgeInsets.zero,
                                indicatorWeight: NowPlayingOptionsSelector._tabIndicatorWeight,
                                labelPadding: const EdgeInsets.symmetric(horizontal: NowPlayingOptionsSelector._tabLabelHorizontalPadding),

                                /// Little hack to hide the indicator when closed
                                indicatorColor: draggableController != null &&
                                        (!draggableController!.isAttached || draggableController!.size <= minSize)
                                    ? theme.secondaryHeaderColor
                                    : null,
                                tabs: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: NowPlayingOptionsSelector._tabLabelVerticalPadding,
                                      bottom: NowPlayingOptionsSelector._tabLabelVerticalPadding,
                                    ),
                                    child: Text(
                                      L.of(context)!.up_next_queue_label.toUpperCase(),
                                      style: theme.textTheme.labelLarge,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: NowPlayingOptionsSelector._tabLabelVerticalPadding,
                                      bottom: NowPlayingOptionsSelector._tabLabelVerticalPadding,
                                    ),
                                    // If the episode does not support transcripts, grey out
                                    // the option.
                                    child: snapshot.hasData &&
                                            snapshot.data?.playing != null &&
                                            snapshot.data!.playing!.hasTranscripts
                                        ? Text(
                                            L.of(context)!.transcript_label.toUpperCase(),
                                            style: theme.textTheme.labelLarge,
                                          )
                                        : Text(
                                            L.of(context)!.transcript_label.toUpperCase(),
                                            style: theme
                                                .textTheme
                                                .labelLarge!
                                                .copyWith(color: theme.disabledColor),
                                          ),
                                  ),
                                ],
                              );
                            }),
                      ),
                      const Padding(padding: EdgeInsets.only(bottom: NowPlayingOptionsSelector._tabContentTopPadding)),
                      const Expanded(
                        child: TabBarView(
                          children: [
                            UpNextView(),
                            TranscriptView(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  bool optionsSliderOpen() {
    return (draggableController != null && draggableController!.isAttached && draggableController!.size == 1.0);
  }

  @override
  void initState() {
    draggableController = DraggableScrollableController();
    super.initState();
  }
}

class NowPlayingOptionsScaffold extends StatelessWidget {
  const NowPlayingOptionsScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: NowPlayingOptionsSelector.baseSize - 8.0,
    );
  }
}

/// This implementation displays the additional options in a tab set outside of a
/// draggable sheet.
///
/// Currently these options are Up Next & Transcript.
class NowPlayingOptionsSelectorWide extends StatefulWidget {
  final double? scrollPos;
  static const baseSize = 68.0;

  const NowPlayingOptionsSelectorWide({super.key, this.scrollPos});

  @override
  State<NowPlayingOptionsSelectorWide> createState() => _NowPlayingOptionsSelectorWideState();
}

class _NowPlayingOptionsSelectorWideState extends State<NowPlayingOptionsSelectorWide> {
  DraggableScrollableController? draggableController;

  @override
  Widget build(BuildContext context) {
    final queueBloc = Provider.of<QueueBloc>(context, listen: false);
    final theme = Theme.of(context);
    final scrollController = ScrollController();

    return DefaultTabController(
      length: 2,
      child: LayoutBuilder(builder: (BuildContext ctx, BoxConstraints constraints) {
        return SingleChildScrollView(
          controller: scrollController,
          child: ConstrainedBox(
            constraints: BoxConstraints.expand(
              height: constraints.maxHeight,
            ),
            child: Material(
              color: theme.secondaryHeaderColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.0),
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[800]!, width: 1.0),
                      ),
                    ),
                    child: StreamBuilder<QueueState>(
                        initialData: QueueEmptyState(),
                        stream: queueBloc.queue,
                        builder: (context, snapshot) {
                          return TabBar(
                            automaticIndicatorColorAdjustment: false,
                            tabs: [
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                                child: Text(
                                  L.of(context)!.up_next_queue_label.toUpperCase(),
                                  style: theme.textTheme.labelLarge,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 16.0, bottom: 16.0),
                                child: snapshot.hasData &&
                                        snapshot.data?.playing != null &&
                                        snapshot.data!.playing!.hasTranscripts
                                    ? Text(
                                        L.of(context)!.transcript_label.toUpperCase(),
                                        style: theme.textTheme.labelLarge,
                                      )
                                    : Text(
                                        L.of(context)!.transcript_label.toUpperCase(),
                                        style: theme
                                            .textTheme
                                            .labelLarge!
                                            .copyWith(color: theme.disabledColor),
                                      ),
                              ),
                            ],
                          );
                        }),
                  ),
                  const Expanded(
                    child: TabBarView(
                      children: [
                        UpNextView(),
                        TranscriptView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}
