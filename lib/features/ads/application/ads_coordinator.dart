import '../../entitlements/domain/entitlement.dart';
import '../data/ad_consent_repository.dart';
import '../domain/ad_gateway.dart';

/// Calls a replaceable gateway only after all gates pass, and checks them again
/// when a request completes (a Pro purchase/revocation may happen in between).
class AdsCoordinator {
  AdsCoordinator({
    required this.gateway,
    required this.consent,
    required Entitlement? Function() entitlement,
    required bool Function() online,
    DateTime Function()? clock,
    this.policy = const AdPlacementPolicy(),
  }) : _entitlement = entitlement,
       _online = online,
       _clock = clock ?? DateTime.now;

  final AdGateway gateway;
  final AdConsentRepository consent;
  final AdPlacementPolicy policy;
  final Entitlement? Function() _entitlement;
  final bool Function() _online;
  final DateTime Function() _clock;
  final Set<AdPlacement> _inFlight = {};
  bool _disposed = false;

  bool canShow(AdPlacement placement) {
    if (_disposed) return false;
    try {
      return policy.allows(
        placement: placement,
        consent: consent.current,
        entitlement: _entitlement(),
        now: _clock(),
        configured: gateway.isConfigured,
        online: _online(),
      );
    } on Object {
      return false; // Unknown entitlement/connectivity fails closed.
    }
  }

  Future<AdCreative?> load(AdPlacement placement) async {
    await consent.load();
    if (!canShow(placement) || !_inFlight.add(placement)) return null;
    try {
      final creative = await gateway.load(placement);
      return canShow(placement) ? creative : null;
    } on Object {
      return null; // Ads never block guest editing or navigation.
    } finally {
      _inFlight.remove(placement);
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await gateway.dispose();
    } on Object {
      /* Non-critical adapter. */
    }
  }
}
