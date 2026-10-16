import 'package:flutter/foundation.dart' show FlutterError;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:standby_pro/src/services/spotify_service.dart';
import 'package:standby_pro/src/services/token_store.dart';

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) =>
      Future.error(FlutterError('no such asset: $key'));
}

const _id = '5376303de3b742aa9dd58c23d3283c39';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only 32 hex characters count as a Client ID', () {
    expect(SpotifyService.validClientId(_id), isTrue);
    expect(SpotifyService.validClientId(_id.substring(1)), isFalse);
    expect(SpotifyService.validClientId('${_id}0'), isFalse);
    expect(SpotifyService.validClientId('z' * 32), isFalse);
    expect(SpotifyService.validClientId(''), isFalse);
  });

  test(
    'a pasted Client ID is cleaned, kept, and found again after a restart',
    () async {
      final a = SpotifyService(assets: _EmptyBundle(), tokens: TokenStore());
      await a.load();
      expect(a.isConfigured, isFalse);
      expect(await a.saveClientId('not an id'), isFalse);
      expect(a.isConfigured, isFalse);
      expect(await a.saveClientId('  ${_id.toUpperCase()}\n'), isTrue);
      expect(a.clientId, _id);
      expect(a.usingSavedClientId, isTrue);

      final b = SpotifyService(assets: _EmptyBundle(), tokens: TokenStore());
      await b.load(); // a new start
      expect(b.clientId, _id);
      expect(b.isConfigured, isTrue);
    },
  );

  test('removing it forgets it and signs out', () async {
    final s = SpotifyService(assets: _EmptyBundle(), tokens: TokenStore());
    await s.load();
    await s.saveClientId(_id);
    await s.removeClientId();
    expect(s.isConfigured, isFalse);
    expect(s.usingSavedClientId, isFalse);
    expect(s.isConnected, isFalse);
    final again = SpotifyService(assets: _EmptyBundle(), tokens: TokenStore());
    await again.load();
    expect(again.isConfigured, isFalse);
  });
}
