import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/entitlements/data/guest_entitlement_repository.dart';
import 'package:framelab/features/entitlements/domain/entitlement.dart';

void main() {
  final now = DateTime.utc(2026, 9, 28, 12);
  const policy = EntitlementPolicy();

  test(
    'guest repository provides Free without an account or purchase',
    () async {
      const repository = GuestEntitlementRepository();
      expect(repository.current.isProAt(now), isFalse);
      final entitlement = await repository.watch().first;
      expect(entitlement.source, EntitlementSource.guest);
      expect(entitlement.expiresAt, isNull);
      expect(policy.shouldShowAds(entitlement, now), isTrue);
      for (final feature in PremiumFeature.values) {
        expect(policy.allows(feature, entitlement, now), isFalse);
      }
    },
  );

  for (final source in [
    EntitlementSource.localMock,
    EntitlementSource.googlePlay,
  ]) {
    test(
      '$source Pro expires exactly at expiry, including feature and ads policy',
      () {
        final entitlement = Entitlement.pro(source: source, expiresAt: now);
        final before = now.subtract(const Duration(microseconds: 1));
        final after = now.add(const Duration(microseconds: 1));
        expect(entitlement.isProAt(before), isTrue);
        expect(entitlement.isProAt(now), isFalse);
        expect(entitlement.isProAt(after), isFalse);
        expect(
          policy.allows(PremiumFeature.backgroundRemoval, entitlement, before),
          isTrue,
        );
        expect(
          policy.allows(PremiumFeature.backgroundRemoval, entitlement, now),
          isFalse,
        );
        expect(policy.shouldShowAds(entitlement, before), isFalse);
        expect(policy.shouldShowAds(entitlement, now), isTrue);
      },
    );
  }

  test(
    'active Pro unlocks current benefits, but cannot unlock future tools',
    () {
      final entitlement = Entitlement.pro(
        source: EntitlementSource.localMock,
        expiresAt: now.add(const Duration(days: 30)),
      );
      for (final feature in PremiumFeature.values) {
        final future =
            feature == PremiumFeature.future4kExport ||
            feature == PremiumFeature.futureOnDeviceTools;
        expect(
          policy.allows(feature, entitlement, now),
          !future,
          reason: feature.name,
        );
      }
    },
  );

  test('plans retain the requested INR prices and billing periods', () {
    expect(PremiumPlan.monthly.pricePaise, 3900);
    expect(PremiumPlan.monthly.interval, PlanInterval.month);
    expect(PremiumPlan.monthly.priceLabel, '₹39/month');
    expect(PremiumPlan.yearly.pricePaise, 29900);
    expect(PremiumPlan.yearly.interval, PlanInterval.year);
    expect(PremiumPlan.yearly.priceLabel, '₹299/year');
    expect(PremiumPlan.monthly.id, isNot(PremiumPlan.yearly.id));
  });
}
