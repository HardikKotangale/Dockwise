import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the Spotify refresh token and the user's own Client ID live: the
/// platform's secure store (Keychain on iPhone and Mac, Android Keystore,
/// Windows Credential Locker), never plain preferences. If a device has no
/// secure store (no keyring on Linux, tests) it falls back to preferences so
/// sign-in still works.
class TokenStore {
  TokenStore({FlutterSecureStorage? secure})
    : _secure =
          secure ??
          // macOS: the file-based login keychain. The data-protection one needs
          // a paid signing team, and without it every write fails, which
          // would leave the token in plain preferences.
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
            // iPhone: readable after the first unlock (a locked bedside phone
            // can still refresh the token) and never copied to another device
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  static const key = 'spotify_refresh';
  static const clientIdKey = 'spotify_client_id';
  final FlutterSecureStorage _secure;

  Future<String?> _secureRead([String key = key]) async {
    try {
      return await _secure.read(key: key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// False when there is no secure store to write to.
  Future<bool> _secureWrite(String token, [String key = key]) async {
    try {
      await _secure.write(key: key, value: token);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> read() => _read(key);
  Future<void> write(String token) => _write(key, token);
  Future<void> clear() => _clear(key);

  /// The Client ID the user made for their own Spotify app (see the setup guide).
  Future<String?> readClientId() => _read(clientIdKey);
  Future<void> writeClientId(String id) => _write(clientIdKey, id);
  Future<void> clearClientId() => _clear(clientIdKey);

  Future<String?> _read(String k) async {
    final saved = await _secureRead(k);
    if (saved != null) return saved;
    // An older install kept the value in plain preferences: move it across
    // once, so nobody has to sign in again.
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(k);
    if (old != null && await _secureWrite(old, k)) await prefs.remove(k);
    return old;
  }

  Future<void> _write(String k, String value) async {
    final prefs = await SharedPreferences.getInstance();
    if (await _secureWrite(value, k)) {
      await prefs.remove(k);
    } else {
      await prefs.setString(k, value); // no secure store here
    }
  }

  Future<void> _clear(String k) async {
    try {
      await _secure.delete(key: k);
    } on MissingPluginException {
      // nothing to clear
    } on PlatformException {
      // nothing to clear
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(k);
  }
}
