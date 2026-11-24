import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart' show roomListing;
import '../../server/server_test_doubles.dart';
import '../admin_test_doubles.dart';

const _network = ApiException(
  code: 'NETWORK',
  message: '网络请求失败，请检查网络后重试。',
  status: null,
);

const _form = RoomForm(
  name: ' 大厅 ',
  description: '',
  slug: 'hall',
  capacity: '16',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAdminApi api;
  late ProviderContainer container;

  AdminRoomsController controller() =>
      container.read(adminRoomsControllerProvider.notifier);
  AdminRoomsState state() => container.read(adminRoomsControllerProvider);

  final hall = roomListing(
    id: 'r1',
    name: '大厅',
    description: '',
    slug: 'hall',
    hasPassword: true,
    onlineCount: 3,
  );

  setUp(() async {
    api = FakeAdminApi()..rooms = [hall];
    container = await switchingContainer(
      store: FakeServerStore(profiles: [serverB]),
      credentials: FakeCredentialStores(),
      extra: [adminApiProvider.overrideWithValue(api)],
    );
    container.listen(adminRoomsControllerProvider, (_, _) {});
    await container.read(adminSessionProvider.notifier).signIn('t-1');
  });

  test('rooms that cannot be read say why and keep what was read, the '
      'capacity new rooms start from with them', () async {
    expect(state().defaultCapacity, isNull);
    api.defaultCapacity = 32;
    await controller().load();
    api.listRoomsError = const ApiException(
      code: 'INTERNAL',
      message: '服务器出错了',
      status: 500,
    );

    await controller().load();

    expect(state().rooms.single.name, '大厅');
    expect(state().defaultCapacity, 32);
    expect(state().loading, isFalse);
    expect(state().error, '服务器出错了');
  });

  test('a list read before a later one does not replace it', () async {
    final earlier = api.listRoomsGate = Completer();
    final first = controller().load();
    final later = api.listRoomsGate = Completer();
    final second = controller().load();

    api.rooms = [roomListing(id: 'r2', name: '新的')];
    later.complete();
    await second;
    api.rooms = [hall];
    earlier.complete();
    await first;

    expect(state().rooms.single.name, '新的');
    expect(state().loading, isFalse);
  });

  test('a new room without an answer may exist: it is not sent again and the '
      'rooms are read again', () async {
    api.createRoomError = _network;
    final listed = api.listRoomsCalls;

    final result = await controller().create(_form);
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<String>>());
    expect(api.createdDrafts, hasLength(1));
    expect(api.listRoomsCalls, listed + 1);
  });

  test('a refusal from the server is shown as the server put it', () async {
    api.updateRoomError = const ApiException(
      code: 'NOT_FOUND',
      message: '房间不存在',
      status: 404,
    );
    final listed = api.listRoomsCalls;

    final result = await controller().update(
      hall,
      const RoomForm(name: '小厅', description: '', slug: 'hall', capacity: '16'),
    );
    await pumpEventQueue();

    expect(
      result,
      isA<MutationFailed<void>>()
          .having((r) => r.code, 'code', 'NOT_FOUND')
          .having((r) => r.message, 'message', '房间不存在'),
    );
    expect(api.listRoomsCalls, listed + 1);
  });

  test('a change that changes nothing is not sent', () async {
    final listed = api.listRoomsCalls;
    final tokens = api.tokens.length;

    final result = await controller().update(
      hall,
      const RoomForm(name: '大厅', description: '', slug: 'hall', capacity: '16'),
    );

    expect(
      result,
      isA<MutationNotSent<void>>().having(
        (r) => r.message,
        'message',
        '没有需要保存的修改。',
      ),
    );
    expect(api.updates, isEmpty);
    expect(api.tokens, hasLength(tokens));
    expect(api.listRoomsCalls, listed);
  });
}
