import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/entitlements/data/local_mock_entitlement_repository.dart';
import 'package:framelab/features/entitlements/data/google_play_purchase_gateway.dart';
import 'package:framelab/features/entitlements/domain/entitlement.dart';
import 'package:framelab/features/entitlements/domain/purchase_gateway.dart';

class MemoryReceiptStorage implements MockEntitlementStorage {
  String? value;
  bool failRead = false;
  bool failWrite = false;
  bool failClear = false;
  Completer<void>? holdWrite;
  int writes = 0;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('storage unavailable');
    return value;
  }

  @override
  Future<void> write(String next) async {
    writes++;
    if (holdWrite case final hold?) await hold.future;
    if (failWrite) throw StateError('disk full');
    value = next;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('disk unavailable');
    value = null;
  }
}

void main() {
  const account = VerifiedPremiumAccount(
    accountId: 'tester@example.com',
    isSimulated: true,
  );
  late DateTime now;
  late MemoryReceiptStorage storage;
  late LocalMockEntitlementRepository repository;
  setUp(() {
    now = DateTime.utc(2026, 1, 31, 8);
    storage = MemoryReceiptStorage();
    repository = LocalMockEntitlementRepository(
      storage: storage,
      enabled: true,
      clock: () => now,
    );
  });
  tearDown(() => repository.dispose());

  test('guests require no account and emit Free before any purchase', () async {
    await repository.initialize();
    expect(repository.current.source, EntitlementSource.guest);
    expect((await repository.watch().first).source, EntitlementSource.guest);
    expect(storage.value, isNull);
  });

  test(
    'monthly test purchase persists source and restores after restart without signup',
    () async {
      final result = await repository.purchase(PremiumPlan.monthly, account);
      expect(result.status, PurchaseStatus.completed);
      expect(result.message, contains('No money was charged'));
      expect(repository.current.source, EntitlementSource.localMock);
      expect(repository.current.expiresAt, DateTime.utc(2026, 2, 28, 8));
      expect(jsonDecode(storage.value!)['version'], 1);
      final restarted = LocalMockEntitlementRepository(
        storage: storage,
        enabled: true,
        clock: () => now,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(
        (await restarted.restoreLastPurchase()).status,
        PurchaseStatus.completed,
      );
      expect(restarted.activePlanId, PremiumPlan.monthly.id);
      expect(restarted.current.expiresAt, repository.current.expiresAt);
      expect(
        (await restarted.restore(
          const VerifiedPremiumAccount(
            accountId: 'different@example.com',
            isSimulated: true,
          ),
        )).status,
        PurchaseStatus.failed,
      );
    },
  );

  test(
    'expiry revokes at the exact instant and restore cannot extend the receipt',
    () async {
      await repository.purchase(PremiumPlan.monthly, account);
      final expiry = repository.current.expiresAt!;
      now = expiry.subtract(const Duration(microseconds: 1));
      expect(repository.current.isProAt(now), isTrue);
      now = expiry;
      expect(repository.current.source, EntitlementSource.guest);
      expect(repository.activePlanId, isNull);
      expect(
        (await repository.restoreLastPurchase()).status,
        PurchaseStatus.failed,
      );
      expect(storage.writes, 1);
    },
  );

  test('expiry emits Free to existing stream listeners', () async {
    final events = <Entitlement>[];
    final subscription = repository.watch().listen(events.add);
    addTearDown(subscription.cancel);
    await repository.purchase(PremiumPlan.monthly, account);
    now = repository.current.expiresAt!;
    repository.current;
    await Future<void>.delayed(Duration.zero);
    expect(
      events.any((value) => value.source == EntitlementSource.localMock),
      isTrue,
    );
    expect(events.last.source, EntitlementSource.guest);
  });

  test(
    'cancel preserves access until expiry and persists cancellation across restart',
    () async {
      await repository.purchase(PremiumPlan.yearly, account);
      final expiry = repository.current.expiresAt;
      expect(
        (await repository.cancelSubscription()).status,
        PurchaseStatus.cancelled,
      );
      expect(repository.isCancelled, isTrue);
      expect(repository.current.expiresAt, expiry);
      final restarted = LocalMockEntitlementRepository(
        storage: storage,
        enabled: true,
        clock: () => now,
      );
      addTearDown(restarted.dispose);
      await restarted.initialize();
      expect(restarted.isCancelled, isTrue);
      expect(restarted.current.isProAt(now), isTrue);
      now = expiry!;
      expect(restarted.current.isProAt(now), isFalse);
    },
  );

  test('reset removes receipt and restores Free immediately', () async {
    await repository.purchase(PremiumPlan.yearly, account);
    expect((await repository.reset()).status, PurchaseStatus.completed);
    expect(storage.value, isNull);
    expect(repository.current.source, EntitlementSource.guest);
    expect(
      (await repository.restoreLastPurchase()).status,
      PurchaseStatus.failed,
    );
  });

  test(
    'double taps and repeated purchases cannot write duplicate receipts',
    () async {
      storage.holdWrite = Completer<void>();
      final first = repository.purchase(PremiumPlan.monthly, account);
      final second = await repository.purchase(PremiumPlan.yearly, account);
      expect(second.status, PurchaseStatus.failed);
      storage.holdWrite!.complete();
      expect((await first).status, PurchaseStatus.completed);
      expect(
        (await repository.purchase(PremiumPlan.yearly, account)).status,
        PurchaseStatus.failed,
      );
      expect(storage.writes, 1);
    },
  );

  test(
    'invalid identity, real identity and spoofed plan cannot unlock test access',
    () async {
      for (final invalid in const [
        VerifiedPremiumAccount(
          accountId: 'tester@example.com',
          isSimulated: false,
        ),
        VerifiedPremiumAccount(accountId: '', isSimulated: true),
        VerifiedPremiumAccount(accountId: 'not-an-email', isSimulated: true),
      ]) {
        expect(
          (await repository.purchase(PremiumPlan.monthly, invalid)).status,
          PurchaseStatus.failed,
        );
      }
      for (final invalidPlan in const [
        PremiumPlan(
          id: 'unknown',
          interval: PlanInterval.month,
          pricePaise: 3900,
        ),
        PremiumPlan(
          id: 'pro_monthly',
          interval: PlanInterval.month,
          pricePaise: 0,
        ),
        PremiumPlan(
          id: 'pro_monthly',
          interval: PlanInterval.year,
          pricePaise: 3900,
        ),
      ]) {
        expect(
          (await repository.purchase(invalidPlan, account)).status,
          PurchaseStatus.failed,
        );
      }
      expect(storage.writes, 0);
      expect(repository.current.isProAt(now), isFalse);
    },
  );

  test(
    'failed write cannot unlock access; retry succeeds after storage recovers',
    () async {
      storage.failWrite = true;
      expect(
        (await repository.purchase(PremiumPlan.monthly, account)).status,
        PurchaseStatus.failed,
      );
      expect(repository.current.isProAt(now), isFalse);
      storage.failWrite = false;
      expect(
        (await repository.purchase(PremiumPlan.monthly, account)).status,
        PurchaseStatus.completed,
      );
    },
  );

  test('failed cancel/reset retain prior access and receipt', () async {
    await repository.purchase(PremiumPlan.monthly, account);
    storage.failWrite = true;
    expect(
      (await repository.cancelSubscription()).status,
      PurchaseStatus.failed,
    );
    expect(repository.isCancelled, isFalse);
    storage.failClear = true;
    expect((await repository.reset()).status, PurchaseStatus.failed);
    expect(repository.current.isProAt(now), isTrue);
  });

  test(
    'storage read failure leaves app usable as Free with diagnostic',
    () async {
      storage.failRead = true;
      await repository.initialize();
      expect(repository.current.source, EntitlementSource.guest);
      expect(repository.initializationWarning, isNotNull);
    },
  );

  test(
    'corrupt JSON, schema and tampered subscription periods fail closed',
    () async {
      await repository.purchase(PremiumPlan.monthly, account);
      final original = jsonDecode(storage.value!) as Map<String, dynamic>;
      for (final bad in [
        'bad json',
        '[]',
        '{}',
        jsonEncode({...original, 'version': 2}),
        jsonEncode({...original, 'accountId': 'invalid'}),
        jsonEncode({...original, 'planId': 'unknown'}),
        jsonEncode({
          ...original,
          'expiresAt': DateTime.utc(2040).toIso8601String(),
        }),
      ]) {
        final otherStorage = MemoryReceiptStorage()..value = bad;
        final other = LocalMockEntitlementRepository(
          storage: otherStorage,
          enabled: true,
          clock: () => now,
        );
        await other.initialize();
        expect(other.current.source, EntitlementSource.guest, reason: bad);
        expect(other.initializationWarning, isNotNull);
        await other.dispose();
      }
    },
  );

  test(
    'release-disabled adapter ignores saved Pro and rejects test controls',
    () async {
      await repository.purchase(PremiumPlan.monthly, account);
      final disabled = LocalMockEntitlementRepository(
        storage: storage,
        enabled: false,
        clock: () => now,
      );
      addTearDown(disabled.dispose);
      await disabled.initialize();
      expect(disabled.current.source, EntitlementSource.guest);
      expect(
        (await disabled.purchase(PremiumPlan.yearly, account)).status,
        PurchaseStatus.failed,
      );
      expect(
        (await disabled.restoreLastPurchase()).status,
        PurchaseStatus.failed,
      );
      expect(
        (await disabled.cancelSubscription()).status,
        PurchaseStatus.failed,
      );
      expect((await disabled.reset()).status, PurchaseStatus.failed);
    },
  );

  test('calendar subscriptions clamp leap days and year boundaries', () {
    expect(
      LocalMockEntitlementRepository.calendarExpiry(
        DateTime.utc(2024, 1, 31),
        PlanInterval.month,
      ),
      DateTime.utc(2024, 2, 29),
    );
    expect(
      LocalMockEntitlementRepository.calendarExpiry(
        DateTime.utc(2024, 2, 29),
        PlanInterval.year,
      ),
      DateTime.utc(2025, 2, 28),
    );
    expect(
      LocalMockEntitlementRepository.calendarExpiry(
        DateTime.utc(2026, 12, 31),
        PlanInterval.month,
      ),
      DateTime.utc(2027, 1, 31),
    );
  });

  test(
    'unconfigured Google Play never pretends a purchase or restore worked',
    () async {
      const gateway = GooglePlayPurchaseGateway();
      expect(
        (await gateway.purchase(PremiumPlan.monthly, account)).status,
        PurchaseStatus.failed,
      );
      expect((await gateway.restore(account)).status, PurchaseStatus.failed);
    },
  );
}
