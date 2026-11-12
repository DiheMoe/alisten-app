import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/github_app_controller.dart';
import 'package:alisten/features/admin/presentation/github_app_sheet.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _offText =
    '在 GitHub 的 Settings → Developer settings → OAuth Apps 新建一个 OAuth App，'
    '填好下面的 Client ID 和 Client Secret 就会开启。';
const _onText = '用户可以用 GitHub 登录、注册和绑定账号。';
const _callbackNote = 'OAuth App 的 Authorization callback URL 填这个地址。';
const _closeMessage =
    '关闭后，不能再用 GitHub 登录、注册或绑定，已经绑定的 GitHub 保持绑定。'
    '只绑定了 GitHub 的账号，关闭之后就无法用 GitHub 登录，重新开启之前也无法在'
    '其他设备上登录。';
const _closeUnknownText = '结果未知，请确认状态后再决定是否重试。';

class GithubAppGroup extends ConsumerStatefulWidget {
  const GithubAppGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<GithubAppGroup> createState() => _GithubAppGroupState();
}

class _GithubAppGroupState extends ConsumerState<GithubAppGroup>
    with AutomaticKeepAliveClientMixin {
  bool _closing = false;

  // 关闭期间列表不能回收这一组：回收后控制器随之释放，结果既不会提示，也不会
  // 重新读取状态。
  @override
  bool get wantKeepAlive => _closing;

  GithubAppController get _github =>
      ref.read(githubAppControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _github.load();
      }),
    );
  }

  // 回调地址不是秘密，用普通剪贴板。
  Future<void> _copy(String url) async {
    final onNotice = widget.onNotice;
    try {
      await Clipboard.setData(ClipboardData(text: url));
    } on Object {
      onNotice(ToastKind.warning, '请手动复制回调地址：$url');
      return;
    }
    onNotice(ToastKind.success, '已复制回调地址');
  }

  Future<void> _close() async {
    final confirmed = await showConfirmSheet(
      context,
      title: '关闭 GitHub 登录',
      message: _closeMessage,
      confirmLabel: '关闭',
      confirmIcon: AlistenIcons.linkBreak,
    );
    if (!confirmed || !mounted || _closing) return;
    setState(() => _closing = true);
    updateKeepAlive();
    final MutationResult<void> result;
    try {
      result = await _github.close();
    } finally {
      if (mounted) {
        setState(() => _closing = false);
        updateKeepAlive();
      }
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        widget.onNotice(ToastKind.success, '已关闭 GitHub 登录');
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, _closeUnknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        widget.onNotice(ToastKind.failure, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AlistenColors.of(context);
    final note = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    final github = ref.watch(githubAppControllerProvider);
    final status = github.status;
    final error = github.error;
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null) ...[
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                status.enabled ? '已开启' : '未开启',
                style: AlistenTypography.bodyStrong.copyWith(
                  color: colors.onGlass,
                ),
              ),
            ),
            const SizedBox(height: AlistenSpacing.xxs),
            Text(status.enabled ? _onText : _offText, style: note),
            const SizedBox(height: AlistenSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    status.callbackUrl,
                    style: AlistenTypography.body.copyWith(
                      color: colors.onGlass,
                    ),
                  ),
                ),
                const SizedBox(width: AlistenSpacing.xs),
                PillButton(
                  label: '复制',
                  icon: AlistenIcons.copySimple,
                  style: PillButtonStyle.ghost,
                  onPressed: () => unawaited(_copy(status.callbackUrl)),
                ),
              ],
            ),
            const SizedBox(height: AlistenSpacing.xxs),
            Text(_callbackNote, style: note),
          ] else if (error == null)
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(
                label: '正在读取',
                icon: AlistenIcons.arrowsClockwise,
                busy: true,
              ),
            ),
          if (error != null) ...[
            if (status != null) const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(
              text: error,
              action: PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: github.loading
                    ? null
                    : () => unawaited(_github.load()),
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AlistenSpacing.xs,
              runSpacing: AlistenSpacing.xs,
              children: [
                if (status.enabled)
                  PillButton(
                    label: '关闭 GitHub 登录',
                    icon: AlistenIcons.linkBreak,
                    style: PillButtonStyle.ghost,
                    busy: _closing,
                    onPressed: () => unawaited(_close()),
                  ),
                PillButton(
                  label: status.enabled ? '修改' : '开启',
                  icon: AlistenIcons.key,
                  style: PillButtonStyle.secondary,
                  onPressed: _closing
                      ? null
                      : () => unawaited(
                          showGithubAppSheet(
                            context,
                            status: status,
                            onNotice: widget.onNotice,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
