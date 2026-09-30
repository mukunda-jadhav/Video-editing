# FrameLab 1.1.0-test — free tools and live editing

This update addresses slow brightness/size adjustments. Photo edits repaint cached image textures, and video adjustments/canvas/layers update the original native video without encoding a preview after each change. Timeline scrubbing seeks the source player directly.

All editing features are now free. Purchase, email verification, mock Pro, entitlements and advertising subsystems are removed. All 14 templates, five fonts, background removal, filters/effects/transitions, 4096px photo export and 720p/1080p video export remain available offline.

The dark home screen prioritizes New project and recent projects. The video editor keeps a preview, timeline and labelled bottom tools. Exact complex transitions/effects and mixed music use explicit composition preview; export always renders the complete recipe. Initial media decoding, segmentation and export still require processing time.

Choose app-arm64-v8a-release.apk for most phones, app-armeabi-v7a-release.apk for 32-bit phones, or app-x86_64-release.apk for the emulator. Android API24+ is required. SHA256SUMS.txt records asset digests. Version code3 and the unchanged test signing key allow an update of the earlier installation. Local projects survive a normal app update; uninstalling removes them.

This remains a test prerelease with development signing. Physical-device frame-rate, media-quality and store-release qualification remain open. Source, license notices and detailed checks are in the repository.

Validation: 137 unit/widget tests, five distinct Android checks, clean analysis, APK signature/ZIP/64-bit ELF16KB inspection and offline x86_64 release launch passed. Live gesture tests retained the native texture/player through eight frames and started zero video encoders.
