import '../../entitlements/domain/entitlement.dart';

/// Only an explicit contextual opt-in is supported. No identifiers or media
/// are passed to an ad adapter. Add a jurisdiction-aware consent adapter before
/// integrating a real SDK; the default build has no SDK or ad requests.
enum AdConsent { unknown, denied, contextual }

enum AdPlacement { home, projects, editor, timeline, export }

class AdCreative {
  const AdCreative({required this.title, required this.body});
  final String title;
  final String body;
}

abstract interface class AdGateway {
  bool get isConfigured;
  Future<AdCreative?> load(AdPlacement placement);
  Future<void> dispose();
}

class AdPlacementPolicy {
  const AdPlacementPolicy();

  bool allows({
    required AdPlacement placement,
    required AdConsent consent,
    required Entitlement? entitlement,
    required DateTime now,
    required bool configured,
    required bool online,
  }) =>
      configured &&
      online &&
      consent == AdConsent.contextual &&
      entitlement != null &&
      !entitlement.isProAt(now) &&
      (placement == AdPlacement.home || placement == AdPlacement.projects);
}
