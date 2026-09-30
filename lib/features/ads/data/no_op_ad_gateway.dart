import '../domain/ad_gateway.dart';

/// Shipping default: no SDK, network traffic, tracking, ads or editor popups.
class NoOpAdGateway implements AdGateway {
  const NoOpAdGateway();
  @override
  bool get isConfigured => false;
  @override
  Future<AdCreative?> load(AdPlacement placement) async => null;
  @override
  Future<void> dispose() async {}
}
