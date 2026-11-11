import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/youtube_cookie_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _hint = '粘贴 cookies.txt 的内容，或请求头里 cookie 的值';
const _unknownText = '结果未知，请确认状态后再决定是否重新填写。';

const _steps = [
  '1. 在电脑浏览器打开无痕窗口，登录用来点歌的 YouTube 账号，账号可能被 YouTube '
      '封禁，建议用不常用的账号。',
  '2. 在同一个标签页打开 www.youtube.com/robots.txt，无痕窗口里只留这一个'
      '标签页。',
  '3. 用 Get cookies.txt LOCALLY 这类扩展导出 youtube.com 的 cookies.txt，或在'
      '开发者工具“网络”面板里复制 robots.txt 请求头中 cookie 的值。',
  '4. 保存之后直接关掉这个无痕窗口，不要再在里面打开 YouTube 的页面。',
];

Future<void> showYoutubeCookieSheet(
  BuildContext context, {
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => YoutubeCookieSheet(onNotice: onNotice),
  );
}

// cookies 只保存在输入框中，面板关闭即释放；服务端不回传已保存的内容。保存期间
// 面板不能关闭，结果要在这里说明。
class YoutubeCookieSheet extends ConsumerStatefulWidget {
  const YoutubeCookieSheet({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<YoutubeCookieSheet> createState() => _YoutubeCookieSheetState();
}

class _YoutubeCookieSheetState extends ConsumerState<YoutubeCookieSheet> {
  final _cookies = TextEditingController();
  bool _saving = false;
  String? _problem;

  // 撤销记录保存在输入框内部，只清空文字仍能撤销回来；换掉输入框才能一并丢弃。
  Key _field = UniqueKey();

  @override
  void dispose() {
    _cookies.dispose();
    super.dispose();
  }

  // 超限在粘贴时立即提示，空白等到保存时再提示。
  void _edited(String cookies) {
    final problem = youtubeCookieProblem(cookies) == youtubeCookieTooLargeText
        ? youtubeCookieTooLargeText
        : null;
    if (problem != _problem) setState(() => _problem = problem);
  }

  Future<void> _save() async {
    if (_saving) return;
    final controller = ref.read(youtubeCookieControllerProvider.notifier);
    setState(() {
      _saving = true;
      _problem = null;
    });
    final MutationResult<void> result;
    try {
      result = await controller.save(_cookies.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // 会话已结束时面板随路由一起关闭，由 token 页说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        _close(ToastKind.success, '已保存 YouTube Cookie');
      case MutationUnknown():
        _close(ToastKind.warning, _unknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
    }
  }

  void _close(ToastKind kind, String text) {
    setState(() {
      _cookies.clear();
      _field = UniqueKey();
    });
    dismissSheet(context);
    widget.onNotice(kind, text);
  }

  @override
  Widget build(BuildContext context) {
    // 面板打开期间控制器不能释放：保存要用到它，而后台页面中的 YouTube 组离开
    // 视图时会被列表回收，不再持有它。
    ref.listen(youtubeCookieControllerProvider, (_, _) {});
    final colors = AlistenColors.of(context);
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
              '填写 YouTube Cookie',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          for (final step in _steps)
            Padding(
              padding: const EdgeInsets.only(bottom: AlistenSpacing.xs),
              child: Text(
                step,
                style: AlistenTypography.secondary.copyWith(
                  color: colors.onGlassMuted,
                ),
              ),
            ),
          const SizedBox(height: AlistenSpacing.sm),
          // 不自动聚焦：键盘和面板同时滑入会让面板的入场掉帧。
          AlistenTextField(
            key: _field,
            controller: _cookies,
            hint: _hint,
            maxLines: 8,
            sensitive: true,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: _edited,
          ),
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
          const SizedBox(height: AlistenSpacing.xl),
          PillButton(
            label: '保存',
            icon: Icons.check_rounded,
            large: true,
            expand: true,
            busy: _saving,
            onPressed: () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
