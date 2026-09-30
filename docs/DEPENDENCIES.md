# Dependencies and assets

Implementation record: 30 September 2026. `pubspec.yaml`, `pubspec.lock` and Android Gradle configuration are authoritative. Pins resolve on Flutter 3.41.9 / Dart 3.11.5; newer releases may need a newer SDK.

| Dependency | Version | Use |
|---|---:|---|
| Flutter / Dart | 3.41.9 / 3.11.5 baseline | UI/runtime, Canvas and isolates |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod/versions/3.3.2) | 3.3.2 | Shared state and injection |
| [go_router](https://pub.dev/packages/go_router/versions/17.5.0) | 17.5.0 | Routes/navigation shell |
| [file_picker](https://pub.dev/packages/file_picker/versions/13.1.0) | 13.1.0 | User-selected local media |
| [image](https://pub.dev/packages/image/versions/4.10.1) | 4.10.1 | Raster filters/codecs |
| [path](https://pub.dev/packages/path/versions/1.9.1) | 1.9.1 | Filesystem paths |
| [path_provider](https://pub.dev/packages/path_provider/versions/2.1.6) | 2.1.6 | Private/temp directories |
| [shared_preferences](https://pub.dev/packages/shared_preferences/versions/2.5.5) | 2.5.5 | Mock receipt and consent |
| [video_player](https://pub.dev/packages/video_player/versions/2.11.1) | 2.11.1 | Rendered preview playback |
| [ffmpeg_kit_flutter_new_full](https://pub.dev/packages/ffmpeg_kit_flutter_new_full/versions/2.5.2) | 2.5.2 | FFmpeg/FFprobe video pipeline |
| [ONNX Runtime Android](https://onnxruntime.ai/docs/tutorials/mobile/deploy-android.html) | 1.30.0 (Gradle) | Native model inference |
| flutter_test / integration_test | Flutter SDK | Unit/widget/device testing |
| flutter_lints | 6.0.0 | Static analysis |

No paid AI/API, Supabase, billing, analytics, network media storage or live ads dependency is installed. There is no code generation. Engines/fonts/model are bundled, so APK size includes native runtimes.

## Video backend

The selected maintained community fork supplies FFmpeg, FFprobe and the required filters. Its package page advertises FFmpeg 8.1.2; native build identifiers may differ, so the measured runtime version belongs in the device test report. Its full package documents LGPL-3.0 distribution without GPL codecs and Android API 24 support. The GPL variant is not installed. [Package documentation](https://pub.dev/packages/ffmpeg_kit_flutter_new_full/versions/2.5.2).

FrameLab uses MPEG-4 intermediates, tries `h264_mediacodec` final output and falls back to `mpeg4`. It does not request `libx264`, `libx265` or GPL-only `eq`. Source paths are arguments, captions are files. The full build is larger than a custom trimmed build. Review native artifacts, notices and corresponding source/distribution obligations before release. Inclusion is not proof of codec availability on every phone. [FFmpeg license information](https://ffmpeg.org/legal.html).

The original retired FFmpegKit package, a Media3 backend and the earlier proposed Drift database are not installed. Current project storage is recoverable per-project JSON. These choices retain requested editing/persistence capabilities.

## Bundled assets

`android/app/src/main/assets/models/u2netp.onnx` comes from [U²-Net](https://github.com/xuebinqin/U-2-Net), distributed as ONNX by [rembg](https://github.com/danielgatis/rembg). U²-Net supplies Apache-2.0 terms; conversion provenance and rembg notice are retained. [ASSET_MANIFEST.json](ASSET_MANIFEST.json) records file/source/digest. Model SHA-256: `309c8469258dda742793dce0ebea8e6dd393174f89934733ecc8b14c76f4ddd8`. Model size does not establish mask quality or peak runtime memory.

| App family | Source font | Notice |
|---|---|---|
| StudioSans | Noto Sans | `assets/fonts/StudioSans-OFL.txt` |
| StudioSerif | Lora | `assets/fonts/StudioSerif-OFL.txt` |
| StudioMono | Roboto Mono | `assets/fonts/StudioMono-OFL.txt` |
| StudioScript | Caveat | `assets/fonts/StudioScript-OFL.txt` |
| StudioDisplay | Bebas Neue | `assets/fonts/StudioDisplay-OFL.txt` |

These fonts come from the [Google Fonts repository](https://github.com/google/fonts) under SIL OFL 1.1. Names are local Flutter aliases; exact URLs/hashes are in the manifest. Templates use code-drawn shapes and editable text. No commercial music or proprietary stock assets are bundled; users select their own local media.

`lib/core/config/bundled_licenses.dart` registers the five font notices and U²-Net/rembg/ONNX Runtime/FFmpegKit notices with Flutter's offline license screen. Native notices are copied into `assets/licenses/` and declared in `pubspec.yaml`. These notices supplement automatic package notices; release distribution still requires checking the actual native dependency bundle and its corresponding-source obligations.

`python scripts/fetch_assets.py` is a developer recovery/update utility. It downloads upstream assets and rewrites the manifest; review changed hashes and notices. Normal setup uses bundled files. Do not silently rerun it during reproducible release builds because upstream font URLs may change.

## Maintenance

Keep the lockfile; check maintenance, SDK/Android constraints and licenses before upgrading, then run tests/device workflows. Native FFmpeg/ONNX need ABI, page-size and distribution checks. Future store/ad packages belong behind current interfaces with configured/tested adapters. Supabase stays optional for verified Premium accounts and has no editing-media access.
