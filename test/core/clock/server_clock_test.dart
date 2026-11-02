import 'package:alisten/core/clock/server_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serverNow is null without samples and uses midpoint offset', () {
    var now = 10000;
    final clock = ServerClock(now: () => now);

    expect(clock.serverNow(), isNull);
    clock.addSample(1000, 1100, 5050);
    now = 2000;

    expect(clock.serverNow(), 6000);
  });

  test('lowest round trip among recent samples wins', () {
    var now = 0;
    final clock = ServerClock(now: () => now);
    clock.addSample(0, 300, 10500);
    clock.addSample(5000, 5100, 15050);
    clock.addSample(10000, 10200, 20400);
    now = 11000;

    expect(clock.serverNow(), 21000);
  });

  test('a lower round trip sample older than fifteen seconds is not used', () {
    var now = 0;
    final clock = ServerClock(now: () => now);
    clock.addSample(0, 10, 60005);
    clock.addSample(20000, 20500, 20250);
    now = 20500;

    expect(clock.serverNow(), 20500);
  });

  test(
    'reset keeps the last estimate only until a sample of the new generation',
    () {
      var now = 0;
      final clock = ServerClock(now: () => now);
      final oldGeneration = clock.generation;
      clock.addSample(0, 100, 1000);
      clock.addSample(100, 400, 1000);

      clock.reset();
      clock.addSample(200, 300, 2000, generation: oldGeneration);

      now = 100;
      expect(clock.serverNow(), 1050, reason: 'the best old sample remains');
      clock.addSample(400, 500, 3000, generation: clock.generation);
      now = 600;
      expect(clock.serverNow(), 3150);
    },
  );

  test('a provisional sample is used only until the first regular sample', () {
    var now = 0;
    final clock = ServerClock(now: () => now);

    clock.addProvisionalSample(0, 10, 5005);
    now = 10;
    expect(clock.serverNow(), 5010);

    clock.addSample(10, 210, 9110);
    now = 210;
    expect(clock.serverNow(), 9210, reason: 'despite the larger round trip');

    clock.addProvisionalSample(300, 310, 1);
    expect(clock.serverNow(), 9210);
  });
}
