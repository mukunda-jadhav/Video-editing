> Historical phase record. [Version1.1](REALTIME_UPDATE.md) replaces subscription/ads code with free access and replaces slow per-edit preview processing.

# Phase 9 — Ads architecture

Status: **No-op offline gateway, consent/policy and Pro suppression implemented. No real ads or ad requests are configured.**

## Implementation

Added an isolated `AdGateway`, consent storage/repository, placement policy and coordinator. Only Home/Projects are eligible; editor/timeline/export placements are denied. Unknown entitlement, denied/unknown consent, offline or unconfigured adapters fail closed. Pro is checked before and after load, concurrent duplicate loads are coalesced, and load/disposal failures do not interrupt free use. Preferences explain/reset the local consent choice. The current gateway returns no creative.

## Files added or changed

- `lib/features/ads/domain/ad_gateway.dart`
- `lib/features/ads/data/no_op_ad_gateway.dart`
- `lib/features/ads/data/ad_consent_repository.dart`
- `lib/features/ads/application/ads_coordinator.dart`
- `lib/features/ads/presentation/ads_providers.dart`
- `lib/features/ads/presentation/ads_widgets.dart`
- `lib/features/settings/presentation/settings_screen.dart`
- `lib/features/home/presentation/home_screen.dart`
- `lib/features/projects/presentation/projects_screen.dart`
- `test/ads_architecture_test.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Reuses `shared_preferences` and Riverpod. No ad SDK, network credentials or paid API is installed. No extra setup is necessary.

## Testing

Run `flutter test test/ads_architecture_test.dart`. Tests exercise Pro/expired/unknown entitlement, consent/configuration/connectivity, denied placements, duplicate loads, errors and late results after Pro activation. On Android confirm no banners, downloads or ad interruptions appear in the default build, including offline.

## Limits and remaining checks

Consent architecture is not a production jurisdiction-aware consent integration. Add a real SDK/consent adapter and provider-specific lifecycle/backoff tests only when configuring live ads. The no-op gateway does not earn advertising revenue.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
