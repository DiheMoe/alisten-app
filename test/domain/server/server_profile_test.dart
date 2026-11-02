import 'package:alisten/domain/server/server_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final profile = ServerProfile(
    origin: 'https://example.com:8443',
    brandName: 'B',
    addedAtMs: 1,
  );

  test('the id and authority come from the origin', () {
    expect(profile.id, 'f475765b53c3272e');
    expect(profile.authority, 'example.com:8443');
  });

  test('a new brand name keeps the server and when it was added', () {
    final renamed = profile.withBrandName('新名字');

    expect(renamed.brandName, '新名字');
    expect(renamed.id, profile.id);
    expect(renamed.origin, profile.origin);
    expect(renamed.addedAtMs, 1);
    expect(renamed, isNot(profile));
  });

  test('the stored form reads back as an equal profile', () {
    final json = profile.toJson();

    expect(json, {
      'origin': 'https://example.com:8443',
      'brandName': 'B',
      'addedAtMs': 1,
    });
    expect(ServerProfile.tryParse(json), profile);
    expect(ServerProfile.tryParse(json).hashCode, profile.hashCode);
  });

  test('a stored profile that is incomplete, mistyped or not in canonical '
      'form is not read', () {
    for (final json in <Object?>[
      {'origin': 'https://Example.com', 'brandName': 'x', 'addedAtMs': 1},
      {'origin': 'https://example.com/', 'brandName': 'x', 'addedAtMs': 1},
      {'brandName': 'x', 'addedAtMs': 1},
      {'origin': 'https://example.com', 'addedAtMs': 1},
      {'origin': 'https://example.com', 'brandName': 'x'},
      {'origin': 'https://example.com', 'brandName': 'x', 'addedAtMs': '1'},
      {'origin': 1, 'brandName': 'x', 'addedAtMs': 1},
      'https://example.com',
      null,
    ]) {
      expect(ServerProfile.tryParse(json), isNull, reason: '$json');
    }
  });

  test('a brand name with nothing visible in it is shown as the authority', () {
    for (final name in ['​', '​‍﻿', '⁠ ‌']) {
      expect(
        profile.withBrandName(name).displayName,
        'example.com:8443',
        reason: name.runes.toList().toString(),
      );
    }
    for (final name in ['周末听歌会', 'B', '​♪', '!', '٣']) {
      expect(profile.withBrandName(name).displayName, name);
    }
  });

  test('a profile can only be made from a canonical origin', () {
    expect(
      () => ServerProfile(
        origin: 'https://Example.com/',
        brandName: 'x',
        addedAtMs: 1,
      ),
      throwsArgumentError,
    );
  });
}
