> Historical phase record. [Version1.1](REALTIME_UPDATE.md) replaces subscription/ads code with free access and replaces slow per-edit preview processing.

# Phase 3 — Video editor

Status: **Implemented and exercised in the three-test Android media suite; the physical-device playback/export matrix remains open.**

## Implementation

Added an immutable timeline, bounded history, clip selection/reordering, trim, split and merge by sequence. Canvas presets plus crop position/zoom resize the output. Playback speed is 0.25–4×, with pitch-preserving audio tempo; clips have mute/volume and a local music track with offset/volume/looping. Timed text and an image overlay are editable. The screen renders a 480p preview, then exports 720p free or 1080p Pro with progress/cancellation. Output is validated with FFprobe before publication. Future 4K is visibly disabled.

## Files added or changed

- `lib/features/video_editor/domain/video_document.dart`
- `lib/features/video_editor/domain/video_history.dart`
- `lib/features/video_editor/domain/video_renderer.dart`
- `lib/features/video_editor/domain/video_render_plan.dart`
- `lib/features/video_editor/data/ffmpeg_video_renderer.dart`
- `lib/features/video_editor/presentation/video_editor_screen.dart`
- `lib/app/editor_host.dart`
- `lib/app/app_router.dart`
- `lib/core/media/media_import_service.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `test/video_document_test.dart`
- `test/video_render_plan_test.dart`
- `test/video_editor_test.dart`
- `integration_test/composition_test.dart`
- `integration_test/native_media_test.dart`
- `integration_test/hardware_export_test.dart`
- `integration_test/media_suite_test.dart`
- `integration_test/android_suite_test.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Adds `ffmpeg_kit_flutter_new_full` and `video_player`. FFmpeg/FFprobe are local native libraries; the app does not need a separately installed ffmpeg executable. Font files are bundled for caption rasterization.

Looped music is first rendered into a finite PCM WAV at the timeline's duration, then mixed with clip audio during composition. This preserves offset, looping and gain while allowing the final native session to finish. It uses temporary disk space and shares the renderer's cancellation/cleanup path.

## Testing

Run `flutter test test/video_document_test.dart test/video_render_plan_test.dart test/video_editor_test.dart`. These verify documents, split/history/timing, compiled commands and editor interactions/layout. Run `flutter test integration_test/android_suite_test.dart -d <android-device-id>` for actual native rendering. The three-test Android media suite passed on the API 37 / 16 KB x86_64 emulator: six composition variants, native model/publication/rendering and validated hardware-encoder fallback. [TESTING.md](TESTING.md) records its scope and remaining physical-device checks.

On Android: import landscape/portrait/silent clips; trim/split/reorder; change speed/crop/volume; add music/text/overlay; play the rendered preview; export both qualities; inspect duration, dimensions, sync and subtitles. Try spaces/non-ASCII paths, unsupported media, cancellation, background/foreground and reopening the project. Record device/native evidence in [TESTING.md](TESTING.md).

## Limits and remaining checks

Preview is disk-rendered after edits, not an instant live compositor. The timeline currently uses labelled clip cards rather than extracted frame thumbnails. There is one image-overlay track and one music track. Long timelines can be slow because joins are rendered sequentially; device profiling remains required. Software MPEG-4 fallback has different compatibility/size from H.264.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
