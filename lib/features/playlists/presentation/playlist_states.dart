import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/playlist/my_playlist.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

/// 在比页面存活更久的地方提示，App 层传入 `toasts.show`。
typedef PlaylistNotice = void Function(ToastKind kind, String text);

/// 失败、没有发出和结果未知都提示；成功只在给了 [success] 时提示。
void reportPlaylistResult(
  PlaylistNotice notice,
  MutationResult<Object?> result, {
  String? success,
}) {
  switch (result) {
    case MutationSucceeded():
      if (success != null) notice(ToastKind.success, success);
    case MutationFailed(:final message):
      notice(ToastKind.failure, message);
    case MutationNotSent(:final message):
      notice(ToastKind.warning, message);
    case MutationUnknown():
      notice(ToastKind.warning, unknownResultText);
  }
}

/// 根导航器上的面板或系统的文件选择器开着、请求还没回来时，链接或通知可能先换
/// 掉页面，而页面是 [provider] 唯一的监听者：直到 [action] 结束都由这里让它
/// 活着。[context] 只在开始时用到。
Future<void> holdingWhile(
  BuildContext context,
  ProviderListenable<Object?> provider,
  Future<void> Function() action,
) async {
  final hold = ProviderScope.containerOf(
    context,
    listen: false,
  ).listen<Object?>(provider, (_, _) {});
  try {
    await action();
  } finally {
    hold.close();
  }
}

/// 在面板的 build 里调用。面板里的歌单和提交都属于打开时的身份：会话、成员或
/// 服务器一换就关闭。打开时身份还没读到的，读到不算换了身份。
void dismissOnOwnerChange(WidgetRef ref, BuildContext context) {
  ref.listen(
    identityControllerProvider.select(
      (identity) => (identity.session, identity.member?.id),
    ),
    (previous, next) {
      if (previous?.$1 != next.$1 || previous?.$2 != null) {
        dismissSheet(context);
      }
    },
  );
}

Future<bool> confirmPlaylistDelete(BuildContext context, MyPlaylist playlist) {
  return showConfirmSheet(
    context,
    title: '删除歌单',
    message: '删除“${playlist.name}”之后，里面的歌也一起删除。',
    confirmLabel: '删除',
    confirmIcon: Icons.delete_outline_rounded,
  );
}

/// 顶栏浮在页面之上，底部的内边距已包含迷你播放条：状态要避开两者。
class PlaylistPageFill extends StatelessWidget {
  const PlaylistPageFill({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.paddingOf(context);
    return SliverFillRemaining(
      child: Padding(
        padding: EdgeInsets.only(
          top: media.top + AlistenSizes.minTouchTarget,
          bottom: media.bottom,
        ),
        child: child,
      ),
    );
  }
}

/// Web 的按钮是“去注册”；App 的站点可能关闭注册，账号组里登录和注册都在，所以
/// 去账号设置。
class PlaylistGuestState extends StatelessWidget {
  const PlaylistGuestState({required this.onOpenAccount, super.key});

  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.star_rounded,
      title: '收藏你喜欢的歌',
      message: '注册账号之后，就能收藏歌曲、建自己的歌单。',
      action: PillButton(
        label: '去账号设置',
        icon: Icons.person_rounded,
        style: PillButtonStyle.secondary,
        onPressed: onOpenAccount,
      ),
    );
  }
}

/// 面板里的游客提示。
class PlaylistGuestPrompt extends StatelessWidget {
  const PlaylistGuestPrompt({
    required this.message,
    required this.onOpenAccount,
    super.key,
  });

  final String message;
  final VoidCallback onOpenAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: AlistenTypography.body.copyWith(
            color: AlistenColors.of(context).onGlass,
          ),
        ),
        const SizedBox(height: AlistenSpacing.lg),
        PillButton(
          label: '去账号设置',
          icon: Icons.person_rounded,
          large: true,
          expand: true,
          onPressed: onOpenAccount,
        ),
      ],
    );
  }
}

class PlaylistLoading extends StatelessWidget {
  const PlaylistLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: BusyIndicator(size: AlistenSizes.iconLg, semanticLabel: '正在加载歌单'),
    );
  }
}

class PlaylistReadFailure extends StatelessWidget {
  const PlaylistReadFailure({
    required this.message,
    required this.onRetry,
    super.key,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: EmptyState(
        icon: Icons.cloud_off_rounded,
        title: '读取失败：$message',
        action: PillButton(
          label: '重试',
          icon: Icons.refresh_rounded,
          style: PillButtonStyle.secondary,
          onPressed: onRetry,
        ),
      ),
    );
  }
}
