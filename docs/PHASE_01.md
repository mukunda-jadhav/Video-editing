# Phase 1 delivery report

> Historical report for the foundation delivered on 28 September 2026. Its preview-only behavior and validation results describe that earlier build. Phases 2–10 now supply the editor engines and integrations; use [MASTER_CHECKLIST.md](MASTER_CHECKLIST.md), [TESTING.md](TESTING.md) and [COMPLETE_SOURCE.md](COMPLETE_SOURCE.md) for the current app.

The current Phase 1 foundation also includes integration changes to `lib/app/app.dart`, `lib/app/app_router.dart`, `lib/app/providers.dart`, `lib/core/config/app_config.dart`, `lib/features/home/presentation/home_screen.dart`, `lib/features/roadmap/domain/development_phase.dart` and `lib/features/roadmap/presentation/roadmap_screen.dart`. Photo/video/template buttons now open implemented editors, project storage is live, and the roadmap distinguishes included code from pending device qualification. The obsolete `feature_preview_screen.dart` was removed. Run `flutter test test/app_test.dart` for current foundation tests; the manual preview checks below apply only to the historical APK.

Date: 28 September 2026. Project: local FrameLab project folder.

## Scope and result

Phase 1 implements architecture and home only. The app launches as a guest, renders a polished original dark home, navigates among Home / Projects / Pro, and exposes a transparent ten-phase roadmap. Photo/video/template actions open clearly labelled future-feature previews. Premium pricing is exactly ₹39/month and ₹299/year; simply browsing Pro never requests an email.

This is not yet a production-ready editor. Import/edit/export, editable templates, background removal, project saving, actual mock entitlement activation and ads remain assigned to Phases 2–10. No requested feature has been removed. The mock purchase flow belongs to Phase 8 in the requested sequence; Phase 1 provides its replaceable gateway, account identity and entitlement contracts.

## Delivered code

- Feature-oriented domain/data/presentation separation and a Riverpod composition root.
- GoRouter stateful bottom-navigation shell, preview routes, error route, and Android back handling.
- Responsive home, original vector/canvas template artwork, shared dark tokens, local system fonts, safe areas and Material tap feedback.
- Honest empty projects adapter, injectable async loading/error/retry UI, no fake saved projects.
- Central plans, entitlements, expiry policy and disabled future 4K/on-device capabilities.
- Purchase gateway contract and explicit simulated-versus-real verified account identity.
- URI-only media contract, native engine/capability boundaries, cancellable export handle and segmentation interface.
- Android API 24 baseline, dark splash, original vector launcher icon and disabled automatic backup.
- Complete source and reproducible checks. [Source snapshot](PHASE_01_SOURCE.md) contains the complete text of application, tests and build configuration; individual source files remain authoritative.

## Dependencies and setup

Installed: Flutter SDK, `flutter_riverpod 3.3.2`, `go_router 17.5.0`; development: `flutter_test` and `flutter_lints 6.0.0`. No code generation, secret keys, account, API token or backend setup is required. Pins match Flutter 3.41.9 / Dart 3.11.5. Full rationale and deferred dependencies: [DEPENDENCIES.md](DEPENDENCIES.md).

```powershell
Set-Location '<path-to-FrameLab-project>'
flutter pub get
flutter devices
flutter run -d <android-device-id>
```

For installation requirements and license troubleshooting, see [README](../README.md). Build with `flutter build apk --debug`. The output is `build/app/outputs/flutter-apk/app-debug.apk` and uses debug signing; it must not be published as a production release.

## Validation results

- `dart format lib test`: passed; final source formatted.
- `flutter analyze`: **passed, no issues**.
- `flutter test`: **35 tests passed**.
- `flutter build apk --debug`: **passed**; rebuilt after the final layout changes.
- APK installation and emulator launch: **passed**.
- Native offline/navigation smoke: **7 checks passed** on API 37 (`sdk_gphone16k_x86_64`, Pixel 8 AVD). Details: [ANDROID_SMOKE_RESULTS.json](ANDROID_SMOKE_RESULTS.json).

The widget matrix includes 320×568, 375×812, 800×1280, 1200×800 and 844×390 logical pixels, each at 100% and 200% system text scaling, plus reduced-motion mode. A real small-screen 200% header overflow discovered in the first test run was fixed and the full suite rerun successfully. Native testing also found a nested-navigation Android Back issue; the handler now belongs to each active tab route, with two system-back regression tests.

Tests also verify guest launch without account forms, correct plan prices, feature previews/back navigation, roadmap access, repository loading/error/manual retry, guest/active/expired Pro boundaries, future-feature denial and rejection of remote media URIs.

Android smoke testing uses the installed Pixel 8 emulator. Cold launch is checked with Wi-Fi and mobile data disabled; their prior settings are restored afterward. Screenshots are actual Android captures, not mockups. The existing preview-system emulator initially displayed a System UI ANR during startup; it was dismissed and app verification continued. No physical-device performance, full TalkBack audit, release signing or real-media export testing is claimed.

## Repeat the checks

```powershell
.\scripts\check.ps1 -BuildApk
```

Manual checks:

1. Launch in airplane/offline mode: home appears without login, permission prompt or download.
2. Open New photo / New video: each states its planned phase and that editing/export are not available. Android Back returns to home.
3. Open Projects: empty state clearly identifies future local saving. Repository tests cover loading and error retry.
4. Open Pro: both exact prices display, with planned benefits and the no-charges notice; no signup appears. Android Back returns home.
5. Open Explore or a template preview: Phase 5 scope appears; no fake template editing.
6. Open the full roadmap and expand the phases. Verify all requested features remain listed.
7. Change Android font scale to 200%, rotate the device, and check scrolling/navigation without clipping. Restore the original device setting afterward.

## Known limitations and next phase

The project repository is intentionally empty and has no persistence until Phase 7. Engine interfaces have no native implementations yet. Entitlement access is a policy contract, not proof that a feature is implemented; all editing feature routes remain previews. The current adapter always supplies a free guest entitlement. Real verification cannot be simulated by merely entering an email; Phase 8 must label its local test verification explicitly and reserve real verification for an actual account adapter.

Media3 is planned for native Android video; true crossfades require additional compositor/FFmpeg work in Phase 4. Background removal will evaluate an on-device general-object model, not silently substitute person-only segmentation. Release quality, media memory benchmarks and device coverage remain Phase 10 obligations.

Next deliverable is **Phase 2: Photo editor**, preserving the full checklist and implementing actual import, operations, preview and export.

## Changed files

This is a new app directory; no files in the sibling projects were changed. The inventory below lists delivered source, tests, docs, configuration and standard Flutter-generated scaffold files. Tool caches, build outputs, IDE metadata, local SDK paths and generated plugin registrants are excluded from the maintained-source inventory. The APK is a separate generated output.

<!-- FILE_INVENTORY -->

- `.gitignore`
- `.metadata`
- `README.md`
- `analysis_options.yaml`
- `android/.gitignore`
- `android/app/build.gradle.kts`
- `android/app/src/debug/AndroidManifest.xml`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/framelab/framelab/MainActivity.kt`
- `android/app/src/main/res/drawable-v21/launch_background.xml`
- `android/app/src/main/res/drawable/framelab_icon.xml`
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/mipmap-hdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-mdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png`
- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png`
- `android/app/src/main/res/values-night/styles.xml`
- `android/app/src/main/res/values-v31/styles.xml`
- `android/app/src/main/res/values/colors.xml`
- `android/app/src/main/res/values/styles.xml`
- `android/app/src/profile/AndroidManifest.xml`
- `android/build.gradle.kts`
- `android/gradle.properties`
- `android/gradle/wrapper/gradle-wrapper.jar`
- `android/gradle/wrapper/gradle-wrapper.properties`
- `android/gradlew`
- `android/gradlew.bat`
- `android/settings.gradle.kts`
- `docs/ANDROID_SMOKE_RESULTS.json`
- `docs/ARCHITECTURE.md`
- `docs/DEPENDENCIES.md`
- `docs/DESIGN_SYSTEM.md`
- `docs/MASTER_CHECKLIST.md`
- `docs/PHASE_01.md`
- `docs/PHASE_01_SOURCE.md`
- `docs/screenshots/phase1-home.png`
- `docs/screenshots/phase1-premium.png`
- `docs/screenshots/phase1-projects.png`
- `lib/app/app.dart`
- `lib/app/app_router.dart`
- `lib/app/providers.dart`
- `lib/core/config/app_config.dart`
- `lib/core/media/media_engine.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/widgets/page_content.dart`
- `lib/features/entitlements/data/guest_entitlement_repository.dart`
- `lib/features/entitlements/domain/entitlement.dart`
- `lib/features/entitlements/domain/purchase_gateway.dart`
- `lib/features/entitlements/presentation/premium_screen.dart`
- `lib/features/home/presentation/home_screen.dart`
- `lib/features/home/presentation/widgets/template_art.dart`
- `lib/features/projects/data/empty_project_repository.dart`
- `lib/features/projects/domain/project_repository.dart`
- `lib/features/projects/presentation/projects_screen.dart`
- `lib/features/roadmap/domain/development_phase.dart`
- `lib/features/roadmap/presentation/feature_preview_screen.dart`
- `lib/features/roadmap/presentation/roadmap_screen.dart`
- `lib/main.dart`
- `pubspec.lock`
- `pubspec.yaml`
- `scripts/check.ps1`
- `scripts/export_source.py`
- `test/app_test.dart`
- `test/entitlement_test.dart`
- `test/media_source_test.dart`
