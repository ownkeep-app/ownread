import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime config loaded from the project `.env` asset.
class AppEnv {
  AppEnv._();

  static const _idleKey = 'PRIVACY_IDLE_SECONDS';
  static const _unlockKey = 'PRIVACY_UNLOCK_HOLD_SECONDS';

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Keep defaults when asset is missing (e.g. some test runners).
    }
  }

  static Duration get privacyIdleTimeout =>
      Duration(seconds: _positiveInt(_idleKey, 60));

  static Duration get privacyUnlockHold =>
      Duration(seconds: _positiveInt(_unlockKey, 3));

  static int _positiveInt(String key, int fallback) {
    String? raw;
    try {
      raw = dotenv.maybeGet(key);
    } catch (_) {
      // Not loaded yet (tests, missing asset): use the default.
    }
    final parsed = int.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }
}
