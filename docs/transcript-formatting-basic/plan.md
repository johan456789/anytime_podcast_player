# Basic Transcript Formatting Support Plan

## Goal

Add basic display support for bold, italic, and underline inside transcript lines.

This phase should be intentionally small: render existing inline formatting in transcript text, while preserving the current transcript model, search behavior, playback seeking, and transcript grouping behavior as much as possible.

## Current State

- Transcript line text is stored as `Subtitle.data` in `lib/entities/transcript.dart`.
- Transcript lines are rendered with plain `Text` in `SubtitleWidget` in `lib/ui/podcast/transcript_view.dart`.
- Search filters against `Subtitle.data` in `lib/services/audio/default_audio_player_service.dart`.
- Transcript lines are grouped in `MobilePodcastService.loadTranscriptByUrl` in `lib/services/podcast/mobile_podcast_service.dart`.

## Supported Markup

Implement a minimal allowlist for these inline HTML tags:

- `<b>` and `<strong>` => `FontWeight.bold`
- `<i>` and `<em>` => `FontStyle.italic`
- `<u>` => `TextDecoration.underline`

Do not support arbitrary HTML, links, images, block elements, CSS, or scripts in this phase.

## Implementation Steps

1. Add a small transcript text renderer helper.

Recommended file:

`lib/ui/podcast/transcript_text.dart`

The helper should expose a widget or function that converts a raw subtitle string into a `TextSpan` tree and applies a base `TextStyle`.

Suggested API:

```dart
TextSpan buildTranscriptTextSpan({
  required String text,
  required TextStyle? baseStyle,
})
```

2. Parse only the allowed inline tags.

Use the existing `html` package if already available in the app dependency graph. The app already imports `package:html/parser.dart` elsewhere, so prefer that over hand-written regex parsing.

Parsing rules:

- Unknown tags should render their text content with the inherited style.
- Invalid markup should degrade to readable plain text.
- Nested supported tags should combine styles, such as bold plus italic.
- HTML entities should decode correctly through the parser.

3. Replace the subtitle body `Text` in `SubtitleWidget`.

Current location:

`lib/ui/podcast/transcript_view.dart`

Replace:

```dart
Text(
  subtitle.data!,
  style: Theme.of(context).textTheme.titleMedium,
)
```

With:

```dart
Text.rich(
  buildTranscriptTextSpan(
    text: subtitle.data ?? '',
    baseStyle: Theme.of(context).textTheme.titleMedium,
  ),
)
```

4. Keep search unchanged for this phase.

Search can continue matching raw `Subtitle.data`. This means markup text may affect search in edge cases, but it keeps the basic implementation small.

5. Add focused tests.

Preferred tests:

- Plain transcript text renders as a single normal span.
- `<b>bold</b>` applies bold.
- `<i>italic</i>` applies italic.
- `<u>underline</u>` applies underline.
- Nested tags combine styles.
- Unknown tags do not apply style but keep text.
- Malformed markup does not throw.

Suggested test file:

`test/unit/ui/transcript_text_test.dart`

If widget-level style inspection is awkward, test the `TextSpan` builder directly.

## Acceptance Criteria

- Transcript lines can display bold, italic, and underline from allowed inline HTML tags.
- Existing transcript playback seeking still works.
- Existing transcript search still works at least as well as before for plain transcripts.
- No unsupported HTML is rendered as widgets or interactive content.
- `flutter analyze` passes.
- Relevant tests pass.

## Non-Goals

- Markdown support.
- Search that strips markup before matching.
- Search result highlighting.
- Sanitizing or normalizing transcript data at persistence time.
- Preserving formatting through grouped word-level transcripts beyond what naturally works with concatenated strings.

## Files Likely To Change

- `lib/ui/podcast/transcript_view.dart`
- `lib/ui/podcast/transcript_text.dart`
- `test/unit/ui/transcript_text_test.dart`

## Risks

- The current transcript grouping code concatenates raw strings. If a transcript source splits markup across subtitle entries, this phase may still produce malformed or partially visible formatting.
- Raw search can match tag names or fail when a query spans markup boundaries.
- `Text.rich` does not automatically behave exactly like `Text` for overflow or semantics in every context, so keep layout changes minimal.
