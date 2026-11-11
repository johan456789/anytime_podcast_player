// Copyright 2020 Ben Hills and the project contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:anytime/bloc/podcast/audio_bloc.dart';
import 'package:anytime/ui/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mini_player_test_harness.dart';

/// Behaviour tests for the mini player's draggable progress bar: the drag
/// reports the scrubbed position on the audio bloc (which the transcript
/// follows live), the bubble shows the dragged timecode, and releasing the
/// drag applies the seek. Taps in the bar's touch target must still reach
/// the surfaces underneath; only horizontal drags are claimed.
///
/// Note on tap observability: the transport buttons and the mini player's
/// own tap handler resolve through streams created outside the test's fake
/// async zone (the bloc's asyncMap, the now-playing sheet behind an
/// awaited subscription cancel), so their effects cannot be observed from a
/// widget test. Tap delivery through the bar is verified two ways: the
/// gesture arena isolation test below (the same overlay structure as the
/// player's bottom edge) and the real-scene assertion that a tap never
/// produces a scrub event.
void main() {
  late AudioBloc audioBloc;
  late MiniPlayerTestAudioPlayerService audioPlayerService;

  setUp(() {
    audioPlayerService = MiniPlayerTestAudioPlayerService();
    audioBloc = AudioBloc(audioPlayerService: audioPlayerService);
  });

  tearDown(() {
    audioBloc.dispose();
    audioPlayerService.disposeService();
  });

  Future<void> pumpPlayer(WidgetTester tester) async {
    await pumpScene(tester, audioBloc: audioBloc, theme: Themes.darkTheme().themeData, sceneBuilder: (context) {
      return mainScreenScene(context);
    }, onMounted: () {
      audioPlayerService.emitPlayback(episode: fixtureEpisode());
    });
  }

  /// The width of the mini player's progress strip in logical pixels.
  double stripWidth(WidgetTester tester) => tester.getSize(find.byType(MiniPlayerProgressBar)).width;

  testWidgets('dragging the playhead reports the scrub position, shows the bubble and seeks on release',
      (tester) async {
    final scrubEvents = <Duration?>[];
    audioBloc.scrubPosition.listen(scrubEvents.add);

    await pumpPlayer(tester);

    // The fixture is 08:36 into a 17:12 episode: the playhead sits at 50%.
    final playhead = tester.getCenter(find.byKey(const Key('miniplayer-playhead')));
    final width = stripWidth(tester);

    final gesture = await tester.startGesture(playhead);
    await gesture.moveBy(Offset(width * 0.25, 0));
    await tester.pump();

    // 75% of 17:12 is 12:54 (774s, exactly 774000ms for this fixture).
    expect(find.byKey(const Key('miniplayer-progress-bubble')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('miniplayer-progress-bubble'))).data,
      '12:54',
    );
    expect(scrubEvents.last, const Duration(milliseconds: 774000));
    // A drag on the bar must not be interpreted as a swipe-to-dismiss.
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(audioPlayerService.stopCalls, 0);

    await gesture.up();
    await tester.pump();

    // Release: the bubble is gone and the seek has been applied.
    expect(find.byKey(const Key('miniplayer-progress-bubble')), findsNothing);
    expect(audioPlayerService.positionSubject.valueOrNull!.position, const Duration(seconds: 774));
    expect(scrubEvents.last, isNull);
  });

  testWidgets('a tap inside the bar touch target does not start a scrub', (tester) async {
    final scrubEvents = <Duration?>[];
    audioBloc.scrubPosition.listen(scrubEvents.add);

    await pumpPlayer(tester);

    final playerRect = tester.getRect(find.byType(MiniPlayer));

    await tester.tapAt(Offset(140.0, playerRect.bottom - 10));
    await tester.pump();

    // The bar only claims horizontal drags: a tap must not move the
    // playhead or report a scrubbed position.
    expect(scrubEvents, [isNull]);
    expect(find.byKey(const Key('miniplayer-progress-bubble')), findsNothing);
    expect(audioPlayerService.positionSubject.valueOrNull!.position, fixturePosition);
  });

  testWidgets('a horizontal drag inside the bar touch target does not turn into a tap underneath',
      (tester) async {
    await pumpPlayer(tester);

    final rewind = tester.getCenter(find.byIcon(Icons.replay_10));
    final playerRect = tester.getRect(find.byType(MiniPlayer));
    final width = stripWidth(tester);

    final gesture = await tester.startGesture(Offset(rewind.dx, playerRect.bottom - 10));
    await gesture.moveBy(Offset(width * 0.1, 0));
    await gesture.up();
    await tester.pump();

    // The scrub moved the position away from where playback was.
    expect(
      audioPlayerService.positionSubject.valueOrNull!.position,
      isNot(fixturePosition),
    );
  });

  testWidgets('the bar exposes slider semantics with the current timecode', (tester) async {
    await pumpPlayer(tester);

    final semantics = tester.getSemantics(find.byType(MiniPlayerProgressBar));

    expect(semantics.flagsCollection.isSlider, isTrue);
    // 08:36 into a 17:12 episode, as the fixture positions it.
    expect(semantics.value, '08:36');
  });

  testWidgets('gesture arena: a translucent horizontal-drag surface does not steal taps from buttons beneath',
      (tester) async {
    // Isolates the exact structure of the mini player's bottom edge: a
    // TextButton in a 66px column with a 20px translucent drag surface
    // overlapping its lower half, matching how the progress bar overlays
    // the transport buttons.
    var buttonTaps = 0;
    var drags = 0;

    Widget scene() => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: 66.0,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Center(
                      child: TextButton(
                        onPressed: () => buttonTaps++,
                        child: const SizedBox(height: 52.0, width: 52.0, child: Text('')),
                      ),
                    ),
                    Positioned(
                      left: 0.0,
                      right: 0.0,
                      bottom: 0.0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (_) => drags++,
                        onHorizontalDragUpdate: (_) {},
                        onHorizontalDragEnd: (_) {},
                        child: const SizedBox(width: double.infinity, height: 20.0),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(scene());

    final buttonCenter = tester.getCenter(find.byType(TextButton));

    // A tap in the overlap reaches the button: the deepest tap recognizer
    // wins the arena over the drag surface.
    await tester.tapAt(Offset(buttonCenter.dx, buttonCenter.dy + 20.0));
    await tester.pump();

    expect(buttonTaps, 1);

    // A fresh scene: a horizontal drag in the same spot is claimed by the
    // drag surface, and the button does not fire.
    buttonTaps = 0;
    drags = 0;
    await tester.pumpWidget(scene());

    final gesture = await tester.startGesture(Offset(buttonCenter.dx, buttonCenter.dy + 20.0));
    await gesture.moveBy(const Offset(40.0, 0.0));
    await gesture.up();
    await tester.pump();

    expect(drags, 1);
    expect(buttonTaps, 0);
  });
}
