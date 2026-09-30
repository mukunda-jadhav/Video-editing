# FrameLab

An offline-first Flutter Android photo, video and template editor. Code covers all ten development phases. **167 unit/widget tests and 4 Android integration tests pass.** Physical-device performance, media-quality and public-release qualification remain open.

Free editing opens without an account. No paid API, media upload service or runtime asset download is used. Premium is a clearly labelled local simulator at **₹39/month** or **₹299/year**: it requests email only after Buy, displays a test code on the device, and makes no charge or real email-verification claim.

## Download Android app

[![Download Android APK](https://img.shields.io/badge/Download_APK-Android_ARM64-A8D56B?style=for-the-badge&logo=android&logoColor=white)](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-arm64-v8a-release.apk)
[![Other downloads](https://img.shields.io/badge/All_downloads-v1.0.0--test-B4A0FF?style=for-the-badge&logo=github&logoColor=white)](https://github.com/mukunda-jadhav/Video-editing/releases/tag/v1.0.0-test)

**Tap the green button for most Android phones.** Android 7.0/API 24 or later is required. Download the APK and open it on your Android phone; allow installation from that browser or file manager when Android asks.

| Device | Direct APK download | Size |
|---|---|---:|
| Current ARM64 Android phones | [Download ARM64 APK](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-arm64-v8a-release.apk) | 84.1 MiB |
| Older 32-bit ARM Android phones | [Download ARMv7 APK](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-armeabi-v7a-release.apk) | 94.8 MiB |
| x86_64 Android emulator | [Download x86_64 APK](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/app-x86_64-release.apk) | 94.1 MiB |

[SHA-256 checksums](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.0.0-test/SHA256SUMS.txt) · [Release notes](https://github.com/mukunda-jadhav/Video-editing/releases/tag/v1.0.0-test)

This **test prerelease** enables the local Pro simulator and uses the Android debug test key. No payment is taken, and the displayed verification code is a local simulation. Free editing requires no account. To test Pro, open Pro, choose a plan, enter an email, and use the test code shown in the app.

All three APKs passed signature/ZIP alignment checks; 64-bit native libraries passed 16 KB ELF alignment checks. The x86_64 build was installed and cold-launched offline on the API 37 / 16 KB emulator. Native editing tests used debug integration builds; physical-phone and release-mode media qualification remain open. Exact hashes, sizes and build evidence are in [TESTING.md](docs/TESTING.md), [the APK report](docs/RELEASE_APK_REPORT.json) and [publishing notes](docs/PUBLISHING.md).

## Implemented capabilities

- Photo: crop, rotate, flip, resize, brightness/contrast/saturation/exposure, filters, blur, editable text, shapes/stickers, image layers, background replacement, social presets and PNG export.
- Video: clip timeline, trim/split/reorder/merge, canvas crop/resize, 0.25–4× speed, mute/volume, local music, timed text and image overlay, filters/effects, overlapping transitions, rendered preview and MP4 export.
- Fourteen editable templates across Instagram posts, Stories, Reels, YouTube thumbnails, product ads, festival and business posters. Five are free; the rest require local Pro.
- On-device U²-Net-P background removal, bundled fonts/model, local project autosave/recovery/relinking, central entitlement state, mock restore/reset and an offline no-op ads adapter.

Free exports fit within **1920 px** for photos and use **720p** video. Pro photos retain up to **4096 px**, and Pro video offers **1080p**. Video 4K and additional Premium on-device tools remain explicitly future capabilities, as requested. The photo size limit does not imply 4K video support.

## Setup

Baseline: Flutter **3.41.9**, Dart **3.11.5**, Android SDK platform **36**, JDK from Android Studio; Android minimum API **24**. Keep `pubspec.lock`. Build-time dependencies need internet; normal editing runs offline after installation.

```powershell
git clone https://github.com/mukunda-jadhav/Video-editing.git
Set-Location Video-editing
flutter doctor -v
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

Use an Android emulator or phone with USB debugging enabled. If needed, review Android SDK licenses using `flutter doctor --android-licenses`. The model and five fonts are already bundled; no keys, backend, Supabase project, billing setup or Python runtime is required to run the app.

```powershell
flutter build apk --debug
```

Test APK: `build/app/outputs/flutter-apk/app-debug.apk`. Debug builds enable the local Pro simulator. It is disabled by default in release builds; `--dart-define=ENABLE_MOCK_PRO=true` explicitly enables it for a release-mode test. Never present that build as real billing. The current application ID and debug signing are development defaults.

After running Android integration tests, rebuild the normal application with `flutter build apk --release --split-per-abi --dart-define=ENABLE_MOCK_PRO=true`. Let the normal build regenerate platform tooling; using `--no-pub` immediately after tests can retain their plugin registrant.

For store signing, copy `android/key.properties.example` to the ignored `android/key.properties` and supply your own keystore path and credentials locally. Gradle uses that key when configured; otherwise release builds use the debug key for local testing. Keep signing credentials out of the source snapshot and repository.

## Verify and read the code

```powershell
.\scripts\check.ps1 -BuildApk
python scripts/export_source.py
```

The editable `.dart`, Kotlin, Gradle, XML and test files are the **complete code**. [Complete source snapshot](docs/COMPLETE_SOURCE.md) is a generated reading copy; binary fonts, model, icons and wrapper remain in their normal project folders. It excludes caches, local SDK paths, signing secrets and build outputs.

- [Master checklist and remaining gates](docs/MASTER_CHECKLIST.md)
- [Architecture and folder structure](docs/ARCHITECTURE.md)
- [Dependencies and asset provenance](docs/DEPENDENCIES.md)
- [Test commands, actual results and device checklist](docs/TESTING.md)
- Phase reports: [1](docs/PHASE_01.md), [2](docs/PHASE_02.md), [3](docs/PHASE_03.md), [4](docs/PHASE_04.md), [5](docs/PHASE_05.md), [6](docs/PHASE_06.md), [7](docs/PHASE_07.md), [8](docs/PHASE_08.md), [9](docs/PHASE_09.md), [10](docs/PHASE_10.md)

Each phase report supplies its changed-file inventory, implementation details, dependencies, setup and testing steps. Shared files appear in more than one phase because integration changed them repeatedly.

## Current limits

The video preview is a rendered 480p proxy, so edits require a render before playback. FFmpeg tries Android H.264 encoding and reports a software MPEG-4 fallback when needed. The three-test Android media suite passes on an API 37 / 16 KB x86_64 emulator, including looped music and encoder fallback. Guest/editor route smoke tests and scoped screenshot review also pass; the normal app APKs are built and inspected in [the validation record](docs/TESTING.md). Device codec, output compatibility, model edge quality and long-project performance need the device matrix in the checklist. Resource bounds and their reasons are documented in Phase 10.

Google Play Billing, real verified Premium accounts and a live ad SDK are intentionally not configured. Replaceable contracts and no-op adapters are supplied. Supabase remains optional for a future verified-account adapter and never receives editing media. Public-release signing/store setup and distribution obligations remain open. Physical-device performance, media quality and release-mode editing checks still require the acceptance matrix; real billing/email/live-ad adapters remain future configuration work.
