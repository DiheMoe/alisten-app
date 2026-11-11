import 'package:alisten/domain/member/pairing_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePairingCode', () {
    for (final (input, expected) in [
      ('abcd2345', 'ABCD2345'),
      (' abcd 2345 ', 'ABCD2345'),
      ('\tABCD\n2345', 'ABCD2345'),
      ('ABCD-2345', 'ABCD2345'),
      ('abcd%2D2345', 'ABCD2345'),
      ('ABCD%202345', 'ABCD2345'),
      ('AB%zzCD', 'AB%ZZCD'),
      ('AB%FFCD', 'AB%FFCD'),
    ]) {
      test('"$input" becomes "$expected"', () {
        expect(normalizePairingCode(input), expected);
      });
    }
  });

  group('isPairingCode', () {
    test('accepts 8 of the digits 2–9 and letters other than I and O', () {
      expect(isPairingCode('ABCD2345'), isTrue);
      expect(isPairingCode('XYZ98765'), isTrue);
    });

    for (final invalid in [
      'ABCD2340',
      'ABCD234O',
      'ABCD2341',
      'ABCD234I',
      'ABCD234',
      'ABCD23456',
      'abcd2345',
      '',
    ]) {
      test('rejects "$invalid"', () => expect(isPairingCode(invalid), isFalse));
    }
  });

  test('a code is shown in two groups and spelled out for screen readers', () {
    expect(formatPairingCode('ABCD2345'), 'ABCD-2345');
    expect(formatPairingCode('ABC'), 'ABC');
    expect(spokenPairingCode('ABCD2345'), '配对码 A B C D 2 3 4 5');
  });

  test('the seconds left round up and stop at zero', () {
    expect(pairingSecondsLeft(10000, 0), 10);
    expect(pairingSecondsLeft(10000, 1), 10);
    expect(pairingSecondsLeft(10000, 9001), 1);
    expect(pairingSecondsLeft(10000, 10000), 0);
    expect(pairingSecondsLeft(10000, 20000), 0);
  });

  test('the countdown reads minutes and two-digit seconds', () {
    expect(pairingCountdownText(300), '5:00');
    expect(pairingCountdownText(299), '4:59');
    expect(pairingCountdownText(61), '1:01');
    expect(pairingCountdownText(60), '1:00');
    expect(pairingCountdownText(59), '0:59');
    expect(pairingCountdownText(0), '0:00');
  });
}
