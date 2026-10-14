import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/services/token_store.dart';

/// A secure store in memory (or one that does not exist on this device).
class _Secure extends FlutterSecureStorage {
  _Secure({this.missing = false});
  final bool missing;
  final values = <String, String>{};

  void _check() {
    if (missing) throw MissingPluginException('no secure store');
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check();
    return values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check();
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _check();
    values.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an old plain token moves into the secure store, once', () async {
    SharedPreferences.setMockInitialValues({TokenStore.key: 'old'});
    final secure = _Secure();
    final store = TokenStore(secure: secure);
    expect(await store.read(), 'old'); // nobody has to sign in again
    expect(secure.values[TokenStore.key], 'old');
    expect(
      (await SharedPreferences.getInstance()).getString(TokenStore.key),
      isNull,
    ); // and it is gone from plain preferences
    expect(await store.read(), 'old'); // now read from the secure store
  });

  test('a new token is written securely and never to preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final secure = _Secure();
    await TokenStore(secure: secure).write('fresh');
    expect(secure.values[TokenStore.key], 'fresh');
    expect(
      (await SharedPreferences.getInstance()).getString(TokenStore.key),
      isNull,
    );
  });

  test('signing out clears both places', () async {
    SharedPreferences.setMockInitialValues({TokenStore.key: 'leftover'});
    final secure = _Secure()..values[TokenStore.key] = 'tok';
    final store = TokenStore(secure: secure);
    await store.clear();
    expect(secure.values, isEmpty);
    expect(await store.read(), isNull);
  });

  test(
    'with no secure store on the device it still works, in preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = TokenStore(secure: _Secure(missing: true));
      await store.write('tok');
      expect(await store.read(), 'tok');
      await store.clear();
      expect(await store.read(), isNull);
    },
  );
}
