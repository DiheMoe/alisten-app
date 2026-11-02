import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the site admin never speaks of a room owner', () {
    final files = Directory('lib/features/admin')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(files, isNotEmpty);
    for (final file in files) {
      expect(file.readAsStringSync(), isNot(contains('房主')), reason: file.path);
    }
  });
}
