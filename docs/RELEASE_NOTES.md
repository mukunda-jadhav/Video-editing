# FrameLab v1.0.0-test

First public test prerelease of the offline Flutter Android photo/video/template studio. Free editing needs no account; media processing, projects, fonts and the background-removal model stay on the device.

Includes crop/adjustments/filters/text/stickers/background replacement and HD photo export; video trim/split/merge/crop/speed/audio/music/text/overlays/filters/effects/transitions and 720p/1080p export; 14 editable templates; local save/recovery; on-device U²-Net-P background removal; centralized mock Pro and ads architecture.

Download app-arm64-v8a-release.apk for most phones, app-armeabi-v7a-release.apk for 32-bit ARM phones, or app-x86_64-release.apk for the emulator. Android API 24+ is required. SHA256SUMS.txt contains download digests.

These APKs enable mock Pro (₹39/month and ₹299/year shown for testing) and use an Android debug test signing key. No charges are made; email verification is simulated locally. Real Google Play Billing/email verification/live ads are not configured. 4K video and additional Premium on-device tools remain future capabilities.

Validation: 167 unit/widget tests and 4 Android integration checks passed on an API 37/16 KB emulator. APK signatures and ZIP/64-bit ELF alignment passed; the x86_64 main release launched offline. Native editing tests used debug builds. Physical-device performance, media quality, accessibility and release-mode editing qualification remain open.

Bundled model/fonts/native runtimes are open-source; licenses/provenance and source links are in docs/DEPENDENCIES.md, assets/licenses, assets/fonts, android/app/src/main/assets/models and the app's offline license screen. See README and docs/MASTER_CHECKLIST.md for setup and remaining public-store release work.
