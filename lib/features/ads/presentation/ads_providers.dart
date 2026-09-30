import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/providers.dart';
import '../application/ads_coordinator.dart';
import '../data/ad_consent_repository.dart';
import '../data/no_op_ad_gateway.dart';
import '../domain/ad_gateway.dart';

final adGatewayProvider = Provider<AdGateway>((ref) => const NoOpAdGateway());
// Fail closed. A future connectivity adapter can override this, after a real
// SDK has been configured. Editing itself never depends on connectivity.
final adsOnlineProvider = Provider<bool>((ref) => false);
final adConsentRepositoryProvider = Provider<AdConsentRepository>(
  (ref) => AdConsentRepository(PreferencesAdConsentStorage()),
);
final adConsentProvider = FutureProvider<AdConsent>(
  (ref) => ref.watch(adConsentRepositoryProvider).load(),
);
final adsCoordinatorProvider = Provider<AdsCoordinator>((ref) {
  final repository = ref.watch(entitlementRepositoryProvider);
  final online = ref.watch(adsOnlineProvider);
  final coordinator = AdsCoordinator(
    gateway: ref.watch(adGatewayProvider),
    consent: ref.watch(adConsentRepositoryProvider),
    entitlement: () => repository.current,
    online: () => online,
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});
final workspaceAdProvider = FutureProvider.autoDispose
    .family<AdCreative?, AdPlacement>((ref, placement) async {
      ref.watch(entitlementProvider);
      final ready = ref.watch(adConsentProvider.future);
      final coordinator = ref.watch(adsCoordinatorProvider);
      await ready;
      return coordinator.load(placement);
    });
