> Historical phase record. [Version1.1](REALTIME_UPDATE.md) replaces subscription/ads code with free access and replaces slow per-edit preview processing.

# Phase 7 — Local project save/load

Status: **Durable repository, autosave and recovery flows implemented; process-death/storage-failure tests remain a device gate.**

## Implementation

Replaced the empty startup repository with app-private project directories. Versioned JSON recipes are written through pending/current/backup promotion and serialized operations. Loads validate IDs, schema and metadata size and recover backup/pending manifests. Originals and masks stay in assets; photo thumbnails are copied into durable storage. The library supports search, kind filter, rename, reopen and delete. Missing-media paths prompt relinking; failures retain the recipe. Editors autosave and attempt save before leaving.

## Files added or changed

- `lib/features/projects/domain/project_document.dart`
- `lib/features/projects/domain/project_repository.dart`
- `lib/features/projects/data/local_project_repository.dart`
- `lib/features/projects/data/empty_project_repository.dart`
- `lib/features/projects/presentation/projects_screen.dart`
- `lib/app/editor_host.dart`
- `lib/app/providers.dart`
- `lib/main.dart`
- `lib/core/media/media_import_service.dart`
- `lib/features/photo_editor/presentation/photo_editor_screen.dart`
- `lib/features/video_editor/presentation/video_editor_screen.dart`
- `test/local_project_repository_test.dart`
- `test/template_catalog_test.dart`
- `test/photo_document_test.dart`
- `test/video_editor_test.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Uses `path` and `path_provider`; no database service or account is required. Startup creates an application-support projects directory. The current schema is version 1. Atomic JSON was selected instead of earlier proposed Drift to keep projects independently recoverable.

## Testing

Run `flutter test test/local_project_repository_test.dart test/template_catalog_test.dart`, then the full suite. Tests cover recipe round-trips, pending/backup recovery, damaged projects, invalid schema/path IDs, ordered saves and deletion. Create photo/video/template projects on Android, close/reopen the app and compare recipes/output. Kill the process after an autosave and during a write; verify previous/current recovery. Test missing assets and relinking, corrupted metadata alongside healthy projects, search/rename/delete, no-storage and permission failure.

## Limits and remaining checks

Undo history is session-local; the editable recipe persists. Later schema versions need explicit migration code; unknown versions are rejected with an update message. Project files are private and Android backup is disabled; uninstall removes them. Video timeline thumbnails are not yet generated.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
