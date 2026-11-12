import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/api_key_controller.dart';
import 'package:alisten/features/admin/presentation/admin_time.dart';
import 'package:alisten/features/admin/presentation/secret_box.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _notFound = 'NOT_FOUND';
// 服务端重置 Key 后会通知断开用旧 Key 打开的事件流；通知发送失败时回复失败，
// 这些事件流仍然连着。
const _resetLostText =
    'Key 已重置，但没有收到新 Key，请再重置一次。旧 Key 已不能发起新请求，'
    '但已经连上的 bot 可能还没有断开。';
const _generateLostText = 'Key 已生成，但没有收到它，请再生成一次。';
const _mayBeInvalidText = '旧 Key 可能已经失效。';
const _resetUnknownText = '结果未知，旧 Key 可能已经失效。请确认生成时间后再决定是否重置。';
const _generateUnknownText = '结果未知，请确认状态后再决定是否生成。';
const _resetMaybeTakenText = 'Key 可能已经重置，旧 Key 可能已失效。';
const _generateMaybeTakenText = 'Key 可能已经生成，需要时请再生成一次。';
const _closeUncopiedText = '还没有复制 Key，关闭后不能再查看。确定关闭？';

Future<void> showApiKeySheet(
  BuildContext context, {
  required RoomListing room,
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => ApiKeySheet(room: room, onNotice: onNotice),
  );
}

// 新 Key 只保存在本面板的 State 中，面板关闭即丢弃，之后无法再查看。重置期间
// 面板不能关闭，否则拿不到新 Key，旧 Key 却已失效；Key 尚未复制时关闭要先确认。
class ApiKeySheet extends ConsumerStatefulWidget {
  const ApiKeySheet({required this.room, required this.onNotice, super.key});

  final RoomListing room;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<ApiKeySheet> createState() => _ApiKeySheetState();
}

class _ApiKeySheetState extends ConsumerState<ApiKeySheet> {
  String? _key;
  bool _copied = false;
  bool _resetting = false;
  bool _askingToClose = false;
  ({String text, StatusTone tone})? _problem;

  bool get _keepOpen => _resetting || (_key != null && !_copied);

  ApiKeyController get _controller =>
      ref.read(apiKeyControllerProvider(widget.room.id).notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _controller.load();
      }),
    );
  }

  Future<void> _reset(ApiKeyStatus before) async {
    final generated = before.generated;
    final onNotice = widget.onNotice;
    final confirmed = await showConfirmSheet(
      context,
      title: generated ? '重置 API Key？' : '生成 API Key？',
      message: generated
          ? '重置后旧 Key 立即失效，正在使用它的 bot 需要换成新 Key。'
          : '新 Key 只显示一次，生成后请立即复制。',
      confirmLabel: generated ? '重置' : '生成',
      confirmIcon: AlistenIcons.key,
    );
    if (!confirmed || !mounted || _resetting) return;
    setState(() {
      _resetting = true;
      _key = null;
      _copied = false;
      _problem = null;
    });
    final MutationResult<String> result;
    try {
      result = await _controller.reset();
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
    // 会话已结束时面板随路由一起关闭，由 token 页说明原因；请求已发出时 Key
    // 可能已经更换，改用面板关闭后仍可见的应用级提示说明。
    if (!mounted || !ref.read(adminSessionProvider).active) {
      if (result is MutationUnknown<String>) {
        onNotice(
          ToastKind.warning,
          generated ? _resetMaybeTakenText : _generateMaybeTakenText,
        );
      }
      return;
    }
    // 未成功时控制器已重新读取状态：生成时间变了，说明服务端已经重置，只是新
    // Key 没有送达。
    final after = ref.read(apiKeyControllerProvider(widget.room.id)).status;
    final lost = after != null && after.createdAtMs > before.createdAtMs;
    setState(() {
      _problem = switch (result) {
        MutationSucceeded() => null,
        MutationUnknown() || MutationFailed() when lost => (
          text: generated ? _resetLostText : _generateLostText,
          tone: StatusTone.warning,
        ),
        MutationUnknown() => (
          text: generated ? _resetUnknownText : _generateUnknownText,
          tone: StatusTone.warning,
        ),
        MutationFailed(:final code, :final message) => (
          text: generated && code != _notFound
              ? '$message\n$_mayBeInvalidText'
              : message,
          tone: StatusTone.danger,
        ),
        MutationNotSent(:final message) => (
          text: message,
          tone: StatusTone.danger,
        ),
      };
      if (result case MutationSucceeded(:final value)) _key = value;
    });
  }

  Future<void> _copy(String key) async {
    final onNotice = widget.onNotice;
    if (!await _controller.copy(key)) {
      onNotice(ToastKind.failure, '没能复制，请重试。');
      return;
    }
    if (mounted) setState(() => _copied = true);
    onNotice(ToastKind.success, 'API Key 已复制');
  }

  Future<void> _confirmClose() async {
    if (_askingToClose || _resetting) return;
    _askingToClose = true;
    final confirmed = await showConfirmSheet(
      context,
      title: '关闭这个面板？',
      message: _closeUncopiedText,
      confirmLabel: '关闭',
    );
    _askingToClose = false;
    if (!confirmed || !mounted) return;
    dismissSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final keyState = ref.watch(apiKeyControllerProvider(widget.room.id));
    final status = keyState.status;
    final error = keyState.error;
    final key = _key;
    final problem = _problem;
    return PopScope<void>(
      canPop: !_keepOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_resetting) unawaited(_confirmClose());
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'API Key',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.xxs),
          Text(
            widget.room.name,
            style: AlistenTypography.secondary.copyWith(
              color: colors.onGlassMuted,
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          if (status != null)
            Text(
              status.generated
                  ? '已生成，生成于 ${formatAdminTime(status.createdAtMs)}'
                  : '还没有生成 API Key',
              style: AlistenTypography.body.copyWith(color: colors.onGlass),
            )
          else if (keyState.loading)
            const Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(
                label: '正在读取',
                icon: AlistenIcons.arrowsClockwise,
                busy: true,
              ),
            ),
          if (error != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(
              text: error,
              action: PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: keyState.loading
                    ? null
                    : () => unawaited(_controller.load()),
              ),
            ),
          ],
          if (key != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            SecretBox(secret: key, onCopy: () => unawaited(_copy(key))),
            const SizedBox(height: AlistenSpacing.xs),
            PillButton(
              label: '复制',
              icon: AlistenIcons.copySimple,
              expand: true,
              onPressed: () => unawaited(_copy(key)),
            ),
            const SizedBox(height: AlistenSpacing.sm),
            const InlineMessage(
              text: '关闭后不能再查看，请现在复制',
              tone: StatusTone.warning,
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            InlineMessage(text: problem.text, tone: problem.tone),
          ],
          const SizedBox(height: AlistenSpacing.xl),
          PillButton(
            label: status?.generated ?? false ? '重置 API Key' : '生成 API Key',
            icon: AlistenIcons.key,
            style: key == null
                ? PillButtonStyle.primary
                : PillButtonStyle.secondary,
            expand: true,
            busy: _resetting,
            onPressed: status == null ? null : () => unawaited(_reset(status)),
          ),
        ],
      ),
    );
  }
}
