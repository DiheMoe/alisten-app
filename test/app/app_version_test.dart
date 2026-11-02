import 'dart:io';

import 'package:alisten/app/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version shown is the one the app is built with', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);

    expect(appVersion, version);
  });
}
