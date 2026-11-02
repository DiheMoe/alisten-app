import 'dart:async';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../server_test_doubles.dart';

void main() {
  late FakeServerProbe probe;
  late ProviderContainer container;

  AddServerController controller() =>
      container.read(addServerControllerProvider.notifier);
  AddServerState state() => container.read(addServerControllerProvider);

  setUp(() {
    probe = FakeServerProbe();
    container = ProviderContainer(
      overrides: [
        buildEnvironmentProvider.overrideWithValue(testEnvironment),
        serverStoreProvider.overrideWithValue(
          FakeServerStore(profiles: [serverB]),
        ),
        serverProbeProvider.overrideWithValue(probe),
        serverNowProvider.overrideWithValue(() => 4321),
      ],
    );
    addTearDown(container.dispose);
    container.listen(addServerControllerProvider, (_, _) {});
  });

  test('an HTTP address is refused here without asking it', () async {
    await controller().check('http://example.org');

    expect(state().problem, '只支持 https 地址');
    expect(state().problem, serverAddressCleartextText);
    expect(state().found, isNull);
    expect(state().checking, isFalse);
    expect(probe.probed, isEmpty);
  });

  test('something that is not an address says what to type', () async {
    await controller().check('https://');

    expect(state().problem, serverAddressMalformedText);
    expect(state().problem, '请输入服务器地址，例如 https://example.com');
    expect(probe.probed, isEmpty);
  });

  test('a server already saved, written any way, is not asked again', () async {
    await controller().check('example.com:8443');

    expect(state().problem, serverAlreadySavedText);
    expect(state().problem, '已经添加过这个服务器，可以在列表中切换');
    expect(probe.probed, isEmpty);

    await controller().check('LiveHouse.dihe.moe/');

    expect(state().problem, serverAlreadySavedText);
    expect(probe.probed, isEmpty);
  });

  test('a server that answers is found under its canonical address and '
      'brand name', () async {
    probe.results['https://example.org'] = const ProbeSucceeded(
      origin: 'https://example.org',
      brandName: '新站',
    );

    final checking = controller().check('example.org');
    expect(state().checking, isTrue);
    expect(state().problem, isNull);
    await checking;

    expect(probe.probed, ['https://example.org']);
    expect(state().checking, isFalse);
    expect(state().problem, isNull);
    final found = state().found!;
    expect(found.origin, 'https://example.org');
    expect(found.brandName, '新站');
    expect(found.addedAtMs, 4321);
    expect(
      container.read(serverDirectoryProvider).byId(found.id),
      isNull,
      reason: 'found, not saved',
    );
  });

  test('a server that fails the check says why', () async {
    probe.results['https://example.org'] = const ProbeFailed(
      ProbeFailure.incompatible,
    );

    await controller().check('example.org');

    expect(state().problem, '这个服务器与当前 App 版本不兼容');
    expect(state().found, isNull);
    expect(state().checking, isFalse);
  });

  test('a check still running when the address is edited is '
      'dropped', () async {
    probe
      ..results['https://example.org'] = const ProbeSucceeded(
        origin: 'https://example.org',
        brandName: '新站',
      )
      ..gate = Completer<void>();

    final checking = controller().check('example.org');
    await pumpEventQueue();
    controller().edited();
    expect(state().checking, isFalse);
    probe.gate!.complete();
    await checking;

    expect(state().checking, isFalse);
    expect(state().found, isNull);
    expect(state().problem, isNull);
  });

  test('editing clears the result', () async {
    probe.results['https://example.org'] = const ProbeFailed(
      ProbeFailure.unreachable,
    );
    await controller().check('example.org');
    expect(state().problem, isNotNull);

    controller().edited();

    expect(state().problem, isNull);
    expect(state().found, isNull);
  });

  test('a check still running when another one starts is dropped', () async {
    probe
      ..results['https://example.org'] = const ProbeSucceeded(
        origin: 'https://example.org',
        brandName: '新站',
      )
      ..gate = Completer<void>();

    final first = controller().check('example.org');
    await pumpEventQueue();
    await controller().check('example.com:8443');
    probe.gate!.complete();
    await first;

    expect(state().problem, serverAlreadySavedText);
    expect(state().found, isNull);
    expect(state().checking, isFalse);
  });
}
