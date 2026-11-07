import 'package:anytime/ui/widgets/markdown_spans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseStyle = TextStyle(fontSize: 16.0);
  final chips = <(String, int)>[];

  WidgetSpan chipBuilder(String label, int seconds) {
    chips.add((label, seconds));

    return WidgetSpan(child: SizedBox(key: ValueKey('$label:$seconds')));
  }

  setUp(() {
    chips.clear();
  });

  group('buildMarkdownSpans', () {
    test('plain text becomes a single span', () {
      final spans = buildMarkdownSpans('Just some text.', baseStyle: baseStyle, chipBuilder: chipBuilder);

      final joined = spans.whereType<TextSpan>().map((s) => s.text).join();
      expect(joined, contains('Just some text.'));
      expect(chips, isEmpty);
    });

    test('bold renders with bold weight', () {
      final spans = buildMarkdownSpans('a **bold** word', baseStyle: baseStyle, chipBuilder: chipBuilder);

      final flattened = <TextStyle>[];
      void walk(List<InlineSpan> spans) {
        for (final span in spans) {
          if (span is TextSpan) {
            if (span.style != null) {
              flattened.add(span.style!);
            }

            walk(span.children ?? const <InlineSpan>[]);
          }
        }
      }

      walk(spans);

      expect(flattened.any((style) => style.fontWeight == FontWeight.w700), isTrue);
    });

    test('bullet list items are prefixed with a bullet', () {
      final spans = buildMarkdownSpans('- one\n- two', baseStyle: baseStyle, chipBuilder: chipBuilder);

      final joined = spans.whereType<TextSpan>().map((s) => s.text ?? '').join();
      expect(joined, contains('•  one'));
      expect(joined, contains('•  two'));
    });

    test('timestamps inside list items become chips', () {
      final spans = buildMarkdownSpans('- see [2:07] now', baseStyle: baseStyle, chipBuilder: chipBuilder);

      expect(chips, contains(('2:07', 127)));
      expect(spans.whereType<WidgetSpan>(), isNotEmpty);
    });

    test('timestamps in plain paragraphs become chips', () {
      buildMarkdownSpans('Covered at [1:02:03] in depth.', baseStyle: baseStyle, chipBuilder: chipBuilder);

      expect(chips, contains(('1:02:03', 3723)));
    });

    test('headings render bold and larger', () {
      final spans = buildMarkdownSpans('## Heading', baseStyle: baseStyle, chipBuilder: chipBuilder);

      final flattened = <TextStyle>[];
      void walk(List<InlineSpan> spans) {
        for (final span in spans) {
          if (span is TextSpan) {
            if (span.style != null) {
              flattened.add(span.style!);
            }

            walk(span.children ?? const <InlineSpan>[]);
          }
        }
      }

      walk(spans);

      expect(flattened.any((style) => style.fontWeight == FontWeight.w700 && (style.fontSize ?? 16) > 16), isTrue);
    });

    test('empty text produces no spans', () {
      expect(buildMarkdownSpans('', baseStyle: baseStyle, chipBuilder: chipBuilder), isEmpty);
    });
  });
}
