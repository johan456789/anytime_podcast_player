# Production Transcript Formatting Support Plan

## Goal

Harden transcript formatting after the basic bold, italic, and underline rendering support has landed.

This phase should make formatted transcripts robust across parsing, search, persistence, grouping, accessibility, and tests.

## Prerequisite

The basic support plan has already been implemented:

`docs/transcript-formatting-basic/plan.md`

Expected baseline:

- Allowed inline tags render in transcript lines.
- Rendering is isolated behind a transcript text helper.
- Existing playback and basic search behavior still work.

## Production Scope

Support these behaviors:

- Format rendering remains limited to bold, italic, and underline.
- Search uses plain visible transcript text, not raw markup.
- Transcript grouping preserves visible text and avoids leaking broken tags.
- Malformed, unsupported, or hostile markup is sanitized into readable text.
- Accessibility semantics expose readable plain text.
- Tests cover parser, search, grouping, and UI behavior.

## Implementation Steps

1. Introduce a normalized transcript text representation.

Keep `Subtitle.data` for storage compatibility, but add helper functions that derive:

- Plain visible text for search and semantics.
- Styled spans for rendering.
- Sanitized inline representation if needed for grouping.

Recommended file:

`lib/services/transcript/transcript_text_parser.dart`

Possible API:

```dart
class ParsedTranscriptText {
  final String plainText;
  final TextSpan textSpan;
}

ParsedTranscriptText parseTranscriptText({
  required String rawText,
  required TextStyle? baseStyle,
});
```

Keep Flutter UI dependencies out of service-layer files if that conflicts with existing architecture. If so, split plain-text parsing and `TextSpan` building:

- `lib/core/transcript_text.dart` for plain parsing/sanitization.
- `lib/ui/podcast/transcript_text.dart` for Flutter `TextSpan` building.

2. Make search match plain visible text.

Current location:

`lib/services/audio/default_audio_player_service.dart`

Change transcript filtering from raw `subtitle.data!.toLowerCase().contains(...)` to a plain-text helper.

Acceptance examples:

- Searching `bold word` matches `<b>bold</b> word`.
- Searching `hello world` matches `hello <i>world</i>`.
- Searching `b` should not match only because a `<b>` tag exists.

3. Preserve accessibility semantics.

In `SubtitleWidget`, wrap rich text with semantics when needed so screen readers get visible plain text, not markup.

Possible shape:

```dart
Semantics(
  label: parsed.plainText,
  child: ExcludeSemantics(
    child: Text.rich(parsed.textSpan),
  ),
)
```

Only use this if Flutter's default `TextSpan` semantics are not sufficient in testing.

4. Harden transcript grouping.

Current location:

`lib/services/podcast/mobile_podcast_service.dart`

The grouping code concatenates `subtitle.data` values. That is okay for plain text, but risky for formatted fragments.

Review and adjust grouping so it operates on a normalized representation:

- If subtitle fragments contain complete inline tags, preserve them.
- If tags are split across fragments, degrade to plain visible text instead of storing broken markup.
- Preserve spacing behavior currently handled around single-character transcript fragments.

Add tests around grouped transcripts with formatted fragments.

5. Add sanitizer behavior.

Allowed tags:

- `b`, `strong`, `i`, `em`, `u`

Everything else:

- Strip the tag.
- Keep visible text content.
- Drop attributes entirely.
- Never create links, images, embedded widgets, scripts, or styles.

Examples:

- `<script>alert(1)</script>Hello` => `Hello`
- `<a href="...">word</a>` => `word`
- `<span style="font-weight:bold">word</span>` => `word`
- `<b onclick="...">word</b>` => bold `word`, no attributes retained

6. Add test coverage.

Recommended tests:

- Parser plain text extraction.
- Parser `TextSpan` styling for all supported tags.
- Nested and overlapping malformed tags.
- Unsupported tags stripped while preserving visible text.
- Script/style content removed.
- HTML entities decode in both plain text and styled rendering.
- Search matches visible text and ignores markup.
- Grouping preserves complete inline tags.
- Grouping degrades split or malformed markup to visible text.
- Widget test for formatted transcript line rendering.

7. Validate behavior manually.

Use a local sample transcript containing:

```html
This is <b>bold</b>, <i>italic</i>, and <u>underlined</u>.
Nested <b><i>bold italic</i></b>.
Unsupported <a href="https://example.com">link text</a>.
```

Confirm:

- Display is correct.
- Tapping a transcript line still seeks playback.
- Search finds visible text.
- Auto-scroll/highlight behavior is unchanged.

## Acceptance Criteria

- Bold, italic, and underline render correctly from allowed inline HTML.
- Unsupported or unsafe markup cannot create interactive content or hidden behavior.
- Search operates on visible text.
- Accessibility semantics do not expose raw tags.
- Transcript grouping does not leak broken markup into the UI.
- Existing transcript persistence remains backward compatible.
- `flutter analyze` passes.
- Unit and widget tests for transcript formatting pass.

## Non-Goals

- Full HTML rendering.
- Markdown syntax.
- Rich transcript editing.
- Styling beyond bold, italic, and underline.
- Links or tappable inline transcript content.
- Word-level synchronized styling or highlighting.

## Files Likely To Change

- `lib/ui/podcast/transcript_view.dart`
- `lib/ui/podcast/transcript_text.dart`
- `lib/services/audio/default_audio_player_service.dart`
- `lib/services/podcast/mobile_podcast_service.dart`
- Possible shared parser file under `lib/core` or `lib/services/transcript`
- Tests under `test/unit` and possibly `test/widget`

## Risks

- Pulling Flutter `TextSpan` creation into service-layer code would blur architecture boundaries. Keep parser and renderer separate if that becomes awkward.
- Transcript sources may use inconsistent markup conventions. Keep the allowlist small and degrade to visible text.
- Grouping formatted word-level transcripts is the hardest part because markup can be split across timing fragments.
- Sanitizing at display time is safer for backward compatibility than rewriting persisted transcript data.
