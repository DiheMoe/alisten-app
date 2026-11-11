import 'dart:async';

import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/application/account_controller.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [fragment] 是链接里未经检查的原文：只有规范化后合法、且 [serverId] 是当前
/// 服务器时，页面才会填入。
typedef PairPrefill = ({String serverId, String fragment});

final _uppercase = TextInputFormatter.withFunction(
  (_, next) => next.copyWith(text: next.text.toUpperCase()),
);

class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({required this.prefill, required this.onDone, super.key});

  final PairPrefill? prefill;
  final VoidCallback onDone;

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  // 预填只在它所属的服务器上有效：在有效的几分钟里它就是那个服务器的登录
  // 凭据，不能发给另一个服务器。
  String? _prefilled;
  bool _busy = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _prefilled = _prefillFor(widget.prefill);
  }

  @override
  void didUpdateWidget(PairScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.prefill != oldWidget.prefill) {
      _refill(_prefillFor(widget.prefill));
    }
  }

  // 上一个码的说明不留给新填入的码；请求还在途时等它的结果。
  void _refill(String? prefilled) {
    _prefilled = prefilled;
    if (!_busy) _problem = null;
  }

  // 换预填会重建表单，请求是否在途和它的结果要由页面记着：否则新表单能再发一次，
  // 结果也没有地方显示。
  Future<void> _redeem(String input) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    final result = await ref
        .read(accountControllerProvider)
        .redeemPairingCode(input);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _problem = switch (result) {
        MutationSucceeded() => null,
        MutationFailed(:final message) ||
        MutationNotSent(:final message) => message,
        MutationUnknown() => '没有确认结果，请稍后再试。',
      };
    });
    if (result case MutationSucceeded()) widget.onDone();
  }

  String? _prefillFor(PairPrefill? prefill) {
    if (prefill == null ||
        prefill.serverId != ref.read(currentServerProvider).id) {
      return null;
    }
    final code = normalizePairingCode(prefill.fragment);
    return isPairingCode(code) ? code : null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentServerProvider.select((server) => server.id), (_, id) {
      if (_prefilled != null && id != widget.prefill?.serverId) {
        setState(() => _refill(null));
      }
    });
    final colors = AlistenColors.of(context);
    final signedIn = ref.watch(
      identityControllerProvider.select((identity) => identity.account != null),
    );
    final inRoom = ref.watch(
      roomControllerProvider.select((room) => room.activeRoomId != null),
    );
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
        title: '用配对码登录',
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          AlistenSpacing.lg,
          AlistenSpacing.page,
          MediaQuery.paddingOf(context).bottom + AlistenSpacing.xl,
        ),
        children: [
          if (signedIn)
            Text('这台设备已经登录了账号。要换成其他账号，先在设置里退出登录。', style: note)
          else ...[
            if (inRoom) ...[
              Text('登录后会重新进入当前房间；有密码的房间需要再输入一次房间密码。', style: note),
              const SizedBox(height: AlistenSpacing.md),
            ],
            GlassPanel(
              child: _PairForm(
                key: ValueKey(_prefilled),
                initial: _prefilled,
                busy: _busy,
                problem: _problem,
                onSubmit: (input) => unawaited(_redeem(input)),
              ),
            ),
            const SizedBox(height: AlistenSpacing.md),
            Text(
              '在已登录的设备上打开设置，点“在新设备上登录”就能看到配对码。'
              '只输入你自己生成的配对码：登录之后，这台设备上的操作都属于那个账号。',
              style: note,
            ),
          ],
        ],
      ),
    );
  }
}

class _PairForm extends StatefulWidget {
  const _PairForm({
    required this.initial,
    required this.busy,
    required this.problem,
    required this.onSubmit,
    super.key,
  });

  final String? initial;
  final bool busy;
  final String? problem;
  final ValueChanged<String> onSubmit;

  @override
  State<_PairForm> createState() => _PairFormState();
}

class _PairFormState extends State<_PairForm> {
  late final _code = TextEditingController(
    text: switch (widget.initial) {
      final code? => formatPairingCode(code),
      null => '',
    },
  );

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() => widget.onSubmit(_code.text);

  @override
  Widget build(BuildContext context) {
    final problem = widget.problem;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlistenTextField(
          controller: _code,
          label: '配对码',
          maxLength: 16,
          inputFormatters: [_uppercase],
          sensitive: true,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        if (problem != null) ...[
          const SizedBox(height: AlistenSpacing.sm),
          InlineMessage(text: problem),
        ],
        const SizedBox(height: AlistenSpacing.lg),
        PillButton(
          label: '登录',
          icon: Icons.check_rounded,
          expand: true,
          busy: widget.busy,
          onPressed: widget.busy ? null : _submit,
        ),
      ],
    );
  }
}
