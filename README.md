# FrameLab

A free, offline Flutter Android photo and video editor. All templates, filters, transitions, fonts, background removal and export quality are available without an account.

## Download

[![Download Android APK](https://img.shields.io/badge/Download_APK-Android_ARM64-40E0D0?style=for-the-badge&logo=android&logoColor=black)](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-arm64-v8a-release.apk)

[ARM64 — most phones](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-arm64-v8a-release.apk) · [ARMv7 — 32-bit phones](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-armeabi-v7a-release.apk) · [x86_64 — emulator](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/app-x86_64-release.apk) · [Checksums](https://github.com/mukunda-jadhav/Video-editing/releases/download/v1.1.0-test/SHA256SUMS.txt)

Android 7.0/API 24 or later. Open the APK after downloading and allow installation from your browser/file manager when prompted. If a browser stalls finishing the file, copy the download link into Chrome. This test prerelease uses the same development signing key as the previous version and a higher version code, so it can update an existing installation.

## What changed in 1.2

- Tap and drag photos, video, text and image layers directly on the canvas; pinch to resize. Photo layers also rotate and have corner handles.
- Fit/fill framing, selection outlines, center snapping and alignment/nudge controls replace position sliders. A labeled bottom toolbar and dismissible tool panels keep the canvas visible.
- Filters show source-preview thumbnails, categories and adjustable Strength. Everything is bundled and works offline; no setup or downloading is needed.
- Automatic and manual Erase/Restore background removal for photos, static overlays and moving video subjects, with replacement colors/images.
- Video cutout runs on-device, preserves original audio and offers progress/cancel. Brush corrections are fixed image regions across the trimmed clip; split clips when different time ranges need different masks. Original footage and cutout recipes remain editable.
- Up to 12 independently positioned video image overlays, preserved local projects, free 720p/1080p export and no accounts, purchases or ads.

Brightness, size, placement and filter gestures reuse cached textures/native decoders; they do not render a complete video after each edit. Background segmentation and final export require processing time. Complex transition/music previews remain an explicit composition action. 4K video remains future work.

## Tools

Photo: crop, rotate, flip, resize, color adjustments, filters, blur, text, shapes/stickers, image layers, on-device automatic/manual U²-Net-P background removal/replacement, social sizes and PNG export.

Video: trim, split, reorder/merge, crop/resize, 0.25–4× speed, mute/volume, local music, text, multiple draggable image overlays, automatic/manual video cutout, filters, effects, transitions and MP4 export. Templates cover posts, Stories, Reels, thumbnails, product ads, festival and business posters.

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
flutter build apk --release --split-per-abi --target lib/main.dart
```

Release builds use a local signing key if `android/key.properties` is configured; otherwise the development debug key is used. Keep keys and credentials outside Git. No purchase build define is needed.

173 unit/widget tests and seven Android checks pass. [Photo canvas](docs/screenshots/v12-photo-canvas.png) · [Video canvas](docs/screenshots/v12-video-canvas.png).

## Code and verification

- [Canvas, filters and cutout update](docs/CANVAS_UPDATE.md)
- [Realtime editing update](docs/REALTIME_UPDATE.md)
- [Master checklist](docs/MASTER_CHECKLIST.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Dependencies and notices](docs/DEPENDENCIES.md)
- [Test commands and results](docs/TESTING.md)
- [Published APK evidence](docs/PUBLISHING.md)
- [Complete source reading copy](docs/COMPLETE_SOURCE.md)

Editable source files are authoritative. The original ten phase reports remain as historical development records; 1.1/1.2 supersede their subscription/ads architecture and rendered-preview behavior. Physical-phone performance and media-quality qualification remain necessary before a production-store release.
