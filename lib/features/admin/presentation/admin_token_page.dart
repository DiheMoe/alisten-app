import 'dart:async';

import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/admin_sign_in_controller.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminTokenPage extends ConsumerStatefulWidget {
  const AdminTokenPage({super.key});

  @override
  ConsumerState<AdminTokenPage> createState() => _AdminTokenPageState();
}

class _AdminTokenPageState extends ConsumerState<AdminTokenPage> {
  final _token = TextEditingController();

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final entered = await ref
        .read(adminSignInControllerProvider.notifier)
        .submit(_token.text);
    if (entered && mounted) _token.clear();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final signIn = ref.watch(adminSignInControllerProvider);
    final notice = ref.watch(
      adminSessionProvider.select((session) => session.notice),
    );
    final server = ref.watch(currentServerProvider);
    final cooling = signIn.cooldownSeconds > 0;
    final error = signIn.error;
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '站点管理',
        subtitle: server.authority,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          AlistenSpacing.lg,
          AlistenSpacing.page,
          MediaQuery.paddingOf(context).bottom + AlistenSpacing.xl,
        ),
        children: [
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '管理 token 只保存在内存中，退出后台后需要重新输入。',
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
                const SizedBox(height: AlistenSpacing.md),
                AlistenTextField(
                  controller: _token,
                  label: '管理 token',
                  obscureText: true,
                  sensitive: true,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => unawaited(_submit()),
                ),
                if (notice != null) ...[
                  const SizedBox(height: AlistenSpacing.sm),
                  InlineMessage(text: notice, tone: StatusTone.warning),
                ],
                if (error != null) ...[
                  const SizedBox(height: AlistenSpacing.sm),
                  InlineMessage(text: error),
                ],
                const SizedBox(height: AlistenSpacing.lg),
                PillButton(
                  label: cooling ? '请等待 ${signIn.cooldownSeconds} 秒' : '进入后台',
                  icon: cooling
                      ? AlistenIcons.hourglassHigh
                      : AlistenIcons.signIn,
                  expand: true,
                  busy: signIn.busy,
                  onPressed: cooling ? null : () => unawaited(_submit()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
