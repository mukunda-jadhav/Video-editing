# 1.2 canvas and cutout update

## Behavior

Photo base media, text, shapes and image overlays support tap selection, direct dragging, pinch scaling and rotation. Selected items have an outline, resize handle and center guides. Video clips support drag/pinch placement with fit/fill; video text and multiple static image overlays support direct placement and scaling. Position sliders are replaced by direct canvas gestures plus alignment/nudge buttons. Each gesture commits one undo step; preview changes reuse source textures/decoders and start no encoder.

The bottom toolbar has labeled tools, compact contextual panels and a close/done action so users can regain canvas space. This is an original interface with familiar editing patterns; no proprietary CapCut assets, catalog or parity claim.

## Filters

Open Filters, select a category, tap a source-preview thumbnail and adjust Strength. Photo and video filters are bundled and free. There is no account, API key or filter-download setup. Strength is saved and exported. Flutter live color processing can approximate some FFmpeg YUV color behavior; explicit composed preview/export remains the final recipe.

## Backgrounds

Photo Background actions and video Overlay cutout actions offer automatic local U²-Net-P segmentation plus manual Erase/Restore, zoom/pan, brush size and undo/redo. Original images are preserved for restoration. Manual photo output is bounded to 4096 px/8 MP with downsampling disclosed.

Video Cutout processes every frame on-device in small storage-aware batches, reuses one ONNX session per batch and recycles each frame. It supports automatic segmentation, manual-only masks, automatic masks plus manual corrections, solid/image replacement backgrounds, progress, cancellation and original audio. Output is up to 1920 px/30 fps. Manual brushes are fixed source-image regions across the selected trimmed clip; they do not track a subject. Split/trim a clip when different time ranges need different corrections. The original recipe and manual strokes are retained for reopening and restoration. Segmentation quality can vary on detailed hair, complex backgrounds and fast motion.

## Files changed and complete code

The maintained source and generated [COMPLETE_SOURCE.md](COMPLETE_SOURCE.md) contain the complete implementation. Files are listed in [CANVAS_CHANGED_FILES.txt](CANVAS_CHANGED_FILES.txt).

## Dependencies and setup

No dependency added; existing Flutter, video_player, FFmpeg, image and owned Android ONNX bridge are used. Follow README setup. Run `flutter pub get` after pulling. The application remains offline and free; user media never leaves the device.

## Verification

Verified on 1 October 2026:

- `flutter analyze --no-pub`: no issues (`canvas-analyze.log`).
- `flutter test --no-pub`: **173 unit/widget tests passed** (`canvas-unit.log`). Coverage includes actual pointer dragging/pinching/rotation, one-step undo, rotated hit testing, retained native photo textures after source deletion, decoded image-provider reuse, legacy project defaults, filter strength, preview/export pixels, brush erase/restore/history and cutout-source trim mapping.
- `flutter test integration_test/canvas_suite_test.dart -d emulator-5554`: **7 Android checks passed** (`canvas-android.log`) on the Pixel 8 AVD, API 37, x86_64 with 16 KB pages. The suite registers two cutout/placement checks, two live-edit checks and three native-media checks; these are seven unique checks, not additional counts for their component assertions.
- Real Android assertions cover fixed-region manual video cutout, source-audio presence and trim, unchanged original bytes, an actual multi-frame ONNX batch with erase/restore and image replacement, cutout cancellation, moved video/multiple overlay export pixels, cached photo/player live changes, and the existing composition/720p/1080p/encoder-fallback pipeline.

The native integration run uses a debug test entry point. All three normal 1.2 release APKs built and passed signature, ZIP and 64-bit ELF 16 KB inspection. The x86_64 release cold-launched offline in 3713 ms with no fatal Flutter/AndroidRuntime error; this is one emulator observation. See [APK records](RELEASE_APK_REPORT.json) and [release launch evidence](CANVAS_ANDROID_RELEASE.json). Public download verification remains pending. [TESTING.md](TESTING.md) contains repeatable commands; [MASTER_CHECKLIST.md](MASTER_CHECKLIST.md) distinguishes completed work from release acceptance.

Physical ARM-phone frame timing, peak memory, thermal/battery stress, long projects, segmentation quality and production-store qualification remain open. Manual video brushes remain fixed source regions; tracked brushes and tracked manual subject masks are not implemented. “Best Android editor” and full CapCut parity are not claimed.
