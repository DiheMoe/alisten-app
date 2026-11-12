import 'dart:async';

import 'package:alisten/domain/member/github.dart';
import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/application/github_controller.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/account/presentation/credentials_form.dart';
import 'package:alisten/features/account/presentation/github_notice.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    required this.onDone,
    required this.onOpenRegister,
    required this.onOpenPairing,
    required this.onNotice,
    super.key,
  });

  final VoidCallback onDone;
  final VoidCallback onOpenRegister;
  final VoidCallback onOpenPairing;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // 两种登录都会换掉会话，一种在途时不能再发起另一种。
  bool _loggingIn = false;

  Future<MutationResult<Object?>> _login(
    String username,
    String password,
  ) async {
    setState(() => _loggingIn = true);
    try {
      return await ref
          .read(accountControllerProvider)
          .login(username: username, password: password);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _loggedIn() {
    widget.onNotice(ToastKind.success, '已登录');
    widget.onDone();
  }

  // 结果用发起时取到的 onNotice 提示：浏览器返回时登录页可能已经不在。
  Future<void> _signInWithGithub() async {
    final onNotice = widget.onNotice;
    final result = await ref.read(githubControllerProvider.notifier).signIn();
    noticeGithubResult(onNotice, result);
    if (result is MutationSucceeded && mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final inRoom = ref.watch(
      roomControllerProvider.select((room) => room.activeRoomId != null),
    );
    final site =
        ref.watch(siteCapabilitiesProvider).value ?? SiteCapabilities.unknown;
    final github = ref.watch(githubControllerProvider);
    final note = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '登录',
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          AlistenSpacing.lg,
          AlistenSpacing.page,
          MediaQuery.paddingOf(context).bottom + AlistenSpacing.xl,
        ),
        children: [
          if (inRoom) ...[
            Text('登录后会重新进入当前房间；有密码的房间需要再输入一次房间密码。', style: note),
            const SizedBox(height: AlistenSpacing.md),
          ],
          GlassPanel(
            child: CredentialsForm(
              submitLabel: '登录',
              newAccount: false,
              enabled: github == null,
              onSubmit: _login,
              onDone: _loggedIn,
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          Text('忘记密码需联系管理员。', style: note),
          const SizedBox(height: AlistenSpacing.xl),
          const _OtherWaysDivider(),
          const SizedBox(height: AlistenSpacing.md),
          if (site.githubLogin) ...[
            PillButton(
              label: '用 GitHub 登录',
              style: PillButtonStyle.secondary,
              expand: true,
              busy: github == GithubIntent.login,
              onPressed: github == null && !_loggingIn
                  ? () => unawaited(_signInWithGithub())
                  : null,
            ),
            const SizedBox(height: AlistenSpacing.sm),
          ],
          PillButton(
            label: '输入配对码',
            style: PillButtonStyle.secondary,
            expand: true,
            onPressed: widget.onOpenPairing,
          ),
          if (site.registrationOpen) ...[
            const SizedBox(height: AlistenSpacing.xl),
            PillButton(
              label: '注册账号',
              style: PillButtonStyle.ghost,
              onPressed: widget.onOpenRegister,
            ),
          ],
        ],
      ),
    );
  }
}

class _OtherWaysDivider extends StatelessWidget {
  const _OtherWaysDivider();

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final line = Expanded(
      child: SizedBox(
        height: AlistenSizes.hairline,
        child: ColoredBox(color: colors.glassStroke),
      ),
    );
    // 限制文字宽度：大字号时文字换行，两侧的线不会被挤没。
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          line,
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.7),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlistenSpacing.sm,
              ),
              child: Text(
                '其他登录方式',
                textAlign: TextAlign.center,
                style: AlistenTypography.secondary.copyWith(
                  color: colors.onGlassMuted,
                ),
              ),
            ),
          ),
          line,
        ],
      ),
    );
  }
}
