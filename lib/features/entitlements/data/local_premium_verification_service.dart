import 'dart:math';

import '../domain/purchase_gateway.dart';

class LocalVerificationChallenge {
  const LocalVerificationChallenge({
    required this.email,
    required this.displayCode,
    required this.expiresAt,
  });
  final String email;
  final String displayCode;
  final DateTime expiresAt;
}

class LocalVerificationException implements Exception {
  const LocalVerificationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Local test identity adapter. Displaying a code does not prove email ownership.
/// Nothing is sent over the network and no email is delivered.
class LocalPremiumVerificationService {
  LocalPremiumVerificationService({DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random.secure();
  final DateTime Function() _clock;
  final Random _random;
  LocalVerificationChallenge? _challenge;
  int _attempts = 0;
  static const maxAttempts = 5;
  static const lifetime = Duration(minutes: 5);
  int get attemptsRemaining => maxAttempts - _attempts;

  static bool isValidEmail(String input) {
    final email = input.trim();
    final parts = email.split('@');
    return parts.length == 2 &&
        parts.first.length <= 64 &&
        parts.last
            .split('.')
            .every((label) => label.isNotEmpty && label.length <= 63) &&
        email.length <= 254 &&
        RegExp(
          r'^[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$',
        ).hasMatch(email) &&
        !email.split('@').first.startsWith('.') &&
        !email.split('@').first.endsWith('.') &&
        !email.split('@').first.contains('..');
  }

  LocalVerificationChallenge begin(String email) {
    if (!isValidEmail(email)) {
      throw const LocalVerificationException('Enter a valid email address.');
    }
    _attempts = 0;
    return _challenge = LocalVerificationChallenge(
      email: email.trim().toLowerCase(),
      displayCode: (100000 + _random.nextInt(900000)).toString(),
      expiresAt: _clock().add(lifetime),
    );
  }

  VerifiedPremiumAccount verify(String code) {
    final challenge = _challenge;
    if (challenge == null) {
      throw const LocalVerificationException(
        'Start a local verification first.',
      );
    }
    if (!challenge.expiresAt.isAfter(_clock())) {
      _challenge = null;
      throw const LocalVerificationException(
        'The test code expired. Generate a new code.',
      );
    }
    if (_attempts >= maxAttempts) {
      throw const LocalVerificationException(
        'Too many attempts. Generate a new test code.',
      );
    }
    _attempts++;
    if (code.trim() != challenge.displayCode) {
      throw LocalVerificationException(
        'Incorrect test code. $attemptsRemaining attempts remaining.',
      );
    }
    _challenge = null;
    return VerifiedPremiumAccount(
      accountId: challenge.email,
      isSimulated: true,
    );
  }

  void cancel() {
    _challenge = null;
    _attempts = 0;
  }
}
