# FrameLab 1.2 verification

Current-source verification record, 1 October 2026. The application is version **1.2.0+4**. All editing is free; Premium, checkout, verification and ads flows have been removed. Historical phase reports and [REALTIME_UPDATE.md](REALTIME_UPDATE.md) describe earlier releases and do not replace these checks.

## Completed checks

| Check | Result and scope |
|---|---|
| Static analysis | `flutter analyze --no-pub`: **no issues**, `canvas-analyze.log`. |
| Full unit/widget suite | `flutter test --no-pub`: **173 passed**, `canvas-unit.log`. |
| Consolidated Android suite | `flutter test integration_test/canvas_suite_test.dart -d emulator-5554`: **7 passed**, `canvas-android.log`; Pixel 8 AVD, Android API 37, x86_64, 16 KB pages. |
| Photo interaction | Actual pointer drag/pinch/rotation, rotated selection, one-step undo, and next-frame brightness/ratio changes. A real native texture remains the same over 16 gesture frames after deleting its source file. |
| Video interaction | Clip/text/image direct placement, legacy layout compatibility, decoder/provider reuse, multiple overlays, one-step undo and no automatic encoder jobs during live changes. |
| Photo pixels and brushes | Shared preview/export painter verifies transforms and filter strength; manual erase/restore, brush history and source-coordinate behavior are tested. |
| Video cutout and placement | Real Android fixed-region manual cutout preserves an audio track and trim; source bytes remain unchanged. A multi-frame ONNX batch verifies erase/restore and image replacement. Cancellation and moved-video/two-overlay export pixels pass. |
| Native media regression | Actual local ONNX, composition/music, filters/effects/transitions, 720p/1080p output, MediaStore publication, cancellation and validated hardware/software fallback. |

The seven Android checks comprise **2 cutout/placement + 2 live-edit + 3 native-media checks**. Running component test files again is a rerun, not extra unique coverage. ONNX pipeline assertions on synthetic images do not establish real-world subject/hair quality. Cutout audio is AAC-transcoded; track presence is verified, not bit-identical audio or universal lip-sync accuracy.

All three normal 1.2 release APKs built and passed signature, ZIP and 64-bit ELF 16 KB checks: [RELEASE_APK_REPORT.json](RELEASE_APK_REPORT.json). ABI version codes are ARM64 2004, ARMv7 1004 and x86_64 4004 (base code 4). The installed x86_64 release cold-launched offline in **3713 ms**, with no fatal Flutter/AndroidRuntime errors: [launch record](CANVAS_ANDROID_RELEASE.json), [reviewed home](screenshots/v12-release-home.png). This is one emulator launch observation; release-mode editing and physical-phone qualification remain open. Public 1.2 download verification remains pending.

## Setup and repeatable commands

Use the locked dependencies with Flutter 3.41.9 / Dart 3.11.5, Android SDK platform 36 and a Java 17-compatible Android toolchain. Runtime target is Android API 24+. Dependency resolution needs internet; editing/model inference uses local media and bundled assets.

```powershell
flutter doctor -v
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze --no-pub
flutter test --no-pub
flutter devices
flutter test integration_test/canvas_suite_test.dart -d <android-device-id>
```

The consolidated suite imports `canvas_cutout_test.dart`, `realtime_editor_test.dart` and `media_suite_test.dart`. Use a component file only to isolate a failure. `flutter test` alone does not run Android integration tests.

For an x86_64 emulator with limited storage, package only its debug ABI:

```powershell
$previousTestAbi = $env:FRAMELAB_TEST_ABI
try {
    $env:FRAMELAB_TEST_ABI = 'x86_64'
    flutter test integration_test/canvas_suite_test.dart -d <android-device-id>
} finally {
    if ($null -eq $previousTestAbi) {
        Remove-Item Env:FRAMELAB_TEST_ABI -ErrorAction SilentlyContinue
    } else {
        $env:FRAMELAB_TEST_ABI = $previousTestAbi
    }
}
```

Use `arm64-v8a` for an ARM64 phone when selecting a debug ABI. The override affects debug packaging only. Restore it before ordinary builds.

Integration tests install a test entry point. Rebuild the ordinary application with dependency/tooling regeneration enabled before distributing an APK:

```powershell
flutter build apk --release --split-per-abi
```

No mock-purchase define is needed. Skipping dependency/tooling regeneration with `--no-pub` immediately after integration tests can retain a test plugin registrant; rerun the normal build instead of editing generated Android files. Output is under `build/app/outputs/flutter-apk/`. ARM64 is the usual phone APK; x86_64 is for the emulator. The development signing key is a test-distribution key, not completed store signing.

Optional UI capture is separate from the seven-check suite:

```powershell
flutter drive --driver=test_driver/ui_screenshots.dart --target=integration_test/ui_smoke_test.dart --dart-define=CAPTURE_SCREENSHOTS=true -d <android-device-id>
```

Captures show Flutter-composited content; they do not establish native picker/player surface coverage. Record this run and inspect its images before claiming current screenshots. Synthetic fixtures are generated locally. Native tests publish named smoke exports to the gallery for inspection; they may be removed there afterward.

## Coverage guide

| Test files | Purpose |
|---|---|
| `app_test.dart` | Free/offline routes, navigation, loading/error, responsive layout and reduced motion. |
| `photo_document_test.dart`, `photo_renderer_test.dart`, `photo_editor_test.dart` | Saved recipe defaults, transforms, filters/alpha, direct gestures, native texture reuse, history and dialog/layout behavior. |
| `background_refine_test.dart` | Source-coordinate erase/restore, pixels, bounded output, brush history and saved brush data. |
| `video_document_test.dart`, `video_render_plan_test.dart`, `video_editor_test.dart` | Trim/split/history, multiple overlays, drag/pinch, fit/fill positions, filter strength, preview resources and export plans. |
| `video_cutout_source_test.dart` | Reopening processed clips maps current trim back to original source while retaining current edits. |
| `local_project_repository_test.dart`, `template_catalog_test.dart` | Durable projects, original/cutout media references, recovery/relinking and freely editable templates. |
| `media_source_test.dart` | Local-media boundaries and rejection of remote media URIs. |
| `canvas_cutout_test.dart` | Native video cutout/audio/trim, ONNX brush/replacement batches, cancellation and placed-overlay export pixels. |
| `realtime_editor_test.dart` | Real Android source texture/player reuse, next-frame live color/ratio response and encode-free scrubbing. |
| `composition_test.dart`, `native_media_test.dart`, `hardware_export_test.dart` | Native compositions/music, ONNX/publication/export pipeline and validated final encoder/fallback. |

Complete implementation and changed files: [CANVAS_UPDATE.md](CANVAS_UPDATE.md), [CANVAS_CHANGED_FILES.txt](CANVAS_CHANGED_FILES.txt) and [COMPLETE_SOURCE.md](COMPLETE_SOURCE.md).

## Physical-device and release acceptance still open

Record device/RAM, Android/API, build mode/hash, source media, observed results and peak resources. Use profile/release builds for timing.

| Workflow | Required evidence |
|---|---|
| Offline/update | Cold launch, editing without accounts/uploads, normal update retains existing local projects. |
| Photo/filters/templates | EXIF JPEG/transparent PNG, every editing tool, save/reopen/undo, all designs and exported dimensions/appearance in another viewer. |
| Video/audio | Real landscape/portrait/audio/silent inputs, short/long timelines, all tools/transitions, preview/export quality, sync and encoder compatibility. |
| Automatic/manual cutout | Portrait/product/hair/glass/low contrast/multiple subjects, moving media, alpha edges, repeated runs, resume/cancel/retry and replacement backgrounds. |
| Manual video brushes | Fixed source regions only. Verify intended time ranges using split/trim; subject tracking and tracked manual masks remain future work. |
| Persistence/storage | Process kill, interrupted writes, missing media, corruption, low storage/disk-full and cancelled-work cleanup. |
| Accessibility | Small/large screens, landscape, 200%+ text, TalkBack, alignment/nudge alternatives, keyboard actions and reduced motion. |
| Performance/lifecycle | Physical low/mid/high ARM phones: continuous gestures/scrubbing, FPS/frame timings, peak RAM, battery/thermal behavior, background/foreground and long-project stress. |
| Release/store | Current APK hashes/signatures, all ABI/16 KB checks, release-mode media acceptance, signing/identity, notices/source obligations and store/data-safety qualification. |

4K export remains future engine/device qualification. The verified test scope does not establish full CapCut parity, tracked manual video masking or universal physical-phone performance.
