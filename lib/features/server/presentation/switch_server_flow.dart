import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/server/application/server_switcher.dart';
import 'package:alisten/features/server/presentation/join_server_sheet.dart';
import 'package:alisten/features/settings/index.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 切换成功返回 true；取消或失败返回 false，失败已提示。[onSwitching] 在面板
/// 关闭、真正开始切换时调用，此后切换和保存资料可能还要等待网络。
Future<bool> switchServerFlow(
  BuildContext context,
  WidgetRef ref,
  ServerProfile target, {
  required void Function(ToastKind kind, String text) onNotice,
  VoidCallback? onSwitching,
}) async {
  final switcher = ref.read(serverSwitcherProvider);
  // 切换成功后无论页面是否还在都要保存资料，所以在等待前取得。
  final settings = ref.read(settingsControllerProvider.notifier);
  JoinProfile? joining;
  var storedEmail = '';
  if (await switcher.needsJoinConfirmation(target)) {
    if (!context.mounted) return false;
    storedEmail = ref.read(settingsControllerProvider).value.email;
    joining = await showJoinServerSheet(
      context,
      brandName: target.displayName,
      nickname: ref.read(identityControllerProvider).member?.name ?? '',
      email: storedEmail,
    );
    if (joining == null || !context.mounted) return false;
  }
  onSwitching?.call();
  switch (await switcher.switchTo(target)) {
    case SwitchFailed(:final message):
      onNotice(ToastKind.failure, message);
      return false;
    case SwitchSucceeded(:final server):
      final name = server.displayName;
      if (joining == null ||
          await _saveProfile(settings, joining, storedEmail: storedEmail)) {
        onNotice(ToastKind.success, '已切换到 $name');
      } else {
        onNotice(ToastKind.warning, '已切换到 $name，但昵称和邮箱没能保存，可以在设置里修改。');
      }
      return true;
  }
}

// 本机存有邮箱而面板中已清空时也要保存，才能清掉它。
Future<bool> _saveProfile(
  SettingsController settings,
  JoinProfile profile, {
  required String storedEmail,
}) async {
  if (profile.nickname.isEmpty &&
      profile.email.isEmpty &&
      storedEmail.isEmpty) {
    return true;
  }
  final result = await settings.saveProfile(
    nickname: profile.nickname,
    email: profile.email,
  );
  return result is MutationSucceeded<Object?>;
}
