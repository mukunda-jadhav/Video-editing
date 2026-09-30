# Phase 5 — Templates

Status: **Fourteen template recipes and editing routes implemented; template browsing and the Everyday studio editing route passed on Android. Every design still needs device visual/export review.**

## Implementation

Five free and nine Pro templates cover Instagram posts, Stories, Reels, YouTube thumbnails, product ads, festival posters and business posters. Photo designs become editable shape/text/layer recipes. Users replace/add images, edit text, colors, position, size, rotation and z-order. Reels open the video editor with editable timed captions and require the user's footage. Templates use the same save/export paths as original projects; Pro template export is rechecked.

## Files added or changed

- `lib/features/templates/domain/template_catalog.dart`
- `lib/features/templates/presentation/templates_screen.dart`
- `lib/features/home/presentation/home_screen.dart`
- `lib/features/home/presentation/widgets/template_art.dart`
- `lib/app/editor_host.dart`
- `lib/app/app_router.dart`
- `assets/fonts/`
- `pubspec.yaml`
- `docs/ASSET_MANIFEST.json`
- `test/template_catalog_test.dart`
- `integration_test/ui_smoke_test.dart`
- `test_driver/ui_screenshots.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Uses existing Flutter/editor dependencies and five bundled OFL fonts. Template art is code and text, so no remote stock-asset subscription or paid API is required.

## Testing

Run `flutter test test/template_catalog_test.dart test/app_test.dart test/photo_document_test.dart test/video_document_test.dart`. Open every category and both free/Pro designs; change headline, image, palette and layout; save/reopen/export. Verify a denied Pro purchase leaves free browsing/editing accessible. For Reels add local footage, edit caption timing and export.

## Limits and remaining checks

Bundled copy/layouts are starting points, not a stock media or music library. Reels need imported footage. Template visual/readability review and device export checks remain in [TESTING.md](TESTING.md).

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
