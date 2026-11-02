import 'package:alisten/features/search/data/shared_text_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = EventChannel('moe.dihe.alisten/shared_text');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, null);
  });

  test('on Android, the texts the activity forwards are read from its '
      'channel', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(
            onListen: (arguments, events) {
              events
                ..success('分享 https://b23.tv/xyz')
                ..success(42)
                ..success('https://163cn.tv/abcd');
            },
          ),
        );

    final texts = PlatformSharedTextSource(android: true).texts;

    expect(await texts.take(2).toList(), [
      '分享 https://b23.tv/xyz',
      'https://163cn.tv/abcd',
    ]);
  });

  test('elsewhere nothing is shared and the channel is not used', () async {
    var listened = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
          channel,
          MockStreamHandler.inline(onListen: (_, _) => listened = true),
        );

    expect(
      await PlatformSharedTextSource(android: false).texts.toList(),
      isEmpty,
    );
    expect(listened, isFalse);
  });
}
