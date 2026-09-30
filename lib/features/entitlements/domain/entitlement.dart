enum PremiumFeature {
  allTemplates,
  premiumFilters,
  premiumEffects,
  premiumTransitions,
  backgroundRemoval,
  higherQualityExport,
  extraFontsAndStickers,
  future4kExport,
  futureOnDeviceTools,
}

enum PlanInterval { month, year }

/// Prices use integer paise. Play Billing will supply localized prices later.
class PremiumPlan {
  const PremiumPlan({
    required this.id,
    required this.interval,
    required this.pricePaise,
  });
  final String id;
  final PlanInterval interval;
  final int pricePaise;
  String get priceLabel => '₹${pricePaise ~/ 100}/${interval.name}';
  static const monthly = PremiumPlan(
    id: 'pro_monthly',
    interval: PlanInterval.month,
    pricePaise: 3900,
  );
  static const yearly = PremiumPlan(
    id: 'pro_yearly',
    interval: PlanInterval.year,
    pricePaise: 29900,
  );
  static const values = [monthly, yearly];
}

enum EntitlementSource { guest, localMock, googlePlay }

class Entitlement {
  const Entitlement.free() : source = EntitlementSource.guest, expiresAt = null;
  const Entitlement.pro({
    required this.source,
    required DateTime this.expiresAt,
  }) : assert(source != EntitlementSource.guest);
  final EntitlementSource source;
  final DateTime? expiresAt;
  bool isProAt(DateTime now) =>
      source != EntitlementSource.guest && (expiresAt?.isAfter(now) ?? false);
}

/// Editors must check this again at export, independently of feature readiness.
class EntitlementPolicy {
  const EntitlementPolicy();
  bool allows(PremiumFeature feature, Entitlement entitlement, DateTime now) {
    if (feature == PremiumFeature.future4kExport ||
        feature == PremiumFeature.futureOnDeviceTools) {
      return false;
    }
    return entitlement.isProAt(now);
  }

  bool shouldShowAds(Entitlement entitlement, DateTime now) =>
      !entitlement.isProAt(now);
}

abstract interface class EntitlementRepository {
  Entitlement get current;
  Stream<Entitlement> watch();
}
