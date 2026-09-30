import 'package:shared_preferences/shared_preferences.dart';
import '../domain/ad_gateway.dart';

abstract interface class AdConsentStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class PreferencesAdConsentStorage implements AdConsentStorage {
  PreferencesAdConsentStorage([SharedPreferencesAsync? preferences])
    : _preferences = preferences;
  final SharedPreferencesAsync? _preferences;
  static const key = 'framelab.ads.contextual_consent.v1';
  @override
  Future<String?> read() async {
    try {
      return await (_preferences ?? SharedPreferencesAsync()).getString(key);
    } on Object {
      // Flutter widget tests and recovery UI can run without a platform
      // preferences backend. Fail closed instead of breaking the editor.
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    // Let the repository keep opt-in disabled when persistence fails.
    await (_preferences ?? SharedPreferencesAsync()).setString(key, value);
  }
}

class AdConsentRepository {
  AdConsentRepository(this.storage);
  final AdConsentStorage storage;
  AdConsent _current = AdConsent.unknown;
  Future<AdConsent>? _initialization;
  Future<void> _writes = Future<void>.value();
  int _generation = 0;
  AdConsent get current => _current;

  Future<AdConsent> load() async {
    await (_initialization ??= _load());
    return _current;
  }

  Future<AdConsent> _load() async {
    try {
      final value = await storage.read();
      _current =
          AdConsent.values
              .where((consent) => consent.name == value)
              .firstOrNull ??
          AdConsent.unknown;
    } on Object {
      _current = AdConsent.unknown;
    }
    return _current;
  }

  Future<void> setConsent(AdConsent consent) async {
    await load();
    final generation = ++_generation;
    // Revoke in memory immediately, even if the preference write fails.
    // Opt-in is exposed only once the write succeeds.
    if (consent != AdConsent.contextual) _current = consent;
    final write = _writes.then((_) => storage.write(consent.name));
    _writes = write.catchError((Object _) {});
    await write;
    if (generation == _generation) _current = consent;
  }
}
