import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/youtube_cookie_controller.dart';
import 'package:alisten/features/admin/presentation/admin_time.dart';
import 'package:alisten/features/admin/presentation/youtube_cookie_sheet.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _clearUnknownText = '结果未知，请确认状态后再决定是否重试。';

class YoutubeGroup extends ConsumerStatefulWidget {
  const YoutubeGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<YoutubeGroup> createState() => _YoutubeGroupState();
}

class _YoutubeGroupState extends ConsumerState<YoutubeGroup>
    with AutomaticKeepAliveClientMixin {
  bool _clearing = false;

  // 清除期间列表不能回收这一组：回收后控制器随之释放，清除结果既不会提示，
  // 也不会重新读取状态。
  @override
  bool get wantKeepAlive => _clearing;

  YoutubeCookieController get _cookies =>
      ref.read(youtubeCookieControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _cookies.load();
      }),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showConfirmSheet(
      context,
      title: '清除 YouTube Cookie？',
      message: '清除后，下载 YouTube 链接时不再携带 cookies',
      confirmLabel: '清除',
      confirmIcon: AlistenIcons.trash,
    );
    if (!confirmed || !mounted || _clearing) return;
    setState(() => _clearing = true);
    updateKeepAlive();
    final MutationResult<void> result;
    try {
      result = await _cookies.clear();
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
        updateKeepAlive();
      }
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        widget.onNotice(ToastKind.success, '已清除 YouTube Cookie');
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, _clearUnknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        widget.onNotice(ToastKind.failure, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AlistenColors.of(context);
    final cookie = ref.watch(youtubeCookieControllerProvider);
    final status = cookie.status;
    final error = cookie.error;
    final saved = status?.saved ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlistenSpacing.md,
        vertical: AlistenSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (status != null)
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                saved
                    ? '已配置，最近填写于 ${formatAdminTime(status.updatedAtMs)}'
                    : '未配置',
                style: AlistenTypography.body.copyWith(color: colors.onGlass),
              ),
            )
          else if (error == null)
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
                onPressed: cookie.loading
                    ? null
                    : () => unawaited(_cookies.load()),
              ),
            ),
          ],
          const SizedBox(height: AlistenSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AlistenSpacing.xs,
            runSpacing: AlistenSpacing.xs,
            children: [
              if (saved)
                PillButton(
                  label: '清除',
                  icon: AlistenIcons.trash,
                  style: PillButtonStyle.ghost,
                  busy: _clearing,
                  onPressed: () => unawaited(_clear()),
                ),
              PillButton(
                label: saved ? '覆盖' : '填写',
                icon: AlistenIcons.clipboardText,
                style: PillButtonStyle.secondary,
                onPressed: (status == null && error == null) || _clearing
                    ? null
                    : () => unawaited(
                        showYoutubeCookieSheet(
                          context,
                          onNotice: widget.onNotice,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
