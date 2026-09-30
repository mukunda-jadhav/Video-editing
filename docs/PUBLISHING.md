# FrameLab public test prerelease

Prepared on 30 September 2026 for [mukunda-jadhav/Video-editing](https://github.com/mukunda-jadhav/Video-editing).

## Publication status

The intended GitHub prerelease tag is **v1.0.0-test**. Source and APK assets are prepared; publication/upload confirmation is pending. This document does not claim the GitHub release is already available. After the release assets are uploaded, the README download buttons will link directly to those APK files.

This is a testing prerelease. It enables the local Pro simulator, uses the Android debug test signing key, and makes no charge or real email-verification claim. Premium prices remain ₹39/month and ₹299/year. Free editing requires no account.

## Artifacts

| Target | APK release asset | Bytes | SHA-256 |
|---|---|---:|---|
| ARM64: most current Android phones | `app-arm64-v8a-release.apk` | 88135415 | `7437a8195f5464c907b89e8b02e2016f68e455e9fa1ca3070cf21c38e6efb43c` |
| ARMv7: 32-bit ARM phones | `app-armeabi-v7a-release.apk` | 99415833 | `b90bd954822e5dab2062affda01d8f757e71878e0eb8b37a51ecf4a63f36a1df` |
| x86_64: Android emulator | `app-x86_64-release.apk` | 98702859 | `2f3382e31de200e0be8d901b6984831c0b5904a0ca9ac05296ac15cb3bb1eb2c` |

Source build outputs live under `build/app/outputs/flutter-apk/` locally. APKs belong in GitHub Releases rather than the source Git history. [RELEASE_APK_REPORT.json](RELEASE_APK_REPORT.json) records the same artifact sizes, hashes, signing and ZIP/ELF alignment results with repository-relative build paths.

The source repository includes the editable Flutter/Kotlin code, tests, build configuration, pinned lockfile, bundled fonts/model, notices and development reports. It excludes build caches, logs, generated plugin registrants, local SDK configuration, IDE metadata and signing credentials.

## Build the same test configuration

```powershell
git clone https://github.com/mukunda-jadhav/Video-editing.git
Set-Location Video-editing
flutter pub get
flutter build apk --release --split-per-abi --dart-define=ENABLE_MOCK_PRO=true
```

Use the baseline Flutter 3.41.9 / Dart 3.11.5 and Android SDK platform 36. The app supports Android API 24 and later. Build dependencies need internet; normal media editing uses local data and bundled runtimes/model. Rebuilding with a different SDK or signing key may produce different APK hashes.

Signing credentials remain local: `android/key.properties.example` is a placeholder template, while `android/key.properties` and keystores are ignored. Release builds use a supplied local key when configured and otherwise use the debug key for testing. Mock Pro is disabled in ordinary release builds unless explicitly enabled with the define above.

## Validation scope

The current implementation passed 167 unit/widget tests and four Android integration checks on an API 37 / 16 KB x86_64 emulator. The APKs passed signature and ZIP alignment checks; 64-bit native libraries passed 16 KB ELF alignment checks. The x86_64 main-app release was cold-launched offline. Exact evidence and limitations are in [TESTING.md](TESTING.md).

Native editing integration tests ran in debug builds. Physical-phone performance, media quality and release-mode editing qualification remain open. Google Play Billing, real verified Premium accounts and a live ad SDK are future configuration work. Future 4K video and additional Premium on-device tools remain disabled as requested.

Bundled fonts/model/runtime notices and their provenance remain in the source and the app's offline license screen. [DEPENDENCIES.md](DEPENDENCIES.md) records native package versions, source links and distribution review notes. Test prerelease publication does not establish store readiness; use the [master checklist](MASTER_CHECKLIST.md) for remaining production qualification.
