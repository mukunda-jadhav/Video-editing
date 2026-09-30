# Phase 2 — Photo editor

Status: **Implemented; the template editor route/canvas was exercised and visually reviewed on the emulator. Real-photo picker/export coverage remains in the physical-device matrix.**

## Implementation

Added a nondestructive photo document, bounded undo/redo, selectable/movable/resizable/rotatable layers and a bottom editing toolbar. Crop, quarter-turn rotation, horizontal flip, canvas resize, brightness, contrast, saturation, exposure, blur and seven filters render locally. Text, five font families, shapes, vector stickers, image layers, z-order/opacity, solid/image backgrounds and social presets share the export compositor. Free PNG export fits within 1920 px; Pro keeps up to 4096 px. Pro filters/fonts/stickers are gated and checked again at export. Background removal is integrated in Phase 6.

## Files added or changed

- `lib/features/photo_editor/domain/photo_document.dart`
- `lib/features/photo_editor/data/photo_renderer.dart`
- `lib/features/photo_editor/presentation/photo_editor_screen.dart`
- `lib/core/media/media_import_service.dart`
- `lib/core/media/native_media_service.dart`
- `lib/app/editor_host.dart`
- `lib/app/app_router.dart`
- `pubspec.yaml`
- `pubspec.lock`
- `test/photo_document_test.dart`
- `test/photo_renderer_test.dart`
- `test/photo_editor_test.dart`
- `integration_test/ui_smoke_test.dart`
- `test_driver/ui_screenshots.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Adds `image`, `file_picker`, `path` and `path_provider`; fonts are bundled. The native publish bridge is shared with Phase 6. Setup is ordinary Flutter dependency resolution; media is selected through the Android picker.

## Testing

Run `flutter test test/photo_document_test.dart test/photo_renderer_test.dart test/photo_editor_test.dart`. Renderer tests cover corrupt input, transforms, filters and alpha composition; widget tests cover layout, guest edits, Pro denial and layer interaction. See [TESTING.md](TESTING.md) for actual run status.

On Android: import an EXIF-rotated JPEG and transparent PNG; adjust every slider; crop/rotate/resize; add and edit text; drag/reorder layers; add stickers/backgrounds; undo/redo; export and open the PNG in another viewer. Check small/landscape/large-text layouts, corrupt/oversized input, cancellation and media staying offline.

## Limits and remaining checks

Color management/HDR and broad image-format behavior require device checks. Automatic background removal is in Phase 6. The editor bounds source decoding/layer counts to reduce memory pressure; these controls are not a low-memory-device benchmark.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
