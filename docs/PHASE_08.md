# Phase 8 — Premium and local mock entitlement

Status: **Local test checkout, persistence, expiry, restore/reset and feature gates implemented. Real billing/email are intentionally unconfigured.**

## Implementation

Central plans are ₹39/month and ₹299/year. Guest launch and all free editing remain account-free. Buy opens the email form and explicitly simulated verification flow; a six-digit code is displayed locally, expires after five minutes and has attempt limits. Successful local purchase creates a calendar-month/year expiry. Restore reads this installation's test receipt, reset revokes it and expired/corrupt receipts fail closed. The Pro state gates templates, filters/effects/transitions, background removal, export quality, extra fonts/stickers and ads. Future 4K/tools stay denied.

## Files added or changed

- `lib/features/entitlements/domain/entitlement.dart`
- `lib/features/entitlements/domain/purchase_gateway.dart`
- `lib/features/entitlements/data/local_mock_entitlement_repository.dart`
- `lib/features/entitlements/data/local_premium_verification_service.dart`
- `lib/features/entitlements/data/google_play_purchase_gateway.dart`
- `lib/features/entitlements/data/guest_entitlement_repository.dart`
- `lib/features/entitlements/presentation/premium_screen.dart`
- `lib/app/providers.dart`
- `lib/app/editor_host.dart`
- `lib/main.dart`
- `test/entitlement_test.dart`
- `test/premium_repository_test.dart`
- `test/premium_verification_test.dart`
- `test/premium_screen_test.dart`

## Complete code and setup

The files above are complete editable code, not snippets. The [full source snapshot](COMPLETE_SOURCE.md) includes all maintained text source/configuration; binary assets remain in their project folders. Run `flutter pub get`, then `flutter run -d <android-device-id>` from the project root. No API key or account setup is required. See [README](../README.md) for toolchain setup and [dependencies](DEPENDENCIES.md) for exact pins.

## Dependencies and phase setup

Adds `shared_preferences` for a local test receipt. Debug enables the simulator. Private release-mode tests can opt in with `--dart-define=ENABLE_MOCK_PRO=true`; ordinary release disables it. No store products, API key, email service or Supabase configuration is needed.

## Testing

Run `flutter test test/entitlement_test.dart test/premium_repository_test.dart test/premium_verification_test.dart test/premium_screen_test.dart`. Check no form appears before Buy, exact plan prices, invalid email/code errors, expiry/retry/attempt limit, monthly/yearly end dates, failed persistence, restore/reset and future-feature denial. Relaunch Android after activation/reset and verify gates.

## Limits and remaining checks

Displayed test codes do not prove email ownership; local preferences are not payment security. `GooglePlayPurchaseGateway` fails closed until a real adapter is supplied. A real integration needs store-provided prices, purchase listening, validation/acknowledgement, restore and real account verification. Supabase remains optional and absent.

[Master checklist](MASTER_CHECKLIST.md) · [Actual validation results](TESTING.md)
