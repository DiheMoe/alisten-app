import 'dart:async';
import 'dart:io';

import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:alisten/core/avatar/disk_avatar_cache.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'avatar_test_doubles.dart';

void main() {
  late Directory root;
  late Directory avatars;
  late AvatarServer server;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('alisten-avatars-');
    avatars = Directory('${root.path}/avatars');
    server = AvatarServer();
  });

  tearDown(() => root.delete(recursive: true));

  // 每个实例相当于应用的一次运行。
  DiskAvatarCache open([AvatarServer? via]) {
    return DiskAvatarCache(
      AvatarLoader(Dio()..httpClientAdapter = via ?? server),
      directory: () async => avatars,
    );
  }

  Future<void> storedInEarlierRun(List<int> avatar) async {
    await open(AvatarServer()..avatars[gravatar] = avatar).load(avatarUrl());
  }

  Future<List<File>> files() async {
    if (!await avatars.exists()) return const [];
    return [await for (final entity in avatars.list()) File(entity.path)];
  }

  Future<List<List<int>>> stored() async {
    return [for (final file in await files()) await file.readAsBytes()];
  }

  test(
    'an avatar is downloaded once, stored under a name that does not '
    'reveal its address, and read from this device after a restart',
    () async {
      server.avatars[gravatar] = [1, 2, 3];

      expect(await open().load(avatarUrl()), [1, 2, 3]);

      expect(server.requests, [gravatar]);
      expect(await stored(), [
        [1, 2, 3],
      ]);
      final name = (await files()).single.uri.pathSegments.last;
      expect(name, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(name, isNot(contains('abc123')));
      final restarted = open(AvatarServer());
      expect(await restarted.load(avatarUrl()), [1, 2, 3]);
      await restarted.refreshing;
    },
  );

  test('a stored avatar is shown without waiting for any site', () async {
    await storedInEarlierRun([1]);
    final respond = Completer<void>();
    server
      ..avatars[gravatar] = [1]
      ..responding = respond.future;
    final cache = open();

    expect(await cache.load(avatarUrl()), [1]);

    respond.complete();
    await cache.refreshing;
  });

  test('a member without an avatar is not stored', () async {
    server.missing.add(gravatar);

    expect(await open().load(avatarUrl()), isNull);
    expect(await stored(), isEmpty);
  });

  test('an avatar no site can serve fails and is not stored', () async {
    await expectLater(
      open().load(avatarUrl()),
      throwsA(isA<AvatarUnavailable>()),
    );
    expect(await stored(), isEmpty);
  });

  test('a stored avatar is checked again once per run, in the '
      'background', () async {
    await storedInEarlierRun([1]);
    server.avatars[gravatar] = [1];
    final cache = open();

    await Future.wait([cache.load(avatarUrl()), cache.load(avatarUrl())]);
    await cache.refreshing;
    expect(await cache.load(avatarUrl()), [1]);
    await cache.refreshing;

    expect(server.requests, [gravatar]);
    expect(await stored(), [
      [1],
    ]);
  });

  test('an avatar downloaded in this run is not checked again', () async {
    server.avatars[gravatar] = [1];
    final cache = open();

    await cache.load(avatarUrl());
    await cache.load(avatarUrl());
    await cache.refreshing;

    expect(server.requests, [gravatar]);
  });

  test('a changed avatar replaces the stored one, while the stored one '
      'is shown', () async {
    await storedInEarlierRun([1]);
    server.avatars[gravatar] = [2];
    final cache = open();

    expect(await cache.load(avatarUrl()), [1]);
    await cache.refreshing;

    expect(await stored(), [
      [2],
    ]);
  });

  test('an avatar its owner removed is deleted from this device after it '
      'was shown', () async {
    await storedInEarlierRun([1]);
    server.missing.add(gravatar);
    final cache = open();

    expect(await cache.load(avatarUrl()), [1]);
    await cache.refreshing;

    expect(await stored(), isEmpty);
  });

  test('a stored avatar is kept when no site can be reached', () async {
    await storedInEarlierRun([1]);
    final cache = open();

    expect(await cache.load(avatarUrl()), [1]);
    await cache.refreshing;

    expect(server.requests, [gravatar, weavatar, cravatar]);
    expect(await stored(), [
      [1],
    ]);
  });

  test('an avatar that arrives after the cache was cleared is shown but '
      'not stored', () async {
    server.avatars[gravatar] = [1];
    final respond = Completer<void>();
    server.responding = respond.future;
    final cache = open();
    final loading = cache.load(avatarUrl());
    await server.requested;

    await cache.clear();
    respond.complete();

    expect(await loading, [1]);
    expect(await stored(), isEmpty);
    expect(await cache.size(), 0);
  });

  test('a check that finishes after the cache was cleared is not '
      'stored', () async {
    await storedInEarlierRun([1]);
    server.avatars[gravatar] = [2];
    final respond = Completer<void>();
    server.responding = respond.future;
    final cache = open();
    expect(await cache.load(avatarUrl()), [1]);
    await server.requested;

    await cache.clear();
    respond.complete();
    await cache.refreshing;

    expect(await stored(), isEmpty);
    expect(await cache.size(), 0);
  });

  test('a removal the check finds after the cache was cleared spares the '
      'avatar stored since', () async {
    await storedInEarlierRun([1]);
    server.missing.add(gravatar);
    final respond = Completer<void>();
    server.responding = respond.future;
    final cache = open();
    expect(await cache.load(avatarUrl()), [1]);
    await server.requested;

    await cache.clear();
    await storedInEarlierRun([2]);
    respond.complete();
    await cache.refreshing;

    expect(await stored(), [
      [2],
    ]);
  });

  test('an avatar asked for twice at once is downloaded and stored '
      'once', () async {
    server.avatars[gravatar] = [1];
    final cache = open();
    await cache.load(avatarUrl('chosen-site'));
    server.requests.clear();

    final both = await Future.wait([
      cache.load(avatarUrl()),
      cache.load(avatarUrl()),
    ]);

    expect(both, [
      [1],
      [1],
    ]);
    expect(server.requests, [gravatar]);
    expect(await files(), hasLength(2));
  });

  test('the avatars used longest ago are let go beyond the size '
      'limit', () async {
    var now = DateTime.utc(2026, 11, 4);
    final cache = DiskAvatarCache(
      AvatarLoader(Dio()..httpClientAdapter = server),
      directory: () async => avatars,
      maxBytes: 4,
      now: () => now = now.add(const Duration(seconds: 1)),
    );
    server.avatars[gravatar] = [1, 2, 3];

    await cache.load(avatarUrl('first'));
    await cache.trimming;
    server.avatars[gravatar] = [4, 5, 6];
    await cache.load(avatarUrl('second'));
    await cache.trimming;

    expect(await stored(), [
      [4, 5, 6],
    ]);
  });

  test('the size counts every stored avatar, and clearing removes them '
      'all', () async {
    server.avatars[gravatar] = [1, 2, 3];
    final cache = open();
    await cache.load(avatarUrl('a'));
    await cache.load(avatarUrl('b'));
    expect(await cache.size(), 6);

    await cache.clear();

    expect(await stored(), isEmpty);
    expect(await cache.size(), 0);
  });

  test('a cache that has stored nothing is empty', () async {
    final cache = open();

    expect(await cache.size(), 0);
    await cache.clear();
    expect(await cache.size(), 0);
  });

  test('avatars are still downloaded when there is no cache directory, '
      'which is logged once', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);
    server.avatars[gravatar] = [1];
    final cache = DiskAvatarCache(
      AvatarLoader(Dio()..httpClientAdapter = server),
      directory: () async => throw const FileSystemException('unavailable'),
    );

    expect(await cache.load(avatarUrl()), [1]);
    expect(await cache.load(avatarUrl()), [1]);
    expect(server.requests, [gravatar, gravatar]);
    expect(
      records.where((message) => message.contains('directory unavailable')),
      hasLength(1),
    );
  });

  test('nothing logged while caching avatars carries their address', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    final nowhere = DiskAvatarCache(
      AvatarLoader(Dio()..httpClientAdapter = server),
      directory: () async => throw const FileSystemException('unavailable'),
    );

    await expectLater(
      nowhere.load(avatarUrl()),
      throwsA(isA<AvatarUnavailable>()),
    );
    server.avatars[gravatar] = [1];
    await nowhere.load(avatarUrl());

    expect(records, contains(startsWith('alisten.avatars cache directory')));
    expect(records, everyElement(isNot(contains('abc123'))));
  });
}
