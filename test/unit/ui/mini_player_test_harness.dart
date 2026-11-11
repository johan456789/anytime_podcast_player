// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/bloc/podcast/queue_bloc.dart';
import 'package:anytime/entities/episode.dart';
import 'package:anytime/entities/podcast.dart';
import 'package:anytime/entities/sleep.dart';
import 'package:anytime/entities/transcript.dart';
import 'package:anytime/state/queue_event_state.dart';
import 'package:anytime/state/transcript_state_event.dart';
import 'package:anytime/l10n/L.dart';
import 'package:anytime/services/audio/audio_player_service.dart';
import 'package:anytime/services/podcast/podcast_service.dart';
import 'package:anytime/ui/podcast/mini_player.dart';
import 'package:anytime/ui/podcast/now_playing_floating_player.dart';
import 'package:anytime/ui/podcast/transcript_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

export 'package:anytime/ui/podcast/mini_player.dart';
export 'package:anytime/ui/podcast/now_playing_floating_player.dart';
export 'package:anytime/ui/widgets/mini_player_progress_bar.dart';

/// Playback position used for the mini player fixtures: 08:36 into a 17:12
/// episode so the progress bar is exactly half full, mirroring the design
/// reference.
const Duration fixturePosition = Duration(minutes: 8, seconds: 36);
const Duration fixtureLength = Duration(minutes: 17, seconds: 12);

/// Minimal audio service: the mini players only read the playing state, the
/// now-playing episode and the play position streams. [seek] and [advance]
/// update the position stream so interactive tests can scrub and simulate
/// playback continuing underneath.
class MiniPlayerTestAudioPlayerService extends AudioPlayerService {
  final playingStateSubject = SyncValueStream<AudioState>();
  final episodeSubject = SyncValueStream<Episode?>();
  final positionSubject = SyncValueStream<PositionState>();
  final transcriptSubject = SyncValueStream<TranscriptState>();
  final queueStateSubject = SyncValueStream<QueueListState>.seeded(
    QueueListState(playing: null, queue: []),
  );

  /// Call counters so tests can assert which transport actions the UI
  /// triggered (e.g. that a playhead drag does not hit the rewind button).
  int playCalls = 0;
  int rewindCalls = 0;
  int fastForwardCalls = 0;
  int stopCalls = 0;

  MiniPlayerTestAudioPlayerService() {
    playingState = playingStateSubject;
    episodeEvent = episodeSubject;
    playPosition = positionSubject;
    transcriptEvent = transcriptSubject;
    queueState = queueStateSubject;
  }

  void emitPlayback({
    required Episode episode,
    Duration position = fixturePosition,
    Duration length = fixtureLength,
    AudioState state = AudioState.pausing,
  }) {
    playingStateSubject.add(state);
    episodeSubject.add(episode);
    positionSubject.add(_positionState(position, length, episode));
    emitTranscript(fixtureTranscript());
  }

  void emitTranscript(Transcript transcript) {
    transcriptSubject.add(TranscriptUpdateState(transcript: transcript));
  }

  /// Emits a playback position at [position] with the current length, the
  /// way the real audio service reports position updates.
  void emitPosition(Duration position) {
    final current = positionSubject.valueOrNull;

    if (current == null) {
      return;
    }

    positionSubject.add(_positionState(position, current.length, current.episode));
  }

  /// Moves playback forward, as the real audio service would while playing.
  void advance(Duration by) {
    final current = positionSubject.valueOrNull;

    if (current == null) {
      return;
    }

    positionSubject.add(_positionState(
      current.position + by,
      current.length,
      current.episode,
    ));
  }

  PositionState _positionState(Duration position, Duration length, Episode? episode) {
    final percentage = length > Duration.zero ? (position.inMilliseconds * 100 / length.inMilliseconds).round() : 0;

    return PositionState(
      position: position,
      length: length,
      percentage: percentage.clamp(0, 100),
      episode: episode,
    );
  }

  void disposeService() {
    playingStateSubject.close();
    episodeSubject.close();
    positionSubject.close();
    transcriptSubject.close();
    queueStateSubject.close();
  }

  @override
  Future<void> playEpisode({required Episode episode, bool resume = true}) async {}

  @override
  Future<void> playLatestEpisode({required Podcast podcast, bool resume = true}) async {}

  @override
  Future<void> playNextUnplayedEpisode({required Podcast podcast, bool resume = true}) async {}

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> pause() async {}

  @override
  Future<void> rewind() async {
    rewindCalls++;
  }

  @override
  Future<void> fastForward() async {
    fastForwardCalls++;
  }

  /// When true, seek requests are held instead of applied; the test lands
  /// them with [landHeldSeek]. This simulates the real audio service's seek
  /// latency so tests can emit stale pre-seek positions in that window.
  bool holdSeeks = false;
  PositionState? _heldSeek;

  /// Applies a seek previously held by [holdSeeks], the way the audio
  /// service reports the position once the seek lands.
  void landHeldSeek() {
    final held = _heldSeek;

    if (held != null) {
      _heldSeek = null;
      positionSubject.add(held);
    }
  }

  @override
  Future<void> seek({required int position}) async {
    final current = positionSubject.valueOrNull;

    if (current == null) {
      return;
    }

    final target = _positionState(
      Duration(seconds: position),
      current.length,
      current.episode,
    );

    if (holdSeeks) {
      _heldSeek = target;
      return;
    }

    positionSubject.add(target);
  }

  @override
  Future<Episode?> resume() async => null;

  @override
  Future<void> addUpNextLatestEpisode({required Podcast podcast}) async {}

  @override
  Future<void> addUpNextUnplayedEpisode({required Podcast podcast}) async {}

  @override
  Future<void> addUpNextEpisode(Episode episode) async {}

  @override
  Future<bool> removeUpNextEpisode(Episode episode) async => true;

  @override
  Future<bool> moveUpNextEpisode(Episode episode, int oldIndex, int newIndex) async => true;

  @override
  Future<void> clearUpNext() async {}

  @override
  Future<void> suspend() async {}

  @override
  Future<void> setPlaybackSpeed(double speed) async {}

  @override
  Future<void> trimSilence(bool trim) async {}

  @override
  Future<void> volumeBoost(bool boost) async {}

  /// Filters the current transcript the way the real service does, keeping
  /// captions whose body contains the search text.
  @override
  Future<void> searchTranscript(String search) async {
    final current = transcriptSubject.valueOrNull?.transcript;

    if (current == null) {
      return;
    }

    final lower = search.toLowerCase();
    final filtered =
        current.subtitles.where((s) => (s.data ?? '').toLowerCase().contains(lower)).toList();

    transcriptSubject.add(TranscriptUpdateState(
      transcript: Transcript(subtitles: filtered, filtered: true),
    ));
  }

  @override
  Future<void> clearTranscript() async {
    emitTranscript(fixtureTranscript());
  }

  @override
  void sleep(Sleep sleep) {}
}

/// Deterministic transcript covering the whole episode with contiguous lines
/// (no silence gaps): every caption simply states its own timecode range.
Transcript fixtureTranscript() {
  const lineSeconds = 15;
  final lineCount = fixtureLength.inSeconds ~/ lineSeconds;

  String twoDigits(int n) => n >= 10 ? '$n' : '0$n';
  String format(Duration d) => '${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds % 60)}';

  final subtitles = <Subtitle>[];

  for (var i = 0; i < lineCount; i++) {
    final start = Duration(seconds: i * lineSeconds);
    final displayEnd = i + 1 < lineCount ? Duration(seconds: (i + 1) * lineSeconds) : fixtureLength;

    subtitles.add(Subtitle(
      index: i,
      start: start,
      // The last line's matching window runs past the episode length so that
      // a scrub to the very end (position == length) still matches it.
      end: displayEnd + const Duration(seconds: lineSeconds),
      data: 'timecode ${format(start)} - ${format(displayEnd)}',
    ));
  }

  return Transcript(subtitles: subtitles);
}

Episode fixtureEpisode() => Episode(
      guid: 'complete-spanish-34',
      podcast: 'Language Transfer',
      title: 'Complete Spanish 34',
      author: 'Language Transfer',
      // Fails fast in the test environment; the players fall back to the
      // bundled placeholder artwork.
      imageUrl: 'https://localhost/cover.jpg',
      duration: fixtureLength.inSeconds,
    )..transcript = fixtureTranscript();

/// Minimal stand-in for [PodcastService]; the transcript scene only needs a
/// [QueueBloc] to exist, and its queue stream comes from the audio service.
class MiniPlayerTestPodcastService implements PodcastService {
  @override
  Future<void> saveQueue(List<Episode> episodes) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Loads the bundled Montserrat faces and the Material icon font so screenshots
/// show real glyphs instead of the test font blocks.
Future<void> loadAppFonts() async {
  final fontLoader = FontLoader('MontserratMedium')
    ..addFont(rootBundle.load('assets/fonts/Montserrat-Medium.otf'))
    ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.otf'));
  await fontLoader.load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];

  if (flutterRoot != null) {
    final iconFont = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');

    if (iconFont.existsSync()) {
      final iconFontLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(iconFont.readAsBytesSync().buffer.asByteData()));
      await iconFontLoader.load();
    }
  }
}

ThemeData themedForShots(ThemeData theme) => theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: 'MontserratMedium'),
      primaryTextTheme: theme.primaryTextTheme.apply(fontFamily: 'MontserratMedium'),
    );

/// The mini player content row, mock library list rows and the tabbed sheet
/// below the floating player are intentionally simple stand-ins; what matters
/// is that the players themselves render exactly as they do in the app.
Widget mainScreenScene(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  final boxColor = dark ? const Color(0xff333333) : const Color(0xffe0e0e0);
  final barColor = dark ? const Color(0xff262626) : const Color(0xffefefef);
  final l = L.of(context)!;

  // A flat strip stands in for the bottom navigation bar; a real
  // BottomNavigationBar's elevation shadow renders as a solid band over the
  // mini player in the test rasteriser and would cover the progress bar.
  Widget navItem(IconData icon, String label, bool selected) {
    final color = selected ? theme.iconTheme.color : theme.hintColor;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 24.0),
        Text(label, style: theme.textTheme.bodySmall!.copyWith(color: color, fontSize: 11.0)),
      ],
    );
  }

  return Scaffold(
    backgroundColor: theme.scaffoldBackgroundColor,
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12.0),
            children: [
              for (var i = 0; i < 8; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: boxColor, borderRadius: BorderRadius.circular(6.0)),
                      ),
                      const SizedBox(width: 12.0),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 12, width: 200, decoration: BoxDecoration(color: barColor)),
                            const SizedBox(height: 8.0),
                            Container(height: 10, width: 120, decoration: BoxDecoration(color: barColor)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const MiniPlayer(),
      ],
    ),
    bottomNavigationBar: Container(
      height: 56.0,
      color: theme.bottomAppBarTheme.color,
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          navItem(Icons.library_music, l.library, true),
          navItem(Icons.explore, l.discover, false),
          navItem(Icons.download, l.downloads, false),
        ],
      ),
    ),
  );
}

Widget nowPlayingScene(BuildContext context) {
  final theme = Theme.of(context);
  final l = L.of(context)!;

  return Scaffold(
    backgroundColor: theme.scaffoldBackgroundColor,
    body: Column(
      children: [
        const FloatingPlayer(),
        Expanded(
          child: Container(
            color: theme.secondaryHeaderColor,
            child: DefaultTabController(
              initialIndex: 1,
              length: 3,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2.0)),
                    ),
                  ),
                  TabBar(
                    automaticIndicatorColorAdjustment: false,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicatorColor: theme.colorScheme.secondary,
                    labelColor: theme.textTheme.bodyLarge!.color,
                    unselectedLabelColor: theme.disabledColor,
                    tabs: [
                      Tab(child: Text(l.up_next_queue_label.toUpperCase(), style: theme.textTheme.labelLarge)),
                      Tab(child: Text(l.transcript_label.toUpperCase(), style: theme.textTheme.labelLarge)),
                      Tab(child: Text(l.ask_ai_label.toUpperCase(), style: theme.textTheme.labelLarge)),
                    ],
                  ),
                  const Expanded(
                    child: TranscriptView(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Pumps a mini player scene at a phone size (390x844 logical, 3x) with the
/// app localisations and font-applied theme in place.
Future<void> pumpScene(
  WidgetTester tester, {
  required AudioBloc audioBloc,
  required ThemeData theme,
  required Widget Function(BuildContext) sceneBuilder,
  VoidCallback? onMounted,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final queueBloc = QueueBloc(
    audioPlayerService: audioBloc.audioPlayerService,
    podcastService: MiniPlayerTestPodcastService(),
  );
  addTearDown(queueBloc.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<AudioBloc>.value(value: audioBloc),
        Provider<QueueBloc>.value(value: queueBloc),
      ],
      child: MaterialApp(
        theme: themedForShots(theme),
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
          child: Builder(builder: sceneBuilder),
        ),
      ),
    ),
  );

  // Emit playback state once the tree is mounted so listeners that need the
  // widget tree attached (e.g. the transcript list) receive it.
  if (onMounted != null) {
    onMounted();
    await tester.pump();
  }

  // QueueBloc persists the queue through a 2 second debounce started in its
  // constructor; pump past it so no timer is left pending at the end of the
  // test.
  await tester.pump(const Duration(seconds: 2));

  // A few fixed pumps so the artwork cross-fade and streams settle without
  // waiting on the (blocked) network client, then a bare pump to flush any
  // pending paint before the boundary is captured.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

/// Captures the current [RepaintBoundary] frame as PNG bytes. Pumps one
/// extra frame first so anything scheduled around the last event (e.g. a
/// pending seek confirmation) has rendered before the capture.
Future<Uint8List> captureBoundaryPng(WidgetTester tester) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('shot-boundary')));
  final bytes = await tester.binding.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.0);

    return image.toByteData(format: ui.ImageByteFormat.png);
  });

  expect(bytes, isNotNull);

  return bytes!.buffer.asUint8List();
}

/// Captures the current frame and writes it to [path], creating parent
/// directories as needed.
Future<void> captureTo(WidgetTester tester, String path) async {
  final bytes = await captureBoundaryPng(tester);

  File(path).createSync(recursive: true);
  File(path).writeAsBytesSync(bytes);
}

/// A single-value stream with synchronous delivery, for test fakes.
///
/// rxdart's seeded [BehaviorSubject] delivers every event through an async
/// transformer regardless of its `sync` flag, which makes widget-test
/// delivery depend on which zone the subject was created in. Tests emit
/// events and pump a single frame, so delivery must be deterministic:
/// listeners receive the value within the same call that emits it, and a
/// late subscriber receives the current value immediately.
class SyncValueStream<T> extends Stream<T> implements ValueStream<T> {
  final StreamController<T> _controller = StreamController<T>.broadcast(sync: true);

  T? _current;
  bool _hasEvent = false;

  SyncValueStream();

  SyncValueStream.seeded(T value) {
    _current = value;
    _hasEvent = true;
  }

  Object? _error;
  StackTrace? _stackTrace;

  void add(T event) {
    _current = event;
    _hasEvent = true;
    _controller.add(event);
  }

  Future<void> close() => _controller.close();

  @override
  T? get valueOrNull => _current;

  @override
  T get value => _current as T;

  @override
  bool get hasValue => _current != null;

  @override
  Object? get errorOrNull => _error;

  @override
  Object get error => _error!;

  @override
  bool get hasError => _error != null;

  @override
  StackTrace? get stackTrace => _stackTrace;

  @override
  StreamNotification<T>? get lastEventOrNull => _hasEvent ? DataNotification<T>(_current as T) : null;

  @override
  bool get isBroadcast => true;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription =
        _controller.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

    // Late subscribers get the current value, like a seeded subject would.
    if (_hasEvent) {
      onData?.call(_current as T);
    }

    return subscription;
  }
}
