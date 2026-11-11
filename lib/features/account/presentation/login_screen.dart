import 'dart:async';

import 'package:alisten/domain/server/site_capabilities.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/application/site_capabilities.dart';
import 'package:alisten/features/account/presentation/credentials_form.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({
    required this.onDone,
    required this.onOpenRegister,
    super.key,
  });

  final VoidCallback onDone;
  final VoidCallback onOpenRegister;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AlistenColors.of(context);
    final inRoom = ref.watch(
      roomControllerProvider.select((room) => room.activeRoomId != null),
    );
    final site =
        ref.watch(siteCapabilitiesProvider).value ?? SiteCapabilities.unknown;
    final note = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return AlistenScaffold(
      background: const PageGlow(),
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: Icons.arrow_back_rounded,
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
              onSubmit: (username, password) => ref
                  .read(accountControllerProvider)
                  .login(username: username, password: password),
              onDone: onDone,
            ),
          ),
          const SizedBox(height: AlistenSpacing.md),
          Text('忘记密码需联系管理员。', style: note),
          if (site.registrationOpen) ...[
            const SizedBox(height: AlistenSpacing.md),
            PillButton(
              label: '注册账号',
              style: PillButtonStyle.ghost,
              onPressed: onOpenRegister,
            ),
          ],
        ],
      ),
    );
  }
}
