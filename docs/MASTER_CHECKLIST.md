# FrameLab 1.1 master checklist

The 1.1 update replaces subscriptions and advertising with unrestricted editing. It also replaces per-edit image processing/video encoding with live previews. Original phase reports describe historical implementations; this checklist describes the current app.

## Architecture and home

- [x] Flutter Android, Riverpod, injected local storage/media boundaries.
- [x] Dark project-first home, local project previews and Home / Projects / Templates navigation.
- [x] No account, purchase, verification, entitlement or advertising flow.

## Photo editing

- [x] Crop, rotate, flip, resize, brightness, contrast, saturation, exposure, filters and blur.
- [x] Cached native textures and live GPU canvas changes during gestures.
- [x] Editable text, five fonts, stickers/shapes, image layers and background replacement.
- [x] Social presets, undo/redo, automatic saving and free PNG export up to 4096px.
- [x] Preview/export shared painter and combined color/geometry pixel-parity regression.

## Video editing

- [x] Trim, split, reorder/merge, crop/resize, speed, mute/volume, music, text and overlays.
- [x] Native source playback, coalesced timeline seeks and live color/canvas changes.
- [x] Filters, effects and transitions retained; exact composition preview available explicitly.
- [x] Complete FFmpeg export recipe, output validation, hardware/software fallback and cancellation.
- [x] Free 720p/1080p export. No purchase gate.
- [ ] 4K export (future engine/device qualification).

## Templates and background removal

- [x] All 14 templates editable without a gate; original layouts and fonts preserved.
- [x] Posts, Stories, Reels, thumbnails, product ads, festival/business posters.
- [x] Text/images/colors/layout editing using photo/video recipes.
- [x] Bundled local U²-Net-P model and ONNX Runtime; removal/replacement available to everyone.

## Projects and offline operation

- [x] Local atomic manifests, autosave/recovery, rename/delete/search and missing-media relinking.
- [x] Local media import and gallery exports; no media server or paid APIs.
- [x] Original media and existing saved recipes preserved across application updates.

## Validation and distribution

- [x] 137 unit/widget tests, five Android checks and static analysis passed.
- [x] Three APKs built/inspected; x86_64 release cold-launched offline and home visually reviewed.

Actual 1.1 verification and APK publication are recorded in [REALTIME_UPDATE.md](REALTIME_UPDATE.md), [TESTING.md](TESTING.md), [PUBLISHING.md](PUBLISHING.md) and [PUBLISHED_RELEASE.json](PUBLISHED_RELEASE.json).

- [ ] Physical ARM phone: frame timings during continuous gestures and video scrubbing.
- [ ] Low/mid/high phone memory, thermal/battery, export compatibility and long-project stress checks.
- [ ] Low-storage, process-death, interruption and full TalkBack/media-quality acceptance.
- [ ] Store signing/application identity, data-safety and native-library distribution qualification.

Source and test APKs are public on [GitHub](https://github.com/mukunda-jadhav/Video-editing). A test prerelease does not complete the remaining production qualification.
