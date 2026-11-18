import 'package:alisten/features/admin/data/platform_media_link_opener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  late List<(Uri, LaunchMode)> launched;
  late Exception? failure;

  setUp(() {
    launched = [];
    failure = null;
  });

  Future<bool> launch(
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    if (failure case final error?) throw error;
    launched.add((uri, mode));
    return true;
  }

  test('a link opens outside the app', () async {
    final opener = PlatformMediaLinkOpener(launch: launch);
    expect(await opener.open('https://www.bilibili.com/video/BV1'), isTrue);
    expect(launched, [
      (
        Uri.parse('https://www.bilibili.com/video/BV1'),
        LaunchMode.externalApplication,
      ),
    ]);
  });

  test('a link that is not a web address is not opened', () async {
    final opener = PlatformMediaLinkOpener(launch: launch);
    expect(await opener.open('not a link'), isFalse);
    expect(await opener.open('file:///etc/passwd'), isFalse);
    expect(launched, isEmpty);
  });

  test('a launch that throws reads as not opened', () async {
    failure = Exception('no browser');
    final opener = PlatformMediaLinkOpener(launch: launch);
    expect(await opener.open('https://example.com'), isFalse);
  });
}
