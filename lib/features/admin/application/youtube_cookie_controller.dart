import 'dart:async';
import 'dart:convert';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_api.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const youtubeCookieEmptyText = '请粘贴 cookies';
const youtubeCookieTooLargeText = '内容超过 64 KiB，请只导出 youtube.com 的 cookies';
const youtubeCookieBodyLimit = 65536;

const _notLoadedText = '没能读取 YouTube Cookie 的状态，请稍后重试。';

/// 服务端限制的是 JSON 请求体 `{"cookies": …}` 的总字节数。
String? youtubeCookieProblem(String cookies) {
  if (cookies.trim().isEmpty) return youtubeCookieEmptyText;
  final body = utf8.encode(jsonEncode({'cookies': cookies}));
  if (body.length > youtubeCookieBodyLimit) return youtubeCookieTooLargeText;
  return null;
}

final class YoutubeCookieState {
  const YoutubeCookieState({this.status, this.loading = false, this.error});

  final YoutubeCookieStatus? status;
  final bool loading;
  final String? error;
}

final youtubeCookieControllerProvider =
    NotifierProvider.autoDispose<YoutubeCookieController, YoutubeCookieState>(
      YoutubeCookieController.new,
    );

/// cookies 是凭据：只作为参数交给 [AdminSession.run]，不进入状态或日志。
final class YoutubeCookieController extends Notifier<YoutubeCookieState> {
  int _loads = 0;

  @override
  YoutubeCookieState build() => const YoutubeCookieState();

  Future<void> load() async {
    final attempt = ++_loads;
    bool latest() => ref.mounted && attempt == _loads;
    state = YoutubeCookieState(status: state.status, loading: true);
    try {
      final status = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.getYoutubeCookie(token));
      if (latest()) state = YoutubeCookieState(status: status);
    } on AdminSessionEnded {
      if (latest()) state = YoutubeCookieState(status: state.status);
    } on ApiException catch (error) {
      if (latest()) {
        state = YoutubeCookieState(status: state.status, error: error.message);
      }
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'youtube cookie status not loaded',
        type: '${error.runtimeType}',
      );
      if (latest()) {
        state = YoutubeCookieState(status: state.status, error: _notLoadedText);
      }
    }
  }

  /// cookies 原样发送，不去掉首尾空白。
  Future<MutationResult<void>> save(String cookies) async {
    if (youtubeCookieProblem(cookies) case final problem?) {
      return MutationNotSent(problem);
    }
    return _change(
      (api, token) => api.setYoutubeCookie(token, cookies),
      unexpected: 'youtube cookie save ended unexpectedly',
    );
  }

  Future<MutationResult<void>> clear() {
    return _change(
      (api, token) => api.deleteYoutubeCookie(token),
      unexpected: 'youtube cookie clear ended unexpectedly',
    );
  }

  // 服务端拒绝时状态未变，无需重新读取。
  Future<MutationResult<void>> _change(
    Future<void> Function(AdminApi api, String token) operation, {
    required String unexpected,
  }) {
    return ref
        .read(adminSessionProvider.notifier)
        .change(
          operation,
          unexpected: unexpected,
          reread: (result) async {
            if (result is! MutationFailed<void> && ref.mounted) {
              unawaited(load());
            }
          },
        );
  }
}
