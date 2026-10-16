import 'dart:async';

import 'package:standby_pro/src/features/standby/settings/controls.dart';

/// Runs before every test file. Settings groups open and close; the tests
/// drive the controls inside all of them, so they start with every group open
/// (the tests of the groups' own behaviour switch this off).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SettingsSection.debugOpenAll = true;
  await testMain();
}
