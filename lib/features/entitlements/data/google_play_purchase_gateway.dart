import '../domain/entitlement.dart';
import '../domain/purchase_gateway.dart';

/// Safe replacement boundary. No store SDK is linked until Play configuration,
/// purchase acknowledgement and authoritative receipt verification exist.
class GooglePlayPurchaseGateway implements PurchaseGateway {
  const GooglePlayPurchaseGateway();
  @override
  Future<PurchaseOutcome> purchase(
    PremiumPlan plan,
    VerifiedPremiumAccount account,
  ) async => const PurchaseOutcome(
    status: PurchaseStatus.failed,
    message: 'Google Play Billing is not configured. No purchase was made.',
  );
  @override
  Future<PurchaseOutcome> restore(VerifiedPremiumAccount account) async =>
      const PurchaseOutcome(
        status: PurchaseStatus.failed,
        message: 'Google Play restore is not configured.',
      );
}
