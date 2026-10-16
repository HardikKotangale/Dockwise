// The Spotify sign-in window must hear about the hushdock:// answer. A local
// page sends the window there, as Spotify does after "Agree"; the test passes
// when Dart is told.
import 'dart:async';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the window reports the hushdock redirect', (t) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response
        ..headers.contentType = ContentType.html
        ..write(
          '<html><body><p>Agree</p><script>setTimeout(function(){'
          'location.href="hushdock://spotify-callback?code=abc&state=xyz";'
          '},800);</script></body></html>',
        )
        ..close();
    });
    final heard = Completer<String>();
    final window = await WebviewWindow.create(
      configuration: const CreateConfiguration(
        windowWidth: 420,
        windowHeight: 300,
        title: 'test',
        titleBarHeight: 0,
      ),
    );
    window.addOnUrlRequestCallback((url) {
      debugPrint('URL_SEEN $url');
      if (url.startsWith('hushdock:') && !heard.isCompleted) {
        heard.complete(url);
      }
    });
    window.launch('http://127.0.0.1:${server.port}/');
    final url = await heard.future.timeout(const Duration(seconds: 20));
    window.close();
    await server.close();
    expect(url, contains('code=abc'));
    debugPrint('REDIRECT_OK');
  });
}
