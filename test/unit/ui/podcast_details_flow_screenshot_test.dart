// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/bloc/podcast/episode_bloc.dart';
import 'package:anytime/bloc/podcast/podcast_bloc.dart';
import 'package:anytime/bloc/podcast/queue_bloc.dart';
import 'package:anytime/bloc/settings/settings_bloc.dart';
import 'package:anytime/bloc/ui/pager_bloc.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/ui/anytime_podcast_app.dart' show TitleWidget;
import 'package:anytime/ui/library/library.dart';
import 'package:anytime/ui/podcast/mini_player.dart';
import 'package:anytime/ui/themes.dart';
import 'package:anytime/ui/widgets/podcast_grid_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'mini_player_test_harness.dart' show fixtureEpisode, loadAppFonts, themedForShots;
import 'podcast_details_test_harness.dart'
    show
        FakeDownloadService,
        FakeNotificationService,
        FakePodcastService,
        FakeSettingsService,
        PodcastDetailsTestAudioPlayerService,
        captureRootTo,
        fixtureEpisodes,
        fixturePodcast;

/// The file name tag comes from --dart-define=SHOT_TAG=<tag> and defaults to
/// 'after'; pass 'before' when capturing the pre-change baseline.
const String shotTag = String.fromEnvironment('SHOT_TAG', defaultValue: 'after');

/// Captures the common browsing flow: the library with something playing,
/// then the podcast details opened from a library tile.
///
/// The home scene mirrors the real [AnytimeHomePage] layout - app bar,
/// library fragment, mini player above the bottom navigation bar - so the
/// captures show what the user sees before and after opening a podcast.
/// The page-level assertions only hold for the redesigned details page
/// (player and bottom bar visible), so they are keyed on [shotTag].
void main() {
  testWidgets('library → podcast details flow, dark theme (screenshot)', (tester) async {
    await loadAppFonts();

    // The app bar title uses the regular face, which the shared font loader
    // does not cover.
    final regularFontLoader = FontLoader('MontserratRegular')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Regular.otf'));
    await regularFontLoader.load();

    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final podcast = fixturePodcast(fixtureEpisodes(count: 10));
    final podcastService = FakePodcastService(podcast);
    final audioPlayerService = PodcastDetailsTestAudioPlayerService();
    final audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
    // Grid library layout, as in the user's setup.
    final settingsService = FakeSettingsService()..layoutMode = 1;
    final podcastBloc = PodcastBloc(
      podcastService: podcastService,
      audioPlayerService: audioPlayerService,
      downloadService: FakeDownloadService(),
      notificationService: FakeNotificationService(),
      settingsService: settingsService,
    );
    final episodeBloc = EpisodeBloc(podcastService: podcastService, audioPlayerService: audioPlayerService);
    final queueBloc = QueueBloc(audioPlayerService: audioPlayerService, podcastService: podcastService);
    final settingsBloc = SettingsBloc(
      settingsService: settingsService,
      notificationService: FakeNotificationService(),
    );
    final pagerBloc = PagerBloc();

    addTearDown(() {
      podcastBloc.dispose();
      episodeBloc.dispose();
      queueBloc.dispose();
      settingsBloc.dispose();
      audioBloc.dispose();
      audioPlayerService.disposeService();
      pagerBloc.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PodcastBloc>.value(value: podcastBloc),
          Provider<EpisodeBloc>.value(value: episodeBloc),
          Provider<QueueBloc>.value(value: queueBloc),
          Provider<AudioBloc>.value(value: audioBloc),
          Provider<SettingsBloc>.value(value: settingsBloc),
          Provider<PagerBloc>.value(value: pagerBloc),
        ],
        child: RepaintBoundary(
          key: const Key('root-shot-boundary'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            // Apply the bundled face to the text theme so text renders with
            // real glyphs instead of the test font blocks.
            theme: themedForShots(Themes.darkTheme().themeData),
            localizationsDelegates: const [
              AnytimeLocalisationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en'),
            ],
            home: const RepaintBoundary(
              key: Key('shot-boundary'),
              child: _FlowHomePage(),
            ),
          ),
        ),
      ),
    );

    // Something is playing: the mini player shows above the bottom bar.
    audioPlayerService.emitPlayback(episode: fixtureEpisode());

    // Settle the library load and the artwork fallbacks.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.byType(PodcastGridTile), findsWidgets);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(find.text('Complete Spanish 34'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await captureRootTo(tester, 'demo/screenshots/podcast-flow-$shotTag-1-library-dark.png');

    /// Open the podcast from the library grid.
    await tester.tap(find.byType(PodcastGridTile).first);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Night Shift Radio'), findsWidgets);

    // The pre-change page parks the mini player on the offstage home route,
    // where the failing test-environment artwork request surfaces as a
    // benign StateError; the redesigned page has no such error.
    if (shotTag == 'after') {
      expect(tester.takeException(), isNull);
    } else {
      tester.takeException();
    }

    // Only the redesigned details page keeps the player and the bottom bar
    // visible; the pre-change page covered them with a full-screen route.
    if (shotTag == 'after') {
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Complete Spanish 34'), findsOneWidget);
      expect(find.text('Library'), findsOneWidget);
    } else {
      expect(find.byType(MiniPlayer), findsNothing);
    }

    await captureRootTo(tester, 'demo/screenshots/podcast-flow-$shotTag-2-details-dark.png');

    /// Scroll the episode list; the header collapses and, on the redesigned
    /// page, the title fades into the toolbar while the player and bar stay.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Night Shift Radio'), findsWidgets);

    if (shotTag == 'after') {
      expect(tester.takeException(), isNull);
    } else {
      tester.takeException();
    }

    await captureRootTo(tester, 'demo/screenshots/podcast-flow-$shotTag-3-details-scrolled-dark.png');

    // Pump past the queue save debounce so no timer is left pending.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
  });
}

/// A faithful stand-in for the app's home page: app bar, the library
/// fragment, the mini player and the bottom navigation bar. Uses the
/// original inline [BottomNavigationBar] so the test compiles against the
/// pre-change source as well when capturing 'before' shots.
class _FlowHomePage extends StatelessWidget {
  const _FlowHomePage();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pager = Provider.of<PagerBloc>(context);
    final backgroundColour = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: backgroundColour,
      body: Column(
        children: <Widget>[
          Expanded(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverAppBar(
                  title: TitleWidget(),
                  backgroundColor: backgroundColour,
                  pinned: true,
                  actions: const <Widget>[
                    IconButton(
                      icon: Icon(Icons.search),
                      onPressed: null,
                    ),
                  ],
                ),
                StreamBuilder<int>(
                  stream: pager.currentPage,
                  initialData: 0,
                  builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
                    return snapshot.data == 0 ? const Library() : const SizedBox();
                  },
                ),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: StreamBuilder<int>(
        stream: pager.currentPage,
        initialData: 0,
        builder: (BuildContext context, AsyncSnapshot<int> snapshot) {
          final index = snapshot.data ?? 0;

          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: theme.bottomAppBarTheme.color,
            selectedIconTheme: theme.iconTheme,
            selectedItemColor: theme.iconTheme.color,
            selectedFontSize: 11.0,
            unselectedFontSize: 11.0,
            unselectedItemColor: HSLColor.fromColor(theme.bottomAppBarTheme.color!).withLightness(0.8).toColor(),
            currentIndex: index,
            onTap: pager.changePage,
            items: <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: index == 0 ? const Icon(Icons.library_music) : const Icon(Icons.library_music_outlined),
                label: L.of(context)!.library,
              ),
              BottomNavigationBarItem(
                icon: index == 1 ? const Icon(Icons.explore) : const Icon(Icons.explore_outlined),
                label: L.of(context)!.discover,
              ),
              BottomNavigationBarItem(
                icon: index == 2 ? const Icon(Icons.download) : const Icon(Icons.download_outlined),
                label: L.of(context)!.downloads,
              ),
            ],
          );
        },
      ),
    );
  }
}
