import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/avatar/avatar_loader.dart';
import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'avatar_test_doubles.dart';

void main() {
  late AvatarServer server;
  late AvatarLoader loader;

  setUp(() {
    server = AvatarServer();
    loader = AvatarLoader(Dio()..httpClientAdapter = server);
  });

  test('a 404 from Gravatar means no avatar: no mirror is asked and later '
      'avatars still come from Gravatar', () async {
    server.missing.add(gravatar);

    expect(await loader.load(avatarUrl('a')), isNull);
    expect(await loader.load(avatarUrl('b')), isNull);
    expect(server.requests, [gravatar, gravatar]);
  });

  test('an address known to have no avatar is not asked for again', () async {
    server.missing.add(gravatar);

    await loader.load(avatarUrl());
    expect(await loader.load(avatarUrl()), isNull);
    expect(server.requests, [gravatar]);
  });

  test('avatars loaded before a site is chosen wait for a single probe, '
      'which gives Gravatar 3 seconds and then tries the mirrors '
      'together', () {
    fakeAsync((async) {
      server
        ..hanging.addAll([gravatar, weavatar])
        ..avatars[cravatar] = [3];
      final loaded = <Uint8List?>[];
      for (final hash in ['a', 'b', 'c']) {
        unawaited(loader.load(avatarUrl(hash)).then(loaded.add));
      }

      async.elapse(const Duration(milliseconds: 2900));
      expect(server.requests, [gravatar]);

      async.elapse(const Duration(milliseconds: 100));
      expect(loaded, [
        [3],
        [3],
        [3],
      ]);
      expect(server.requests, [
        gravatar,
        weavatar,
        cravatar,
        cravatar,
        cravatar,
      ]);
    });
  });

  test('when the chosen site stops answering, the next avatar starts again '
      'from Gravatar', () {
    fakeAsync((async) {
      server.avatars[weavatar] = [2];
      Uint8List? first;
      unawaited(loader.load(avatarUrl('a')).then((bytes) => first = bytes));
      async.flushMicrotasks();
      async.elapse(Duration.zero);
      expect(first, [2]);

      server
        ..avatars.remove(weavatar)
        ..hanging.add(weavatar)
        ..avatars[gravatar] = [1]
        ..requests.clear();
      Uint8List? second;
      unawaited(loader.load(avatarUrl('b')).then((bytes) => second = bytes));
      async.elapse(const Duration(milliseconds: 9900));
      expect(server.requests, [weavatar]);

      async.elapse(const Duration(milliseconds: 100));
      expect(second, [1]);
      expect(server.cancelled, 1);
      server.requests.clear();

      unawaited(loader.load(avatarUrl('c')));
      async.elapse(Duration.zero);
      expect(server.requests, [gravatar]);
    });
  });

  test('when no site can be reached the avatar fails without its address, '
      'and the next one probes again', () async {
    Object? failure;
    try {
      await loader.load(avatarUrl());
    } on AvatarUnavailable catch (error) {
      failure = error;
    }

    expect(failure, isA<AvatarUnavailable>());
    expect('$failure', isNot(contains('abc123')));
    expect(server.requests, [gravatar, weavatar, cravatar]);

    server.avatars[gravatar] = [1];
    expect(await loader.load(avatarUrl()), [1]);
  });
}
