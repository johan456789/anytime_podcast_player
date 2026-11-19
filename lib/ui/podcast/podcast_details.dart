// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:anytime/bloc/podcast/episode_bloc.dart';
import 'package:anytime/bloc/podcast/podcast_bloc.dart';
import 'package:anytime/bloc/podcast/queue_bloc.dart';
import 'package:anytime/bloc/settings/settings_bloc.dart';
import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/feed.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/state/bloc_state.dart';
import 'package:anytime/state/queue_event_state.dart';
import 'package:anytime/ui/podcast/episode_selection.dart';
import 'package:anytime/ui/podcast/funding_menu.dart';
import 'package:anytime/ui/podcast/mini_player.dart';
import 'package:anytime/ui/podcast/playback_error_listener.dart';
import 'package:anytime/ui/podcast/podcast_context_menu.dart';
import 'package:anytime/ui/podcast/podcast_episode_list.dart';
import 'package:anytime/ui/podcast/selection_action_bar.dart';
import 'package:anytime/ui/widgets/action_text.dart';
import 'package:anytime/ui/widgets/app_bottom_navigation.dart';
import 'package:anytime/ui/widgets/delayed_progress_indicator.dart';
import 'package:anytime/ui/widgets/episode_filter_selector.dart';
import 'package:anytime/ui/widgets/episode_sort_selector.dart';
import 'package:anytime/ui/widgets/placeholder_builder.dart';
import 'package:anytime/ui/widgets/platform_back_button.dart';
import 'package:anytime/ui/widgets/platform_progress_indicator.dart';
import 'package:anytime/ui/widgets/podcast_html.dart';
import 'package:anytime/ui/widgets/podcast_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dialogs/flutter_dialogs.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

/// This Widget takes a search result and builds a list of currently available podcasts.
///
/// From here a user can option to subscribe/unsubscribe or play a podcast directly
/// from a search result.
class PodcastDetails extends StatefulWidget {
  final Podcast podcast;
  final PodcastBloc _podcastBloc;

  const PodcastDetails(
    this.podcast,
    this._podcastBloc, {
    super.key,
  });

  @override
  State<PodcastDetails> createState() => _PodcastDetailsState();
}

class _PodcastDetailsState extends State<PodcastDetails> {
  final log = Logger('PodcastDetails');
  final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  final ScrollController _sliverScrollController = ScrollController();
  bool toolbarCollapsed = false;

  /// Scroll offset at which the podcast title fades into the toolbar. The
  /// compact header (artwork, title and description) sits below the toolbar;
  /// once the user has scrolled past it the toolbar title gives context again.
  static const double _titleCollapseOffset = 180.0;

  /// Multi-selection state for the episode list.
  final EpisodeSelection _selection = EpisodeSelection();

  /// The episodes currently displayed in the list; used by the select all
  /// action so it respects any active search or filter.
  List<Episode> _visibleEpisodes = <Episode>[];

  @override
  void initState() {
    super.initState();

    // Load the details of the Podcast specified in the URL
    log.fine('initState() - load feed');

    // Rebuild whenever the episode selection changes so the selection app
    // bar, tiles and action bar stay in sync.
    _selection.addListener(_handleSelectionChanged);

    widget._podcastBloc.load(Feed(
      podcast: widget.podcast,
      backgroundFetch: true,
      errorSilently: true,
    ));

    // We only want to display the podcast title when the toolbar is in a
    // collapsed state. Add a listener and set toollbarCollapsed variable
    // as required. The text display property is then based on this boolean.
    _sliverScrollController.addListener(() {
      if (!toolbarCollapsed &&
          _sliverScrollController.hasClients &&
          _sliverScrollController.offset > _titleCollapseOffset) {
        setState(() {
          toolbarCollapsed = true;
        });
      } else if (toolbarCollapsed &&
          _sliverScrollController.hasClients &&
          _sliverScrollController.offset < _titleCollapseOffset) {
        setState(() {
          toolbarCollapsed = false;
        });
      }
    });

    widget._podcastBloc.backgroundLoading.where((event) => event is BlocPopulatedState<void>).listen((event) {
      if (mounted) {
        /// If we have not scrolled (save a few pixels) just refresh the episode list;
        /// otherwise prompt the user to prevent unexpected list jumping
        if (_sliverScrollController.offset < 20) {
          widget._podcastBloc.podcastEvent(PodcastEvent.refresh);
        } else {
          scaffoldMessengerKey.currentState!.showSnackBar(SnackBar(
            content: Text(L.of(context)!.new_episodes_label),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: L.of(context)!.new_episodes_view_now_label,
              onPressed: () {
                _sliverScrollController.animateTo(100,
                    duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
                widget._podcastBloc.podcastEvent(PodcastEvent.refresh);
              },
            ),
            duration: const Duration(seconds: 5),
          ));
        }
      }
    });
  }

  @override
  void dispose() {
    _sliverScrollController.dispose();
    _selection.removeListener(_handleSelectionChanged);
    _selection.dispose();

    super.dispose();
  }

  void _handleSelectionChanged() {
    if (mounted) {
      setState(() {
        // Rebuild so the app bar and the bottom action bar reflect the
        // current selection state.
      });
    }
  }

  Future<void> _handleRefresh() async {
    log.fine('_handleRefresh');

    widget._podcastBloc.load(Feed(
      podcast: widget.podcast,
      forceFetch: true,
    ));
  }

  /// The podcast shown in the compact header: the loaded details when
  /// available, falling back to any partial data still loading, or the
  /// podcast the user navigated here with.
  Podcast _resolvePodcast(BlocState<Podcast>? state) {
    if (state is BlocPopulatedState<Podcast> && state.results != null) {
      return state.results!;
    }

    if (state is BlocLoadingState<Podcast> && state.data != null) {
      return state.data!;
    }

    return widget.podcast;
  }

  /// TODO: This really needs a refactor. There are too many nested streams on this now and it needs simplifying.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);

    return Semantics(
      header: false,
      label: L.of(context)!.semantics_podcast_details_header,
      child: PopScope(
        canPop: !_selection.selecting,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            // Back was intercepted to leave selection mode first.
            _exitSelection();
            return;
          }

          podcastBloc.podcastSearchEvent('');
        },
        child: ScaffoldMessenger(
          key: scaffoldMessengerKey,
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            // The mini player and the app's bottom navigation bar remain in
            // place while the user browses this podcast's episodes.
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const MiniPlayer(),
                if (_selection.selecting)
                  // The action bar sits above the navigation bar, so it must
                  // not apply the bottom safe area inset a second time.
                  MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: _buildSelectionActionBar(context),
                  ),
                const AppBottomNavigationBar(embedded: true),
              ],
            ),
            body: RefreshIndicator(
              displacement: 60.0,
              onRefresh: _handleRefresh,
              child: CustomScrollView(
                // Disable pull-to-refresh while selecting so a drag does not
                // fight with the selection.
                physics: _selection.selecting ? const ClampingScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                controller: _sliverScrollController,
                slivers: <Widget>[
                  _buildPodcastAppBar(theme),
                  StreamBuilder<BlocState<Podcast>>(
                      initialData: BlocEmptyState<Podcast>(),
                      stream: podcastBloc.details,
                      builder: (context, snapshot) {
                        final state = snapshot.data;

                        if (state is BlocErrorState) {
                          return SliverFillRemaining(
                            hasScrollBody: false,
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: <Widget>[
                                  const Icon(
                                    Icons.error_outline,
                                    size: 50,
                                  ),
                                  Text(
                                    L.of(context)!.no_podcast_details_message,
                                    style: theme.textTheme.bodyMedium,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        // The compact header is always displayed - the artwork
                        // and title are usually already known from the search
                        // result or subscription before the feed has finished
                        // loading.
                        return SliverToBoxAdapter(
                            child: PlaybackErrorListener(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              PodcastTitle(_resolvePodcast(state)),
                              if (state is BlocLoadingState)
                                const Padding(
                                  padding: EdgeInsets.all(24.0),
                                  child: Center(
                                    child: PlatformProgressIndicator(),
                                  ),
                                ),
                              const Divider(),
                            ],
                          ),
                        ));
                      }),
                  StreamBuilder<BlocState<Podcast>>(
                      initialData: BlocEmptyState<Podcast>(),
                      stream: podcastBloc.details,
                      builder: (context1, snapshot1) {
                        final state = snapshot1.data;

                        if (state is BlocPopulatedState<Podcast>) {
                          return StreamBuilder<List<Episode?>?>(
                              stream: podcastBloc.episodes,
                              builder: (context, snapshot) {
                                if (snapshot.hasData) {
                                  _visibleEpisodes = snapshot.data!.whereType<Episode>().toList();

                                  return snapshot.data!.isNotEmpty
                                      ? PodcastEpisodeList(
                                          episodes: snapshot.data!,
                                          play: true,
                                          download: true,
                                          selection: _selection,
                                        )
                                      : const SliverToBoxAdapter(child: NoEpisodesFound());
                                } else {
                                  return const SliverToBoxAdapter(
                                      child: SizedBox(
                                    height: 200,
                                    width: 200,
                                  ));
                                }
                              });
                        } else {
                          return const SliverToBoxAdapter(
                              child: SizedBox(
                            height: 200,
                            width: 200,
                          ));
                        }
                      }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The podcast details toolbar.
  ///
  /// The podcast title fades in once the user has scrolled past the compact
  /// header. While episodes are being selected the bar switches to the
  /// selection count with a close button and a select all action.
  Widget _buildPodcastAppBar(ThemeData theme) {
    final selecting = _selection.selecting;
    final allSelected = _visibleEpisodes.isNotEmpty && _selection.containsAll(_visibleEpisodes);
    final foregroundColour = theme.appBarTheme.foregroundColor!;

    return SliverAppBar(
      title: selecting
          ? AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                L.of(context)!.episodes_selected_count(_selection.count),
                key: ValueKey<int>(_selection.count),
                style: theme.textTheme.titleLarge?.copyWith(color: foregroundColour),
              ),
            )
          : AnimatedOpacity(
              opacity: toolbarCollapsed ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 500),
              child: Text(widget.podcast.title),
            ),
      leading: selecting
          ? _SelectionCloseButton(
              iconColour: foregroundColour,
              decorationColour: const Color(0x00000000),
              onPressed: _exitSelection,
            )
          : PlatformBackButton(
              iconColour: foregroundColour,
              decorationColour: const Color(0x00000000),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
      actions: selecting
          ? <Widget>[
              IconButton(
                icon: Icon(
                  allSelected ? Icons.deselect : Icons.select_all,
                  color: foregroundColour,
                ),
                tooltip: allSelected ? L.of(context)!.deselect_all_label : L.of(context)!.select_all_label,
                onPressed: () {
                  if (allSelected) {
                    _selection.selectNone();
                  } else {
                    _selection.selectAll(_visibleEpisodes);
                  }
                },
              ),
            ]
          : null,
      floating: false,
      pinned: true,
      snap: false,
    );
  }

  /// The bulk action bar shown under the episode list while selecting.
  Widget _buildSelectionActionBar(BuildContext context) {
    return SelectionActionBar(
      selection: _selection,
      onMarkPlayed: _handleBulkMarkPlayed,
      onMarkUnplayed: _handleBulkMarkUnplayed,
      onDownload: _handleBulkDownload,
      onQueue: _handleBulkQueue,
      onDeleteDownloads: _handleBulkDeleteDownloads,
    );
  }

  void _exitSelection() {
    _selection.clear();
  }

  void _handleBulkMarkPlayed() {
    final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);
    final changed = _selection.episodes.where((e) => !e.played).toList();

    if (changed.isEmpty) {
      return;
    }

    // Snapshot the current state before the bloc flips the episodes so the
    // change can be undone.
    final undoStates = [for (var e in changed) EpisodePlayedState(e, e.played, e.position)];

    podcastBloc.markEpisodesPlayed(changed);
    _exitSelection();

    scaffoldMessengerKey.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(L.of(context)!.episodes_marked_played_count(changed.length)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: L.of(context)!.undo_label,
          onPressed: () => podcastBloc.restoreEpisodePlayedState(undoStates),
        ),
      ));
  }

  void _handleBulkMarkUnplayed() {
    final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);
    final changed = _selection.episodes.where((e) => e.played).toList();

    if (changed.isEmpty) {
      return;
    }

    final undoStates = [for (var e in changed) EpisodePlayedState(e, e.played, e.position)];

    podcastBloc.markEpisodesUnplayed(changed);
    _exitSelection();

    scaffoldMessengerKey.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(L.of(context)!.episodes_marked_unplayed_count(changed.length)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: L.of(context)!.undo_label,
          onPressed: () => podcastBloc.restoreEpisodePlayedState(undoStates),
        ),
      ));
  }

  void _handleBulkDownload() {
    final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);
    final toDownload =
        _selection.episodes.where((e) => e.downloadState == DownloadState.none && !e.downloaded).toList();

    if (toDownload.isEmpty) {
      return;
    }

    for (var e in toDownload) {
      podcastBloc.downloadEpisode(e);
    }

    _exitSelection();

    scaffoldMessengerKey.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(L.of(context)!.episodes_downloading_count(toDownload.length)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
  }

  void _handleBulkQueue() {
    final queueBloc = Provider.of<QueueBloc>(context, listen: false);
    final selected = _selection.episodes;

    if (selected.isEmpty) {
      return;
    }

    // Episodes are queued in selection order.
    for (var e in selected) {
      queueBloc.queueEvent(QueueAddEvent(episode: e));
    }

    _exitSelection();

    scaffoldMessengerKey.currentState!
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(L.of(context)!.episodes_queued_count(selected.length)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
  }

  void _handleBulkDeleteDownloads() {
    final episodeBloc = Provider.of<EpisodeBloc>(context, listen: false);
    final downloaded = _selection.episodes.where((e) => e.downloaded).toList();

    if (downloaded.isEmpty) {
      return;
    }

    showPlatformDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) => BasicDialogAlert(
        title: Text(L.of(context)!.bulk_delete_downloads_title),
        content: Text(L.of(context)!.bulk_delete_downloads_confirmation),
        actions: <Widget>[
          BasicDialogAction(
            title: ActionText(
              L.of(context)!.cancel_button_label,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
            },
          ),
          BasicDialogAction(
            title: ActionText(
              L.of(context)!.delete_button_label,
            ),
            iosIsDefaultAction: true,
            iosIsDestructiveAction: true,
            onPressed: () {
              Navigator.pop(dialogContext);

              for (var e in downloaded) {
                episodeBloc.deleteDownload(e);
              }

              _exitSelection();

              scaffoldMessengerKey.currentState!
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: Text(L.of(context)!.episode_downloads_deleted_count(downloaded.length)),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 5),
                ));
            },
          ),
        ],
      ),
    );
  }
}

/// The close button shown in the app bar while episodes are being selected.
///
/// Styled like [PlatformBackButton] - a circular decoration behind an icon -
/// so it looks consistent with the back button beside it.
class _SelectionCloseButton extends StatelessWidget {
  final Color iconColour;
  final Color decorationColour;
  final VoidCallback onPressed;

  const _SelectionCloseButton({
    required this.iconColour,
    required this.decorationColour,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        child: Center(
          child: SizedBox(
            height: 48.0,
            width: 48.0,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Container(
                margin: const EdgeInsets.all(6.0),
                height: 48.0,
                width: 48.0,
                decoration: ShapeDecoration(
                  color: decorationColour,
                  shape: const CircleBorder(),
                ),
                child: Icon(
                  Icons.close,
                  size: 26.0,
                  color: iconColour,
                  semanticLabel: L.of(context)!.selection_mode_close_label,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the podcast artwork in the compact header.
///
/// The artwork is a [Hero] so it animates from the podcast tile in the
/// library, search results or discovery grid.
class _PodcastArtwork extends StatelessWidget {
  static const size = 96.0;

  final Podcast podcast;
  final PlaceholderBuilder? placeholderBuilder;

  const _PodcastArtwork({
    required this.podcast,
    required this.placeholderBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = podcast.imageUrl;

    return Hero(
      tag: '${podcast.imageUrl}:${podcast.link}',
      child: ExcludeSemantics(
        child: imageUrl == null || imageUrl.isEmpty
            ? Container(
                height: size,
                width: size,
                color: Theme.of(context).dividerColor,
              )
            : PodcastImage(
                key: Key('details${podcast.imageUrl}'),
                url: imageUrl,
                width: size,
                height: size,
                borderRadius: 12.0,
                placeholder: placeholderBuilder != null
                    ? placeholderBuilder?.builder()(context)
                    : const DelayedCircularProgressIndicator(),
                errorPlaceholder: placeholderBuilder != null
                    ? placeholderBuilder?.errorBuilder()(context)
                    : const Image(image: AssetImage('assets/images/anytime-placeholder-logo.png')),
              ),
      ),
    );
  }
}

/// Renders the compact podcast header - artwork, title, copyright,
/// description, follow/unfollow and overflow button.
///
/// If the episode description is fairly long, an overflow icon is also shown
/// and a portion of the episode description is shown. Tapping the overflow
/// icons allows the user to expand and collapse the text.
///
/// Description is rendered by [PodcastDescription].
/// Follow/Unfollow button rendered by [FollowButton].
class PodcastTitle extends StatefulWidget {
  final Podcast podcast;

  const PodcastTitle(this.podcast, {super.key});

  @override
  State<PodcastTitle> createState() => _PodcastTitleState();
}

class _PodcastTitleState extends State<PodcastTitle> with SingleTickerProviderStateMixin {
  final GlobalKey descriptionKey = GlobalKey();
  final maxHeight = 100.0;
  PodcastHtml? description;
  bool showOverflow = false;
  bool showEpisodeSearch = false;
  final StreamController<bool> isDescriptionExpandedStream = StreamController<bool>.broadcast();
  final _episodeSearchController = TextEditingController();
  final _searchFocus = FocusNode();

  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 200),
    vsync: this,
  );

  late final _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.fastOutSlowIn,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = Provider.of<SettingsBloc>(context, listen: false).currentSettings;
    final podcastBloc = Provider.of<PodcastBloc>(context, listen: false);
    final placeholderBuilder = PlaceholderBuilder.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 0.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Compact header: the artwork sits beside the title so the episode
          // list begins much higher up the screen than with the old poster
          // header.
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _PodcastArtwork(podcast: widget.podcast, placeholderBuilder: placeholderBuilder),
              Expanded(
                child: MergeSemantics(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.podcast.title,
                          style: theme.textTheme.titleLarge,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((widget.podcast.copyright ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              widget.podcast.copyright!,
                              style: theme.textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              StreamBuilder<bool>(
                  stream: isDescriptionExpandedStream.stream,
                  initialData: false,
                  builder: (context, snapshot) {
                    final expanded = snapshot.data!;
                    return ExcludeSemantics(
                      child: Visibility(
                        visible: showOverflow,
                        child: SizedBox(
                          height: 48.0,
                          width: 48.0,
                          child: expanded
                              ? TextButton(
                                  style: const ButtonStyle(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: Icon(
                                    Icons.expand_less,
                                    semanticLabel: L.of(context)!.semantics_collapse_podcast_description,
                                  ),
                                  onPressed: () {
                                    isDescriptionExpandedStream.add(false);
                                  },
                                )
                              : TextButton(
                                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                                  child: Icon(
                                    Icons.expand_more,
                                    semanticLabel: L.of(context)!.semantics_expand_podcast_description,
                                  ),
                                  onPressed: () {
                                    isDescriptionExpandedStream.add(true);
                                  },
                                ),
                        ),
                      ),
                    );
                  })
            ],
          ),
          PodcastDescription(
            key: descriptionKey,
            content: description,
            isDescriptionExpandedStream: isDescriptionExpandedStream,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8.0, right: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                FollowButton(widget.podcast),
                PodcastContextMenu(widget.podcast),
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (showEpisodeSearch) {
                        _controller.reverse();
                      } else {
                        _controller.forward();
                        _searchFocus.requestFocus();
                      }
                      showEpisodeSearch = !showEpisodeSearch;
                    });
                  },
                  icon: Icon(
                    Icons.search,
                    semanticLabel: L.of(context)!.search_episodes_label,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                SortButton(widget.podcast),
                FilterButton(widget.podcast),
                if (settings.showFunding) FundingMenu(widget.podcast.funding)
              ],
            ),
          ),
          SizeTransition(
            sizeFactor: _animation,
            child: Padding(
                padding: const EdgeInsets.all(7.0),
                child: TextField(
                    focusNode: _searchFocus,
                    controller: _episodeSearchController,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.all(0.0),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: Icon(
                          Icons.close,
                          semanticLabel: L.of(context)!.clear_search_button_label,
                        ),
                        onPressed: () {
                          _episodeSearchController.clear();
                          podcastBloc.podcastSearchEvent('');
                        },
                      ),
                      isDense: true,
                      filled: true,
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8.0)),
                        borderSide: BorderSide.none,
                        gapPadding: 0.0,
                      ),
                      hintText: L.of(context)!.search_episodes_label,
                    ),
                    onChanged: ((search) {
                      podcastBloc.podcastSearchEvent(search);
                    }),
                    onSubmitted: ((search) {
                      podcastBloc.podcastSearchEvent(search);
                    }),
                    onTapOutside: (event) => _searchFocus.unfocus())),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    _initDescription();

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _checkDescriptionOverflow();
    });
  }

  @override
  void didUpdateWidget(PodcastTitle oldWidget) {
    super.didUpdateWidget(oldWidget);

    // When the feed finishes loading we may receive richer podcast details
    // than the stub the user navigated here with - refresh the description.
    if (widget.podcast.description != oldWidget.podcast.description) {
      _initDescription();

      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
        _checkDescriptionOverflow();
      });
    }
  }

  void _initDescription() {
    description = PodcastHtml(
      key: ValueKey(widget.podcast.url),
      content: widget.podcast.description ?? '',
      fontSize: FontSize.medium,
      clipboard: false,
    );
  }

  void _checkDescriptionOverflow() {
    final descriptionContext = descriptionKey.currentContext;

    if (mounted && descriptionContext != null && descriptionContext.size != null) {
      setState(() {
        showOverflow = descriptionContext.size!.height == maxHeight;
      });
    }
  }

  @override
  void dispose() {
    isDescriptionExpandedStream.close();
    _episodeSearchController.dispose();
    _searchFocus.dispose();
    _controller.dispose();
    _animation.dispose();

    description = null;

    super.dispose();
  }
}

/// This class wraps the description in an expandable box.
///
/// This handles the common case whereby the description is very long and, without
/// this constraint, would require the use to always scroll before reaching the
/// podcast episodes.
///
/// TODO: Animate between the two states.
class PodcastDescription extends StatelessWidget {
  final PodcastHtml? content;
  final StreamController<bool>? isDescriptionExpandedStream;
  static const maxHeight = 100.0;
  static const padding = 4.0;

  const PodcastDescription({
    super.key,
    this.content,
    this.isDescriptionExpandedStream,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PodcastDescription.padding),
      child: StreamBuilder<bool>(
          stream: isDescriptionExpandedStream!.stream,
          initialData: false,
          builder: (context, snapshot) {
            final expanded = snapshot.data!;
            return AnimatedSize(
              duration: const Duration(milliseconds: 150),
              curve: Curves.fastOutSlowIn,
              alignment: Alignment.topCenter,
              child: Container(
                constraints: expanded
                    ? const BoxConstraints()
                    : BoxConstraints.loose(const Size(double.infinity, maxHeight - padding)),
                child: expanded
                    ? content
                    : ShaderMask(
                        shaderCallback: LinearGradient(
                          colors: [Colors.white, Colors.white.withAlpha(0)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0.9, 1],
                        ).createShader,
                        child: content),
              ),
            );
          }),
    );
  }
}

class NoEpisodesFound extends StatelessWidget {
  const NoEpisodesFound({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            L.of(context)!.episode_filter_no_episodes_title_label,
            style: theme.textTheme.titleLarge,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(64.0, 24.0, 64.0, 64.0),
            child: Text(
              L.of(context)!.episode_filter_no_episodes_title_description,
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class FollowButton extends StatelessWidget {
  final Podcast podcast;

  const FollowButton(this.podcast, {super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = Provider.of<PodcastBloc>(context);

    return StreamBuilder<BlocState<Podcast>>(
        stream: bloc.details,
        builder: (context, snapshot) {
          var ready = false;
          var subscribed = false;

          // To prevent jumpy UI, we always need to display the follow/unfollow button.
          // Display a disabled follow button until the full state it loaded.
          if (snapshot.hasData) {
            final state = snapshot.data;

            if (state is BlocPopulatedState<Podcast>) {
              ready = true;
              subscribed = state.results!.subscribed;
            }
          }
          return Semantics(
            liveRegion: true,
            child: subscribed
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.fromLTRB(10.0, 4.0, 10.0, 4.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    icon: const Icon(
                      Icons.delete_outline,
                    ),
                    label: Text(L.of(context)!.unsubscribe_label),
                    onPressed: ready
                        ? () {
                            showPlatformDialog<void>(
                              context: context,
                              useRootNavigator: false,
                              builder: (_) => BasicDialogAlert(
                                title: Text(L.of(context)!.unsubscribe_label),
                                content: Text(L.of(context)!.unsubscribe_message),
                                actions: <Widget>[
                                  BasicDialogAction(
                                    title: ActionText(
                                      L.of(context)!.cancel_button_label,
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context);
                                    },
                                  ),
                                  BasicDialogAction(
                                    title: ActionText(
                                      L.of(context)!.unsubscribe_button_label,
                                    ),
                                    iosIsDefaultAction: true,
                                    iosIsDestructiveAction: true,
                                    onPressed: () {
                                      bloc.podcastEvent(PodcastEvent.unsubscribe);

                                      Navigator.pop(context);
                                      Navigator.pop(context);
                                    },
                                  ),
                                ],
                              ),
                            );
                          }
                        : null,
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.fromLTRB(10.0, 4.0, 10.0, 4.0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                    ),
                    icon: const Icon(
                      Icons.add,
                    ),
                    label: Text(L.of(context)!.subscribe_label),
                    onPressed: ready
                        ? () {
                            bloc.podcastEvent(PodcastEvent.subscribe);
                          }
                        : null,
                  ),
          );
        });
  }
}

class FilterButton extends StatelessWidget {
  final Podcast podcast;

  const FilterButton(this.podcast, {super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = Provider.of<PodcastBloc>(context);

    return StreamBuilder<BlocState<Podcast>>(
        stream: bloc.details,
        builder: (context, snapshot) {
          Podcast? podcast;

          if (snapshot.hasData) {
            final state = snapshot.data;

            if (state is BlocPopulatedState<Podcast>) {
              podcast = state.results!;
            }
          }

          return EpisodeFilterSelectorWidget(
            podcast: podcast,
          );
        });
  }
}

class SortButton extends StatelessWidget {
  final Podcast podcast;

  const SortButton(this.podcast, {super.key});

  @override
  Widget build(BuildContext context) {
    final bloc = Provider.of<PodcastBloc>(context);

    return StreamBuilder<BlocState<Podcast>>(
        stream: bloc.details,
        builder: (context, snapshot) {
          Podcast? podcast;

          if (snapshot.hasData) {
            final state = snapshot.data;

            if (state is BlocPopulatedState<Podcast>) {
              podcast = state.results!;
            }
          }

          return EpisodeSortSelectorWidget(
            podcast: podcast,
          );
        });
  }
}
