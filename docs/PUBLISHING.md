# FrameLab 1.2.0-test publication

The [1.2 release](https://github.com/mukunda-jadhav/Video-editing/releases/tag/v1.2.0-test) is public. All three APKs and the checksum file returned HTTP 200 without authentication; sizes and GitHub SHA-256 digests match local artifacts. See [PUBLISHED_RELEASE.json](PUBLISHED_RELEASE.json).

| Asset | Bytes | SHA256 |
|---|---:|---|
| app-arm64-v8a-release.apk | 86731749 | `1d0091621a8fe0e28a0502fe2b8fab18a63f4c65c973ce35c8b2ed561897124a` |
| app-armeabi-v7a-release.apk | 97782789 | `42a255528d930c6da734e9bf0d020682d1af0c460ed49ce258cde447d13190cf` |
| app-x86_64-release.apk | 97299196 | `6830eb69683bc2d5c632d3cb9dbe001766e8e592cd5c3201a1a9e55c7a70a23a` |

The APKs use the existing development signing key. Base version code is 4; ARM64 is 2004, ARMv7 is 1004 and x86_64 is 4004. Install over the previous matching-ABI version to retain local projects; uninstalling removes private projects.

All signatures, ZIP alignment and 64-bit ELF 16 KB checks passed: [RELEASE_APK_REPORT.json](RELEASE_APK_REPORT.json). Offline x86_64 release launch also passed: [CANVAS_ANDROID_RELEASE.json](CANVAS_ANDROID_RELEASE.json). This is a test prerelease; physical-phone/store qualification and release-mode editing acceptance remain open. [Test scope and commands](TESTING.md).
