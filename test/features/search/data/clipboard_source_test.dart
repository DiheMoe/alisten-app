import 'package:alisten/features/search/data/clipboard_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('moe.dihe.alisten/clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;

  setUp(() {
    calls = [];
    messenger
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return call.method == 'primaryClipStamp' ? 1234 : null;
      })
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call.method);
        return call.method == 'Clipboard.getData' ? {'text': '晴天'} : null;
      });
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('on Android, the clipboard is stamped by the activity without its '
      'content being read', () async {
    final clipboard = PlatformClipboardSource(android: true);

    expect(await clipboard.stamp(), 1234);
    expect(calls, ['primaryClipStamp']);
  });

  test('the content is read from the system clipboard', () async {
    expect(await PlatformClipboardSource(android: true).read(), '晴天');
    expect(calls, ['Clipboard.getData']);
  });

  test('elsewhere the clipboard carries no stamp and the activity is not '
      'asked', () async {
    expect(await PlatformClipboardSource(android: false).stamp(), isNull);
    expect(calls, isEmpty);
  });

  test('without an answer from the activity, nothing is stamped', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'error');
    });
    expect(await PlatformClipboardSource(android: true).stamp(), isNull);

    messenger.setMockMethodCallHandler(channel, null);
    expect(await PlatformClipboardSource(android: true).stamp(), isNull);
  });
}
