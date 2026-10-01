# 1.2 canvas, filters and cutout acceptance

- [x] Photo/base/layer drag, pinch, rotation, corner handles and center guides.
- [x] Video clip drag/pinch, fit/fill; direct text/image placement and multiple overlays.
- [x] One undo entry per gesture, cached native preview media, position export parity.
- [x] Labeled bottom tools, contextual panel close and alignment/nudge alternatives.
- [x] Offline source-preview filter browser, categories, saved/exported strength.
- [x] Photo/static overlay automatic removal and manual erase/restore/zoom/history.
- [x] Moving-video automatic masks, manual fixed-region corrections, replacement backgrounds, original audio and source restoration.
- [x] Bounded video frame batches, native session reuse, progress/cancel and saved cutout recipes.
- [x] Current static analysis: no issues; full unit/widget suite: 173 passed.
- [x] Seven Android checks passed on Pixel 8 API 37 x86_64 / 16 KB emulator: cutout/placement, live edits and native media.
- [x] 1.2 normal release APKs built; signatures, ZIP/64-bit ELF 16 KB checks and offline x86_64 release launch passed.
- [x] Public 1.2 download publication and anonymous asset/hash verification.
- [ ] Tracked manual video brushes/subject masks (current manual brushes are fixed source regions).

Current verification is recorded in [CANVAS_UPDATE.md](CANVAS_UPDATE.md) and [TESTING.md](TESTING.md). Debug native tests do not complete release/store or physical-phone qualification.

# Core app checklist (current 1.2 source)

The app remains free after the 1.1 removal of subscriptions/advertising. The 1.2 update adds direct canvas placement, source-preview filters and automatic/manual cutout. Original phase reports describe historical implementations; the implementation checklist below describes current source.

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

- [x] Current 1.2: 173 unit/widget tests, seven Android checks and static analysis passed.
- [x] Previous 1.1 distribution: three APKs built/inspected; x86_64 release cold-launched offline and home visually reviewed.
- [ ] Current 1.2 release APK inspection, installed-release acceptance and public distribution (pending).
- [x] Public 1.1.0-test release: all APK/checksum download URLs verified anonymously with matching bytes and hashes.

Historical 1.1 verification and APK publication are recorded in [REALTIME_UPDATE.md](REALTIME_UPDATE.md), [TESTING.md](TESTING.md), [PUBLISHING.md](PUBLISHING.md) and [PUBLISHED_RELEASE.json](PUBLISHED_RELEASE.json).

- [ ] Physical ARM phone: frame timings during continuous gestures and video scrubbing.
- [ ] Low/mid/high phone memory, thermal/battery, export compatibility and long-project stress checks.
- [ ] Low-storage, process-death, interruption and full TalkBack/media-quality acceptance.
- [ ] Store signing/application identity, data-safety and native-library distribution qualification.

Source and test APKs are public on [GitHub](https://github.com/mukunda-jadhav/Video-editing). A test prerelease does not complete the remaining production qualification.
