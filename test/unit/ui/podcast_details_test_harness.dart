// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/bloc/podcast/episode_bloc.dart';
import 'package:anytime/bloc/podcast/podcast_bloc.dart';
import 'package:anytime/bloc/podcast/queue_bloc.dart';
import 'package:anytime/bloc/settings/settings_bloc.dart';
import 'package:anytime/bloc/ui/pager_bloc.dart';
import 'package:anytime/entities/app_settings.dart';
import 'package:anytime/entities/downloadable.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/services/download/download_service.dart';
import 'package:anytime/services/notifications/notification_service.dart';
import 'package:anytime/services/podcast/podcast_service.dart';
import 'package:anytime/services/settings/settings_service.dart';
import 'package:anytime/state/episode_state.dart';
import 'package:anytime/state/library_state.dart';
import 'package:anytime/ui/podcast/podcast_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

import 'mini_player_test_harness.dart' show MiniPlayerTestAudioPlayerService, SyncValueStream, themedForShots;

export 'mini_player_test_harness.dart' show loadAppFonts, themedForShots, captureTo;

/// Captures the whole rendered view, including navigator overlays such as
/// dialogs, which sit outside the page-level [RepaintBoundary].
Future<void> captureRootTo(WidgetTester tester, String path) async {
  await tester.pump();

  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('root-shot-boundary'), skipOffstage: false));
  final bytes = await tester.binding.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);

    return image.toByteData(format: ui.ImageByteFormat.png);
  });

  expect(bytes, isNotNull);

  File(path).createSync(recursive: true);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// A subscribed fixture podcast; the id makes [Podcast.subscribed] true.
Podcast fixturePodcast(List<Episode> episodes) => Podcast(
      guid: 'night-shift-radio',
      url: 'https://example.com/night-shift.rss',
      link: 'https://example.com/night-shift',
      title: 'Night Shift Radio',
      description: 'Late-night conversations about everything that happens after dark.',
      imageUrl: 'https://localhost/banner.jpg',
      thumbImageUrl: 'https://localhost/banner.jpg',
      copyright: '© 2026 Night Shift Radio',
      id: 1,
      subscribedDate: DateTime(2025, 1, 1),
      episodes: episodes,
    );

/// A realistic mixed-state feed: the latest episodes are fresh, a couple are
/// in progress, two are downloaded and a few are already played.
List<Episode> fixtureEpisodes({required int count}) {
  final titles = [
    'The Long Dark',
    'Static Bloom',
    'Embers',
    'Ferry Tales',
    'Midnight Screening',
    'Night Lines',
    'The Quiet Quarter',
    'Neon Rain',
    'Dead Air',
    'First Light',
  ];

  return List.generate(count, (i) {
    final played = i == 4 || i == 5;
    final downloaded = i == 3 || i == 5;

    return Episode(
      guid: 'night-shift-${i + 1}',
      pguid: 'night-shift-radio',
      podcast: 'Night Shift Radio',
      title: titles[i % titles.length],
      description: 'A late-night conversation recorded after the studio lights went out.',
      imageUrl: 'https://localhost/art.jpg',
      thumbImageUrl: 'https://localhost/art.jpg',
      publicationDate: DateTime.now().subtract(Duration(days: i, hours: 3)),
      contentUrl: 'https://localhost/ep.mp3',
      duration: 3271,
      length: downloaded ? 63460000 : 0,
      position: i == 2 ? 612000 : 0,
      played: played,
      downloadState: downloaded ? DownloadState.downloaded : DownloadState.none,
      downloadPercentage: downloaded ? 100 : 0,
      filepath: downloaded ? '/downloads/night-shift-${i + 1}.mp3' : null,
    );
  });
}

/// In-memory [PodcastService]: the podcast details page only needs feed
/// loading, played state persistence and download deletion, all of which
/// mutate the fixture and push episode updates the same way the real
/// repository does.
class FakePodcastService implements PodcastService {
  final BehaviorSubject<EpisodeState> _episodeSubject = BehaviorSubject<EpisodeState>();
  final BehaviorSubject<Podcast?> _podcastSubject = BehaviorSubject<Podcast?>();

  FakePodcastService(this.podcast);

  final Podcast podcast;

  @override
  Future<Podcast?> loadPodcast({
    required Podcast podcast,
    bool highlightNewEpisodes = false,
    bool ignoreCache = false,
  }) async =>
      this.podcast;

  @override
  Future<Podcast?> loadPodcastById({required int id}) async => podcast;

  @override
  Future<List<Episode>> loadDownloads() async => podcast.episodes.where((e) => e.downloaded).toList();

  @override
  Future<List<Episode>> loadEpisodes() async => podcast.episodes;

  @override
  Future<List<Podcast>> subscriptions() async => <Podcast>[podcast];

  @override
  Future<Podcast?> save(Podcast podcast, {bool withEpisodes = true}) async => podcast;

  @override
  Future<Episode> saveEpisode(Episode episode) async {
    _episodeSubject.add(EpisodeUpdateState(episode));

    return episode;
  }

  @override
  Future<List<Episode>> saveEpisodes(List<Episode> episodes) async {
    for (var e in episodes) {
      _episodeSubject.add(EpisodeUpdateState(e));
    }

    return episodes;
  }

  @override
  Future<void> toggleEpisodePlayed(Episode episode) async {
    episode
      ..played = !episode.played
      ..position = 0;

    _episodeSubject.add(EpisodeUpdateState(episode));
  }

  @override
  Future<void> deleteDownload(Episode episode) async {
    episode
      ..filepath = null
      ..filename = null
      ..downloadPercentage = 0
      ..downloadState = DownloadState.none;

    _episodeSubject.add(EpisodeUpdateState(episode));
  }

  @override
  Future<void> refreshFeeds({bool manual = false, background = false}) async {}

  @override
  Future<void> saveQueue(List<Episode> episodes) async {}

  @override
  Stream<Podcast?> get podcastListener => _podcastSubject.stream;

  @override
  Stream<EpisodeState> get episodeListener => _episodeSubject.stream;

  @override
  Stream<LibraryState> get libraryListener => const Stream<LibraryState>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The mini player fake audio service plus the playback error stream needed
/// by [PlaybackErrorListener].
class PodcastDetailsTestAudioPlayerService extends MiniPlayerTestAudioPlayerService {
  final errorSubject = SyncValueStream<int>();

  PodcastDetailsTestAudioPlayerService() {
    playbackError = errorSubject;
  }

  @override
  void disposeService() {
    super.disposeService();

    errorSubject.close();
  }
}

class FakeDownloadService implements DownloadService {
  @override
  Future<bool> downloadEpisode(Episode episode) async => true;

  @override
  Future<Episode?> findEpisodeByTaskId(String taskId) async => null;

  @override
  void dispose() {}
}

class FakeNotificationService implements NotificationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(false);
}

class FakeSettingsService implements SettingsService {
  @override
  AppSettings? settings = AppSettings.sensibleDefaults();

  @override
  String theme = 'System';

  @override
  bool markDeletedEpisodesAsPlayed = false;

  @override
  bool deleteDownloadedPlayedEpisodes = false;

  @override
  bool storeDownloadsSDCard = false;

  @override
  double playbackSpeed = 1.0;

  @override
  String searchProvider = 'itunes';

  @override
  bool externalLinkConsent = true;

  @override
  bool autoOpenNowPlaying = false;

  @override
  bool showFunding = false;

  @override
  int autoUpdateEpisodePeriod = 0;

  @override
  bool trimSilence = false;

  @override
  bool volumeBoost = false;

  @override
  int layoutMode = 0;

  @override
  String layoutOrder = 'asc';

  @override
  bool layoutHighlight = true;

  @override
  bool layoutCount = true;

  @override
  bool autoPlay = false;

  @override
  bool backgroundUpdate = false;

  @override
  bool backgroundUpdateMobileData = false;

  @override
  bool updateNotification = false;

  @override
  String aiChatEndpoint = '';

  @override
  String aiChatApiKey = '';

  @override
  String aiChatModel = '';

  @override
  DateTime lastFeedRefresh = DateTime(2025);

  @override
  Stream<String> get settingsListener => const Stream<String>.empty();
}

/// Pumps the full [PodcastDetails] page with the app's theme, localisations
/// and blocs wired to the in-memory services, and settles the initial feed
/// load so the episode list is rendered.
///
/// [onReady] runs once the page has been pumped but before the load is
/// settled; use it to emit playback state so the mini player renders.
Future<void> pumpPodcastDetails(
  WidgetTester tester, {
  required ThemeData theme,
  required Podcast podcast,
  void Function(PodcastDetailsTestAudioPlayerService audioPlayerService)? onReady,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final podcastService = FakePodcastService(podcast);
  final audioPlayerService = PodcastDetailsTestAudioPlayerService();
  final audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
  final podcastBloc = PodcastBloc(
    podcastService: podcastService,
    audioPlayerService: audioPlayerService,
    downloadService: FakeDownloadService(),
    notificationService: FakeNotificationService(),
    settingsService: FakeSettingsService(),
  );
  final episodeBloc = EpisodeBloc(podcastService: podcastService, audioPlayerService: audioPlayerService);
  final queueBloc = QueueBloc(audioPlayerService: audioPlayerService, podcastService: podcastService);
  final settingsBloc = SettingsBloc(
    settingsService: FakeSettingsService(),
    notificationService: FakeNotificationService(),
  );
  // The embedded bottom navigation bar reads the pager for the selected tab.
  final pagerBloc = PagerBloc();

  addTearDown(() {
    podcastBloc.dispose();
    episodeBloc.dispose();
    queueBloc.dispose();
    settingsBloc.dispose();
    audioBloc.dispose();
    audioPlayerService.disposeService();
    pagerBloc.dispose();
    podcastService._episodeSubject.close();
    podcastService._podcastSubject.close();
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
          // The Material 2 snack bar resolves its content style from a fresh
          // default ThemeData, which drops the bundled font; mirror its
          // inverted-brightness style but with the app font applied so snack
          // bars render like the rest of the app.
          theme: themedForShots(theme).copyWith(
            snackBarTheme: themedForShots(theme).snackBarTheme.copyWith(
                  contentTextStyle: ThemeData(
                    useMaterial3: false,
                    brightness: theme.brightness == Brightness.light ? Brightness.dark : Brightness.light,
                  ).textTheme.titleMedium?.copyWith(fontFamily: 'MontserratMedium'),
                ),
          ),
          localizationsDelegates: const [
            AnytimeLocalisationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
          ],
          home: RepaintBoundary(
            key: const Key('shot-boundary'),
            child: PodcastDetails(podcast, podcastBloc),
          ),
        ),
      ),
    ),
  );

  onReady?.call(audioPlayerService);

  // Settle the feed load: loading state, populated podcast and episode list.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));

  // Let the artwork requests resolve (they fail without a network in the
  // test environment); runAsync allows the real network stack to progress
  // outside the test clock so captures show the fallback artwork everywhere
  // instead of a half-loaded state.
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
  });

  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();

  // Pump past the queue save debounce so no timer is left pending.
  await tester.pump(const Duration(seconds: 2));
  await tester.pump();
}
