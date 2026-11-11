import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notLoadedText = '暂时无法获取注册状态。';
const _sessionEndedText = '后台已退出，注册状态没有修改。';

final class AdminRegistrationState {
  const AdminRegistrationState({this.open, this.loading = false, this.error});

  final bool? open;
  final bool loading;
  final String? error;
}

final adminRegistrationControllerProvider =
    NotifierProvider.autoDispose<
      AdminRegistrationController,
      AdminRegistrationState
    >(AdminRegistrationController.new);

final class AdminRegistrationController
    extends Notifier<AdminRegistrationState> {
  @override
  AdminRegistrationState build() => const AdminRegistrationState();

  Future<void> load() async {
    state = AdminRegistrationState(open: state.open, loading: true);
    try {
      final open = await ref
          .read(adminSessionProvider.notifier)
          .run((api, _) => api.getRegistrationOpen());
      if (ref.mounted) state = AdminRegistrationState(open: open);
    } on AdminSessionEnded {
      if (ref.mounted) state = AdminRegistrationState(open: state.open);
    } on Object catch (error) {
      if (error is! ApiException) {
        AppLog.warn(
          'admin',
          'registration not loaded',
          type: '${error.runtimeType}',
        );
      }
      if (ref.mounted) {
        state = AdminRegistrationState(open: state.open, error: _notLoadedText);
      }
    }
  }

  Future<MutationResult<bool>> setOpen(bool open) async {
    final result = await ref
        .read(adminSessionProvider.notifier)
        .change<bool>(
          (api, token) async {
            await (open
                ? api.openRegistration(token)
                : api.closeRegistration(token));
            return open;
          },
          unexpected: 'registration switch ended unexpectedly',
          sessionEnded: _sessionEndedText,
          reread: (result) async {
            if (result is MutationUnknown<bool> && ref.mounted) {
              unawaited(load());
            }
          },
        );
    if (result case MutationSucceeded(:final value) when ref.mounted) {
      state = AdminRegistrationState(open: value);
    }
    return result;
  }
}
