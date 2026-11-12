import 'dart:async';

import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/application/add_server_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 点“添加并切换”时返回检测通过但尚未保存的服务器，其他方式关闭返回 null。
Future<ServerProfile?> showAddServerSheet(BuildContext context) {
  return showSheetPanel<ServerProfile>(
    context,
    builder: (_) => const _AddServerSheet(),
  );
}

class _AddServerSheet extends ConsumerStatefulWidget {
  const _AddServerSheet();

  @override
  ConsumerState<_AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends ConsumerState<_AddServerSheet> {
  final _address = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  bool get _typed => _address.text.trim().isNotEmpty;

  void _check() {
    if (!_typed) return;
    unawaited(
      ref.read(addServerControllerProvider.notifier).check(_address.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final state = ref.watch(addServerControllerProvider);
    final found = state.found;
    final problem = state.problem;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '添加服务器',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.lg),
        // 不自动聚焦：键盘与面板同时滑入会让入场动画明显掉帧。
        AlistenTextField(
          controller: _address,
          label: '服务器地址',
          hint: 'https://example.com',
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          onChanged: (_) {
            ref.read(addServerControllerProvider.notifier).edited();
            setState(() {});
          },
          onSubmitted: (_) => _check(),
        ),
        if (problem != null) ...[
          const SizedBox(height: AlistenSpacing.md),
          InlineMessage(text: problem),
        ],
        if (found != null) ...[
          const SizedBox(height: AlistenSpacing.md),
          _FoundServer(server: found),
        ],
        const SizedBox(height: AlistenSpacing.xl),
        if (found == null)
          PillButton(
            label: '检测',
            icon: AlistenIcons.globe,
            large: true,
            expand: true,
            busy: state.checking,
            onPressed: _typed ? _check : null,
          )
        else
          PillButton(
            label: '添加并切换',
            icon: AlistenIcons.arrowsLeftRight,
            large: true,
            expand: true,
            onPressed: () => Navigator.of(context).pop(found),
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

class _FoundServer extends StatelessWidget {
  const _FoundServer({required this.server});

  final ServerProfile server;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: AlistenTint.fill),
        borderRadius: BorderRadius.circular(AlistenRadii.sm),
        border: Border.all(
          color: colors.success.withValues(alpha: AlistenTint.stroke),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AlistenSpacing.sm),
        child: Semantics(
          container: true,
          liveRegion: true,
          child: Row(
            children: [
              Icon(
                AlistenIcons.checkCircleFill,
                size: AlistenSizes.iconSm,
                color: colors.success,
              ),
              const SizedBox(width: AlistenSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AlistenTypography.bodyStrong.copyWith(
                        color: colors.onGlass,
                      ),
                    ),
                    Text(
                      server.authority,
                      style: AlistenTypography.secondary.copyWith(
                        color: colors.onGlassMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
