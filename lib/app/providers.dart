import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/entitlements/data/guest_entitlement_repository.dart';
import '../features/entitlements/domain/entitlement.dart';
import '../features/projects/data/empty_project_repository.dart';
import '../features/projects/domain/project_repository.dart';
import '../features/projects/domain/project_document.dart';
import '../core/media/native_media_service.dart';
import '../core/media/media_import_service.dart';

/// Composition root: swap adapters without changing feature UI.
final entitlementRepositoryProvider = Provider<EntitlementRepository>(
  (ref) => const GuestEntitlementRepository(),
);
final entitlementProvider = StreamProvider<Entitlement>(
  (ref) => ref.watch(entitlementRepositoryProvider).watch(),
);
final entitlementPolicyProvider = Provider((ref) => const EntitlementPolicy());
final projectRepositoryProvider = Provider<ProjectRepository>(
  (ref) => const EmptyProjectRepository(),
);
final recentProjectsProvider = FutureProvider<List<ProjectSummary>>(
  (ref) => ref.watch(projectRepositoryProvider).listRecent(),
  retry: (count, error) => null,
);

final projectStoreProvider = Provider<ProjectStore>((ref) {
  final repository = ref.watch(projectRepositoryProvider);
  return repository is ProjectStore ? repository : EphemeralProjectStore();
});
final nativeMediaServiceProvider = Provider(
  (ref) => const NativeMediaService(),
);
final mediaImportServiceProvider = Provider(
  (ref) => MediaImportService(
    ref.watch(projectStoreProvider),
    ref.watch(nativeMediaServiceProvider),
  ),
);
