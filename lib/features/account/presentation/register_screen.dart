import 'dart:async';

import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/account/presentation/credentials_form.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RegisterScreen extends ConsumerWidget {
  const RegisterScreen({required this.onDone, super.key});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '注册账号',
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
            child: CredentialsForm(
              submitLabel: '注册',
              newAccount: true,
              onSubmit: (username, password) => ref
                  .read(accountControllerProvider)
                  .register(username: username, password: password),
              onDone: onDone,
            ),
          ),
        ],
      ),
    );
  }
}
