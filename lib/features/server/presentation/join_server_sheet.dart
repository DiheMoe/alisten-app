import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';

final class JoinProfile {
  const JoinProfile({required this.nickname, required this.email});

  final String nickname;
  final String email;
}

Future<JoinProfile?> showJoinServerSheet(
  BuildContext context, {
  required String brandName,
  required String nickname,
  required String email,
}) {
  return showSheetPanel<JoinProfile>(
    context,
    builder: (_) => _JoinServerSheet(
      brandName: brandName,
      nickname: nickname,
      email: email,
    ),
  );
}

class _JoinServerSheet extends StatefulWidget {
  const _JoinServerSheet({
    required this.brandName,
    required this.nickname,
    required this.email,
  });

  final String brandName;
  final String nickname;
  final String email;

  @override
  State<_JoinServerSheet> createState() => _JoinServerSheetState();
}

class _JoinServerSheetState extends State<_JoinServerSheet> {
  late final _nickname = TextEditingController(text: widget.nickname);
  late final _email = TextEditingController(text: widget.email);

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    super.dispose();
  }

  void _join() {
    Navigator.of(context)
        .pop(JoinProfile(nickname: _nickname.text, email: _email.text));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '加入 ${widget.brandName}',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        Text(
          '将以下面的昵称和邮箱加入，之后可以在设置里修改。邮箱只用来显示 Gravatar 头像。',
          style: AlistenTypography.body.copyWith(color: colors.onGlassMuted),
        ),
        const SizedBox(height: AlistenSpacing.lg),
        AlistenTextField(
          controller: _nickname,
          label: '昵称',
          maxLength: 80,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: AlistenSpacing.md),
        AlistenTextField(
          controller: _email,
          label: '邮箱',
          maxLength: 320,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _join(),
        ),
        const SizedBox(height: AlistenSpacing.xl),
        PillButton(
          label: '加入',
          icon: Icons.login_rounded,
          large: true,
          expand: true,
          glow: true,
          onPressed: _join,
        ),
        const SizedBox(height: AlistenSpacing.xs),
        PillButton(
          label: '取消',
          style: PillButtonStyle.ghost,
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
