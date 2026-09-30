# FrameLab

A free, offline Flutter Android photo and video editor. All templates, filters, transitions, fonts, background removal and export quality are available without an account.

## Download

[![Download Android APK](https://img.shields.io/badge/Download_APK-Android_ARM64-40E0D0?style=for-the-badge&logo=android&logoColor=black)](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-arm64-v8a-release.apk)

[ARM64 — most phones](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-arm64-v8a-release.apk) · [ARMv7 — 32-bit phones](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-armeabi-v7a-release.apk) · [x86_64 — emulator](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-x86_64-release.apk) · [Checksums](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/SHA256SUMS.txt)

Android 7.0/API 24 or later. Open the APK after downloading and allow installation from your browser/file manager when prompted. If a browser stalls finishing the file, copy the download link into Chrome. This test prerelease uses the same development signing key as the previous version and a higher version code, so it can update an existing installation.

## What changed in 1.1

- Brightness, contrast, saturation, exposure, filters, crop and size update the photo canvas directly from cached native textures.
- Video adjustments, canvas changes and overlays update the original-video preview without rendering the entire project after each edit.
- Video scrubbing seeks the source player with pending requests coalesced. The project timeline and bottom tools keep the preview visible.
- All purchase, verification, entitlement and advertising code removed. All 14 templates and editing tools are free; photos export up to 4096px and video at 720p/1080p.
- A focused dark home screen with New project, media shortcuts and local projects.

Full transition composition, music mixing and complex effects can be checked with the explicit composed preview. Export always renders the complete recipe. Initial media decoding, background removal and export require processing time; slider changes do not trigger those jobs. 4K video remains future work.

## Tools

Photo: crop, rotate, flip, resize, color adjustments, filters, blur, text, shapes/stickers, image layers, on-device U²-Net-P background removal/replacement, social sizes and PNG export.

Video: trim, split, reorder/merge, crop/resize, 0.25–4× speed, mute/volume, local music, text, image overlays, filters, effects, transitions and MP4 export. Templates cover posts, Stories, Reels, thumbnails, product ads, festival and business posters.

Projects save locally with autosave, recovery and missing-media relinking. Original media remains local; processing uses no paid APIs or media servers.

## Setup

Baseline: Flutter 3.41.9 / Dart 3.11.5, Android SDK platform 36 and Java 17-compatible tooling. Keep the lockfile. Dependencies need internet at build time.

```powershell
git clone https://github.com/mukunda-jadhav/Video-editing.git
Set-Location Video-editing
flutter pub get
flutter run -d <android-device-id>
```

```powershell
flutter analyze
flutter test
flutter build apk --release --split-per-abi
```

Release builds use a local signing key if `android/key.properties` is configured; otherwise the development debug key is used. Keep keys and credentials outside Git. No purchase build define is needed.

137 unit/widget tests and five Android checks pass. [Updated home screenshot](docs/screenshots/v11-release-home.png).

## Code and verification

- [Realtime editing update](docs/REALTIME_UPDATE.md)
- [Master checklist](docs/MASTER_CHECKLIST.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Dependencies and notices](docs/DEPENDENCIES.md)
- [Test commands and results](docs/TESTING.md)
- [Published APK evidence](docs/PUBLISHING.md)
- [Complete source reading copy](docs/COMPLETE_SOURCE.md)

Editable source files are authoritative. The original ten phase reports remain as historical development records; 1.1 supersedes their subscription/ads architecture and rendered-preview behavior. Physical-phone performance and media-quality qualification remain necessary before a production-store release.
