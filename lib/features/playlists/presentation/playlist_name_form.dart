import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/presentation/playlist_states.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const playlistNameMaxLength = 50;

/// 新建、重命名、复制分享歌单和保存为我的歌单共用。名字的其他规则以服务端为准，
/// 这里只要求去掉首尾空白之后不为空。请求期间不能关闭；失败时错误留在字段下方，
/// 用户可以改了再试。
class PlaylistNameForm<T> extends StatefulWidget {
  const PlaylistNameForm({
    required this.title,
    required this.confirmLabel,
    required this.busyLabel,
    required this.onSubmit,
    required this.onSucceeded,
    this.initialName = '',
    this.confirmIcon = AlistenIcons.checkBold,
    this.onCancel,
    super.key,
  });

  final String title;
  final String initialName;
  final String confirmLabel;
  final String busyLabel;
  final IconData confirmIcon;
  final Future<MutationResult<T>> Function(String name) onSubmit;
  final ValueChanged<T> onSucceeded;

  /// 为 null 时没有“取消”。
  final VoidCallback? onCancel;

  @override
  State<PlaylistNameForm<T>> createState() => _PlaylistNameFormState<T>();
}

class _PlaylistNameFormState<T> extends State<PlaylistNameForm<T>> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  )..addListener(_changed);
  bool _submitting = false;
  ({String text, StatusTone tone})? _problem;

  bool get _ready => !_submitting && _name.text.trim().isNotEmpty;

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _submitting = true;
      _problem = null;
    });
    final result = await widget.onSubmit(_name.text);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _problem = switch (result) {
        MutationSucceeded() => null,
        MutationFailed(:final message) || MutationNotSent(:final message) => (
          text: message,
          tone: StatusTone.danger,
        ),
        MutationUnknown() => (
          text: unknownResultText,
          tone: StatusTone.warning,
        ),
      };
    });
    if (result case MutationSucceeded(:final value)) widget.onSucceeded(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final problem = _problem;
    final cancel = widget.onCancel;
    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              widget.title,
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          AlistenTextField(
            controller: _name,
            label: '歌单名',
            maxLength: playlistNameMaxLength,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submit()),
          ),
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            InlineMessage(text: problem.text, tone: problem.tone),
          ],
          const SizedBox(height: AlistenSpacing.xl),
          PillButton(
            label: _submitting ? widget.busyLabel : widget.confirmLabel,
            icon: widget.confirmIcon,
            large: true,
            expand: true,
            busy: _submitting,
            onPressed: _ready ? () => unawaited(_submit()) : null,
          ),
          if (cancel != null) ...[
            const SizedBox(height: AlistenSpacing.xs),
            PillButton(
              label: '取消',
              style: PillButtonStyle.ghost,
              expand: true,
              onPressed: _submitting ? null : cancel,
            ),
          ],
        ],
      ),
    );
  }
}

/// 成功时以结果关闭，取消或关掉时返回 null。[guestMessage] 不为 null 时，确认不是
/// 账号之后显示它和“去账号设置”，不显示表单。
Future<T?> showPlaylistNameSheet<T>(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required String busyLabel,
  required Future<MutationResult<T>> Function(String name) onSubmit,
  String initialName = '',
  IconData confirmIcon = AlistenIcons.checkBold,
  bool cancellable = true,
  String? guestMessage,
  VoidCallback? onOpenAccount,
}) {
  return showSheetPanel<T>(
    context,
    builder: (_) => PlaylistNameSheet<T>(
      title: title,
      confirmLabel: confirmLabel,
      busyLabel: busyLabel,
      onSubmit: onSubmit,
      initialName: initialName,
      confirmIcon: confirmIcon,
      cancellable: cancellable,
      guestMessage: guestMessage,
      onOpenAccount: onOpenAccount,
    ),
  );
}

class PlaylistNameSheet<T> extends ConsumerWidget {
  const PlaylistNameSheet({
    required this.title,
    required this.confirmLabel,
    required this.busyLabel,
    required this.onSubmit,
    this.initialName = '',
    this.confirmIcon = AlistenIcons.checkBold,
    this.cancellable = true,
    this.guestMessage,
    this.onOpenAccount,
    super.key,
  });

  final String title;
  final String confirmLabel;
  final String busyLabel;
  final Future<MutationResult<T>> Function(String name) onSubmit;
  final String initialName;
  final IconData confirmIcon;
  final bool cancellable;
  final String? guestMessage;
  final VoidCallback? onOpenAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    dismissOnOwnerChange(ref, context);
    // 面板在根导航器上，可能比打开它的页面活得久；onSubmit 要用列表控制器，
    // 所以无论是否显示游客提示都要监听，让它存活。
    final guest = ref.watch(
      myPlaylistsControllerProvider.select((list) => list.guest),
    );
    final message = guestMessage;
    if (message != null && guest) {
      return PlaylistGuestPrompt(
        message: message,
        onOpenAccount: () {
          dismissSheet(context);
          onOpenAccount?.call();
        },
      );
    }
    return PlaylistNameForm<T>(
      title: title,
      initialName: initialName,
      confirmLabel: confirmLabel,
      busyLabel: busyLabel,
      confirmIcon: confirmIcon,
      onSubmit: onSubmit,
      onSucceeded: (value) => dismissSheet(context, value),
      onCancel: cancellable ? () => dismissSheet(context) : null,
    );
  }
}
