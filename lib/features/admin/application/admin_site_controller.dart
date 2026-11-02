import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const brandNameRuleText = '品牌名要有 1 到 20 个字，不能含换行、制表符等特殊字符';

const _maxBrandNameLength = 20;
const _invalidArgument = 'INVALID_ARGUMENT';
const _notLoadedText = '没能读取品牌名，请稍后重试。';
const _sessionEndedText = '后台已退出，品牌名没有保存。';

final _control = RegExp(r'\p{Cc}', unicode: true);

/// 与服务端规则一致，长度按 Unicode 码点计。
String? brandNameProblem(String input) {
  final name = input.trim();
  final length = name.runes.length;
  if (length < 1 ||
      length > _maxBrandNameLength ||
      _control.hasMatch(name) ||
      !hasVisibleCharacter(name)) {
    return brandNameRuleText;
  }
  return null;
}

final class AdminSiteState {
  const AdminSiteState({this.brandName, this.loading = false, this.error});

  final String? brandName;
  final bool loading;
  final String? error;
}

final adminSiteControllerProvider =
    NotifierProvider.autoDispose<AdminSiteController, AdminSiteState>(
      AdminSiteController.new,
    );

final class AdminSiteController extends Notifier<AdminSiteState> {
  @override
  AdminSiteState build() => const AdminSiteState();

  Future<void> load() async {
    state = AdminSiteState(brandName: state.brandName, loading: true);
    final session = ref.read(adminSessionProvider.notifier);
    final directory = ref.read(serverDirectoryProvider.notifier);
    final serverId = ref.read(currentServerProvider).id;
    try {
      final name = await session.run((api, _) => api.getBrandName());
      if (ref.mounted) state = AdminSiteState(brandName: name);
      await _updateListed(directory, serverId, name);
    } on AdminSessionEnded {
      if (ref.mounted) state = AdminSiteState(brandName: state.brandName);
    } on ApiException catch (error) {
      if (ref.mounted) {
        state = AdminSiteState(
          brandName: state.brandName,
          error: error.message,
        );
      }
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'brand name not loaded',
        type: '${error.runtimeType}',
      );
      if (ref.mounted) {
        state = AdminSiteState(
          brandName: state.brandName,
          error: _notLoadedText,
        );
      }
    }
  }

  Future<MutationResult<String>> save(String input) async {
    if (brandNameProblem(input) case final problem?) {
      return MutationNotSent(problem);
    }
    final name = input.trim();
    final directory = ref.read(serverDirectoryProvider.notifier);
    // 会话保证等待期间不会切换服务器，此刻的当前服务器就是保存品牌名的服务器。
    final serverId = ref.read(currentServerProvider).id;
    final result = await ref
        .read(adminSessionProvider.notifier)
        .change(
          (api, token) => api.updateBrandName(token, name),
          unexpected: 'brand name save ended unexpectedly',
          refusals: const {_invalidArgument: brandNameRuleText},
          sessionEnded: _sessionEndedText,
          reread: (result) async {
            if (result is MutationUnknown<String> && ref.mounted) {
              unawaited(load());
            }
          },
        );
    if (result case MutationSucceeded(value: final saved)) {
      if (ref.mounted) state = AdminSiteState(brandName: saved);
      await _updateListed(directory, serverId, saved);
    }
    return result;
  }

  // 写入列表失败不影响服务端已保存的结果。服务端回复的名字同样要校验后才写入，
  // 异常的服务端不能把超长或含控制字符的名字留在列表里。
  Future<void> _updateListed(
    ServerDirectory directory,
    String id,
    String name,
  ) async {
    if (brandNameProblem(name) != null) {
      AppLog.warn('admin', 'brand name from server not listed');
      return;
    }
    try {
      await directory.updateBrandName(id, name);
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'brand name not listed',
        type: '${error.runtimeType}',
      );
    }
  }
}
