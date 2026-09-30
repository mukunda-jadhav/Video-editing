import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/ads/application/ads_coordinator.dart';
import 'package:framelab/features/ads/data/ad_consent_repository.dart';
import 'package:framelab/features/ads/data/no_op_ad_gateway.dart';
import 'package:framelab/features/ads/domain/ad_gateway.dart';
import 'package:framelab/features/entitlements/domain/entitlement.dart';

class _MemoryConsent implements AdConsentStorage {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('unavailable');
    return value;
  }

  @override
  Future<void> write(String next) async {
    if (failWrite) throw StateError('unavailable');
    value = next;
  }
}

class _TestGateway implements AdGateway {
  bool configured = true;
  bool fail = false;
  bool disposed = false;
  int loads = 0;
  Completer<AdCreative?>? pending;
  @override
  bool get isConfigured => configured;
  @override
  Future<AdCreative?> load(AdPlacement placement) async {
    loads++;
    if (fail) throw StateError('ad adapter failed');
    return pending == null
        ? const AdCreative(title: 'Test ad', body: 'Contextual test')
        : pending!.future;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  late _MemoryConsent storage;
  late AdConsentRepository consent;
  late _TestGateway gateway;
  late AdsCoordinator coordinator;
  late DateTime now;
  late Entitlement? entitlement;
  late bool online;
  setUp(() {
    storage = _MemoryConsent();
    consent = AdConsentRepository(storage);
    gateway = _TestGateway();
    now = DateTime.utc(2026, 9, 29);
    entitlement = const Entitlement.free();
    online = true;
    coordinator = AdsCoordinator(
      gateway: gateway,
      consent: consent,
      entitlement: () => entitlement,
      online: () => online,
      clock: () => now,
    );
  });
  tearDown(() => coordinator.dispose());

  test('no-op gateway is unconfigured and produces no inventory', () async {
    const noOp = NoOpAdGateway();
    expect(noOp.isConfigured, isFalse);
    for (final placement in AdPlacement.values) {
      expect(await noOp.load(placement), isNull);
    }
  });

  test('unknown or denied consent never calls the gateway', () async {
    expect(await coordinator.load(AdPlacement.home), isNull);
    await consent.setConsent(AdConsent.denied);
    expect(await coordinator.load(AdPlacement.projects), isNull);
    expect(gateway.loads, 0);
  });

  test(
    'only Home and Projects are eligible with explicit contextual consent',
    () async {
      await consent.setConsent(AdConsent.contextual);
      for (final placement in AdPlacement.values) {
        final creative = await coordinator.load(placement);
        expect(
          creative != null,
          placement == AdPlacement.home || placement == AdPlacement.projects,
          reason: placement.name,
        );
      }
      expect(gateway.loads, 2);
    },
  );

  test('Pro suppresses requests until exact expiry', () async {
    await consent.setConsent(AdConsent.contextual);
    final expiry = now.add(const Duration(hours: 1));
    entitlement = Entitlement.pro(
      source: EntitlementSource.localMock,
      expiresAt: expiry,
    );
    expect(await coordinator.load(AdPlacement.home), isNull);
    expect(gateway.loads, 0);
    now = expiry;
    expect(await coordinator.load(AdPlacement.home), isNotNull);
    expect(gateway.loads, 1);
  });

  test(
    'unknown entitlement, offline mode and unconfigured gateways fail closed',
    () async {
      await consent.setConsent(AdConsent.contextual);
      entitlement = null;
      expect(await coordinator.load(AdPlacement.home), isNull);
      entitlement = const Entitlement.free();
      online = false;
      expect(await coordinator.load(AdPlacement.home), isNull);
      online = true;
      gateway.configured = false;
      expect(await coordinator.load(AdPlacement.home), isNull);
      expect(gateway.loads, 0);
    },
  );

  test('purchasing Pro during load discards the late ad', () async {
    await consent.setConsent(AdConsent.contextual);
    gateway.pending = Completer<AdCreative?>();
    final load = coordinator.load(AdPlacement.home);
    await Future<void>.delayed(Duration.zero);
    entitlement = Entitlement.pro(
      source: EntitlementSource.localMock,
      expiresAt: now.add(const Duration(days: 30)),
    );
    gateway.pending!.complete(const AdCreative(title: 'Late', body: 'Hidden'));
    expect(await load, isNull);
  });

  test('revoking consent during load discards the late ad', () async {
    await consent.setConsent(AdConsent.contextual);
    gateway.pending = Completer<AdCreative?>();
    final load = coordinator.load(AdPlacement.home);
    await Future<void>.delayed(Duration.zero);
    await consent.setConsent(AdConsent.denied);
    gateway.pending!.complete(const AdCreative(title: 'Late', body: 'Hidden'));
    expect(await load, isNull);
  });

  test(
    'concurrent same-slot loads are deduplicated and errors do not block editing',
    () async {
      await consent.setConsent(AdConsent.contextual);
      gateway.pending = Completer<AdCreative?>();
      final first = coordinator.load(AdPlacement.home);
      await Future<void>.delayed(Duration.zero);
      expect(await coordinator.load(AdPlacement.home), isNull);
      gateway.pending!.complete(null);
      expect(await first, isNull);
      expect(gateway.loads, 1);
      gateway.pending = null;
      gateway.fail = true;
      expect(await coordinator.load(AdPlacement.home), isNull);
      gateway.fail = false;
      expect(await coordinator.load(AdPlacement.home), isNotNull);
    },
  );

  test('disposal prevents new ads and discards pending work', () async {
    await consent.setConsent(AdConsent.contextual);
    gateway.pending = Completer<AdCreative?>();
    final load = coordinator.load(AdPlacement.home);
    await Future<void>.delayed(Duration.zero);
    await coordinator.dispose();
    gateway.pending!.complete(const AdCreative(title: 'Late', body: 'Hidden'));
    expect(await load, isNull);
    expect(await coordinator.load(AdPlacement.home), isNull);
    expect(gateway.disposed, isTrue);
  });

  test('consent survives restart and cached loads reflect changes', () async {
    expect(await consent.load(), AdConsent.unknown);
    await consent.setConsent(AdConsent.contextual);
    expect(await consent.load(), AdConsent.contextual);
    expect(await AdConsentRepository(storage).load(), AdConsent.contextual);
    await consent.setConsent(AdConsent.denied);
    expect(await consent.load(), AdConsent.denied);
    expect(await AdConsentRepository(storage).load(), AdConsent.denied);
  });

  test('storage errors and unknown schema never imply consent', () async {
    storage.failRead = true;
    expect(await consent.load(), AdConsent.unknown);
    storage.failRead = false;
    storage.value = 'personalized-from-future';
    expect(await AdConsentRepository(storage).load(), AdConsent.unknown);
    storage.failWrite = true;
    await expectLater(
      consent.setConsent(AdConsent.contextual),
      throwsStateError,
    );
    expect(consent.current, AdConsent.unknown);
  });

  test('failed revoke still suppresses ads in this session', () async {
    await consent.setConsent(AdConsent.contextual);
    storage.failWrite = true;
    await expectLater(consent.setConsent(AdConsent.denied), throwsStateError);
    expect(consent.current, AdConsent.denied);
    expect(await coordinator.load(AdPlacement.home), isNull);
  });

  test('concurrent preference changes respect the final choice', () async {
    final optIn = consent.setConsent(AdConsent.contextual);
    final revoke = consent.setConsent(AdConsent.denied);
    await Future.wait([optIn, revoke]);
    expect(consent.current, AdConsent.denied);
    expect(await AdConsentRepository(storage).load(), AdConsent.denied);
  });
}
