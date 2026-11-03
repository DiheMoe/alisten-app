import 'dart:async';

import 'package:alisten/features/update/application/update_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _cannotOpen = '没能打开链接，请稍后再试。';

// 长说明在不超过这一比例的屏幕高度内单独滚动，不把按钮挤出屏幕。
const _notesShare = 0.4;

/// [onNotice] 必须比面板存活更久。
Future<void> showUpdateSheet(
  BuildContext context,
  UpdateAvailable update, {
  required void Function(ToastKind kind, String text) onNotice,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => UpdateSheet(update: update, onNotice: onNotice),
  );
}

class UpdateSheet extends ConsumerStatefulWidget {
  const UpdateSheet({required this.update, required this.onNotice, super.key});

  final UpdateAvailable update;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends ConsumerState<UpdateSheet> {
  final _notes = ScrollController();
  bool _opening = false;

  UpdateController get _controller =>
      ref.read(updateControllerProvider.notifier);

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _opening = true);
    final opened = await _controller.open(widget.update.release);
    if (!opened) widget.onNotice(ToastKind.failure, _cannotOpen);
    if (!mounted) return;
    if (opened) {
      _close();
    } else {
      setState(() => _opening = false);
    }
  }

  Future<void> _skip() async {
    await _controller.skip(widget.update);
    _close();
  }

  // 等待期间面板可能已被关闭：收起动画结束前组件仍挂载，但栈顶已是下方页面，
  // 此时 pop 会把那个页面弹掉。
  void _close() {
    if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final installed = ref.watch(installedVersionProvider);
    final notes = widget.update.release.notes;
    final android = defaultTargetPlatform == TargetPlatform.android;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '发现新版本 ${widget.update.version}',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        const SizedBox(height: AlistenSpacing.xxs),
        Text(
          '当前版本 $installed',
          style: AlistenTypography.secondary.copyWith(
            color: colors.onGlassMuted,
          ),
        ),
        if (notes.trim().isNotEmpty) ...[
          const SizedBox(height: AlistenSpacing.md),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * _notesShare,
            ),
            child: Scrollbar(
              controller: _notes,
              child: SingleChildScrollView(
                controller: _notes,
                child: Text(
                  notes,
                  style: AlistenTypography.body.copyWith(color: colors.onGlass),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: AlistenSpacing.xl),
        PillButton(
          label: android ? '下载更新' : '前往发布页',
          icon: android ? Icons.download_rounded : Icons.open_in_new_rounded,
          busy: _opening,
          large: true,
          expand: true,
          onPressed: () => unawaited(_open()),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        // 打开链接期间不能关闭面板，否则打不开时的提示会在面板关闭之后才出现。
        PillButton(
          label: '稍后',
          style: PillButtonStyle.secondary,
          expand: true,
          onPressed: _opening ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: AlistenSpacing.xs),
        PillButton(
          label: '跳过这个版本',
          style: PillButtonStyle.ghost,
          expand: true,
          onPressed: _opening ? null : () => unawaited(_skip()),
        ),
      ],
    );
  }
}
