import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/domain/playlist/playlist_file.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/application/playlist_requests.dart'
    show unexpectedFailureText;
import 'package:alisten/features/playlists/index.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../playlists_test_doubles.dart';

final _server = NotifierProvider<_Server, int>(_Server.new);

/// 选文件要等用户选完：[answer] 完成之前一直挂起。
final class _HeldFileSource implements PlaylistFileSource {
  final answer = Completer<PlaylistFileResult?>();

  @override
  Future<PlaylistFileResult?> pick() => answer.future;
}

final class _Server extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state++;
}

void main() {
  late FakePlaylistApi server;

  setUp(() {
    server = FakePlaylistApi()
      ..playlists.addAll([favoritesPlaylist, playlist('pl-1')]);
  });

  Future<
    ({
      OpenedPlaylists opened,
      ProviderSubscription<MyPlaylistsState> list,
      MyPlaylistsController controller,
    })
  >
  open({
    bool signedIn = true,
    bool restored = true,
    Override? playlistApi,
  }) async {
    final opened = await playlistsContainer(
      playlists: server,
      playlistApi: playlistApi,
      signedIn: signedIn,
      restored: restored,
    );
    final list = opened.container.listen(
      myPlaylistsControllerProvider,
      (_, _) {},
    );
    await pumpEventQueue();
    return (
      opened: opened,
      list: list,
      controller: opened.container.read(myPlaylistsControllerProvider.notifier),
    );
  }

  List<String> ids(ProviderSubscription<MyPlaylistsState> list) => [
    for (final playlist in list.read().playlists ?? const <MyPlaylist>[])
      playlist.id,
  ];

  Override switchable(FakePlaylistApi other) => playlistApiProvider
      .overrideWith((ref) => ref.watch(_server) == 0 ? server : other);

  Future<void> signOut(OpenedPlaylists opened) => opened.container
      .read(identityControllerProvider.notifier)
      .signOut((api) => api.logout());

  group('belonging', () {
    test('a guest sends nothing and is told as a guest', () async {
      final (:opened, :list, controller: _) = await open(signedIn: false);

      expect(list.read().guest, isTrue);
      expect(list.read().playlists, isNull);
      expect(server.calls, isEmpty);
      expect(opened.api.getMeCalls, 1);
    });

    test('an account reads its playlists at once', () async {
      final (opened: _, :list, controller: _) = await open();

      expect(ids(list), ['fav', 'pl-1']);
      expect(list.read().loadedAtMs, testNowMs);
      expect(list.read().guest, isFalse);
    });

    test('an identity not read yet is restored first; a guest only once '
        'that ends', () async {
      final opened = await playlistsContainer(
        playlists: server,
        signedIn: false,
        restored: false,
      );
      final gate = Completer<Member>();
      opened.api.getMeResult = gate;
      final list = opened.container.listen(
        myPlaylistsControllerProvider,
        (_, _) {},
      );
      await pumpEventQueue();

      expect(opened.api.getMeCalls, 1);
      expect(list.read().guest, isFalse);
      expect(list.read().playlists, isNull);

      gate.complete(FakeAlistenApi.member);
      await pumpEventQueue();
      expect(list.read().guest, isTrue);
      expect(server.calls, isEmpty);
    });

    test('a restore that finds an account reads the list', () async {
      final (:opened, :list, controller: _) = await open(restored: false);

      expect(opened.api.getMeCalls, 1);
      expect(ids(list), ['fav', 'pl-1']);
    });

    test('a restore that fails is a failed read with a retry, never a '
        'guest', () async {
      final opened = await playlistsContainer(
        playlists: server,
        restored: false,
      );
      opened.api.getMeError = networkError;
      final list = opened.container.listen(
        myPlaylistsControllerProvider,
        (_, _) {},
      );
      await pumpEventQueue();

      expect(list.read().guest, isFalse);
      expect(list.read().error, networkError.message);
      expect(list.read().playlists, isNull);

      opened.api.getMeError = null;
      await opened.container
          .read(myPlaylistsControllerProvider.notifier)
          .retry();
      await pumpEventQueue();
      expect(opened.api.getMeCalls, 2);
      expect(ids(list), ['fav', 'pl-1']);
      expect(list.read().error, isNull);
    });

    test('a restore refused by a rate limit tells the wait, and one that '
        'ends unexpectedly tells the credentials cannot be read', () async {
      for (final (error, told) in [
        (
          apiError(
            'RATE_LIMITED',
            message: '请求太频繁，请稍后再试。',
            status: 429,
            retryAfter: const Duration(seconds: 3),
          ),
          '请求太频繁，请 3 秒后再试',
        ),
        (Exception('keystore'), identityUnreadableText),
      ]) {
        final opened = await playlistsContainer(
          playlists: server,
          restored: false,
        );
        opened.api.getMeError = error;
        final list = opened.container.listen(
          myPlaylistsControllerProvider,
          (_, _) {},
        );
        await pumpEventQueue();

        expect(list.read().error, told, reason: '$error');
        expect(list.read().guest, isFalse);
      }
    });

    test('signing in starts over with the new account', () async {
      final (:opened, :list, controller: _) = await open(signedIn: false);
      expect(list.read().guest, isTrue);

      await opened.container
          .read(identityControllerProvider.notifier)
          .adoptSession(
            (api) => api.login(username: 'mao', password: 'password1'),
          );
      await pumpEventQueue();

      expect(list.read().guest, isFalse);
      expect(ids(list), ['fav', 'pl-1']);
    });

    test('a guest who registers keeps the session and is read once the '
        'account appears', () async {
      final (:opened, :list, controller: _) = await open(signedIn: false);
      final identity = opened.container.read(identityControllerProvider);

      opened.container
          .read(identityControllerProvider.notifier)
          .updateAccount(identity.member!.id, testAccount);
      await pumpEventQueue();

      expect(
        opened.container.read(identityControllerProvider).session,
        identity.session,
      );
      expect(ids(list), ['fav', 'pl-1']);
    });

    test('signing out clears the list', () async {
      final (:opened, :list, controller: _) = await open();

      await signOut(opened);
      await pumpEventQueue();

      expect(list.read().playlists, isNull);
    });

    test('a new server starts over with its own playlists, and a read from '
        'before is dropped', () async {
      final other = FakePlaylistApi()..playlists.add(playlist('elsewhere'));
      final (:opened, :list, :controller) = await open(
        playlistApi: playlistApiProvider.overrideWith(
          (ref) => ref.watch(_server) == 0 ? server : other,
        ),
      );
      final stale = server.hold('listMine');
      unawaited(controller.load());
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      expect(ids(list), ['elsewhere']);

      stale.complete();
      await pumpEventQueue();
      expect(ids(list), ['elsewhere']);
    });

    test('a read answered as the server changes, before the list starts '
        'over, is dropped', () async {
      final other = FakePlaylistApi()..playlists.add(playlist('elsewhere'));
      final (:opened, :list, :controller) = await open(
        playlistApi: switchable(other),
      );
      final stale = server.hold('listMine');
      unawaited(controller.load());
      await pumpEventQueue();
      other.hold('listMine');

      opened.container.read(_server.notifier).next();
      stale.complete();
      await pumpEventQueue();

      expect(other.count('listMine'), 1);
      expect(list.read().playlists, isNull);
    });

    test('a read answered after signing out is not shown to the '
        'guest', () async {
      final (:opened, :list, :controller) = await open();
      final stale = server.hold('listMine');
      unawaited(controller.load());
      await pumpEventQueue();

      await signOut(opened);
      await pumpEventQueue();
      stale.complete();
      await pumpEventQueue();

      expect(list.read().guest, isTrue);
      expect(list.read().playlists, isNull);
    });

    test('a guest moving to a server whose identity cannot be read yet is '
        'a failed read, not a guest', () async {
      final (:opened, :list, controller: _) = await open(
        signedIn: false,
        playlistApi: switchable(FakePlaylistApi()),
      );
      expect(list.read().guest, isTrue);

      // 列表可能在身份重置之前就按新服务器重新开始，这时身份还是旧服务器的。
      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      opened.api.getMeError = networkError;
      await opened.container
          .read(identityControllerProvider.notifier)
          .resetForServerChange();
      await pumpEventQueue();

      expect(list.read().guest, isFalse);
      expect(list.read().error, networkError.message);
    });

    test('coming back to the foreground reads again, only while in '
        'use', () async {
      final (:opened, :list, controller: _) = await open();
      final visibility = opened.container.read(appVisibleProvider.notifier);

      visibility.follow(AppLifecycleState.paused);
      await pumpEventQueue();
      expect(server.count('listMine'), 1);

      visibility.follow(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(server.count('listMine'), 2);

      visibility.follow(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(server.count('listMine'), 2);

      list.close();
      await opened.container.pump();
      visibility
        ..follow(AppLifecycleState.paused)
        ..follow(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(server.count('listMine'), 2);
    });
  });

  group('the list', () {
    test('of two reads out of order only the later one is kept', () async {
      final (opened: _, :list, :controller) = await open();
      final first = server.hold('listMine');
      unawaited(controller.load());
      await pumpEventQueue();
      server.playlists.add(playlist('pl-2'));

      await controller.load();
      first.complete();
      await pumpEventQueue();

      expect(ids(list), ['fav', 'pl-1', 'pl-2']);
    });

    test('a new playlist is in the list before it is read again', () async {
      final (opened: _, :list, :controller) = await open();
      server.hold('listMine');

      final result = await controller.create('  夜跑  ');

      final created = (result as MutationSucceeded<MyPlaylist>).value;
      expect(created.name, '夜跑');
      expect(server.calls, contains('create 夜跑'));
      expect(ids(list), ['fav', 'pl-1', created.id]);
      await pumpEventQueue();
      expect(ids(list), ['fav', 'pl-1', created.id]);
      expect(server.count('listMine'), 2);
    });

    test('renaming, sharing, stopping a share and deleting change the list '
        'first', () async {
      final (opened: _, :list, :controller) = await open();
      for (var i = 0; i < 4; i++) {
        server.hold('listMine');
      }
      MyPlaylist mine(String id) =>
          list.read().playlists!.firstWhere((playlist) => playlist.id == id);

      await controller.rename(mine('pl-1'), ' 晨跑 ');
      expect(mine('pl-1').name, '晨跑');

      final shared = await controller.share(mine('pl-1'));
      expect(mine('pl-1').shareId, (shared as MutationSucceeded<String>).value);

      await controller.unshare(mine('pl-1'));
      expect(mine('pl-1').shareId, isNull);

      await controller.delete(mine('pl-1'));
      expect(ids(list), ['fav']);
      await pumpEventQueue();
      expect(server.count('listMine'), 5);
    });

    test('a share link is on the site of the current server', () async {
      final (:opened, list: _, :controller) = await open();
      final host = opened.container.read(appConfigProvider).linkHost;

      expect(controller.shareLink(shareIdA), 'https://$host/s/$shareIdA');
    });

    test('a playlist made before signing out is not put in the guest '
        'list', () async {
      final (:opened, :list, :controller) = await open();
      final gate = server.hold('create');
      final creating = controller.create('夜跑');
      await pumpEventQueue();

      await signOut(opened);
      await pumpEventQueue();
      gate.complete();
      final result = await creating;
      await pumpEventQueue();

      expect(result, isA<MutationSucceeded<MyPlaylist>>());
      expect(list.read().guest, isTrue);
      expect(list.read().playlists, isNull);
      expect(server.count('listMine'), 1);
    });

    test('a change answered after a server switch is told as done on the '
        'old server, not the new one', () async {
      final other = FakePlaylistApi();
      final (:opened, :list, :controller) = await open(
        playlistApi: switchable(other),
      );
      final gate = server.hold('create');
      final creating = controller.create('夜跑');
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      gate.complete();
      final result = await creating;
      await pumpEventQueue();

      expect(
        result,
        isA<MutationNotSent<MyPlaylist>>().having(
          (r) => r.message,
          'message',
          doneOnOldServerText,
        ),
      );
      expect(server.calls, contains('create 夜跑'));
      expect(ids(list), isEmpty);
      expect(other.count('listMine'), 1);
    });

    test('a change whose answer is lost after a server switch may have been '
        'done on the old server; a refusal was not done', () async {
      for (final (error, told) in [
        (networkError, unsureOnOldServerText),
        (Exception('boom'), unsureOnOldServerText),
        (apiError('CONFLICT', message: '最多只能建 50 个歌单'), serverChangedNotice),
      ]) {
        final (:opened, list: _, :controller) = await open(
          playlistApi: switchable(FakePlaylistApi()),
        );
        final gate = server.hold('create');
        server.failNext('create', error);
        final creating = controller.create('夜跑');
        await pumpEventQueue();

        opened.container.read(_server.notifier).next();
        await pumpEventQueue();
        gate.complete();

        expect(
          await creating,
          isA<MutationNotSent<MyPlaylist>>().having(
            (r) => r.message,
            'message',
            told,
          ),
          reason: '$error',
        );
      }
    });

    test('a change whose token read outlasts a server switch is sent to '
        'neither server', () async {
      final other = FakePlaylistApi();
      final (:opened, list: _, :controller) = await open(
        playlistApi: switchable(other),
      );
      final reading = Completer<void>();
      opened.credentials.readMemberTokenGate = reading;
      final creating = controller.create('夜跑');
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      reading.complete();

      expect(
        await creating,
        isA<MutationNotSent<MyPlaylist>>().having(
          (r) => r.message,
          'message',
          serverChangedNotice,
        ),
      );
      expect(server.count('create') + other.count('create'), 0);
    });
  });

  group('failures', () {
    test('a name the server refuses is told by the naming rule', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('create', apiError('INVALID_ARGUMENT'));

      final result = await controller.create('x' * 60);

      expect(
        result,
        isA<MutationFailed<MyPlaylist>>()
            .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
            .having((r) => r.message, 'message', '歌单名要 1 到 50 个字。'),
      );
    });

    test('a rename or a copy of a shared playlist the server refuses is told '
        'by the naming rule', () async {
      final (opened: _, list: _, :controller) = await open();
      server
        ..failNext('rename', apiError('INVALID_ARGUMENT'))
        ..failNext('copyShared', apiError('INVALID_ARGUMENT'));

      final renamed = await controller.rename(playlist('pl-1'), 'x' * 60);
      final copied = await controller.copyShared(shareIdA, 'x' * 60);

      for (final result in [renamed, copied]) {
        expect(
          result,
          isA<MutationFailed<Object?>>()
              .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
              .having((r) => r.message, 'message', invalidPlaylistNameText),
        );
      }
    });

    test('a conflict is told with the server message', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('create', apiError('CONFLICT', message: '最多只能建 50 个歌单'));

      final result = await controller.create('夜跑');

      expect((result as MutationFailed).message, '最多只能建 50 个歌单');
    });

    test('a rate limit was not carried out', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext(
        'create',
        apiError(
          'RATE_LIMITED',
          message: '请求太频繁，请稍后再试。',
          status: 429,
          retryAfter: const Duration(seconds: 3),
        ),
      );

      final result = await controller.create('夜跑');

      expect(
        result,
        isA<MutationNotSent<MyPlaylist>>().having(
          (r) => r.message,
          'message',
          '请求太频繁，请 3 秒后再试',
        ),
      );
    });

    test('a rate limited read tells the wait', () async {
      final (opened: _, :list, :controller) = await open();
      server.failNext(
        'listMine',
        apiError(
          'RATE_LIMITED',
          message: '请求太频繁，请稍后再试。',
          status: 429,
          retryAfter: const Duration(seconds: 3),
        ),
      );

      await controller.load();

      expect(list.read().error, '请求太频繁，请 3 秒后再试');
    });

    test('a change without a member token was not sent', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext(
        'create',
        apiError(LocalErrorCodes.noToken, message: '还没有身份'),
      );

      final result = await controller.create('夜跑');

      expect(
        result,
        isA<MutationNotSent<MyPlaylist>>().having(
          (r) => r.message,
          'message',
          '还没有身份',
        ),
      );
    });

    test('a lost answer is unknown, and the list is read again', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('rename', networkError);

      final result = await controller.rename(playlist('pl-1'), '晨跑');
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<void>>());
      expect(server.count('listMine'), 2);
    });

    test('a change that ends unexpectedly is unknown, and the list is read '
        'again', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('share', Exception('boom'));

      final result = await controller.share(playlist('pl-1'));
      await pumpEventQueue();

      expect(result, isA<MutationUnknown<String>>());
      expect(server.count('listMine'), 2);
    });

    test('a read that ends unexpectedly is told by the general '
        'text', () async {
      final (opened: _, :list, :controller) = await open();
      server.failNext('listMine', Exception('boom'));

      await controller.load();

      expect(list.read().error, unexpectedFailureText);
      expect(ids(list), ['fav', 'pl-1']);
    });

    test('a playlist gone from the server reads the list again', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('delete', apiError('NOT_FOUND', status: 404));

      await controller.delete(playlist('pl-1'));
      await pumpEventQueue();

      expect(server.count('listMine'), 2);
    });

    test('FORBIDDEN refreshes the identity and tells the server '
        'message', () async {
      final (:opened, :list, :controller) = await open();
      final before = opened.api.getMeCalls;
      server.failNext(
        'listMine',
        apiError('FORBIDDEN', message: '注册账号之后才能使用歌单', status: 403),
      );

      await controller.load();

      expect(list.read().error, '注册账号之后才能使用歌单');
      await pumpEventQueue();
      expect(opened.api.getMeCalls, before + 1);
    });

    test('a change refused as FORBIDDEN refreshes the identity and tells the '
        'server message', () async {
      final (:opened, list: _, :controller) = await open();
      final before = opened.api.getMeCalls;
      server.failNext(
        'create',
        apiError('FORBIDDEN', message: '注册账号之后才能使用歌单', status: 403),
      );

      final result = await controller.create('夜跑');
      await pumpEventQueue();

      expect(
        result,
        isA<MutationFailed<MyPlaylist>>()
            .having((r) => r.code, 'code', 'FORBIDDEN')
            .having((r) => r.message, 'message', '注册账号之后才能使用歌单'),
      );
      expect(opened.api.getMeCalls, before + 1);
    });

    test('a refused change replaces the identity and tells the text it '
        'gives, once', () async {
      final (:opened, :list, :controller) = await open();
      // 服务端为替换的身份新建的是游客。
      opened.api.account = null;
      server.failNext('create', apiError('UNAUTHORIZED', status: 401));

      final result = await controller.create('夜跑');
      await pumpEventQueue();

      expect(
        result,
        isA<MutationFailed<MyPlaylist>>()
            .having((r) => r.code, 'code', 'UNAUTHORIZED')
            .having((r) => r.message, 'message', signedOutNotice),
      );
      expect(opened.api.createMemberCalls, 1);
      expect(opened.credentials.memberToken, 'new-member-token');
      expect(list.read().guest, isTrue);
    });

    test('a refused read replaces the identity without an error', () async {
      final opened = await playlistsContainer(playlists: server);
      server.failNext('listMine', apiError('UNAUTHORIZED', status: 401));
      final list = opened.container.listen(
        myPlaylistsControllerProvider,
        (_, _) {},
      );
      await pumpEventQueue();

      expect(list.read().error, isNull);
      expect(opened.api.createMemberCalls, 1);
    });

    test('the token read before the request is the one handed over as '
        'refused', () async {
      final (:opened, list: _, :controller) = await open();
      server
        ..onCall = (method) {
          if (method == 'create') {
            opened.credentials.memberToken = 'renewed-elsewhere';
          }
        }
        ..failNext('create', apiError('UNAUTHORIZED', status: 401));

      await controller.create('夜跑');

      expect(opened.api.createMemberCalls, 0, reason: 'already renewed');
      expect(opened.credentials.memberToken, 'renewed-elsewhere');
    });

    test('a token that cannot be read is handed over as none', () async {
      final (:opened, list: _, :controller) = await open();
      opened.credentials.readMemberTokenError = Exception('keystore');
      server.failNext('create', apiError('UNAUTHORIZED', status: 401));

      final result = await controller.create('夜跑');

      expect((result as MutationFailed).code, 'UNAUTHORIZED');
      expect(opened.api.createMemberCalls, 1);
    });
  });

  group('imports', () {
    final file = PlaylistFile(
      name: '旧歌单',
      tracks: const [
        PlaylistFileTrack(
          track: Track(source: TrackSource.qq, id: '1'),
          title: '晴天',
          durationMs: 0,
        ),
      ],
      truncated: true,
    );

    test('a file becomes a new playlist in the list', () async {
      final (opened: _, :list, :controller) = await open();
      server.hold('listMine');

      final result = await controller.importFile(file);

      final imported = (result as MutationSucceeded<ImportedPlaylist>).value;
      expect(imported.imported, 1);
      expect(server.calls, contains('importFile 旧歌单 1'));
      expect(ids(list), contains(imported.playlist.id));
    });

    test('a file the server refuses is told as unsuitable content', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('importFile', apiError('INVALID_ARGUMENT'));

      final result = await controller.importFile(file);

      expect((result as MutationFailed).message, '文件里有不符合要求的内容，没有导入。');
    });

    test('a link over 2048 bytes is not sent, counted in bytes', () async {
      final (opened: _, list: _, :controller) = await open();

      final long = await controller.importLink('歌' * 683, '导入的歌单');
      expect(
        long,
        isA<MutationNotSent<ImportedPlaylist>>().having(
          (r) => r.message,
          'message',
          '文字太长了，只粘贴歌单的链接或分享文字就好。',
        ),
      );
      expect(server.count('resolveLink'), 0);

      await controller.importLink('歌' * 682, '导入的歌单');
      expect(server.count('resolveLink'), 1);
    });

    test('a link is resolved, then imported under the given name', () async {
      final (opened: _, list: _, :controller) = await open();

      final result = await controller.importLink(
        '  https://music.163.com/playlist?id=24381616  ',
        ' 导入的歌单 ',
      );

      expect(result, isA<MutationSucceeded<ImportedPlaylist>>());
      expect(server.calls.where((call) => !call.startsWith('listMine')), [
        'resolveLink https://music.163.com/playlist?id=24381616',
        'importPlatform 导入的歌单 netease:24381616',
      ]);
    });

    test('a link that cannot be resolved is not imported, and the server '
        'says why', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext(
        'resolveLink',
        apiError('INVALID_ARGUMENT', message: '不是网易云或 QQ 音乐的歌单链接'),
      );

      final result = await controller.importLink('https://example.com', '歌单');

      expect((result as MutationFailed).message, '不是网易云或 QQ 音乐的歌单链接');
      expect(server.count('importPlatform'), 0);
    });

    test('a link imported under a name the server refuses is told by the '
        'naming rule, not the server text', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext(
        'importPlatform',
        apiError('INVALID_ARGUMENT', message: 'name：长度必须在 1 到 50 之间'),
      );

      final result = await controller.importLink(
        'https://music.163.com/playlist?id=24381616',
        '导入的歌单',
      );

      expect(
        result,
        isA<MutationFailed<ImportedPlaylist>>()
            .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
            .having((r) => r.message, 'message', invalidPlaylistNameText),
      );
    });

    test('a link whose resolution is lost failed, changed nothing and needs '
        'no read again', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('resolveLink', networkError);

      final result = await controller.importLink('https://example.com', '歌单');
      await pumpEventQueue();

      expect(
        result,
        isA<MutationFailed<ImportedPlaylist>>()
            .having((r) => r.code, 'code', LocalErrorCodes.network)
            .having((r) => r.message, 'message', networkError.message),
      );
      expect(server.count('importPlatform'), 0);
      expect(server.count('listMine'), 1);
    });

    test('a link not resolved for a rate limit or a missing token was not '
        'sent', () async {
      final (opened: _, list: _, :controller) = await open();
      for (final (error, told) in [
        (
          apiError(
            'RATE_LIMITED',
            message: '请求太频繁，请稍后再试。',
            status: 429,
            retryAfter: const Duration(seconds: 3),
          ),
          '请求太频繁，请 3 秒后再试',
        ),
        (apiError(LocalErrorCodes.noToken, message: '还没有身份'), '还没有身份'),
      ]) {
        server.failNext('resolveLink', error);

        final result = await controller.importLink('https://example.com', '歌单');

        expect(
          result,
          isA<MutationNotSent<ImportedPlaylist>>().having(
            (r) => r.message,
            'message',
            told,
          ),
          reason: error.code,
        );
      }
      expect(server.count('importPlatform'), 0);
    });

    test('a link whose resolution is refused replaces the identity and tells '
        'the text it gives', () async {
      final (:opened, list: _, :controller) = await open();
      opened.api.account = null;
      server.failNext('resolveLink', apiError('UNAUTHORIZED', status: 401));

      final result = await controller.importLink('https://example.com', '歌单');

      expect(
        result,
        isA<MutationFailed<ImportedPlaylist>>()
            .having((r) => r.code, 'code', 'UNAUTHORIZED')
            .having((r) => r.message, 'message', signedOutNotice),
      );
      expect(opened.api.createMemberCalls, 1);
      expect(server.count('importPlatform'), 0);
    });

    test('a link resolved across a server switch is imported on neither '
        'server', () async {
      final other = FakePlaylistApi();
      final (:opened, list: _, :controller) = await open(
        playlistApi: switchable(other),
      );
      final gate = server.hold('resolveLink');
      final importing = controller.importLink(
        'https://music.163.com/playlist?id=24381616',
        '导入的歌单',
      );
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      gate.complete();

      expect(
        await importing,
        isA<MutationNotSent<ImportedPlaylist>>().having(
          (r) => r.message,
          'message',
          serverChangedNotice,
        ),
      );
      expect(server.count('importPlatform') + other.count('importPlatform'), 0);
    });

    test('a link resolved before signing out is not imported for whoever '
        'comes next', () async {
      final (:opened, list: _, :controller) = await open();
      final gate = server.hold('resolveLink');
      final importing = controller.importLink(
        'https://music.163.com/playlist?id=24381616',
        '导入的歌单',
      );
      await pumpEventQueue();

      await signOut(opened);
      gate.complete();
      final result = await importing;

      expect(
        result,
        isA<MutationNotSent<ImportedPlaylist>>().having(
          (r) => r.message,
          'message',
          identityRenewedNotice,
        ),
      );
      expect(server.count('importPlatform'), 0);
    });

    test('saving a NetEase playlist tells a refused name by the '
        'rule', () async {
      final (opened: _, list: _, :controller) = await open();
      server.failNext('importPlatform', apiError('INVALID_ARGUMENT'));

      final result = await controller.importPlatform(
        source: TrackSource.netease,
        playlistId: '1001',
        name: '华语流行',
      );

      expect((result as MutationFailed).message, invalidPlaylistNameText);
    });

    test('a shared playlist copied is a new playlist in the list', () async {
      final (opened: _, :list, :controller) = await open();
      server
        ..sharedPlaylist = SharedPlaylist(
          name: '夜跑',
          favorites: false,
          ownerName: '阿柚',
          ownerAvatarHash: '',
          items: [song('a'), song('b')],
        )
        ..hold('listMine');

      final result = await controller.copyShared(shareIdA, '夜跑');

      final copied = (result as MutationSucceeded<MyPlaylist>).value;
      expect(copied.trackCount, 2);
      expect(ids(list), contains(copied.id));
    });
  });

  group('importing a picked file', () {
    late FakePlaylistFileSource files;
    const file = PlaylistFile(
      name: '旧歌单',
      tracks: [
        PlaylistFileTrack(
          track: Track(source: TrackSource.qq, id: '1'),
          title: '晴天',
          durationMs: 0,
        ),
      ],
      truncated: true,
    );

    setUp(() => files = FakePlaylistFileSource());

    Future<
      ({
        OpenedPlaylists opened,
        ProviderSubscription<MyPlaylistsState> list,
        MyPlaylistsController controller,
      })
    >
    openWith(PlaylistFileSource source) async {
      final opened = await playlistsContainer(
        playlists: server,
        overrides: [playlistFileSourceProvider.overrideWithValue(source)],
      );
      final list = opened.container.listen(
        myPlaylistsControllerProvider,
        (_, _) {},
      );
      await pumpEventQueue();
      return (
        opened: opened,
        list: list,
        controller: opened.container.read(
          myPlaylistsControllerProvider.notifier,
        ),
      );
    }

    test('a picked file is parsed, imported and says it was cut', () async {
      files.next = file;
      final (opened: _, :list, :controller) = await openWith(files);
      server.hold('listMine');

      final result = await controller.importFromFile();

      final imported = (result! as MutationSucceeded<ImportedFile>).value;
      expect(imported.playlist.name, '旧歌单');
      expect(imported.imported, 1);
      expect(imported.truncated, isTrue);
      expect(files.picks, 1);
      expect(server.calls, contains('importFile 旧歌单 1'));
      expect(ids(list), contains(imported.playlist.id));
    });

    test('a cancelled pick sends nothing', () async {
      final (opened: _, list: _, :controller) = await openWith(files);

      expect(await controller.importFromFile(), isNull);
      expect(files.picks, 1);
      expect(server.count('importFile'), 0);
    });

    test('a file that is not a playlist is told and nothing is sent', () async {
      files.next = const PlaylistFileProblem('这个文件不是导出的歌单。');
      final (opened: _, list: _, :controller) = await openWith(files);

      final result = await controller.importFromFile();

      expect(
        result,
        isA<MutationFailed<ImportedFile>>().having(
          (r) => r.message,
          'message',
          '这个文件不是导出的歌单。',
        ),
      );
      expect(server.count('importFile'), 0);
    });

    test('a file picked while signing out is not imported for whoever comes '
        'next', () async {
      final source = _HeldFileSource();
      final (:opened, list: _, :controller) = await openWith(source);
      final importing = controller.importFromFile();
      await pumpEventQueue();

      await signOut(opened);
      source.answer.complete(file);
      final result = await importing;

      expect(
        result,
        isA<MutationNotSent<ImportedFile>>().having(
          (r) => r.message,
          'message',
          identityRenewedNotice,
        ),
      );
      expect(server.count('importFile'), 0);
    });
  });
}
