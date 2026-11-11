import 'dart:async';
import 'dart:ui' show Rect;

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/track_order.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playback/index.dart';
import 'package:alisten/features/playlists/application/my_playlist_controller.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../playlists_test_doubles.dart';

final _server = NotifierProvider<_Server, int>(_Server.new);

final class _Server extends Notifier<int> {
  @override
  int build() => 0;

  void next() => state++;
}

const _a = Track(source: TrackSource.netease, id: 'a');
const _b = Track(source: TrackSource.netease, id: 'b');

void main() {
  late FakePlaylistApi server;
  late FakePlaylistExporter exporter;
  late OpenedPlaylists opened;
  late ProviderSubscription<MyPlaylistState> detail;
  late MyPlaylistController controller;

  Future<void> open({Override? playlistApi}) async {
    opened = await playlistsContainer(
      playlists: server,
      playlistApi: playlistApi,
      exporter: exporter,
    );
    detail = opened.container.listen(
      myPlaylistControllerProvider('pl-1'),
      (_, _) {},
    );
    await pumpEventQueue();
    controller = opened.container.read(
      myPlaylistControllerProvider('pl-1').notifier,
    );
  }

  List<String>? keys() => [
    for (final item in detail.read().items ?? const <TrackSummary>[])
      trackKey(item.track),
  ];

  Override switchable(FakePlaylistApi other) => playlistApiProvider
      .overrideWith((ref) => ref.watch(_server) == 0 ? server : other);

  Future<void> signOut() async {
    await opened.container
        .read(identityControllerProvider.notifier)
        .signOut((api) => api.logout());
    await pumpEventQueue();
  }

  Future<void> signIn() async {
    await opened.container
        .read(identityControllerProvider.notifier)
        .adoptSession(
          (api) => api.login(username: 'mao', password: 'password1'),
        );
    await pumpEventQueue();
  }

  setUp(() {
    exporter = FakePlaylistExporter();
    server = FakePlaylistApi()
      ..playlists.addAll([
        favoritesPlaylist,
        playlist('pl-1', name: '夜跑', trackCount: 4),
      ])
      ..contents['pl-1'] = [song('a'), song('b'), song('c'), song('d')];
  });

  test('reads the songs when opened', () async {
    await open();

    expect(keys(), ['netease:a', 'netease:b', 'netease:c', 'netease:d']);
    expect(detail.read().gone, isFalse);
  });

  test('a playlist the server does not know is gone', () async {
    server.playlists.removeLast();
    await open();

    expect(detail.read().gone, isTrue);
  });

  test('a playlist missing from a list read later is gone', () async {
    await open();

    server.playlists.removeLast();
    await opened.container.read(myPlaylistsControllerProvider.notifier).load();
    await pumpEventQueue();

    expect(detail.read().gone, isTrue);
  });

  test('a failed read drops the old songs', () async {
    await open();
    server.failNext('items', networkError);

    await controller.load();

    expect(detail.read().items, isNull);
    expect(detail.read().error, networkError.message);
  });

  test('songs read as NOT_FOUND make the playlist gone and read the list '
      'again', () async {
    await open();
    final lists = server.count('listMine');
    server.failNext(
      'items',
      apiError('NOT_FOUND', message: '歌单不存在', status: 404),
    );

    await controller.load();
    await pumpEventQueue();

    expect(detail.read().gone, isTrue);
    expect(server.count('listMine'), lists + 1);
  });

  test('coming back to the foreground reads the songs again, only while '
      'in use', () async {
    await open();
    final visibility = opened.container.read(appVisibleProvider.notifier);
    final reads = server.count('items');

    visibility.follow(AppLifecycleState.paused);
    await pumpEventQueue();
    expect(server.count('items'), reads);

    visibility.follow(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(server.count('items'), reads + 1);

    visibility.follow(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(server.count('items'), reads + 1);

    detail.close();
    await opened.container.pump();
    visibility
      ..follow(AppLifecycleState.paused)
      ..follow(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(server.count('items'), reads + 1);
  });

  test('a new updatedAtMs in the list reads the songs again', () async {
    await open();
    final reads = server.count('items');

    server.contents['pl-1']!.insert(0, song('e'));
    server.playlists[1] = playlist('pl-1', name: '夜跑', updatedAtMs: 500);
    await opened.container.read(myPlaylistsControllerProvider.notifier).load();
    await pumpEventQueue();

    expect(server.count('items'), reads + 1);
    expect(keys()!.first, 'netease:e');
  });

  test('moving and removing change the list first', () async {
    await open();
    server
      ..hold('move')
      ..hold('remove');

    unawaited(controller.move(moveTo(keys()!, {'netease:d'}, 0)!));
    expect(keys(), ['netease:d', 'netease:a', 'netease:b', 'netease:c']);

    unawaited(controller.remove([_a]));
    expect(keys(), ['netease:d', 'netease:b', 'netease:c']);
  });

  test('a move sends the songs and the song to go before', () async {
    await open();

    await controller.move(moveTo(keys()!, {'netease:a'}, 2)!);

    expect(server.calls, contains('move pl-1 netease:a before netease:d'));
    await controller.move(moveTo(keys()!, {'netease:b'}, 3)!);
    expect(server.calls, contains('move pl-1 netease:b'));
  });

  test('a failure puts the songs and the selection back, and the edits '
      'after it are not sent', () async {
    await open();
    controller
      ..startSelecting()
      ..toggle('netease:a')
      ..toggle('netease:b');
    final gate = server.hold('move');
    server.failNext('move', apiError('CONFLICT', message: '歌单已经变了，刷新之后再试'));

    final first = controller.move(
      moveTo(keys()!, {'netease:a', 'netease:b'}, 2)!,
    );
    final second = controller.remove([_a, _b]);
    expect(keys(), ['netease:c', 'netease:d']);
    expect(detail.read().selected, isEmpty);

    gate.complete();
    expect((await first as MutationFailed?)?.message, '歌单已经变了，刷新之后再试');
    expect(await second, isNull);
    expect(server.count('remove'), 0);
    await pumpEventQueue();
    expect(keys(), ['netease:a', 'netease:b', 'netease:c', 'netease:d']);
    expect(detail.read().selected, {'netease:a', 'netease:b'});
  });

  test('an edit after a failure is sent as usual', () async {
    await open();
    server.failNext('move', apiError('CONFLICT', message: '歌单已经变了，刷新之后再试'));

    await controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
    final result = await controller.remove([_a]);

    expect(result, isA<MutationSucceeded<void>>());
    expect(server.calls, contains('remove pl-1 netease:a'));
  });

  test('reads during edits are not used, and the last edit reads '
      'again', () async {
    await open();
    final gate = server.hold('move');
    final reads = server.count('items');

    final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
    await controller.load();
    expect(server.count('items'), reads, reason: 'not sent during edits');
    expect(keys()!.first, 'netease:d');

    gate.complete();
    await moving;
    await pumpEventQueue();
    // 编辑结束后读一次；列表里的 updatedAtMs 随之变化，可能再读一次。
    expect(server.count('items'), greaterThan(reads));
    expect(keys(), ['netease:d', 'netease:a', 'netease:b', 'netease:c']);
  });

  test('a read answered during an edit is not used', () async {
    await open();
    final read = server.hold('items');
    unawaited(controller.load());
    await pumpEventQueue();
    final gate = server.hold('move');

    final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
    read.complete();
    await pumpEventQueue();

    expect(keys(), ['netease:d', 'netease:a', 'netease:b', 'netease:c']);
    gate.complete();
    await moving;
  });

  test('a lost answer is rolled back and then calibrated', () async {
    await open();
    server
      ..onCall = (method) {
        if (method == 'remove') server.contents['pl-1']!.removeAt(0);
      }
      ..failNext('remove', networkError);

    final result = await controller.remove([_a]);

    expect(result, isA<MutationUnknown<void>>());
    await pumpEventQueue();
    expect(keys(), ['netease:b', 'netease:c', 'netease:d']);
  });

  test('a move the server calls a client defect is rolled back, and only '
      'its code is logged', () async {
    await open();
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add(message);
    addTearDown(() => AppLog.onRecord = null);
    server.failNext(
      'move',
      apiError('INVALID_ARGUMENT', message: 'before 不能是要移动的歌', status: 400),
    );

    final result = await controller.move(moveTo(keys()!, {'netease:a'}, 2)!);

    expect((result as MutationFailed).message, 'before 不能是要移动的歌');
    expect(keys(), ['netease:a', 'netease:b', 'netease:c', 'netease:d']);
    expect(records, contains('move refused code=INVALID_ARGUMENT'));
    expect(
      records.where(
        (record) =>
            record.contains('netease:') ||
            record.contains('夜跑') ||
            record.contains('before 不能'),
      ),
      isEmpty,
    );
  });

  test('a move before a song gone from the server is told by the server and '
      'calibrated', () async {
    await open();
    server.contents['pl-1']!.removeLast();

    final result = await controller.move(moveTo(keys()!, {'netease:a'}, 2)!);

    expect((result as MutationFailed).message, '歌单已经变了，刷新之后再试');
    await pumpEventQueue();
    expect(keys(), ['netease:a', 'netease:b', 'netease:c']);
  });

  test('after a read only the selected songs still there stay '
      'selected', () async {
    await open();
    controller
      ..startSelecting()
      ..toggle('netease:a')
      ..toggle('netease:b');

    server.contents['pl-1']!.removeAt(0);
    await controller.load();

    expect(detail.read().selected, {'netease:b'});
  });

  test('selecting: all, none, and an empty playlist stops it', () async {
    await open();
    controller
      ..startSelecting()
      ..selectAll();
    expect(detail.read().selected, hasLength(4));
    controller.clearSelection();
    expect(detail.read().selected, isEmpty);

    controller.selectAll();
    await controller.remove([
      for (final item in detail.read().items!) item.track,
    ]);
    expect(detail.read().selecting, isFalse);
    expect(detail.read().selected, isEmpty);
  });

  test('edits still go out after the page is closed', () async {
    await open();
    final gate = server.hold('move');

    final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
    final removing = controller.remove([_a]);
    detail.close();
    await pumpEventQueue();
    gate.complete();

    expect(await moving, isA<MutationSucceeded<void>>());
    expect(await removing, isA<MutationSucceeded<void>>());
    expect(server.calls, contains('remove pl-1 netease:a'));
    await pumpEventQueue();
    expect(
      opened.container.exists(myPlaylistControllerProvider('pl-1')),
      isFalse,
    );
  });

  test('export reads the songs again first and hands them on', () async {
    await open();
    server.contents['pl-1']!.insert(0, song('new'));
    const origin = Rect.fromLTWH(10, 20, 48, 48);

    final result = await controller.export(origin);

    expect(result, isA<MutationSucceeded<void>>());
    final export = exporter.exports.single;
    expect(export.name, '夜跑');
    expect(export.items.first.track.id, 'new');
    expect(export.exportedAtMs, testNowMs);
    expect(export.origin, origin);
    expect(detail.read().exporting, isFalse);
  });

  test('an export takes the name the playlist has once its songs are '
      'read', () async {
    await open();
    final gate = server.hold('items');
    final exporting = controller.export(null);
    await pumpEventQueue();

    await opened.container
        .read(myPlaylistsControllerProvider.notifier)
        .rename(playlist('pl-1'), '晨跑');
    gate.complete();
    await exporting;

    expect(exporter.exports.single.name, '晨跑');
  });

  test('export says why when the songs cannot be read or the file cannot '
      'be shared', () async {
    await open();
    server.failNext('items', networkError);
    expect(
      (await controller.export(null) as MutationFailed).message,
      '没能导出：${networkError.message}',
    );
    expect(exporter.exports, isEmpty);

    exporter.error = Exception('share');
    expect(
      (await controller.export(null) as MutationFailed).message,
      '导出失败，请稍后重试。',
    );
    expect(exporter.exports, hasLength(1));
  });

  test('an export of a playlist gone from the server reads the list '
      'again', () async {
    await open();
    server.playlists.removeLast();

    final result = await controller.export(null);
    await pumpEventQueue();

    expect((result as MutationFailed).message, '没能导出：歌单不存在');
    expect(detail.read().gone, isTrue);
  });

  test('a failed read during an export keeps the export busy', () async {
    await open();
    final gate = server.hold('items');
    final exporting = controller.export(null);
    await pumpEventQueue();
    expect(detail.read().exporting, isTrue);

    server.failNext('items', networkError);
    await controller.load();
    expect(detail.read().error, networkError.message);
    expect(detail.read().exporting, isTrue);

    gate.complete();
    await exporting;
    expect(detail.read().exporting, isFalse);
  });

  test('an export still finishes after the page is closed', () async {
    await open();
    final gate = server.hold('items');

    final exporting = controller.export(null);
    detail.close();
    await pumpEventQueue();
    gate.complete();

    expect(await exporting, isA<MutationSucceeded<void>>());
    expect(exporter.exports, hasLength(1));
    await opened.container.pump();
    await pumpEventQueue();
    expect(
      opened.container.exists(myPlaylistControllerProvider('pl-1')),
      isFalse,
    );
  });

  group('belonging', () {
    test('a songs read answered after signing out is not shown', () async {
      await open();
      final stale = server.hold('items');
      unawaited(controller.load());
      await pumpEventQueue();

      await signOut();
      stale.complete();
      await pumpEventQueue();

      expect(detail.read().items, isNull);
      expect(detail.read().error, isNull);
    });

    test('a songs read answered after signing in again is not '
        'shown', () async {
      await open();
      final stale = server.hold('items');
      unawaited(controller.load());
      await pumpEventQueue();

      await signOut();
      server.contents['pl-1'] = [song('x')];
      await signIn();
      expect(keys(), ['netease:x']);
      stale.complete();
      await pumpEventQueue();

      expect(keys(), ['netease:x']);
    });

    test('a songs read answered as the server changes is not shown on the '
        'new server', () async {
      final other = FakePlaylistApi()
        ..playlists.add(playlist('pl-1'))
        ..contents['pl-1'] = [song('x')];
      await open(playlistApi: switchable(other));
      final stale = server.hold('items');
      unawaited(controller.load());
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      stale.complete();
      await pumpEventQueue();

      expect(other.count('items'), 0);
      expect(detail.read().items, isNull);
    });

    test('after a server switch the playlist is neither asked of the new '
        'server nor told as gone', () async {
      final other = FakePlaylistApi()..playlists.add(playlist('elsewhere'));
      await open(playlistApi: switchable(other));

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      await controller.load();
      final exported = await controller.export(null);
      await pumpEventQueue();

      expect(other.count('items'), 0);
      expect(detail.read().gone, isFalse);
      expect(detail.read().items, isNull);
      expect(
        exported,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          serverChangedNotice,
        ),
      );
      expect(exporter.exports, isEmpty);
    });

    test('edits queued before signing out are not sent', () async {
      await open();
      final gate = server.hold('move');
      final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
      final removing = controller.remove([_a]);
      await pumpEventQueue();

      await signOut();
      gate.complete();

      expect(await moving, isA<MutationSucceeded<void>>());
      expect(await removing, isNull);
      await pumpEventQueue();
      expect(server.count('remove'), 0);
      expect(detail.read().items, isNull);
    });

    test('an edit that fails after signing out does not put the old songs '
        'back', () async {
      await open();
      controller
        ..startSelecting()
        ..toggle('netease:d');
      final gate = server.hold('move');
      server.failNext('move', apiError('CONFLICT', message: '歌单已经变了，刷新之后再试'));
      final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
      await pumpEventQueue();

      await signOut();
      gate.complete();

      expect((await moving as MutationFailed?)?.code, 'CONFLICT');
      expect(detail.read().items, isNull);
      expect(detail.read().selecting, isFalse);
      expect(detail.read().selected, isEmpty);
    });

    test('with an edit in flight across signing in again, the new songs are '
        'read and the old ones are not put back', () async {
      await open();
      final gate = server.hold('move');
      server.failNext('move', apiError('CONFLICT', message: '歌单已经变了，刷新之后再试'));
      final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
      await pumpEventQueue();

      await signOut();
      server.contents['pl-1']!.insert(0, song('x'));
      await signIn();
      final fresh = [
        'netease:x',
        'netease:a',
        'netease:b',
        'netease:c',
        'netease:d',
      ];
      expect(keys(), fresh);

      gate.complete();
      await moving;
      expect(keys(), fresh);
    });

    test('an edit answered after a server switch puts nothing back, and the '
        'edit queued behind it is sent to neither server', () async {
      final other = FakePlaylistApi()
        ..playlists.add(playlist('pl-1'))
        ..contents['pl-1'] = [song('x')];
      await open(playlistApi: switchable(other));
      final gate = server.hold('move');
      final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
      final removing = controller.remove([_a]);
      await pumpEventQueue();

      opened.container.read(_server.notifier).next();
      await pumpEventQueue();
      expect(keys(), isEmpty);

      gate.complete();
      expect(
        await moving,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          doneOnOldServerText,
        ),
      );
      expect(await removing, isNull);
      expect(keys(), isEmpty);
      await pumpEventQueue();
      expect(server.count('remove') + other.count('remove'), 0);
      expect(other.count('items'), 0);
      expect(keys(), isEmpty);
    });

    test('an export whose songs arrive after signing out is not handed '
        'on', () async {
      await open();
      final gate = server.hold('items');
      final exporting = controller.export(null);
      await pumpEventQueue();

      await signOut();
      gate.complete();

      expect(
        await exporting,
        isA<MutationNotSent<void>>().having(
          (r) => r.message,
          'message',
          identityRenewedNotice,
        ),
      );
      expect(exporter.exports, isEmpty);
      expect(detail.read().exporting, isFalse);
    });

    test('an export whose read ends after a server switch is told as not '
        'done, failed or not', () async {
      for (final failure in [networkError, null]) {
        await open(playlistApi: switchable(FakePlaylistApi()));
        final gate = server.hold('items');
        if (failure != null) server.failNext('items', failure);
        final exporting = controller.export(null);
        await pumpEventQueue();

        opened.container.read(_server.notifier).next();
        await pumpEventQueue();
        gate.complete();

        expect(
          await exporting,
          isA<MutationNotSent<void>>().having(
            (r) => r.message,
            'message',
            serverChangedNotice,
          ),
          reason: '$failure',
        );
        expect(exporter.exports, isEmpty);
      }
    });

    test('keeps a page opened again after an edit from before is '
        'voided', () async {
      await open();
      final gate = server.hold('move');
      final moving = controller.move(moveTo(keys()!, {'netease:d'}, 0)!);
      await pumpEventQueue();

      detail.close();
      await signOut();
      await opened.container.pump();
      await pumpEventQueue();
      final reopened = opened.container.listen(
        myPlaylistControllerProvider('pl-1'),
        (_, _) {},
      );
      await pumpEventQueue();

      gate.complete();
      await moving;
      await opened.container.pump();
      await pumpEventQueue();

      expect(
        opened.container.exists(myPlaylistControllerProvider('pl-1')),
        isTrue,
      );
      expect(reopened.read().items, isNull);
    });

    test('keeps a page opened again after an export from before is '
        'voided', () async {
      await open();
      final gate = server.hold('items');
      final exporting = controller.export(null);
      await pumpEventQueue();

      detail.close();
      await signOut();
      await opened.container.pump();
      await pumpEventQueue();
      final reopened = opened.container.listen(
        myPlaylistControllerProvider('pl-1'),
        (_, _) {},
      );
      await pumpEventQueue();

      gate.complete();
      expect(await exporting, isA<MutationNotSent<void>>());
      await opened.container.pump();
      await pumpEventQueue();

      expect(
        opened.container.exists(myPlaylistControllerProvider('pl-1')),
        isTrue,
      );
      expect(reopened.read().exporting, isFalse);
      expect(exporter.exports, isEmpty);
    });
  });
}
