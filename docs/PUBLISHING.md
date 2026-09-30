# FrameLab 1.1.0-test publication

Free real-time editing update; release assets prepared for [v1.1.0-test](https://github.com/mukunda-jadhav/Video-editing/releases/tag/v1.1.0-test). The release is public; all four anonymous downloads returned HTTP 200 with matching sizes and SHA-256 digests. Verification is recorded in [PUBLISHED_RELEASE.json](PUBLISHED_RELEASE.json).

| Asset | Bytes | SHA256 |
|---|---:|---|
| app-arm64-v8a-release.apk | 86402517 | `af2980f41b317ad13ae02e0cec2221c58bff49ea669f73b7e2ec0533f56aac52` |
| app-armeabi-v7a-release.apk | 97420789 | `6d6ca5836172bfadd311e3f83233bf43b071d4b42448b7d337ae27bfbbb33aa5` |
| app-x86_64-release.apk | 96904428 | `f188702adad15bfc66464cff7473d8160746ffaac11a2b949fe894f722744783` |

APKs use the existing development signing key and version code 3. The build has no purchase/verification/ads configuration. A normal update keeps local projects; uninstalling removes app-private projects.

Signature, ZIP and 64-bit ELF 16 KB alignment checks passed. Complete binary inspection is in [RELEASE_APK_REPORT.json](RELEASE_APK_REPORT.json); tests and remaining acceptance limits are in [REALTIME_UPDATE.md](REALTIME_UPDATE.md) and [TESTING.md](TESTING.md). This is a test prerelease, with physical-device/store qualification still open.
