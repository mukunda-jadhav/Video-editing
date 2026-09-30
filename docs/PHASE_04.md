# Phase 4 — Transitions and effects

Status: **Implemented through the shared FFmpeg recipe/preview/export path and exercised in the Android media suite; real-media boundary quality still needs physical-device validation.**

## Implementation

Cut concatenates clips. Dissolve, wipe, slide and circle use real overlapping `xfade` video transitions with matching `acrossfade` audio. Overlap is clamped to adjacent clip lengths and subtracted from sequence duration. Slide/circle require Pro. Filters include mono, vivid, warm, cool and cinema; basic effects include vignette, soft blur, mirror and fade. Restricted filters/effects use central Pro status and export gating.

## Files added or changed

- `lib/features/video_editor/domain/video_document.dart`
- `lib/features/video_editor/domain/video_render_plan.dart`
- `lib/features/video_editor/data/ffmpeg_video_renderer.dart`
- `lib/features/video_editor/presentation/video_editor_screen.dart`
- `test/video_document_test.dart`
- `test/video_render_plan_test.dart`
- `integration_test/native_media_test.dart`
- `integration_test/media_suite_test.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Uses the Phase 3 FFmpeg full package. No additional package or server is needed. Intermediate streams share frame rate, timebase, pixel format, audio rate and channel layout before joining.

## Testing

Run the video document/render-plan tests from Phase 3. Tests cover overlap duration, all transition variants, audio composition, short clips and each filter/effect plan. The consolidated Android suite runs generated clips through every enabled transition; use [TESTING.md](TESTING.md) for the actual execution outcome.

On Android: export two differently colored clips with distinct audio tones through every transition; inspect actual overlap, audio continuity and duration. Repeat three clips, short edges, sped-up clips and a mixture of cut/crossfade. Compare rendered preview to final output.

## Limits and remaining checks

Pure command tests do not establish that native filters execute correctly. Output frame continuity and audio/video sync across real codecs must be measured; no fade-out/fade-in substitute is presented as crossfade.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
