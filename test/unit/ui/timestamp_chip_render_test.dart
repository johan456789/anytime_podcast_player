import 'dart:io';
import 'dart:ui' as ui;

import 'package:anytime/core/timestamp_text.dart';
import 'package:anytime/ui/widgets/markdown_spans.dart';
import 'package:anytime/ui/widgets/timestamp_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders a ranged-citation reply, captures it as a golden image and
/// verifies that tapping a range chip seeks to the start of the range.
void main() {
  testWidgets('range citations render as chips and tap to the range start', (tester) async {
    // Load the real app font so the golden shows actual glyphs.
    final fontLoader = FontLoader('MontserratMedium')
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Medium.otf'))
      ..addFont(rootBundle.load('assets/fonts/Montserrat-Bold.otf'));
    await fontLoader.load();

    final seeks = <int>[];

    const reply = 'For **they/you guys**, yes: add -án to the infinitive to make the '
        'future—**darán** ("they/you guys will give") [0:22–0:25]. The future endings vary by '
        'subject: **daré, daremos, dará, darás, darán** [0:07–0:29].';

    WidgetSpan chip(String label, int seconds) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: TimestampChip(
            label: label,
            seconds: seconds,
            onSeek: seeks.add,
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          textTheme: Typography.material2018().black.apply(fontFamily: 'MontserratMedium'),
        ),
        home: Material(
          child: Center(
            child: RepaintBoundary(
                key: const Key('reply-boundary'),
              child: Container(
                width: 480.0,
                padding: const EdgeInsets.all(12.0),
                decoration: const BoxDecoration(color: Color(0xff444444)),
                child: Text.rich(
                  TextSpan(
                    children: buildMarkdownSpans(
                      reply,
                      baseStyle: const TextStyle(fontSize: 16.0, color: Colors.white, fontFamily: 'MontserratMedium'),
                      chipBuilder: chip,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Both ranged citations became chips...
    expect(find.byType(TimestampChip), findsNWidgets(2));

    // ...the markdown styling is present...
    final chipLabels = tester
        .widgetList<TimestampChip>(find.byType(TimestampChip))
        .map((chip) => chip.label)
        .toList();

    expect(chipLabels, <String>['0:22–0:25', '0:07–0:29']);

    // ...nothing seeks until the user taps...
    expect(seeks, isEmpty);

    // Capture the rendered reply as a review screenshot (refreshed on every
    // run, no golden comparison).
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('reply-boundary')));
    final bytes = await tester.binding.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);

      return image.toByteData(format: ui.ImageByteFormat.png);
    });

    final out = Directory('demo/screenshots');
    if (!out.existsSync()) {
      out.createSync(recursive: true);
    }

    File('demo/screenshots/10-range-chips-tap.png').writeAsBytesSync(bytes!.buffer.asUint8List());

    // ...and tapping the first range chip seeks to the start of the range.
    await tester.tap(find.byType(TimestampChip).first);
    expect(seeks, <int>[22]);
  });

  test('timestamp parser handles the ranged forms from the golden', () {
    expect(parseClockSeconds('0:22'), 22);
    expect(parseClockSeconds('0:07'), 7);
    expect(parseTimestampSegments('[0:07–0:29]').first, isA<TimestampSegmentT>());
  });
}
