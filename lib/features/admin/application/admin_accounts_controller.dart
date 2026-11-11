import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/sensitive_clipboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const accountNotFoundText = '没有这个用户名的账号。';
const _notLoadedText = '没能查找账号，请稍后重试。';

final class AdminAccountsState {
  const AdminAccountsState({
    this.account,
    this.searching = false,
    this.problem,
  });

  final AdminAccountView? account;
  final bool searching;
  final String? problem;
}

final adminAccountsControllerProvider =
    NotifierProvider.autoDispose<AdminAccountsController, AdminAccountsState>(
      AdminAccountsController.new,
    );

/// 重置得到的新密码只作为 [resetPassword] 的结果交给调用方，不进入状态。
final class AdminAccountsController extends Notifier<AdminAccountsState> {
  int _searches = 0;

  @override
  AdminAccountsState build() => const AdminAccountsState();

  Future<void> find(String input) async {
    final username = input.trim();
    if (usernameProblem(username) case final problem?) {
      _searches++;
      state = AdminAccountsState(problem: problem);
      return;
    }
    final search = ++_searches;
    bool latest() => ref.mounted && search == _searches;
    state = const AdminAccountsState(searching: true);
    try {
      final account = await ref
          .read(adminSessionProvider.notifier)
          .run((api, token) => api.findAccount(token, username));
      if (latest()) state = AdminAccountsState(account: account);
    } on AdminSessionEnded {
      if (latest()) state = const AdminAccountsState();
    } on ApiException catch (error) {
      if (latest()) {
        state = AdminAccountsState(
          problem: error.code == 'NOT_FOUND'
              ? accountNotFoundText
              : error.message,
        );
      }
    } on Object catch (error) {
      AppLog.warn('admin', 'account not found', type: '${error.runtimeType}');
      if (latest()) state = const AdminAccountsState(problem: _notLoadedText);
    }
  }

  Future<MutationResult<String>> resetPassword() async {
    final account = state.account;
    if (account == null) return const MutationNotSent(accountNotFoundText);
    return ref
        .read(adminSessionProvider.notifier)
        .change(
          (api, token) => api.resetAccountPassword(token, account.username),
          unexpected: 'account password reset ended unexpectedly',
          reread: (_) async {},
        );
  }

  /// 失败时返回 false，不得退回普通剪贴板。
  Future<bool> copy(String password) async {
    try {
      await ref.read(sensitiveClipboardProvider).copy(password);
    } on Object {
      return false;
    }
    return true;
  }
}
