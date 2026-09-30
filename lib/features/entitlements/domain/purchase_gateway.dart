import 'entitlement.dart';

/// Contract shared by the local simulator and a future Play Billing adapter.
/// Signup/verification is initiated only after explicit purchase intent.
abstract interface class PurchaseGateway {
  Future<PurchaseOutcome> purchase(
    PremiumPlan plan,
    VerifiedPremiumAccount account,
  );
  Future<PurchaseOutcome> restore(VerifiedPremiumAccount account);
}

/// Produced by the verification adapter, not by merely entering an email.
class VerifiedPremiumAccount {
  const VerifiedPremiumAccount({
    required this.accountId,
    required this.isSimulated,
  });
  final String accountId;
  final bool isSimulated;
}

enum PurchaseStatus { completed, cancelled, pending, failed }

class PurchaseOutcome {
  const PurchaseOutcome({required this.status, this.entitlement, this.message});
  final PurchaseStatus status;
  final Entitlement? entitlement;
  final String? message;
}
