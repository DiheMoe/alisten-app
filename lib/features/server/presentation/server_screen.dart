import 'dart:async';

import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/application/server_directory.dart';
import 'package:alisten/features/server/presentation/add_server_sheet.dart';
import 'package:alisten/features/server/presentation/switch_server_flow.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/confirm_sheet.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({
    required this.onSwitched,
    required this.onNotice,
    super.key,
  });

  final VoidCallback onSwitched;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  // 切换或删除进行中不接受新操作，以免叠出两个面板或删掉正要切换的服务器。
  bool _busy = false;

  // 确认面板关闭后才标出进行中的行：面板盖住页面时转圈只会白白耗电。
  ({String id, String label})? _working;

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(serverDirectoryProvider.notifier).refreshBrands());
  }

  Future<void> _switch(ServerProfile server) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final switched = await switchServerFlow(
        context,
        ref,
        server,
        onNotice: widget.onNotice,
        onSwitching: () {
          if (mounted) setState(() => _working = (id: server.id, label: '切换中'));
        },
      );
      if (switched && mounted) widget.onSwitched();
    } finally {
      if (mounted) _idle();
    }
  }

  void _idle() {
    setState(() {
      _busy = false;
      _working = null;
    });
  }

  Future<void> _add() async {
    if (_busy) return;
    final found = await showAddServerSheet(context);
    if (found != null && mounted) await _switch(found);
  }

  Future<void> _remove(ServerProfile server) async {
    if (_busy) return;
    final name = server.displayName;
    final confirmed = await showConfirmSheet(
      context,
      title: '删除 $name？',
      message: '会删除这台设备在这个服务器上的身份和房间票据。',
      confirmLabel: '删除',
      confirmIcon: AlistenIcons.trash,
    );
    if (!confirmed || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _working = (id: server.id, label: '删除中');
    });
    try {
      await ref.read(serverDirectoryProvider.notifier).remove(server.id);
    } on Object {
      widget.onNotice(ToastKind.failure, '没能删除 $name，请重试。');
    } finally {
      if (mounted) _idle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final directory = ref.watch(serverDirectoryProvider);
    final working = _working;
    return AlistenScaffold(
      background: const PageGlow(),
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '服务器',
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
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, server) in directory.profiles.indexed) ...[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AlistenSpacing.md,
                      ),
                      child: SizedBox(
                        height: AlistenSizes.hairline,
                        child: ColoredBox(color: colors.glassStroke),
                      ),
                    ),
                  _ServerRow(
                    server: server,
                    current: server.id == directory.currentId,
                    builtIn: directory.isDefault(server),
                    workingLabel: working?.id == server.id
                        ? working?.label
                        : null,
                    onSwitch: working == null
                        ? () => unawaited(_switch(server))
                        : null,
                    onDelete: working == null
                        ? () => unawaited(_remove(server))
                        : null,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          PillButton(
            label: '添加服务器',
            icon: AlistenIcons.plusBold,
            expand: true,
            onPressed: working == null ? () => unawaited(_add()) : null,
          ),
        ],
      ),
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.server,
    required this.current,
    required this.builtIn,
    required this.workingLabel,
    required this.onSwitch,
    required this.onDelete,
  });

  final ServerProfile server;
  final bool current;
  final bool builtIn;
  final String? workingLabel;
  final VoidCallback? onSwitch;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final name = server.displayName;
    final deletable = !current && !builtIn;
    final details = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AlistenSizes.largeTouchTarget,
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AlistenSpacing.md,
          AlistenSpacing.sm,
          deletable ? AlistenSpacing.xxs : AlistenSpacing.md,
          AlistenSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.bodyStrong.copyWith(
                      color: colors.onGlass,
                    ),
                  ),
                  const SizedBox(height: AlistenSpacing.xxs / 2),
                  Text(
                    server.authority,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AlistenTypography.secondary.copyWith(
                      color: colors.onGlassMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (builtIn) ...[
              const SizedBox(width: AlistenSpacing.xs),
              const StatusPill(label: '内置', icon: AlistenIcons.sealCheckFill),
            ],
            if (current) ...[
              const SizedBox(width: AlistenSpacing.xs),
              const StatusPill(
                label: '当前',
                icon: AlistenIcons.checkCircleFill,
                tone: StatusTone.success,
              ),
            ],
            if (workingLabel case final label?) ...[
              const SizedBox(width: AlistenSpacing.xs),
              StatusPill(
                label: label,
                icon: AlistenIcons.arrowsClockwise,
                busy: true,
              ),
            ],
          ],
        ),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: current
              ? MergeSemantics(child: details)
              : Pressable(
                  onPressed: onSwitch,
                  dimWhenDisabled: workingLabel == null,
                  child: details,
                ),
        ),
        if (deletable)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: AlistenSpacing.xs),
            child: IconCircleButton(
              icon: AlistenIcons.trash,
              semanticLabel: '删除 $name',
              style: IconCircleButtonStyle.plain,
              diameter: AlistenSizes.rowAction,
              iconSize: AlistenSizes.iconSm,
              onPressed: onDelete,
            ),
          ),
      ],
    );
  }
}
