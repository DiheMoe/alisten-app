import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/shared/ui/toast.dart';

/// [GithubOutcome.verified] 不提示：由调用方打开设置用户名和密码的面板。
void noticeGithubResult(
  void Function(ToastKind kind, String text) onNotice,
  MutationResult<GithubOutcome> result,
) {
  switch (result) {
    case MutationSucceeded(value: GithubOutcome.signedIn):
      onNotice(ToastKind.success, '已登录');
    case MutationSucceeded(value: GithubOutcome.registered):
      onNotice(ToastKind.success, '已用 GitHub 注册');
    case MutationSucceeded(value: GithubOutcome.bound):
      onNotice(ToastKind.success, '已绑定 GitHub');
    case MutationSucceeded(value: GithubOutcome.verified):
      break;
    case MutationFailed(:final message) || MutationNotSent(:final message):
      onNotice(ToastKind.failure, message);
    case MutationUnknown():
      onNotice(ToastKind.warning, githubUnknownText);
  }
}
