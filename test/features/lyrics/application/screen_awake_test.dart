import 'package:alisten/features/lyrics/application/screen_awake.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lyrics_test_doubles.dart';

void main() {
  test('the screen stays on while anyone holds it', () {
    final device = FakeScreenAwakeDevice();
    final screen = ScreenAwake(device)..hold();

    expect(device.requests, [true]);

    screen.release();

    expect(device.requests, [true, false]);
  });

  test('a second holder keeps it on after the first lets go', () {
    final device = FakeScreenAwakeDevice();
    final screen = ScreenAwake(device)
      ..hold()
      ..hold()
      ..release();

    expect(device.keptOn, isTrue);
    expect(device.requests, [true]);

    screen.release();

    expect(device.keptOn, isFalse);
  });

  test('a device that refuses does not break the page', () async {
    final device = FakeScreenAwakeDevice()..failure = StateError('no window');

    ScreenAwake(device).hold();
    await pumpEventQueue();

    expect(device.requests, [true]);
  });
}
