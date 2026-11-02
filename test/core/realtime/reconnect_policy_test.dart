import 'dart:math';

import 'package:alisten/core/realtime/reconnect_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reconnect delay doubles from three seconds to a thirty second cap with ±20% jitter', () {
    const bases = {1: 3000, 2: 6000, 3: 12000, 4: 24000, 5: 30000, 20: 30000};
    for (final MapEntry(key: attempt, value: baseMs) in bases.entries) {
      expect(
        reconnectDelay(attempt, _FixedRandom(0)),
        Duration(milliseconds: baseMs * 8 ~/ 10),
        reason: 'attempt $attempt low',
      );
      expect(
        reconnectDelay(attempt, _FixedRandom(0.5)),
        Duration(milliseconds: baseMs),
        reason: 'attempt $attempt mid',
      );
      final high = reconnectDelay(attempt, _FixedRandom(0.999999));
      expect(high.inMilliseconds, lessThanOrEqualTo(baseMs * 12 ~/ 10));
      expect(high.inMilliseconds, greaterThan(baseMs * 119 ~/ 100));
    }
  });

  test('only unrecoverable close codes stop blind reconnects', () {
    for (final code in [1008, 4401, 4404, 4426]) {
      expect(shouldStopReconnecting(code), isTrue, reason: '$code');
    }
    for (final code in [1006, 1011, 1012, 1013, 4408, 4429]) {
      expect(shouldStopReconnecting(code), isFalse, reason: '$code');
    }
  });
}

final class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final double value;

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
