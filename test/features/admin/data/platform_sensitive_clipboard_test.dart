import 'package:alisten/features/admin/data/platform_sensitive_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('moe.dihe.alisten/clipboard');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  Object? activityAnswer;

  setUp(() {
    calls = [];
    activityAnswer = true;
    messenger
      ..setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return activityAnswer;
      })
      ..setMockMethodCallHandler(SystemChannels.platform, (call) async {
        calls.add(call);
        return null;
      });
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(channel, null)
      ..setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('on Android the text goes to the activity to be marked sensitive, not '
      'to the plain clipboard', () async {
    await PlatformSensitiveClipboard(android: true).copy('k-1');

    final call = calls.single;
    expect(call.method, 'setSensitiveText');
    expect(call.arguments, {'text': 'k-1'});
  });

  test('a copy the activity could not make fails without the text', () async {
    activityAnswer = false;

    await expectLater(
      PlatformSensitiveClipboard(android: true).copy('k-1'),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          isNot(contains('k-1')),
        ),
      ),
    );
  });

  test('a copy the activity did not answer fails', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'error');
    });
    await expectLater(
      PlatformSensitiveClipboard(android: true).copy('k-1'),
      throwsStateError,
    );

    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(
      PlatformSensitiveClipboard(android: true).copy('k-1'),
      throwsStateError,
    );
  });

  test('elsewhere the text goes to the system clipboard', () async {
    await PlatformSensitiveClipboard(android: false).copy('k-1');

    final call = calls.single;
    expect(call.method, 'Clipboard.setData');
    expect(call.arguments, {'text': 'k-1'});
  });
}
