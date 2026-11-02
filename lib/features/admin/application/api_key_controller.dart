import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/sensitive_clipboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notLoadedText = '没能读取 API Key 的状态，请稍后重试。';

final class ApiKeyState {
  const ApiKeyState({this.status, this.loading = false, this.error});

  final ApiKeyStatus? status;
  final bool loading;
  final String? error;
}

final apiKeyControllerProvider = NotifierProvider.autoDispose
    .family<ApiKeyController, ApiKeyState, String>(ApiKeyController.new);

/// 新 Key 只作为 [reset] 的结果交给调用方，不进入状态。
final class ApiKeyController extends Notifier<ApiKeyState> {
  ApiKeyController(this.roomId);

  final String roomId;

  int _loads = 0;

  @override
  ApiKeyState build() => const ApiKeyState();

  Future<void> load() async {
    final attempt = ++_loads;
    bool latest() => ref.mounted && attempt == _loads;
    state = ApiKeyState(status: state.status, loading: true);
    try {
      final status = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.getApiKeyStatus(token, roomId));
      if (latest()) state = ApiKeyState(status: status);
    } on AdminSessionEnded {
      if (latest()) state = ApiKeyState(status: state.status);
    } on ApiException catch (error) {
      if (latest()) {
        state = ApiKeyState(status: state.status, error: error.message);
      }
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'api key status not loaded',
        type: '${error.runtimeType}',
      );
      if (latest()) {
        state = ApiKeyState(status: state.status, error: _notLoadedText);
      }
    }
  }

  /// 失败时返回 false，不得退回普通剪贴板。
  Future<bool> copy(String key) async {
    try {
      await ref.read(sensitiveClipboardProvider).copy(key);
    } on Object {
      return false;
    }
    return true;
  }

  /// 未成功时等重新读取完成再返回：服务端可能已经重置了 Key，调用方可比较前后的
  /// 生成时间来判断。
  Future<MutationResult<String>> reset() {
    return ref
        .read(adminSessionProvider.notifier)
        .change(
          (api, token) => api.resetApiKey(token, roomId),
          unexpected: 'api key reset ended unexpectedly',
          reread: (result) async {
            if (!ref.mounted) return;
            if (result is MutationSucceeded<String>) {
              unawaited(load());
            } else {
              await load();
            }
          },
        );
  }
}
