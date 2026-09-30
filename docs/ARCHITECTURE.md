# FrameLab architecture

Current implementation: Flutter Android UI and local photo/video/template engines, on-device segmentation, durable project files, mock Premium and offline ads architecture. Android API 24+ is the target. See [validation evidence](TESTING.md) before drawing conclusions about device or release readiness.

## Structure

```text
lib/
  main.dart                         Private storage and adapter composition
  app/
    app.dart, app_router.dart        Theme, routes and lifecycle
    providers.dart                  Riverpod dependencies and observable state
    editor_host.dart                Load, import, save, export and Pro gates
  core/
    config/                         Integration flags
    media/                          Local source contracts, import and native bridge
    theme/, widgets/                Shared dark theme and adaptive widgets
  features/
    home/presentation/              Guest home and original template artwork
    photo_editor/domain/            Versioned recipe, layers and history
    photo_editor/data/              Bounded decoding, isolate filters, PNG compositor
    photo_editor/presentation/      Canvas and bottom editing toolbar
    video_editor/domain/            Timeline, history, render plan and contracts
    video_editor/data/              FFmpeg/FFprobe, progress and cancellation
    video_editor/presentation/      Timeline, tools and rendered preview
    templates/domain/, presentation/ Bundled catalog and category browsing
    projects/domain/, data/, presentation/ Local JSON storage and project library
    entitlements/domain/, data/, presentation/ Plans, expiry and simulator
    ads/domain/, application/, data/, presentation/ Consent, policy and no-op gateway
    settings/, roadmap/             Diagnostics, privacy, licenses and roadmap
android/app/src/main/
  kotlin/com/framelab/framelab/     Owned ONNX/MediaStore/storage bridge
  assets/models/                   U²-Net-P and notices
assets/fonts/                      Five local OFL fonts and notices
assets/licenses/                   Bundled native/model notices for offline UI
test/                              Domain, repository and widget tests
integration_test/                  Native media, codec and Android UI checks
test_driver/                       Host-side capture of Android UI screenshots
docs/, scripts/                    Handoff and reproducible checks
```

Feature domains contain recipes/contracts and avoid widget dependencies. Data adapters perform file, preferences, native and FFmpeg operations. Presentation owns local interaction state and bounded history. Riverpod owns repository injection and shared entitlement/project/ads state; `EditorHost` connects callbacks to app services. No code generation is required.

## Media flow

```text
Android picker -> app-private original -> versioned project recipe
                                                |
                     bounded preview <- editor/history -> autosave
                                                |
                           entitlement check -> local render job
                                                |
                                  temporary file -> MediaStore
```

Only user-selected local media is imported. Originals are copied into durable project assets instead of relying on transient picker access. Missing files trigger relinking. Pixels/audio never pass to account or ads interfaces. Channels carry paths and small arguments; video frames remain native.

Photo recipes store normalized crop/layer geometry, image/background paths, color adjustments, blur, filter, orientation and canvas size. Preview/export share the compositor. Raster transforms use `image` in a worker isolate; layer drawing uses Flutter Canvas and bundled fonts. Output is PNG with a 1920 px free / 4096 px Pro maximum edge.

Video recipes store source intervals, speed, clip order, crop/zoom, gain, filters/effects/transitions, timed text, one image-overlay track and one looped music track. Split references the original asset. `VideoRenderPlan` validates recipes and compiles argument arrays; captions use UTF-8 files with expansion disabled.

FFmpeg prepares looped music as a finite PCM WAV using the chosen offset and timeline duration, normalizes clips, joins with concat or `xfade`/`acrossfade`, adds text/overlay/music with the selected music gain, and checks output dimensions/duration with FFprobe. Preparing music separately prevents a looped demuxer from retaining the final composition session after encoding finishes. MPEG-4 intermediates reduce codec assumptions; final encoding tries H.264 MediaCodec then a reported software MPEG-4 fallback. A 480p rendered preview uses the same recipe as 720p/Pro 1080p export. Jobs run serially, superseded work is cancelled, and temporary media is released. This trades instant preview updates for predictable local processing. No Media3 backend is installed.

## Background removal

`NativeMediaService` calls Kotlin `LocalMediaBridge`, which validates private paths, bounds decoding, corrects EXIF orientation, runs bundled U²-Net-P through ONNX Runtime on a worker and returns a transparent PNG. The photo editor replaces its background with a color or image. Pro is checked before inference and at Pro export. No first-use download or inference server is involved.

General salient-object segmentation still needs quality testing on fine hair, glass, multiple subjects and low contrast. Automatic removal is implemented; a manual brush mask-refinement tool is not currently present.

## Projects and recovery

`LocalProjectRepository` stores a versioned JSON manifest plus separate assets per project. It serializes writes, flushes `project.pending`, retains `project.bak`, then promotes the pending file. Load tries current, backup and pending, validating schema, ID and size. Corrupt projects do not hide healthy ones. Validated IDs confine mutations to project directories; metadata is capped at 8 MB.

The implementation uses recoverable files instead of the earlier proposed SQLite database. There is no database setup. Future schema versions must add migrations before acceptance. Autosave and explicit save-before-leaving persist recipes; undo history stays in memory. The library provides search, kind filters, rename, reopen and delete. Android backup is disabled, and uninstall removes private projects.

## Entitlements and account boundary

`PremiumPlan` centralizes ₹39/month and ₹299/year. `EntitlementRepository` streams current/expired state; feature access is checked at selection and export. Future 4K and other future tools remain unavailable even with Pro.

The simulator sequence is Buy -> email syntax validation -> displayed six-digit test challenge -> simulated identity -> mock receipt/expiry. Codes expire after five minutes, have an attempt limit and cannot be reused. No email is sent and mailbox ownership is not verified. Restore reads this installation's test receipt; reset revokes it. Debug enables mock purchases; release requires `ENABLE_MOCK_PRO=true` explicitly.

`PurchaseGateway` models completion, cancellation, pending, failure and restore. `GooglePlayPurchaseGateway` is an unconfigured fail-closed placeholder, not a billing SDK. A future adapter must load store prices, validate/acknowledge purchases and replace simulated identity. Optional Supabase may implement verified Premium accounts only; guest editing and local files remain independent.

## Ads and resources

The no-op `AdGateway` is unconfigured and returns no creatives. `AdsCoordinator` checks placement, consent, configuration, connectivity and known non-Pro status both before and after loading. Editing/export placements are denied; errors cannot block editing. No ad network or SDK is included.

Flutter's image cache is capped at 48 MiB/80 entries. Photo decodes/layer pixels are bounded, preview work serialized and stale results discarded. FFmpeg uses bounded thread counts and one active job per renderer. Native inference releases tensor/bitmap resources on its worker. Import checks size/free storage. These controls are implemented; they do not constitute physical-device benchmarks. See [Phase 10](PHASE_10.md).
