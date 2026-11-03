import 'dart:ffi' show Abi;

import 'package:alisten/domain/release/app_release.dart';
import 'package:alisten/features/update/data/platform_release_opener.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import '../update_test_doubles.dart';

const _download =
    'https://github.com/DiheMoe/alisten-app/releases/download/v1.2.0';
const _page = 'https://github.com/DiheMoe/alisten-app/releases/tag/v1.2.0';

ReleaseAsset _asset(String name) =>
    ReleaseAsset(name: name, downloadUrl: Uri.parse('$_download/$name'));

void main() {
  late List<(Uri, LaunchMode)> launched;
  late bool opens;

  setUp(() {
    launched = [];
    opens = true;
  });

  Future<bool> launch(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    launched.add((uri, mode));
    return opens;
  }

  Future<(Uri, LaunchMode)> openOn(Abi abi, AppRelease release) async {
    expect(
      await PlatformReleaseOpener(abi: abi, launch: launch).open(release),
      isTrue,
    );
    return launched.single;
  }

  final release = testRelease(tag: 'v1.2.0');

  test('a 64-bit ARM Android device downloads the arm64-v8a package in the '
      'browser', () async {
    expect(await openOn(Abi.androidArm64, release), (
      Uri.parse('$_download/Alisten-1.2.0-arm64-v8a.apk'),
      LaunchMode.externalApplication,
    ));
  });

  test('a 32-bit ARM Android device downloads the armeabi-v7a package in '
      'the browser', () async {
    expect(await openOn(Abi.androidArm, release), (
      Uri.parse('$_download/Alisten-1.2.0-armeabi-v7a.apk'),
      LaunchMode.externalApplication,
    ));
  });

  test('an Android device of another architecture opens the release '
      'page', () async {
    for (final abi in [Abi.androidX64, Abi.androidIA32, Abi.androidRiscv64]) {
      launched.clear();

      expect(await openOn(abi, release), (
        Uri.parse(_page),
        LaunchMode.externalApplication,
      ), reason: '$abi');
    }
  });

  test('without a package for the device the release page is opened', () async {
    final missing = testRelease(
      tag: 'v1.2.0',
      assets: [
        _asset('Alisten-1.2.0-armeabi-v7a.apk'),
        _asset('Alisten-1.2.0-arm64-v8a.apk.sha256'),
        _asset('Alisten-1.2.0-arm64-v8a.zip'),
        _asset('Alisten-1.2.0-ios-unsigned.ipa'),
      ],
    );

    expect(await openOn(Abi.androidArm64, missing), (
      Uri.parse(_page),
      LaunchMode.externalApplication,
    ));
  });

  test('iOS opens the release page', () async {
    expect(await openOn(Abi.iosArm64, release), (
      Uri.parse(_page),
      LaunchMode.externalApplication,
    ));
  });

  test('a link the system cannot open is told as not opened', () async {
    opens = false;
    expect(
      await PlatformReleaseOpener(
        abi: Abi.androidArm64,
        launch: launch,
      ).open(release),
      isFalse,
    );

    expect(
      await PlatformReleaseOpener(
        abi: Abi.androidArm64,
        launch: (uri, {mode = LaunchMode.platformDefault}) async =>
            throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      ).open(release),
      isFalse,
    );
  });
}
