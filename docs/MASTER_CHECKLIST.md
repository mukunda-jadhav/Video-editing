# Master delivery checklist

Updated 30 September 2026. Code is present for all ten phases. A checked implementation item means the code/flow exists, not that every Android device or release condition has passed. Actual run evidence is kept in [TESTING.md](TESTING.md); open release/device gates remain visible below. The earlier Phase 1 report is historical.

## Global requirements

- [x] Guest launch and free editing without signup.
- [x] Email form only after Buy; explicitly simulated local verification and no charges.
- [x] Central prices: ₹39/month and ₹299/year.
- [x] No paid AI/API, media upload, remote model/font download at runtime or mandatory backend.
- [x] Offline-first recipes, local originals, local photo/video rendering and on-device removal.
- [x] Riverpod, feature/domain/data/presentation separation and centralized access policy.
- [x] Complete editable code and a source-snapshot exporter.
- [x] [Complete source snapshot](COMPLETE_SOURCE.md) regenerated after final implementation changes: 111 source/configuration/notice files.
- [x] Dependencies, setup, changed-file inventories and test steps for every phase.
- [x] Supabase kept optional and absent; future verified-account adapter does not receive media.
- [ ] Production verification, billing, live ads, store setup and release/device qualification, if shipping publicly.

## 1. Architecture + home — implemented

- [x] Flutter Android scaffold, API 24 minimum, dark splash and original launcher icon.
- [x] Clean feature boundaries, Riverpod dependencies, GoRouter navigation and Android back handling.
- [x] Responsive dark guest home, Home / Projects / Pro shell, template browsing and settings.
- [x] Real editor routes, project empty/loading/error/retry states and development roadmap.
- [x] Entitlement/purchase/media contracts, central prices and future capability policy.
- [x] Guest navigation, layout, reduced-motion and entitlement tests.
- [x] Historical Phase 1 build/emulator evidence preserved and clearly scoped to that build.

## 2. Photo editor — implemented

- [x] Local picker/import, private originals, bounded decoding and orientation handling.
- [x] Crop, rotate, flip, resize, brightness, contrast, saturation and exposure.
- [x] Free/Pro filters and blur.
- [x] Editable text, local fonts, shapes/stickers and image layers; select/move/resize/rotate/reorder.
- [x] Undo/redo, background color/image replacement and social-media presets.
- [x] Shared local preview/export compositor; free PNG up to 1920 px, Pro up to 4096 px.
- [x] Document, renderer and interaction/layout regression tests.
- [ ] Broad real-photo/EXIF/color-format and Android picker/export device matrix.

## 3. Video editor — implemented; Android emulator media checks passed

- [x] Local clip import, probing, labelled clip timeline and reordering.
- [x] Trim, split, merge, crop/resize and canvas presets.
- [x] 0.25–4× speed, mute/volume and local music controls with offset/looping.
- [x] Resolve the native looped-music completion timeout; six native composition variants passed, including audible looped music and wrapped offsets.
- [x] Timed text, filters and timed image overlay.
- [x] Rendered 480p preview and 720p/Pro 1080p export through the same recipe.
- [x] Progress, cancellation, disk cleanup, FFprobe output checks and codec fallback reporting.
- [x] Future 4K capability represented but unavailable, as requested.
- [x] Domain/render-plan/editor-widget tests and three passing native Android media tests.
- [x] Emulator 720p/portrait 1080p output, combined music/captions/overlay, publication, cancellation, cleanup and validated software fallback.
- [ ] Complete native/device playback, codec, synchronization and long-project evidence.

The timeline uses labelled cards; extracted frame thumbnails mentioned in the earlier planning checklist are not implemented. There is one music track and one image-overlay track. Requested timeline, music and overlay operations are present.

## 4. Transitions/effects — implemented

- [x] Cut plus real dissolve/wipe/slide/circle overlaps using FFmpeg xfade/acrossfade.
- [x] Adjacent-clip duration constraints and correct overlap contribution to total duration.
- [x] Basic video effects and free/Pro filters, effects and transition access gates.
- [x] Shared preview/export render plan and overlap/variant tests.
- [x] Every enabled transition/filter/effect executed in the emulator media suite.
- [ ] Rendered boundary/audio-sync quality across real media and the physical-device/codec matrix.

## 5. Templates — implemented

- [x] Instagram posts, Stories, Reels, YouTube thumbnails and product ads.
- [x] Festival and business posters; 14 designs, 5 free and 9 Pro.
- [x] Editable text, images, colors and layout through photo/video recipe routes.
- [x] Bundled fonts/notices, original code-drawn artwork and local catalog recipes.
- [x] Catalog/round-trip/access tests; shared save/export paths and export-time Pro checks.
- [ ] Device visual/readability/export review of every design.

## 6. Background remover — implemented, device qualification pending

- [x] General salient-object U²-Net-P ONNX model bundled for offline first use.
- [x] Kotlin worker, bounded decode, EXIF handling, inference, transparent PNG and cancellation.
- [x] Pro gating and replacement/background/export integration.
- [x] Model source, hash and notices documented; no upload/API key.
- [x] Actual bundled-model inference, alpha variation, PNG dimensions and MediaStore publication passed on the emulator.
- [ ] Record latency/peak memory and mask quality on physical-device portraits/products/hair/low contrast.

Automatic removal is implemented. Manual brush mask refinement appeared in the earlier planning checklist but is not a current tool or a claimed feature.

## 7. Project save/load — implemented

- [x] Versioned JSON project manifests and app-private durable asset directories.
- [x] Serialized atomic pending/current/backup writes and recovery.
- [x] Photo/video/template autosave, save-before-leaving and reopen.
- [x] Search, kind filters, rename, delete and missing-media relinking.
- [x] Invalid ID/schema/oversized or corrupt metadata handling and isolated project failures.
- [x] Storage and template round-trip/corruption/recovery regression tests.
- [ ] Process kill, disk-full and interruption testing on Android.

Storage uses recoverable files rather than the database suggested earlier. Undo history is session-local; recipes persist. Future schema versions need migrations before being accepted.

## 8. Premium/mock entitlement — implemented

- [x] Monthly/yearly plans at exact requested prices; Buy triggers email form.
- [x] Displayed local test code, expiry/attempt limits and clear simulated-verification wording.
- [x] Persist, expire, reset/revoke and restore this installation's local test entitlement.
- [x] Mock disabled by default in release; private test builds can explicitly opt in.
- [x] Replaceable purchase/account contracts and fail-closed unconfigured Google Play adapter.
- [x] Central gates for no ads, full templates, Pro filters/effects/transitions, remover, quality, fonts/stickers.
- [x] Future 4K/additional on-device tools remain unavailable even with Pro.
- [x] Repository, verification, entitlement and checkout UI tests.
- [ ] Real Google Play Billing and genuine mailbox verification when configured in the future.

## 9. Ads architecture — implemented

- [x] No-op offline gateway; no ad SDK, request or banner in the default build.
- [x] Consent repository, configuration/connectivity gates and known-entitlement checks.
- [x] Pro suppression before/after loading and safe late-result disposal.
- [x] Home/Projects-only policy; editing/export cannot be interrupted.
- [x] Duplicate-load coalescing, failure isolation and settings consent controls.
- [x] Policy, consent failure, late-result, error and disposal tests.
- [ ] Provider-specific consent/lifecycle/backoff and device tests only if a live SDK is configured.

## 10. Production optimization — controls implemented, qualification open

- [x] Image cache 48 MiB/80 entries; bounded source/layer decoding and worker raster processing.
- [x] Serialized preview/FFmpeg/native jobs, stale-result disposal, bounded threads and cancellation.
- [x] Import/storage guards, output validation, temporary-file cleanup and local diagnostics.
- [x] Adaptive small/landscape/large-text UI, reduced-motion handling and semantic labels.
- [x] Offline license registry, asset hashes and dependency/distribution documentation.
- [x] Reproducible format/analyze/test/build commands, native-library alignment inspector and complete source exporter.
- [x] Final full unit/widget suite: 167 tests passed on 30 September 2026.
- [x] Source formatting and static analysis passed without issues.
- [x] Three-test Android media suite passed on API 37 with 16 KB pages; native output, looped music and software fallback verified.
- [x] Android guest/template/photo/video route smoke passed.
- [x] Host PNG captures preserved; home, photo-template canvas and empty video editor visually reviewed on the emulator.
- [x] Three main-app release-mode test APKs built with explicit local mock Pro and Android debug signing; sizes/digests recorded.
- [x] APK signatures and ZIP alignment verified; 64-bit native ELF 16 KB alignment passed.
- [x] x86_64 release APK installed/cold-launched offline and its home visually reviewed on the 16 KB emulator.
- [ ] Physical low/mid/high Android profiles: launch, frame timings, peak RAM, export time, thermal/battery and size.
- [ ] Low-memory/storage, background/foreground, cancellation and process-death device tests.
- [ ] TalkBack and real-device accessibility/media-quality review.
- [ ] Physical ARM device/native release-mode media qualification and release distribution obligations.
- [ ] Final application ID/signing, store/data-safety configuration and production service adapters if publishing.

## Handoff per phase

- [x] Reports [1](PHASE_01.md), [2](PHASE_02.md), [3](PHASE_03.md), [4](PHASE_04.md), [5](PHASE_05.md), [6](PHASE_06.md), [7](PHASE_07.md), [8](PHASE_08.md), [9](PHASE_09.md), [10](PHASE_10.md) list files, code location, dependencies, setup, tests and limits.
- [x] README, architecture, dependency/asset inventory and current master checklist supplied.
- [x] Actual validation evidence separated from instructions and future release gates.
- [ ] All native/physical-device release gates passed before labelling the app production ready.
