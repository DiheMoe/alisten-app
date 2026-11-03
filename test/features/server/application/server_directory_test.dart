import 'dart:async';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../server_test_doubles.dart';

const _defaultId = 'fcd7a878032db68b';

void main() {
  late FakeServerStore store;
  late List<String> forgotten;
  late FakeServerProbe probe;

  ProviderContainer open({BuildEnvironment? environment}) {
    final container = ProviderContainer(
      overrides: [
        buildEnvironmentProvider.overrideWithValue(
          environment ?? testEnvironment,
        ),
        serverStoreProvider.overrideWithValue(store),
        scheduleServerDataSweepProvider.overrideWithValue(() async {}),
        forgetServerDataProvider.overrideWithValue((id) async {
          forgotten.add(id);
        }),
        serverNowProvider.overrideWithValue(() => 1000),
        serverProbeProvider.overrideWithValue(probe),
        ...currentServerWiring(),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  ServerDirectoryState stateOf(ProviderContainer container) =>
      container.read(serverDirectoryProvider);

  ServerDirectory directoryOf(ProviderContainer container) =>
      container.read(serverDirectoryProvider.notifier);

  setUp(() {
    store = FakeServerStore();
    forgotten = [];
    probe = FakeServerProbe();
  });

  test('with nothing stored the default server is the only and current '
      'one', () {
    final state = stateOf(open());

    final server = state.profiles.single;
    expect(server.origin, 'https://livehouse.dihe.moe');
    expect(server.brandName, 'Alisten');
    expect(server.addedAtMs, 0);
    expect(server.id, _defaultId);
    expect(state.current.id, _defaultId);
    expect(state.defaultId, _defaultId);
    expect(state.isDefault(server), isTrue);
  });

  test('the default server comes first and the others in the order they '
      'were added', () {
    store.profiles = [serverC, serverB, serverC.withBrandName('重复')];

    final state = stateOf(open());

    expect(state.profiles.map((server) => server.id), [
      _defaultId,
      serverB.id,
      serverC.id,
    ]);
    expect(state.byId(serverC.id), serverC);
    expect(state.isDefault(serverB), isFalse);
  });

  test('a stored HTTP server is kept only when cleartext servers are '
      'allowed', () {
    final cleartext = ServerProfile(
      origin: 'http://10.0.2.2:9876',
      brandName: '本机',
      addedAtMs: 1,
    );
    store.profiles = [cleartext];

    expect(stateOf(open()).byId(cleartext.id), isNull);
    expect(
      stateOf(
        open(
          environment: BuildEnvironment(
            defaultOrigin: 'https://livehouse.dihe.moe',
            isRelease: false,
            allowCleartext: true,
          ),
        ),
      ).byId(cleartext.id),
      cleartext,
    );
  });

  test('a stored current server that is no longer listed falls back to the '
      'default server', () {
    store
      ..profiles = [serverB]
      ..currentId = serverC.id;

    expect(stateOf(open()).current.id, _defaultId);
  });

  test('the stored current server is current', () {
    store
      ..profiles = [serverB]
      ..currentId = serverB.id;

    expect(stateOf(open()).current, serverB);
  });

  group('add', () {
    test('saves a new server, and only renames one already saved', () async {
      final container = open();

      expect(await directoryOf(container).add(serverB), serverB);
      expect(store.profiles, contains(serverB));

      final renamed = await directoryOf(container)
          .add(serverB.withBrandName('新名字'));

      expect(renamed.brandName, '新名字');
      final saved = store.profiles.where((server) => server.id == serverB.id);
      expect(saved.single.brandName, '新名字');
      expect(saved.single.addedAtMs, serverB.addedAtMs);
      expect(stateOf(container).byId(serverB.id)?.brandName, '新名字');
    });

    test('keeps both servers added at the same time', () async {
      final container = open();

      await Future.wait([
        directoryOf(container).add(serverB),
        directoryOf(container).add(serverC),
      ]);

      expect(store.profiles, containsAll([serverB, serverC]));
      expect(stateOf(container).profiles, containsAll([serverB, serverC]));
    });

    test('a failed write throws and changes nothing', () async {
      final container = open();
      store.failProfileWrites = true;

      await expectLater(directoryOf(container).add(serverB), throwsStateError);

      expect(stateOf(container).byId(serverB.id), isNull);
    });

    test('refuses an HTTP server when cleartext servers are not '
        'allowed', () async {
      final container = open();

      await expectLater(
        directoryOf(container).add(
          ServerProfile(
            origin: 'http://example.com',
            brandName: 'x',
            addedAtMs: 1,
          ),
        ),
        throwsArgumentError,
      );

      expect(store.profiles, isEmpty);
    });
  });

  group('setCurrent', () {
    test('saves the current server before it becomes current', () async {
      store.profiles = [serverB, serverC];
      final container = open();
      final seen = <String>[];
      store.onSaveCurrent = (_) => seen.add(stateOf(container).currentId);

      await directoryOf(container).setCurrent(serverB.id);

      expect(seen, [_defaultId]);
      expect(store.currentIdWrites, [serverB.id]);
      expect(stateOf(container).currentId, serverB.id);
      expect(container.read(currentServerProvider), serverB);
    });

    test('a failed write throws and keeps the current server', () async {
      store.profiles = [serverB, serverC];
      final container = open();
      await directoryOf(container).setCurrent(serverB.id);
      store.failCurrentWrites = true;

      await expectLater(
        directoryOf(container).setCurrent(serverC.id),
        throwsStateError,
      );

      expect(stateOf(container).currentId, serverB.id);
    });

    test('an unknown server is refused', () async {
      final container = open();

      await expectLater(
        directoryOf(container).setCurrent(serverB.id),
        throwsArgumentError,
      );

      expect(store.currentIdWrites, isEmpty);
      expect(stateOf(container).currentId, _defaultId);
    });
  });

  group('remove', () {
    test('keeps the default and the current server', () async {
      store
        ..profiles = [serverB, serverC]
        ..currentId = serverB.id;
      final container = open();

      expect(await directoryOf(container).remove(_defaultId), isFalse);
      expect(await directoryOf(container).remove(serverB.id), isFalse);

      expect(forgotten, isEmpty);
      expect(store.profiles, containsAll([serverB, serverC]));
    });

    test('forgets the data of a removed server', () async {
      store
        ..profiles = [serverB, serverC]
        ..currentId = serverB.id;
      final container = open();

      expect(await directoryOf(container).remove(serverC.id), isTrue);

      expect(forgotten, [serverC.id]);
      expect(store.profiles, isNot(contains(serverC)));
      expect(stateOf(container).byId(serverC.id), isNull);
    });

    // 每一步记录服务器 C 当时是否仍在列表中（存储或状态）。
    ProviderContainer removing(
      List<(String, bool)> steps, {
      Error? sweepError,
      Error? forgetError,
    }) {
      late final ProviderContainer container;
      bool listed() =>
          store.profiles.contains(serverC) ||
          stateOf(container).byId(serverC.id) != null;
      container = ProviderContainer(
        overrides: [
          buildEnvironmentProvider.overrideWithValue(testEnvironment),
          serverStoreProvider.overrideWithValue(store),
          scheduleServerDataSweepProvider.overrideWithValue(() async {
            steps.add(('sweep', listed()));
            if (sweepError != null) throw sweepError;
          }),
          forgetServerDataProvider.overrideWithValue((id) async {
            steps.add(('forget', listed()));
            if (forgetError != null) throw forgetError;
          }),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('the sweep is scheduled first and the server is out of the list '
        'before its data is forgotten', () async {
      store.profiles = [serverC];
      final steps = <(String, bool)>[];
      final container = removing(steps);

      expect(await directoryOf(container).remove(serverC.id), isTrue);

      expect(steps, [('sweep', true), ('forget', false)]);
    });

    test('a server whose data could not be forgotten is removed all the same, '
        'and the failure is logged by its type alone', () async {
      final records = <String>[];
      AppLog.onRecord = (name, level, message) => records.add(message);
      addTearDown(() => AppLog.onRecord = null);
      store.profiles = [serverC];
      final steps = <(String, bool)>[];
      final container = removing(
        steps,
        forgetError: StateError('keychain ${serverC.id}'),
      );

      expect(await directoryOf(container).remove(serverC.id), isTrue);

      expect(steps, [('sweep', true), ('forget', false)]);
      expect(store.profiles, isNot(contains(serverC)));
      expect(stateOf(container).byId(serverC.id), isNull);
      expect(records, contains(contains('server data not forgotten')));
      expect(records.where((record) => record.contains(serverC.id)), isEmpty);
    });

    test('a server is kept when the sweep cannot be scheduled', () async {
      store.profiles = [serverC];
      final steps = <(String, bool)>[];
      final container = removing(steps, sweepError: StateError('not saved'));

      await expectLater(
        directoryOf(container).remove(serverC.id),
        throwsStateError,
      );

      expect(steps, [('sweep', true)]);
      expect(store.profiles, contains(serverC));
      expect(stateOf(container).byId(serverC.id), serverC);
    });
  });

  group('brand names', () {
    ServerProfile? saved(String id) {
      for (final profile in store.profiles) {
        if (profile.id == id) return profile;
      }
      return null;
    }

    test('refreshing takes the brand name each server gives now and keeps '
        'the ones it cannot get, rebuilding nothing that follows the current '
        'server', () async {
      store
        ..profiles = [serverB]
        ..currentId = serverB.id;
      probe.brands[serverB.origin] = '新名字';
      final container = open();
      final config = container.read(appConfigProvider);

      await directoryOf(container).refreshBrands();

      expect(stateOf(container).byId(serverB.id)?.brandName, '新名字');
      expect(stateOf(container).byId(_defaultId)?.brandName, 'Alisten');
      expect(saved(serverB.id)?.brandName, '新名字');
      expect(saved(serverB.id)?.addedAtMs, serverB.addedAtMs);
      expect(container.read(currentServerProvider).brandName, '新名字');
      expect(container.read(appConfigProvider), same(config));
      expect(probe.brandRequests, [
        'https://livehouse.dihe.moe',
        serverB.origin,
      ]);
    });

    test('refreshing the current brand asks only the current server', () async {
      store
        ..profiles = [serverB, serverC]
        ..currentId = serverB.id;
      probe.brands[serverB.origin] = '新名字';
      final container = open();

      await directoryOf(container).refreshCurrentBrand();

      expect(probe.brandRequests, [serverB.origin]);
      expect(container.read(currentServerProvider).brandName, '新名字');
      expect(saved(serverB.id)?.brandName, '新名字');
    });

    test('refreshing asks every server at once', () async {
      store.profiles = [serverB, serverC];
      probe.gate = Completer<void>();
      final container = open();

      final refreshing = directoryOf(container).refreshBrands();
      await pumpEventQueue();

      expect(probe.brandRequests, hasLength(3));
      probe.gate!.complete();
      await refreshing;
    });

    test('refreshing writes nothing when no brand name changed', () async {
      store
        ..profiles = [serverB]
        ..failProfileWrites = true;
      probe.brands[serverB.origin] = serverB.brandName;
      final container = open();

      await directoryOf(container).refreshBrands();

      expect(stateOf(container).byId(serverB.id), serverB);
    });

    test('a refresh that cannot be saved does not throw and changes '
        'nothing', () async {
      store
        ..profiles = [serverB]
        ..failProfileWrites = true;
      probe.brands[serverB.origin] = '新名字';
      final container = open();

      await directoryOf(container).refreshBrands();

      expect(stateOf(container).byId(serverB.id), serverB);
    });

    test('a server removed while its brand name is fetched stays '
        'removed', () async {
      store.profiles = [serverB, serverC];
      probe
        ..brands[serverC.origin] = '新名字'
        ..gate = Completer<void>();
      final container = open();

      final refreshing = directoryOf(container).refreshBrands();
      await pumpEventQueue();
      expect(await directoryOf(container).remove(serverC.id), isTrue);
      probe.gate!.complete();
      await refreshing;

      expect(stateOf(container).byId(serverC.id), isNull);
      expect(saved(serverC.id), isNull);
    });

    test('a brand name changed while names are fetched is not overwritten by '
        'the name fetched', () async {
      store.profiles = [serverB, serverC];
      probe
        ..brands[serverB.origin] = '旧的'
        ..brands[serverC.origin] = '新名字'
        ..gate = Completer<void>();
      final container = open();

      final refreshing = directoryOf(container).refreshBrands();
      await pumpEventQueue();
      await directoryOf(container).updateBrandName(serverB.id, '管理改的');
      probe.gate!.complete();
      await refreshing;

      expect(stateOf(container).byId(serverB.id)?.brandName, '管理改的');
      expect(saved(serverB.id)?.brandName, '管理改的');
      expect(stateOf(container).byId(serverC.id)?.brandName, '新名字');
      expect(saved(serverC.id)?.brandName, '新名字');
    });

    test('a brand name is updated and saved', () async {
      store.profiles = [serverB];
      final container = open();

      await directoryOf(container).updateBrandName(serverB.id, '新名字');

      expect(stateOf(container).byId(serverB.id)?.brandName, '新名字');
      expect(saved(serverB.id)?.brandName, '新名字');
    });

    test('an unknown server or an unchanged name writes nothing', () async {
      store
        ..profiles = [serverB]
        ..failProfileWrites = true;
      final container = open();

      await directoryOf(container).updateBrandName(serverC.id, 'x');
      await directoryOf(container)
          .updateBrandName(serverB.id, serverB.brandName);

      expect(stateOf(container).byId(serverC.id), isNull);
      expect(stateOf(container).byId(serverB.id), serverB);
    });

    test('a brand name that cannot be saved throws and is not '
        'taken', () async {
      store
        ..profiles = [serverB]
        ..failProfileWrites = true;
      final container = open();

      await expectLater(
        directoryOf(container).updateBrandName(serverB.id, '新名字'),
        throwsStateError,
      );

      expect(stateOf(container).byId(serverB.id), serverB);
    });
  });

  test('servers are found by the authority of their invite links', () {
    store.profiles = [serverB];
    final state = stateOf(open());

    expect(state.byLinkAuthority('livehouse.dihe.moe')?.id, _defaultId);
    expect(state.byLinkAuthority('example.com:8443'), serverB);
    expect(state.byLinkAuthority('example.com'), isNull);
    expect(state.linkAuthorityOf(serverB), 'example.com:8443');
  });

  test('the default server is found by its configured link host', () {
    final state = stateOf(
      open(
        environment: BuildEnvironment(
          defaultOrigin: 'https://api.example.com',
          defaultLinkHost: 'example.com',
          isRelease: false,
        ),
      ),
    );

    expect(state.defaultLinkHost, 'example.com');
    expect(state.byLinkAuthority('example.com'), state.current);
    expect(state.linkAuthorityOf(state.current), 'example.com');
  });
}
