import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notLoadedText = '没能读取音源账号，请稍后重试。';

final class SourceEntry {
  const SourceEntry({this.status, this.loading = false, this.error});

  final SourceAccountStatus? status;
  final bool loading;
  final String? error;
}

final sourceAccountsControllerProvider =
    NotifierProvider.autoDispose<
      SourceAccountsController,
      Map<LoginSource, SourceEntry>
    >(SourceAccountsController.new);

final class SourceAccountsController
    extends Notifier<Map<LoginSource, SourceEntry>> {
  final Map<LoginSource, int> _loads = {};

  @override
  Map<LoginSource, SourceEntry> build() => {
    for (final source in LoginSource.values) source: const SourceEntry(),
  };

  Future<void> loadAll() async {
    await Future.wait([for (final source in LoginSource.values) load(source)]);
  }

  /// 读取失败或会话已结束时返回 null，并保留已读到的状态。
  Future<SourceAccountStatus?> load(LoginSource source) async {
    final attempt = _loads[source] = (_loads[source] ?? 0) + 1;
    bool latest() => ref.mounted && attempt == _loads[source];
    void put(SourceEntry Function(SourceAccountStatus? previous) entry) {
      if (!latest()) return;
      state = {...state, source: entry(state[source]?.status)};
    }

    put((previous) => SourceEntry(status: previous, loading: true));
    try {
      final status = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.getSourceAccount(token, source));
      put((_) => SourceEntry(status: status));
      return status;
    } on AdminSessionEnded {
      put((previous) => SourceEntry(status: previous));
    } on ApiException catch (error) {
      put((previous) => SourceEntry(status: previous, error: error.message));
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'source account not loaded',
        type: '${error.runtimeType}',
      );
      put((previous) => SourceEntry(status: previous, error: _notLoadedText));
    }
    return null;
  }
}
