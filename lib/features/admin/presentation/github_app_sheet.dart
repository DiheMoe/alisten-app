import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/github_app_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _unknownText = '结果未知，请确认状态后再决定是否重新填写。';

Future<void> showGithubAppSheet(
  BuildContext context, {
  required GithubAppStatus status,
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => GithubAppSheet(status: status, onNotice: onNotice),
  );
}

// Client Secret 只保存在输入框中，面板关闭即释放；服务端不回传已保存的值。
// 保存期间面板不能关闭，结果要在这里说明。
class GithubAppSheet extends ConsumerStatefulWidget {
  const GithubAppSheet({
    required this.status,
    required this.onNotice,
    super.key,
  });

  final GithubAppStatus status;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<GithubAppSheet> createState() => _GithubAppSheetState();
}

class _GithubAppSheetState extends ConsumerState<GithubAppSheet> {
  late final _clientId = TextEditingController(
    text: widget.status.clientId ?? '',
  );
  final _secret = TextEditingController();
  bool _saving = false;
  String? _problem;

  // 撤销记录保存在输入框内部，只清空文字仍能撤销回来；换掉输入框才能一并丢弃。
  Key _idField = UniqueKey();
  Key _secretField = UniqueKey();

  bool get _complete =>
      _clientId.text.trim().isNotEmpty && _secret.text.trim().isNotEmpty;

  @override
  void dispose() {
    _clientId.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_complete) return;
    final controller = ref.read(githubAppControllerProvider.notifier);
    final enabling = !widget.status.enabled;
    setState(() {
      _saving = true;
      _problem = null;
    });
    final MutationResult<void> result;
    try {
      result = await controller.save(
        clientId: _clientId.text,
        clientSecret: _secret.text,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // 会话已结束时面板随路由一起关闭，由 token 页说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        _close(
          ToastKind.success,
          enabling ? '已开启 GitHub 登录' : '已保存 GitHub OAuth App',
        );
      case MutationUnknown():
        _close(ToastKind.warning, _unknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
    }
  }

  void _close(ToastKind kind, String text) {
    setState(() {
      _clientId.clear();
      _secret.clear();
      _idField = UniqueKey();
      _secretField = UniqueKey();
    });
    dismissSheet(context);
    widget.onNotice(kind, text);
  }

  @override
  Widget build(BuildContext context) {
    // 面板打开期间控制器不能释放：保存要用到它，而后台页面中的这一组离开视图时
    // 会被列表回收，不再持有它。
    ref.listen(githubAppControllerProvider, (_, _) {});
    final colors = AlistenColors.of(context);
    final note = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    final secretSet = widget.status.clientSecretSet;
    final problem = _problem;
    return PopScope(
      canPop: !_saving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'GitHub OAuth App',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          // 不自动聚焦：键盘和面板同时滑入会让面板的入场掉帧。
          AlistenTextField(
            key: _idField,
            controller: _clientId,
            label: 'Client ID',
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            key: _secretField,
            controller: _secret,
            label: 'Client Secret',
            hint: secretSet ? '已设置' : null,
            obscureText: true,
            sensitive: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => unawaited(_save()),
          ),
          const SizedBox(height: AlistenSpacing.xxs),
          Text(
            secretSet ? '已设置。已保存的不会显示，保存时要和 Client ID 一起重新填写。' : '保存后不会再显示。',
            style: note,
          ),
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
          const SizedBox(height: AlistenSpacing.xl),
          PillButton(
            label: widget.status.enabled ? '保存' : '开启',
            icon: Icons.check_rounded,
            large: true,
            expand: true,
            busy: _saving,
            onPressed: _complete && !_saving ? () => unawaited(_save()) : null,
          ),
        ],
      ),
    );
  }
}
