import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/lobby/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/application/server_directory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const switchFailedText = '没能切换服务器，请重试。';
const switchBusyText = '正在切换服务器，请稍候。';

sealed class SwitchOutcome {
  const SwitchOutcome();
}

final class SwitchSucceeded extends SwitchOutcome {
  const SwitchSucceeded(this.server);

  final ServerProfile server;
}

final class SwitchFailed extends SwitchOutcome {
  const SwitchFailed(this.message);

  final String message;
}

final serverHasMemberTokenProvider =
    Provider<Future<bool> Function(String serverId)>((ref) {
      throw UnimplementedError('serverHasMemberToken 未注入');
    });

final endAdminSessionProvider = Provider<void Function()>((ref) {
  throw UnimplementedError('endAdminSession 未注入');
});

final serverSwitcherProvider = Provider<ServerSwitcher>(ServerSwitcher.new);

final class ServerSwitcher {
  ServerSwitcher(this._ref);

  final Ref _ref;
  ({String id, Future<SwitchOutcome> outcome})? _switching;

  Future<bool> needsJoinConfirmation(ServerProfile target) async {
    try {
      return !await _ref.read(serverHasMemberTokenProvider)(target.id);
    } on Object catch (error) {
      AppLog.debug(
        'server',
        'member token not read',
        type: '${error.runtimeType}',
      );
      return true;
    }
  }

  /// [target] 可以是未保存的档案，成功后会保存并成为当前服务器。已保存的服务器
  /// 沿用目录中的档案，不写入 [target] 的品牌名。
  Future<SwitchOutcome> switchTo(ServerProfile target) {
    final switching = _switching;
    if (switching != null) {
      if (switching.id == target.id) return switching.outcome;
      return Future.value(const SwitchFailed(switchBusyText));
    }
    final current = _ref.read(currentServerProvider);
    if (current.id == target.id) return Future.value(SwitchSucceeded(current));
    final outcome = _switch(target).whenComplete(() => _switching = null);
    _switching = (id: target.id, outcome: outcome);
    return outcome;
  }

  Future<SwitchOutcome> _switch(ServerProfile target) async {
    final ServerProfile saved;
    try {
      // 播放地址按当前服务器拼出，必须先停止播放再写入新的当前服务器。
      saved = await _ref
          .read(roomControllerProvider.notifier)
          .leaveForServerChange(() async {
            _ref.read(endAdminSessionProvider)();
            final directory = _ref.read(serverDirectoryProvider.notifier);
            // 调用方持有的档案可能已过时，例如加入面板打开期间服务器改了名。
            final added =
                _ref.read(serverDirectoryProvider).byId(target.id) ??
                await directory.add(target);
            await directory.setCurrent(added.id);
            return added;
          });
    } on Object catch (error) {
      AppLog.warn('server', 'switch not saved', type: '${error.runtimeType}');
      return const SwitchFailed(switchFailedText);
    }
    _ref.read(lobbyControllerProvider.notifier).resetForServerChange();
    unawaited(
      _ref.read(identityControllerProvider.notifier).resetForServerChange(),
    );
    return SwitchSucceeded(saved);
  }
}
