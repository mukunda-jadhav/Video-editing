# Phase 6 — On-device background remover

Status: **Bundled U²-Net-P inference, transparent output and PNG publication passed on the Android emulator; real-photo mask quality and physical-device performance remain open.**

## Implementation

Added a Kotlin worker bridge with private-path validation, bounded image decode, EXIF correction, ONNX inference, alpha compositing, cancellation and resource release. The bundled general salient-object U²-Net-P model uses 320×320 inference input and returns a local transparent PNG. Original media remains intact; photo background tools apply solid/image replacements. Pro is required. No paid AI API, media upload or first-run model download occurs. The same bridge publishes exports to Android MediaStore and checks available storage.

## Files added or changed

- `android/app/src/main/kotlin/com/framelab/framelab/LocalMediaBridge.kt`
- `android/app/src/main/kotlin/com/framelab/framelab/MainActivity.kt`
- `android/app/src/main/assets/models/u2netp.onnx`
- `android/app/src/main/assets/models/U2NET-LICENSE.txt`
- `android/app/src/main/assets/models/REMBG-LICENSE.txt`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `lib/core/media/native_media_service.dart`
- `lib/features/photo_editor/presentation/photo_editor_screen.dart`
- `lib/app/editor_host.dart`
- `scripts/fetch_assets.py`
- `docs/ASSET_MANIFEST.json`
- `integration_test/native_media_test.dart`
- `integration_test/media_suite_test.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Adds Gradle `com.microsoft.onnxruntime:onnxruntime-android:1.30.0`. The model and notices are bundled. Standard Android build resolves the runtime. Do not fetch model assets during app launch; the developer fetch script is for reviewed recovery/updates.

## Testing

Run `flutter test integration_test/android_suite_test.dart -d <android-device-id>` to exercise the actual bundled model and transparent output on generated input. The completed media suite exercised inference, alpha variation and publication on synthetic input. [TESTING.md](TESTING.md) records the device and completed suite outcomes. On a device with networking disabled, activate local Pro and remove backgrounds from a person, product and multiple-subject image. Check transparency, rotation, replacement, export, cancellation and repeated runs. Record latency/peak memory, hair/edges, low contrast and glass cases. Verify free users encounter Pro only for the restricted operation.

## Limits and remaining checks

Saliency segmentation does not guarantee professional matting. There is no manual brush mask-refinement UI. The earlier planning checklist mentioned refinement; it remains an enhancement rather than a claimed implementation. Quality and performance on real photos require explicit review.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
