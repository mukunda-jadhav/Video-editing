# FrameLab 1.1 architecture

Flutter Android, Riverpod and replaceable local media/storage boundaries. All editing capabilities are available without an account. Purchase, entitlement, email verification and advertising subsystems have been removed.

```text
lib/app/                   Routes, dependency composition and editor host
lib/core/                  Media import/native bridge, theme, widgets, notices
lib/features/home/         Project creation and recent projects
lib/features/photo_editor/ Recipe/history, cached texture painter, free export
lib/features/video_editor/ Immutable timeline/history, live player, FFmpeg plan
lib/features/templates/    14 editable bundled designs
lib/features/projects/     Atomic local JSON manifests, recovery and relinking
lib/features/settings/     Storage/privacy, diagnostics and offline licenses
android/app/src/main/      ONNX model inference and MediaStore publication
assets/                    Bundled document fonts and license notices
integration_test/          Real native media and gesture regression tests
```

Photo recipes contain source paths and editing values. Source images are decoded into bounded native textures on media changes. Slider and geometry edits repaint through Canvas/color matrices, sharing the painter with export. History/autosave commits happen after gestures. Exports decode higher-resolution sources and render PNG using the same recipe.

Video recipes store clips, trims, speed, audio, color, canvas and timed layers. Live editing plays the original file in the native player and applies color/layout/crop/layers in Flutter. Pending seeks are coalesced, and stale source loads are discarded. Codec initialization is required once when changing source. Exact transitions, complex effects and mixed music use explicit composition preview; final export always runs the full FFmpeg plan with output validation/fallback/cancellation.

EditorHost imports copies into app-private project directories and publishes finished files to Android MediaStore. Storage uses versioned recoverable manifests, atomic writes and bounded metadata. No editing media leaves the device. Riverpod supplies repositories and observable project state; editors receive storage/import/export callbacks.

Resource bounds and physical-device qualification remain in the [master checklist](MASTER_CHECKLIST.md). [REALTIME_UPDATE.md](REALTIME_UPDATE.md) records the 1.1 changes and actual checks.


## Canvas and cutout (1.2)

PhotoDocument persists base-media transforms, filter strength and original cutout sources; the same PhotoPainter geometry drives preview, hit testing and PNG export. VideoClip persists fit/fill, normalized translation, zoom, strength and a bounded original cutout recipe. VideoCanvasPlacement defines shared preview/export coordinates. VideoDocument stores up to 12 immutable image overlays and migrates the previous single-overlay field without truncation.

FilterStrip presents cached source previews and separates selection from strength changes. Canvas gestures update recipes in memory each frame and commit one history step on release. Video image decode bounds depend on the source, so dragging/pinching never requests another decode.

BackgroundRefineScreen uses a native image plus vector alpha-mask brushes, with source-normalized points. PNG encoding runs in a worker on Apply. VideoCutoutService extracts storage-aware batches (up to 30 frames), asks the owned Android bridge to reuse ONNX for those frames, then encodes and restores original audio. Manual video strokes are fixed image-space corrections. Processing and cancellation are explicit workflows, separate from live editing. Original sources and brush recipes remain private and locally editable.
