import 'package:alisten/features/admin/presentation/admin_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a time is shown in local time to the minute, every part two digits '
      'wide', () {
    expect(
      formatAdminTime(DateTime(2026, 11, 2, 9, 5).millisecondsSinceEpoch),
      '2026-11-02 09:05',
    );
    expect(
      formatAdminTime(
        DateTime(2026, 12, 31, 23, 59, 59).millisecondsSinceEpoch,
      ),
      '2026-12-31 23:59',
    );
  });
}
