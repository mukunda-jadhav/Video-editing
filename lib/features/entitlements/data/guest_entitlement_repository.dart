import '../domain/entitlement.dart';

/// Guest access without network I/O or account checks.
class GuestEntitlementRepository implements EntitlementRepository {
  const GuestEntitlementRepository();
  @override
  Entitlement get current => const Entitlement.free();
  @override
  Stream<Entitlement> watch() => Stream.value(current);
}
