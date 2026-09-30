# Validation and repeatable tests

This is the current-source validation record, updated 30 September 2026. Historical Phase 1 results in `PHASE_01.md` and `ANDROID_SMOKE_RESULTS.json` belong to the earlier foundation APK and do not validate today's editing engines.

## Evidence available

| Check | Result and scope |
|---|---|
| Full unit/widget suite | `flutter test --no-pub --reporter expanded`: **167 tests passed** on 30 September 2026 (15 seconds test runtime), in `final-unit-tests.log`. |
| Video editor UI | 12 tests passed, including compact/large-text layout, editing/history, caption dialogs, save retry and preview errors. Included in the full suite; the same 12 passed again after the final empty-state label change (5 seconds), in `final-video-ui-tests.log`. This rerun is a subset, not 12 additional unique tests. |
| Premium checkout UI | 5 tests passed, including keyboard/dialog lifecycle and local-only purchase. Included in the full suite. |
| Repository/template/domain targeted run | 41 tests passed in storage integration work; included in the full suite. |
| Formatting/static analysis | Dart format: **68 files, 0 changed**. `flutter analyze --no-pub`: **no issues** (86.9 seconds), 30 September 2026, in `final-analyze.log`. Targeted analysis of the later `integration_test`/`test_driver` screenshot changes also returned no issues. |
| Main-app Android release build | `flutter build apk --release --split-per-abi --dart-define=ENABLE_MOCK_PRO=true`: passed, exit 0; Gradle `assembleRelease` 130.3 seconds, in `release-build.log`. All three APKs compile the normal `lib/main.dart`, enable the simulator and use the Android debug test key. |
| Android media suite | `flutter test integration_test/media_suite_test.dart -d emulator-5554 --no-pub`: **3 tests passed**, exit 0 (31 seconds test runtime; 126 seconds build), in `media-suite.log`. Covers composition, ONNX/media publication/rendering and encoder fallback. |
| Native ONNX/FFmpeg/MediaStore integration | Passed: actual bundled ONNX inference and alpha variation, PNG publication, six clips with every enabled filter/effect/transition plus crop/speed/mute/music/caption/overlay at 720p, silent portrait 1080p, output probes, cancellation and temporary-file release. |
| Native composition regression | Passed all six variants: plain, text, overlay, music, wrapped music offset and combined. Decoded audible samples at 0.75–0.90 seconds from a 0.4-second music fixture demonstrate actual repetition and offset wrapping. |
| Default encoder/fallback | Passed. The emulator hardware attempt produced invalid output; validation rejected it and a software MPEG-4 retry produced a probed 1280×720 export. The returned codec reports this fallback. |
| Android app UI smoke | `flutter test integration_test/ui_smoke_test.dart -d emulator-5554 --no-pub`: **1 test passed** (9 seconds), in `ui-smoke.log`. Guest home, template browsing and actual photo/video editor routes opened without an account form. Four captures completed; host capture and scoped visual review also passed as described below. |
| Host UI capture/visual review | `flutter drive --driver=test_driver/ui_screenshots.dart --target=integration_test/ui_smoke_test.dart --dart-define=CAPTURE_SCREENSHOTS=true -d emulator-5554 --no-pub`: passed (9 seconds), in `ui-capture.log`. Four PNG files saved; home, photo-template canvas and empty video editor were visually inspected on this one emulator. This does not cover all templates, native picker/player surfaces or all screen sizes. |
| Bundled asset integrity | All **6** font/model SHA-256 values match `ASSET_MANIFEST.json`. |
| APK inspection | All three APK signatures verified with `apksigner`; all three passed `zipalign -c -P 16 -v 4`; all 64-bit native ELF load segments have at least 16 KB alignment. Exact package/signature/library records are in [RELEASE_APK_REPORT.json](RELEASE_APK_REPORT.json). |
| Main-app release launch | x86_64 release APK installed and cold-launched offline with airplane mode enabled on the same API 37 / 16 KB emulator. `am start -W` status: ok, TotalTime **2584 ms**; filtered log had no AndroidRuntime/Flutter fatal error. [Release home screenshot](screenshots/release-home.png) visually reviewed. This is one cold-launch observation, not a universal performance target or release-mode media-pipeline test. |
| Complete source handoff | [COMPLETE_SOURCE.md](COMPLETE_SOURCE.md) regenerated: **112** complete source/configuration/notice files, 593913-byte snapshot. Editable files remain authoritative. |
| Physical-device performance/release qualification | Not performed. |

Media-suite device: Pixel 8 AVD, `sdk_gphone16k_x86_64`, Android API 37, actual page size **16384 bytes**. Measured FFmpeg core version: **n8.1.2**; ONNX Runtime Android: **1.30.0**. An adb memory snapshot was 375740 KB PSS; this is a point-in-time emulator observation, not peak memory or a phone benchmark.

Only completed tool/test runs should replace a pending result. A source snapshot or successful build alone does not establish that a media operation works.

## Built main-app APKs

All files are test builds generated locally on 30 September 2026, with `ENABLE_MOCK_PRO=true` and Android debug signing. The package is `com.framelab.framelab`, version 1.0.0, minimum SDK 24 and target/compile SDK 36. Flutter assigns ABI-specific version codes (ARMv7 1002, ARM64 2002, x86_64 4002).

| APK | Bytes | MiB | SHA-256 |
|---|---:|---:|---|
| [ARM64](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-arm64-v8a-release.apk) | 88135415 | 84.1 | `7437a8195f5464c907b89e8b02e2016f68e455e9fa1ca3070cf21c38e6efb43c` |
| [ARMv7](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-armeabi-v7a-release.apk) | 99415833 | 94.8 | `b90bd954822e5dab2062affda01d8f757e71878e0eb8b37a51ecf4a63f36a1df` |
| [x86_64](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-x86_64-release.apk) | 98702859 | 94.1 | `2f3382e31de200e0be8d901b6984831c0b5904a0ca9ac05296ac15cb3bb1eb2c` |

Native editing/model/media publication tests above ran in debug integration builds. The release APK was checked for packaging/signature/alignment and main-app launch; release-mode media operations and physical-device quality/performance still need the acceptance matrix.

## Local prerequisites and commands

Use Flutter 3.41.9 / Dart 3.11.5 with the locked dependencies, Android SDK platform 36 and Java 17-compatible Android toolchain. Runtime target is Android API 24+. The Android SDK/emulator/device must be configured locally; no account or paid API is involved.

```powershell
git clone https://github.com/mukunda-jadhav/Video-editing.git
Set-Location Video-editing
flutter doctor -v
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test test_driver
flutter analyze
flutter test
flutter build apk --debug
```

`scripts/check.ps1 -BuildApk` bundles dependency resolution, source/test/integration-test format checking, analysis, unit/widget tests and debug build. Output APK: `build/app/outputs/flutter-apk/app-debug.apk`.

For a connected emulator or phone, run the consolidated suite once. It registers the individual tests below, so running the whole `integration_test` directory as well would duplicate coverage.

```powershell
flutter devices
flutter test integration_test/android_suite_test.dart -d <android-device-id>
flutter run -d <android-device-id>
```

For an x86_64 emulator with limited storage, temporarily package only its debug ABI:

```powershell
$previousTestAbi = $env:FRAMELAB_TEST_ABI
try {
    $env:FRAMELAB_TEST_ABI = 'x86_64'
    flutter test integration_test/android_suite_test.dart -d <android-device-id> --no-pub
} finally {
    if ($null -eq $previousTestAbi) {
        Remove-Item Env:FRAMELAB_TEST_ABI -ErrorAction SilentlyContinue
    } else {
        $env:FRAMELAB_TEST_ABI = $previousTestAbi
    }
}
```

Use `arm64-v8a` for an ARM64 device if selecting a debug ABI. The override affects debug packaging only; default builds keep all supported ABIs. Do not install an x86_64-only APK on an ARM phone.

| Android test | Intended assertions |
|---|---|
| `composition_test.dart` | Six native rendering variants: plain, text, image overlay, looped music, wrapped offset and combined; decoded tail samples assert audible repeated music. |
| `native_media_test.dart` | Model availability/storage, actual ONNX transparent output, image/video MediaStore publication, FFprobe/audio detection, video transforms/filters/effects/transitions/captions/overlay/music, 720p and portrait 1080p output, temporary-file release and cancellation. Uses software MPEG-4 for repeatable emulator execution. |
| `hardware_export_test.dart` | Default final-encoder selection, including reported H.264 MediaCodec or software fallback, with output probing. |
| `ui_smoke_test.dart` | Account-free app launch, templates and both editor routes; app-private Flutter composited screenshots for visual inspection. |

`media_suite_test.dart` registers the first three tests; `android_suite_test.dart` adds the UI smoke test. Use the smaller media suite when isolating native rendering, then run `ui_smoke_test.dart` separately if needed. Do not also run the whole directory and count repeated registrations as new coverage.

Fixtures are generated on the device; they are not downloaded. A passing synthetic-media run does **not** prove encoder support on every phone, visual mask quality or long-timeline performance. Media tests publish clearly named `FrameLab_smoke_*` exports to the device gallery; they may be removed there after inspection. UI screenshots are generated under the application's support directory in `qa`. Flutter test may uninstall its temporary test app after completion, so use the screenshot driver to preserve captures on the host before visual review:

```powershell
flutter drive --driver=test_driver/ui_screenshots.dart --target=integration_test/ui_smoke_test.dart --dart-define=CAPTURE_SCREENSHOTS=true -d <android-device-id> --no-pub
```

The driver saves the captured [home](screenshots/phase10-home.png), [template gallery](screenshots/phase10-templates.png), [photo-template editor](screenshots/phase10-photo-editor.png) and [empty video editor](screenshots/phase10-video-editor.png) PNGs under `docs/screenshots/`. The same optional debug ABI override can be used for this command. Captures show Flutter-composited app content; they do not claim native picker or player-surface coverage.

Integration tests replace the installed app with a test entry point. Always rebuild the normal application before handing over an APK:

```powershell
flutter build apk --release --split-per-abi --dart-define=ENABLE_MOCK_PRO=true
```

After integration tests, use the normal release command above with dependency/tooling regeneration enabled. Skipping it with `--no-pub` can retain the integration-test plugin registrant and make the main-app release compilation fail. Re-run the normal build; do not hand-edit `GeneratedPluginRegistrant.java`.

These are test builds with the explicitly enabled simulator. See [PUBLISHING.md](PUBLISHING.md) for public prerelease distribution status. Output files are under `build/app/outputs/flutter-apk/`; `app-arm64-v8a-release.apk` is the usual choice for current Android phones, and `app-x86_64-release.apk` is for the emulator. Release uses a supplied `android/key.properties` keystore when configured, otherwise the development debug key. No store-ready signing or real billing is implied.

Run offline editing checks after installation with networking disabled, then restore the device's previous connectivity settings. Build-time dependency resolution needs internet; editing/model inference does not.

## Automated coverage

| Tests | Purpose |
|---|---|
| `app_test.dart` | Guest launch/routes/back, repository loading/error, adaptive home/Projects/Pro and reduced motion. |
| `photo_document_test.dart`, `photo_renderer_test.dart`, `photo_editor_test.dart` | Recipe serialization/history/access, real raster transforms/alpha, corrupt input and canvas/dialog/layout behavior. |
| `video_document_test.dart`, `video_render_plan_test.dart` | Trim/split/history/overlap, serialized recipes, every effect/transition plan, caption safety and export sizes. Native execution is tested separately. |
| `video_editor_test.dart` | Timeline operations/history, caption and rename dialogs, save/preview failures, schema handling and compact/landscape/large-text layouts. |
| `local_project_repository_test.dart`, `template_catalog_test.dart` | Durable recipe round-trips, corruption/recovery/path validation, template categories/free-Pro access and editable templates. |
| `entitlement_test.dart`, `premium_repository_test.dart`, `premium_verification_test.dart`, `premium_screen_test.dart` | Feature policy, expiry/end dates, local receipt persistence/restore/reset/failures, test-code policy and Buy-only account flow. |
| `ads_architecture_test.dart` | Consent/configuration/connectivity, Pro/unknown entitlement, denied placements, failures and late-result disposal. |
| `media_source_test.dart` | Local media boundaries and rejection of remote media URIs. |

Use the per-phase reports for targeted commands. `flutter test` does not run the Android integration suite automatically.

## Manual/device acceptance matrix

Record device model, Android/API version, RAM, build mode/hash, source media and observed results. Use a profile build for timing; debug timing is not release performance.

| Workflow | Required evidence |
|---|---|
| Guest/offline | Cold launch and photo/video/template editing with no signup, model download or media upload. |
| Photo | EXIF JPEG, transparent PNG, portrait/product media; each operation, undo/redo, background/layers and exported dimensions/appearance in another viewer. |
| Video | Landscape/portrait/audio/silent inputs, short/long clips, every operation, all transitions, preview/export parity, sync and preferred hardware encoder/fallback. |
| Templates | Every category and design, editable text/image/color/layout, save/reopen/export and Pro-denial recovery. |
| Segmentation | Portrait/product/hair/glass/low contrast/multiple subjects; alpha edges, background replacement, latency, peak memory, cancellation and repeated runs. |
| Persistence | Relaunch/process kill, interrupted writes, missing-file relink, corruption alongside healthy projects, rename/delete and disk-full behavior. |
| Premium/ads | No form until Buy, both plans, invalid/expired codes, activation/expiry/restore/reset across restart, no default ads and Pro suppression. |
| Accessibility | Small/large screens, landscape, 200%+ text, TalkBack focus/labels, keyboard actions, contrast and reduced motion. |
| Lifecycle/resources | Low/mid/high phones, low storage/memory, repeated exports, background/foreground, cancellation, cold start/frame timings, RAM and thermal/battery use. |
| Release | ABI/16 KB page-size validation, package/signing, notices/source obligations, store/data-safety and real billing/account/ads only when configured. |

Future 4K video and additional premium on-device tools remain unavailable by design; they are not failures of the currently enabled export choices.
