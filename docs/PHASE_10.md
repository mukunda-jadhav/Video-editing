# Phase 10 — Production optimization

Status: **Resource controls and reproducible checks implemented; physical-device performance/release qualification is not complete.**

## Implementation

Bounded Flutter image caching, photo decodes and layer assets; worker-isolate raster filters; serialized preview updates with stale-result disposal; native ONNX worker/thread limits, cancellation and resource release; serialized FFmpeg jobs with bounded filter/codec threads; disk-backed intermediates, cleanup and output probing; import/publication free-space checks; recovery/error states; reduced-motion and adaptive layouts. Settings expose local device/storage/runtime diagnostics. Source and bundled assets have a documented dependency/provenance inventory.

## Files added or changed

- `lib/main.dart`
- `lib/core/config/bundled_licenses.dart`
- `assets/licenses/`
- `pubspec.yaml`
- `lib/features/photo_editor/data/photo_renderer.dart`
- `lib/features/photo_editor/presentation/photo_editor_screen.dart`
- `lib/features/video_editor/data/ffmpeg_video_renderer.dart`
- `lib/features/video_editor/presentation/video_editor_screen.dart`
- `lib/core/media/media_import_service.dart`
- `android/app/src/main/kotlin/com/framelab/framelab/LocalMediaBridge.kt`
- `android/app/build.gradle.kts`
- `android/app/proguard-rules.pro`
- `android/key.properties.example`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/core/theme/app_theme.dart`
- `scripts/check.ps1`
- `scripts/export_source.py`
- `scripts/verify_apk.py`
- `integration_test/android_suite_test.dart`
- `integration_test/media_suite_test.dart`
- `integration_test/composition_test.dart`
- `integration_test/native_media_test.dart`
- `integration_test/hardware_export_test.dart`
- `integration_test/ui_smoke_test.dart`
- `test_driver/ui_screenshots.dart`
- `docs/screenshots/phase10-home.png`
- `docs/screenshots/phase10-templates.png`
- `docs/screenshots/phase10-photo-editor.png`
- `docs/screenshots/phase10-video-editor.png`
- `docs/screenshots/release-home.png`
- `docs/RELEASE_APK_REPORT.json`
- `test/photo_editor_test.dart`
- `test/video_editor_test.dart`
- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/DEPENDENCIES.md`
- `docs/DESIGN_SYSTEM.md`
- `docs/MASTER_CHECKLIST.md`
- `docs/TESTING.md`
- `docs/PHASE_01.md` through `docs/PHASE_10.md`
- `docs/COMPLETE_SOURCE.md` (generated after final code changes)

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Uses the existing engines and Flutter tooling. No paid profiling or telemetry service is required. Android Studio/DevTools and adb can measure local builds. Use a profile build for timing; debug APK timing is not release performance.

## Testing

The 167-test unit/widget suite, three native media tests and one Android app-route smoke test passed. Screenshot capture saved four PNGs; home, photo-template canvas and the empty video editor were visually inspected on the single API 37 emulator. Run the repeatable format, analysis, build and integration commands in [TESTING.md](TESTING.md). Then profile cold launch, UI frames, peak RSS/PSS, export time, battery/thermal behavior and APK size on low/mid/high Android phones. Test low storage/memory, interruptions, cancellation, repeated edits and app restarts. Audit TalkBack, large text, reduced motion, landscape and exported media in other apps.

`python scripts/verify_apk.py 'build/app/outputs/flutter-apk/*-release.apk'` inspects built APKs and reports their SHA-256, size and native ELF segment alignment as JSON. A failing 64-bit native-library alignment check blocks release. Combine it with Android SDK `zipalign -c -P 16 -v 4 <apk>` and actual installation/execution on a 16 KB page-size device; ELF metadata inspection alone is not a runtime compatibility test.

## Current resource bounds

| Area | Implemented bound |
|---|---|
| Flutter decoded image cache | 48 MiB, 80 entries. |
| Source photos | Up to 60 MiB encoded and 32 megapixels; decode dimensions are reduced before raster processing. |
| Photo canvas/layers | 4096 px maximum canvas edge and 48 editable layers; free export fits 1920 px. |
| Video recipe | 64 clips and 48 text layers; rendering rejects excess items instead of truncating the saved recipe. |
| Video output | 480p preview, 720p free export, 1080p Pro export; maximum dimension 4096 px for supported aspect ratios. This is not enabled 4K export. |
| Native inference | 320 × 320 model input, bounded source decoding, two intra-op threads and one inter-op thread. |
| Import/publication | Checks free space before copying/publishing, with additional 64 MiB import and 16 MiB publication margins. |

These bounds reduce avoidable allocations and unsupported workloads. They do not promise a particular peak RAM, export time or safe project duration on every device. The video pipeline has no fixed total-duration cap; long projects still need sufficient local storage and measured device capacity.

## Limits and remaining checks

Three normal release-mode test APKs were built, signature/ZIP inspected and hashed. Both 64-bit ABIs passed native ELF 16 KB alignment; the x86_64 app cold-launched offline on the actual 16 KB emulator. Native editing tests used debug integration builds, so physical ARM/native release-mode media qualification remains open. Public release still needs physical-device evidence, appropriate signing/store/data-safety configuration and dependency distribution obligations. Billing/email/ads are deliberately simulated/unconfigured, not production services. No claimed universal performance target has been measured. 4K video remains future work.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
