import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_api.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const githubAppInvalidText =
    'Client ID 和 Client Secret 只能包含字母、数字、点、下划线和连字符，请从 GitHub 重新复制。';

const _notLoadedText = '暂时无法获取 GitHub 登录的配置。';
const _incompleteText = '请填写 Client ID 和 Client Secret';

final class GithubAppState {
  const GithubAppState({this.status, this.loading = false, this.error});

  final GithubAppStatus? status;
  final bool loading;
  final String? error;
}

final githubAppControllerProvider =
    NotifierProvider.autoDispose<GithubAppController, GithubAppState>(
      GithubAppController.new,
    );

/// Client Secret 是凭据：只作为参数交给 [AdminSession.run]，不进入状态或日志。
final class GithubAppController extends Notifier<GithubAppState> {
  int _loads = 0;

  @override
  GithubAppState build() => const GithubAppState();

  Future<void> load() async {
    final attempt = ++_loads;
    bool latest() => ref.mounted && attempt == _loads;
    state = GithubAppState(status: state.status, loading: true);
    try {
      final status = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.getGithubApp(token));
      if (latest()) state = GithubAppState(status: status);
    } on AdminSessionEnded {
      if (latest()) state = GithubAppState(status: state.status);
    } on Object catch (error) {
      if (error is! ApiException) {
        AppLog.warn(
          'admin',
          'github app not loaded',
          type: '${error.runtimeType}',
        );
      }
      if (latest()) {
        state = GithubAppState(status: state.status, error: _notLoadedText);
      }
    }
  }

  /// 两项都去掉首尾空白再发送：从网页复制时常带空白，服务端不接受。
  Future<MutationResult<void>> save({
    required String clientId,
    required String clientSecret,
  }) async {
    final id = clientId.trim();
    final secret = clientSecret.trim();
    if (id.isEmpty || secret.isEmpty) {
      return const MutationNotSent(_incompleteText);
    }
    return _change(
      (api, token) =>
          api.setGithubApp(token, clientId: id, clientSecret: secret),
      unexpected: 'github app save ended unexpectedly',
    );
  }

  Future<MutationResult<void>> close() {
    return _change(
      (api, token) => api.deleteGithubApp(token),
      unexpected: 'github app close ended unexpectedly',
    );
  }

  // 服务端拒绝时配置没有变，不用重新读取。
  Future<MutationResult<void>> _change(
    Future<void> Function(AdminApi api, String token) operation, {
    required String unexpected,
  }) {
    return ref
        .read(adminSessionProvider.notifier)
        .change(
          operation,
          unexpected: unexpected,
          refusals: const {'INVALID_ARGUMENT': githubAppInvalidText},
          reread: (result) async {
            if (result is! MutationFailed<void> && ref.mounted) {
              unawaited(load());
            }
          },
        );
  }
}
