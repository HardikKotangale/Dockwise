// Saves the screenshots an integration test takes (binding.takeScreenshot)
// into build/shots/ (works on iOS and Android).
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final f = File('build/shots/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return true;
  },
);
