import 'dart:async';

import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/application/pairing_code_controller.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showPairingCodeSheet(
  BuildContext context, {
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => PairingCodeSheet(onNotice: onNotice),
  );
}

class PairingCodeSheet extends ConsumerStatefulWidget {
  const PairingCodeSheet({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<PairingCodeSheet> createState() => _PairingCodeSheetState();
}

class _PairingCodeSheetState extends ConsumerState<PairingCodeSheet> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _generate();
      }),
    );
  }

  Future<void> _generate() async {
    final onNotice = widget.onNotice;
    final reason = await ref
        .read(pairingCodeControllerProvider.notifier)
        .generate();
    if (reason != null) onNotice(ToastKind.failure, reason);
  }

  @override
  Widget build(BuildContext context) {
    // 配对码属于生成它的服务器上的会话，换了服务器或会话它就已作废。
    ref.listen(
      identityControllerProvider.select(
        (identity) => (identity.session, identity.member?.id),
      ),
      (_, _) => dismissSheet(context),
    );
    final colors = AlistenColors.of(context);
    final pairing = ref.watch(pairingCodeControllerProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '在新设备上登录',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.md),
        ...switch (pairing) {
          PairingCodeLoading() => const <Widget>[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatusPill(
                label: '正在生成配对码…',
                icon: AlistenIcons.arrowsClockwise,
                busy: true,
              ),
            ),
          ],
          PairingCodeReady(:final code, :final secondsLeft) => _ready(
            code,
            secondsLeft,
          ),
          PairingCodeExpired() => _again('配对码已经失效。', StatusTone.warning),
          PairingCodeFailed() => _again('暂时无法生成配对码。', StatusTone.danger),
        },
      ],
    );
  }

  List<Widget> _ready(PairingCode code, int secondsLeft) {
    final colors = AlistenColors.of(context);
    final note = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    final qr = code.qrPng;
    return [
      if (qr != null) ...[
        Center(
          // 深色模式下也是白底，相机才能识别。
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AlistenColors.scanSurface,
              borderRadius: BorderRadius.circular(AlistenRadii.sm),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AlistenSpacing.sm),
              child: Semantics(
                container: true,
                image: true,
                label: '配对二维码',
                child: ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: AlistenSizes.qrCode,
                    child: Image.memory(
                      qr,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.none,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                            child: Icon(
                              AlistenIcons.imageBroken,
                              size: AlistenSizes.iconLg,
                              color: AlistenColors.scanInk,
                            ),
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AlistenSpacing.md),
      ],
      Semantics(
        container: true,
        label: spokenPairingCode(code.code),
        child: ExcludeSemantics(
          child: Text(
            formatPairingCode(code.code),
            textAlign: TextAlign.center,
            style: AlistenTypography.largeTitle.copyWith(color: colors.onGlass),
          ),
        ),
      ),
      const SizedBox(height: AlistenSpacing.xs),
      // 不设成 liveRegion，否则读屏每秒播报一次。
      Text(
        '${pairingCountdownText(secondsLeft)} 后失效',
        textAlign: TextAlign.center,
        style: note,
      ),
      const SizedBox(height: AlistenSpacing.md),
      Text('在新设备上扫描二维码，或者在登录页点“输入配对码”。配对码只能用一次。', style: note),
    ];
  }

  List<Widget> _again(String text, StatusTone tone) => [
    InlineMessage(text: text, tone: tone),
    const SizedBox(height: AlistenSpacing.md),
    PillButton(
      label: '重新生成',
      icon: AlistenIcons.arrowClockwise,
      expand: true,
      onPressed: () => unawaited(_generate()),
    ),
  ];
}
