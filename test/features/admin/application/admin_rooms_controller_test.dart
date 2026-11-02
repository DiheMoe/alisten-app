import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
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

const _unauthorized = ApiException(
  code: 'UNAUTHORIZED',
  message: 'token invalid',
  status: 401,
);

const _form = RoomForm(name: ' 大厅 ', description: '', slug: 'hall');

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

  test('the rooms are read with the admin token', () async {
    await controller().load();

    expect(state().rooms.single.name, '大厅');
    expect(state().loading, isFalse);
    expect(state().error, isNull);
    expect(api.tokens.last, 't-1');
  });

  test('rooms that cannot be read say why and keep what was read', () async {
    await controller().load();
    api.listRoomsError = const ApiException(
      code: 'INTERNAL',
      message: '服务器出错了',
      status: 500,
    );

    await controller().load();

    expect(state().rooms.single.name, '大厅');
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

  test('a new room is sent once and the rooms are read again', () async {
    final listed = api.listRoomsCalls;

    final result = await controller().create(_form);
    await pumpEventQueue();

    expect(
      result,
      isA<MutationSucceeded<String>>().having((r) => r.value, 'value', 'r-new'),
    );
    expect(api.createdDrafts.single.name, '大厅');
    expect(api.createdDrafts.single.slug, 'hall');
    expect(api.tokens.last, 't-1');
    expect(api.listRoomsCalls, listed + 1);
    expect(state().rooms.map((room) => room.id), ['r1', 'r-new']);
  });

  test('a room form with a problem is not sent', () async {
    final listed = api.listRoomsCalls;

    final result = await controller().create(
      const RoomForm(name: '大厅', description: '', slug: 'Hall'),
    );

    expect(
      result,
      isA<MutationNotSent<String>>().having(
        (r) => r.message,
        'message',
        roomSlugRuleText,
      ),
    );
    expect(api.createdDrafts, isEmpty);
    expect(api.listRoomsCalls, listed);
  });

  test('an alias already taken says so', () async {
    api.createRoomError = const ApiException(
      code: 'CONFLICT',
      message: 'slug taken',
      status: 409,
    );
    final listed = api.listRoomsCalls;

    final result = await controller().create(_form);
    await pumpEventQueue();

    expect(
      result,
      isA<MutationFailed<String>>()
          .having((r) => r.code, 'code', 'CONFLICT')
          .having((r) => r.message, 'message', '这个别名已被占用'),
    );
    expect(slugTakenText, '这个别名已被占用');
    expect(api.listRoomsCalls, listed + 1);
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

  test('a success answer this version cannot read leaves the result '
      'unknown', () async {
    api.createRoomError = const ApiException.protocolMismatch(201);

    expect(await controller().create(_form), isA<MutationUnknown<String>>());
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
      const RoomForm(name: '小厅', description: '', slug: 'hall'),
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

  test('a change sends only what changed, by the room id', () async {
    final result = await controller().update(
      hall,
      const RoomForm(
        name: '大厅',
        description: '每晚八点',
        slug: '',
        password: RemovePassword(),
      ),
    );
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    final update = api.updates.single;
    expect(update.roomId, 'r1');
    expect(update.patch.name, isNull);
    expect(update.patch.description, '每晚八点');
    expect(update.patch.slug, '');
    expect(update.patch.password, '');
    expect(state().rooms.single.slug, isNull);
  });

  test('a change that changes nothing is not sent', () async {
    final listed = api.listRoomsCalls;
    final tokens = api.tokens.length;

    final result = await controller().update(
      hall,
      const RoomForm(name: '大厅', description: '', slug: 'hall'),
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

  test('a change with a problem is not sent', () async {
    final result = await controller().update(
      hall,
      const RoomForm(
        name: '大厅',
        description: '',
        slug: 'hall',
        password: SetPassword(''),
      ),
    );

    expect(
      result,
      isA<MutationNotSent<void>>().having(
        (r) => r.message,
        'message',
        '请输入新密码',
      ),
    );
    expect(api.updates, isEmpty);
  });

  test('a deleted room is gone when the rooms are read again', () async {
    await controller().load();
    final listed = api.listRoomsCalls;

    final result = await controller().delete('r1');
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    expect(api.deletedRoomIds, ['r1']);
    expect(api.listRoomsCalls, listed + 1);
    expect(state().rooms, isEmpty);
  });

  test('a token the server no longer takes ends the session; nothing is read '
      'again', () async {
    api.deleteRoomError = _unauthorized;
    final listed = api.listRoomsCalls;

    final result = await controller().delete('r1');
    await pumpEventQueue();

    expect(
      result,
      isA<MutationNotSent<void>>().having(
        (r) => r.message,
        'message',
        '后台会话已结束',
      ),
    );
    expect(container.read(adminSessionProvider).active, isFalse);
    expect(api.listRoomsCalls, listed);
  });

  test('a session already ended sends nothing', () async {
    container.read(adminSessionProvider.notifier).end();

    final result = await controller().create(_form);

    expect(
      result,
      isA<MutationNotSent<String>>().having(
        (r) => r.message,
        'message',
        '后台会话已结束',
      ),
    );
    expect(api.createdDrafts, isEmpty);
  });

  test('a new room sent before the session ended may exist', () async {
    final gate = api.createRoomGate = Completer();
    final pending = controller().create(_form);
    await pumpEventQueue();

    container.read(adminSessionProvider.notifier).end();
    gate.complete();

    expect(await pending, isA<MutationUnknown<String>>());
  });

  for (final (code, status) in [('UNAVAILABLE', 503), ('INTERNAL', 500)]) {
    test('a new room, change or deletion the server could not finish '
        '($code) may have taken effect: none is sent again and the rooms are '
        'read again each time', () async {
      final error = ApiException(
        code: code,
        message: '房间暂时不可用，请稍后再试。',
        status: status,
      );
      api
        ..createRoomError = error
        ..updateRoomError = error
        ..deleteRoomError = error;
      final listed = api.listRoomsCalls;

      final created = await controller().create(_form);
      final updated = await controller().update(
        hall,
        const RoomForm(
          name: '大厅',
          description: '',
          slug: 'hall',
          password: SetPassword('p'),
        ),
      );
      final deleted = await controller().delete('r1');
      await pumpEventQueue();

      expect(created, isA<MutationUnknown<String>>());
      expect(updated, isA<MutationUnknown<void>>());
      expect(deleted, isA<MutationUnknown<void>>());
      expect(api.createdDrafts, hasLength(1));
      expect(api.updates, hasLength(1));
      expect(api.deletedRoomIds, ['r1']);
      expect(api.listRoomsCalls, listed + 3);
    });
  }

  test('a new room, change or deletion turned away for coming too often was '
      'not carried out: it says so and the rooms are not read again', () async {
    const limited = ApiException(
      code: 'RATE_LIMITED',
      message: '请求太频繁，请稍后再试。',
      status: 429,
    );
    api
      ..createRoomError = limited
      ..updateRoomError = limited
      ..deleteRoomError = limited;
    final listed = api.listRoomsCalls;

    final results = [
      await controller().create(_form),
      await controller().update(
        hall,
        const RoomForm(name: '小厅', description: '', slug: 'hall'),
      ),
      await controller().delete('r1'),
    ];
    await pumpEventQueue();

    for (final result in results) {
      expect(
        result,
        isA<MutationNotSent<Object?>>().having(
          (r) => r.message,
          'message',
          '请求太频繁，请稍后再试。',
        ),
      );
    }
    expect(api.listRoomsCalls, listed);
  });

  test('rooms that cannot be read for coming too often say so', () async {
    api.listRoomsError = const ApiException(
      code: 'RATE_LIMITED',
      message: '请求太频繁，请稍后再试。',
      status: 429,
    );

    await controller().load();

    expect(state().error, '请求太频繁，请稍后再试。');
  });

  // 服务端的说明带字段路径（如“slug：格式不正确”），是写给接口调用方的。
  test('a new room or change the server finds against its rules asks for '
      'the form to be checked, without the server wording', () async {
    const invalid = ApiException(
      code: 'INVALID_ARGUMENT',
      message: 'name：不能包含 U+0000',
      status: 400,
    );
    api
      ..createRoomError = invalid
      ..updateRoomError = invalid;

    final created = await controller().create(
      const RoomForm(name: '大\u0000厅', description: '', slug: ''),
    );
    final updated = await controller().update(
      hall,
      const RoomForm(name: '小\u0000厅', description: '', slug: 'hall'),
    );

    for (final result in [created, updated]) {
      expect(
        result,
        isA<MutationFailed<Object?>>()
            .having((r) => r.code, 'code', 'INVALID_ARGUMENT')
            .having((r) => r.message, 'message', '提交的内容不符合要求，请检查后再试。'),
      );
    }
  });

  // 上一次删除结果未知但实际已生效时，再删一次会得到 NOT_FOUND。
  test('a room already gone when deleted counts as deleted, and the rooms are '
      'read again', () async {
    api.deleteRoomError = const ApiException(
      code: 'NOT_FOUND',
      message: '房间不存在',
      status: 404,
    );
    final listed = api.listRoomsCalls;

    final result = await controller().delete('r1');
    await pumpEventQueue();

    expect(result, isA<MutationSucceeded<void>>());
    expect(api.deletedRoomIds, ['r1']);
    expect(api.listRoomsCalls, listed + 1);
  });

  test('a change that fails unexpectedly is unknown, logged by its type '
      'only, and the rooms are read again', () async {
    final records = <String>[];
    AppLog.onRecord = (name, level, message) => records.add('$name $message');
    addTearDown(() => AppLog.onRecord = null);
    api.createRoomError = StateError('t-1 大厅 hall');
    final listed = api.listRoomsCalls;

    final result = await controller().create(_form);
    await pumpEventQueue();

    expect(result, isA<MutationUnknown<String>>());
    expect(api.listRoomsCalls, listed + 1);
    expect(records, contains(contains('StateError')));
    expect(records.where((r) => r.contains('t-1')), isEmpty);
    expect(records.where((r) => r.contains('大厅')), isEmpty);
  });
}
