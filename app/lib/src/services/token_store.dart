import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the Spotify refresh token lives: the platform's secure store (iOS
/// Keychain, Android Keystore, Windows Credential Locker), never plain
/// preferences. If a device has no secure store (no keyring on Linux, tests)
/// it falls back to preferences so sign-in still works.
class TokenStore {
  TokenStore({FlutterSecureStorage? secure})
    : _secure = secure ?? const FlutterSecureStorage();

  static const key = 'spotify_refresh';
  final FlutterSecureStorage _secure;

  Future<String?> _secureRead() async {
    try {
      return await _secure.read(key: key);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// False when there is no secure store to write to.
  Future<bool> _secureWrite(String token) async {
    try {
      await _secure.write(key: key, value: token);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> read() async {
    final saved = await _secureRead();
    if (saved != null) return saved;
    // An older install kept the token in plain preferences: move it across
    // once, so nobody has to sign in again.
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(key);
    if (old != null && await _secureWrite(old)) await prefs.remove(key);
    return old;
  }

  Future<void> write(String token) async {
    final prefs = await SharedPreferences.getInstance();
    if (await _secureWrite(token)) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, token); // no secure store here
    }
  }

  Future<void> clear() async {
    try {
      await _secure.delete(key: key);
    } on MissingPluginException {
      // nothing to clear
    } on PlatformException {
      // nothing to clear
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
