import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entitlement.dart';
import '../domain/purchase_gateway.dart';
import 'local_premium_verification_service.dart';

abstract interface class MockEntitlementStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class PreferencesMockEntitlementStorage implements MockEntitlementStorage {
  PreferencesMockEntitlementStorage(this.preferences);
  final SharedPreferencesAsync preferences;
  static const key = 'framelab.mock_pro.receipt.v1';
  @override
  Future<String?> read() => preferences.getString(key);
  @override
  Future<void> write(String value) => preferences.setString(key, value);
  @override
  Future<void> clear() => preferences.remove(key);
}

/// A deliberately local test adapter. It never charges, renews, contacts a
/// server, or claims that email ownership was verified. Replace this adapter
/// with store-backed purchases and receipt verification before selling Pro.
class LocalMockEntitlementRepository
    implements EntitlementRepository, PurchaseGateway {
  LocalMockEntitlementRepository({
    SharedPreferencesAsync? preferences,
    MockEntitlementStorage? storage,
    bool? enabled,
    DateTime Function()? clock,
  }) : enabled =
           enabled ??
           (kDebugMode || const bool.fromEnvironment('ENABLE_MOCK_PRO')),
       _storage =
           storage ??
           PreferencesMockEntitlementStorage(
             preferences ?? SharedPreferencesAsync(),
           ),
       _clock = clock ?? DateTime.now;

  final bool enabled;
  final MockEntitlementStorage _storage;
  final DateTime Function() _clock;
  final _changes = StreamController<Entitlement>.broadcast(sync: true);
  Entitlement _current = const Entitlement.free();
  _MockReceipt? _receipt;
  Future<void>? _initialization;
  Timer? _expiryTimer;
  bool _busy = false;
  bool _disposed = false;
  String? initializationWarning;

  bool get isCancelled => _receipt?.cancelled ?? false;
  String? get activePlanId =>
      current.isProAt(_clock()) ? _receipt?.planId : null;

  Future<void> initialize() => _initialization ??= _load();

  Future<void> _load() async {
    if (!enabled) return;
    try {
      final raw = await _storage.read();
      if (raw != null) {
        _receipt = _MockReceipt.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
      }
    } on Object {
      _receipt = null;
      initializationWarning =
          'The local test receipt could not be read. Free access is available.';
    }
    _refresh(force: true);
  }

  @override
  Entitlement get current {
    _refresh();
    return _current;
  }

  @override
  Stream<Entitlement> watch() => Stream<Entitlement>.multi((listener) {
    listener.add(current);
    final subscription = _changes.stream.listen(
      listener.add,
      onError: listener.addError,
      onDone: listener.close,
    );
    listener.onCancel = subscription.cancel;
  });

  void _refresh({bool force = false}) {
    if (_disposed) return;
    final receipt = _receipt;
    final next =
        enabled &&
            receipt != null &&
            !receipt.purchasedAt.isAfter(_clock()) &&
            receipt.expiresAt.isAfter(_clock())
        ? Entitlement.pro(
            source: EntitlementSource.localMock,
            expiresAt: receipt.expiresAt,
          )
        : const Entitlement.free();
    if (force ||
        next.source != _current.source ||
        next.expiresAt != _current.expiresAt) {
      _current = next;
      _changes.add(next);
    }
    _expiryTimer?.cancel();
    if (next.isProAt(_clock())) {
      _expiryTimer = Timer(
        next.expiresAt!.difference(_clock()),
        () => _refresh(force: true),
      );
    }
  }

  @override
  Future<PurchaseOutcome> purchase(
    PremiumPlan plan,
    VerifiedPremiumAccount account,
  ) async {
    if (!enabled) {
      return _failed('Local test purchases are disabled in this build.');
    }
    if (_busy) {
      return _failed('Another purchase action is already in progress.');
    }
    _busy = true;
    try {
      await initialize();
      if (!account.isSimulated ||
          !LocalPremiumVerificationService.isValidEmail(account.accountId)) {
        return _failed('Use the local test verification flow first.');
      }
      final selected = PremiumPlan.values
          .where((value) => value.id == plan.id)
          .firstOrNull;
      if (selected == null ||
          selected.pricePaise != plan.pricePaise ||
          selected.interval != plan.interval) {
        return _failed('Unknown subscription plan.');
      }
      if (current.isProAt(_clock())) {
        return _failed(
          'Pro is already active. No duplicate purchase was made.',
        );
      }
      final now = _clock().toUtc();
      final receipt = _MockReceipt(
        planId: selected.id,
        accountId: account.accountId.trim().toLowerCase(),
        purchasedAt: now,
        expiresAt: calendarExpiry(now, selected.interval),
        cancelled: false,
      );
      // Persist before exposing access; a disk failure cannot silently unlock Pro.
      await _storage.write(jsonEncode(receipt.toJson()));
      _receipt = receipt;
      _refresh(force: true);
      return PurchaseOutcome(
        status: PurchaseStatus.completed,
        entitlement: current,
        message: 'Local test Pro activated. No money was charged.',
      );
    } on Object {
      return _failed(
        'The local purchase could not be saved. Please try again.',
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Future<PurchaseOutcome> restore(VerifiedPremiumAccount account) async {
    if (!account.isSimulated) {
      return _failed('Only local test receipts are supported.');
    }
    await initialize();
    if (_receipt?.accountId != account.accountId.trim().toLowerCase()) {
      return _failed('No local test purchase matches this account.');
    }
    return restoreLastPurchase();
  }

  /// Restores only the receipt on this device; it never prompts for an account.
  Future<PurchaseOutcome> restoreLastPurchase() async {
    if (!enabled) {
      return _failed('Local test purchases are disabled in this build.');
    }
    try {
      await initialize();
      _refresh(force: true);
      if (!current.isProAt(_clock())) {
        return _failed(
          'No unexpired local test purchase is available on this device.',
        );
      }
      return PurchaseOutcome(
        status: PurchaseStatus.completed,
        entitlement: current,
        message:
            'Local test purchase restored. This is not Google Play restore.',
      );
    } on Object {
      return _failed('The local test receipt could not be read.');
    }
  }

  /// Cancellation keeps access until expiry, as an eventual store adapter must.
  /// Test subscriptions never auto-renew, regardless of this flag.
  Future<PurchaseOutcome> cancelSubscription() async {
    if (!enabled || _busy) {
      return _failed('Test subscription action is unavailable.');
    }
    _busy = true;
    try {
      await initialize();
      final receipt = _receipt;
      if (receipt == null || !current.isProAt(_clock())) {
        return _failed('There is no active test subscription.');
      }
      final cancelled = receipt.copyCancelled();
      await _storage.write(jsonEncode(cancelled.toJson()));
      _receipt = cancelled;
      _refresh(force: true);
      return PurchaseOutcome(
        status: PurchaseStatus.cancelled,
        entitlement: current,
        message:
            'Test subscription cancelled. Pro stays active until its expiry date.',
      );
    } on Object {
      return _failed('Cancellation could not be saved. Please try again.');
    } finally {
      _busy = false;
    }
  }

  /// Removes the local receipt permanently. Used only by labelled test controls.
  Future<PurchaseOutcome> reset() async {
    if (!enabled || _busy) return _failed('Test reset is unavailable.');
    _busy = true;
    try {
      await initialize();
      await _storage.clear();
      _receipt = null;
      _refresh(force: true);
      return PurchaseOutcome(
        status: PurchaseStatus.completed,
        entitlement: current,
        message: 'Local test receipt removed. You are back on Free.',
      );
    } on Object {
      return _failed('The test receipt could not be removed.');
    } finally {
      _busy = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _expiryTimer?.cancel();
    await _changes.close();
  }

  static PurchaseOutcome _failed(String message) =>
      PurchaseOutcome(status: PurchaseStatus.failed, message: message);

  /// Calendar periods clamp Jan 31 → Feb 28/29 and Feb 29 → Feb 28 next year.
  static DateTime calendarExpiry(DateTime start, PlanInterval interval) {
    final nextYear = start.year + (interval == PlanInterval.year ? 1 : 0);
    final nextMonth = start.month + (interval == PlanInterval.month ? 1 : 0);
    final lastDay = DateTime.utc(nextYear, nextMonth + 1, 0).day;
    return DateTime.utc(
      nextYear,
      nextMonth,
      start.day > lastDay ? lastDay : start.day,
      start.hour,
      start.minute,
      start.second,
      start.millisecond,
      start.microsecond,
    );
  }
}

class _MockReceipt {
  const _MockReceipt({
    required this.planId,
    required this.accountId,
    required this.purchasedAt,
    required this.expiresAt,
    required this.cancelled,
  });
  final String planId;
  final String accountId;
  final DateTime purchasedAt;
  final DateTime expiresAt;
  final bool cancelled;
  factory _MockReceipt.fromJson(Map<String, dynamic> json) {
    final receipt = _MockReceipt(
      planId: json['planId'] as String,
      accountId: json['accountId'] as String,
      purchasedAt: DateTime.parse(json['purchasedAt'] as String).toUtc(),
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
      cancelled: json['cancelled'] as bool,
    );
    if (json['version'] != 1 ||
        receipt.accountId.isEmpty ||
        !PremiumPlan.values.any((plan) => plan.id == receipt.planId) ||
        !LocalPremiumVerificationService.isValidEmail(receipt.accountId) ||
        !receipt.expiresAt.isAfter(receipt.purchasedAt)) {
      throw const FormatException('Invalid local test receipt');
    }
    final plan = PremiumPlan.values.firstWhere(
      (plan) => plan.id == receipt.planId,
    );
    if (receipt.expiresAt !=
        LocalMockEntitlementRepository.calendarExpiry(
          receipt.purchasedAt,
          plan.interval,
        )) {
      throw const FormatException('Invalid local test subscription period');
    }
    return receipt;
  }
  _MockReceipt copyCancelled() => _MockReceipt(
    planId: planId,
    accountId: accountId,
    purchasedAt: purchasedAt,
    expiresAt: expiresAt,
    cancelled: true,
  );
  Map<String, Object> toJson() => {
    'version': 1,
    'planId': planId,
    'accountId': accountId,
    'purchasedAt': purchasedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'cancelled': cancelled,
  };
}
