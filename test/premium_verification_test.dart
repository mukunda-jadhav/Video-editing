import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:framelab/features/entitlements/data/local_premium_verification_service.dart';

void main() {
  test(
    'email validation rejects malformed, too-long and whitespace addresses',
    () {
      for (final email in [
        'a@example.com',
        'name+test@sub.example.in',
        '  TEST@example.com  ',
      ]) {
        expect(
          LocalPremiumVerificationService.isValidEmail(email),
          isTrue,
          reason: email,
        );
      }
      for (final email in [
        '',
        'a',
        'a@',
        '@example.com',
        'a@example',
        'a b@example.com',
        '.a@example.com',
        'a.@example.com',
        'a..b@example.com',
        'a@-example.com',
        'a@example-.com',
        'a@example..com',
        '${'a' * 65}@example.com',
        'a@${'a' * 64}.com',
        'a@@example.com',
      ]) {
        expect(
          LocalPremiumVerificationService.isValidEmail(email),
          isFalse,
          reason: email,
        );
      }
    },
  );

  test(
    'code proves only local test intent; identity explicitly remains simulated',
    () {
      final service = LocalPremiumVerificationService(random: Random(7));
      final challenge = service.begin(' TEST@example.com ');
      expect(challenge.email, 'test@example.com');
      expect(challenge.displayCode, matches(RegExp(r'^\d{6}$')));
      final account = service.verify(challenge.displayCode);
      expect(account.isSimulated, isTrue);
      expect(account.accountId, 'test@example.com');
      expect(
        () => service.verify(challenge.displayCode),
        throwsA(isA<LocalVerificationException>()),
      );
    },
  );

  test('invalid input does not create a challenge', () {
    final service = LocalPremiumVerificationService();
    expect(
      () => service.begin('invalid'),
      throwsA(isA<LocalVerificationException>()),
    );
    expect(
      () => service.verify('123456'),
      throwsA(isA<LocalVerificationException>()),
    );
  });

  test(
    'code expires at five minutes and regenerating permits a fresh attempt',
    () {
      var now = DateTime.utc(2026);
      final service = LocalPremiumVerificationService(clock: () => now);
      final challenge = service.begin('test@example.com');
      now = now.add(LocalPremiumVerificationService.lifetime);
      expect(
        () => service.verify(challenge.displayCode),
        throwsA(isA<LocalVerificationException>()),
      );
      final second = service.begin('test@example.com');
      expect(service.verify(second.displayCode).isSimulated, isTrue);
    },
  );

  test('five wrong attempts lock code, cancel invalidates challenge', () {
    final service = LocalPremiumVerificationService();
    final challenge = service.begin('test@example.com');
    for (
      var index = 0;
      index < LocalPremiumVerificationService.maxAttempts;
      index++
    ) {
      expect(
        () => service.verify('000000'),
        throwsA(isA<LocalVerificationException>()),
      );
    }
    expect(service.attemptsRemaining, 0);
    expect(
      () => service.verify(challenge.displayCode),
      throwsA(isA<LocalVerificationException>()),
    );
    final fresh = service.begin('test@example.com');
    service.cancel();
    expect(
      () => service.verify(fresh.displayCode),
      throwsA(isA<LocalVerificationException>()),
    );
  });
}
