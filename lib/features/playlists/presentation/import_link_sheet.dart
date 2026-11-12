import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/playlists/application/my_playlists_controller.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:alisten/features/playlists/presentation/playlist_name_form.dart';
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

const _defaultImportName = '导入的歌单';

/// 成功时返回导入的歌单。不读剪贴板预填链接：读剪贴板可能触发系统提示，点歌页
/// 也有它自己的剪贴板逻辑。
Future<ImportedPlaylist?> showImportLinkSheet(
  BuildContext context, {
  required Future<MutationResult<ImportedPlaylist>> Function(
    String link,
    String name,
  )
  onSubmit,
}) {
  return showSheetPanel<ImportedPlaylist>(
    context,
    builder: (_) => ImportLinkSheet(onSubmit: onSubmit),
  );
}

class ImportLinkSheet extends ConsumerStatefulWidget {
  const ImportLinkSheet({required this.onSubmit, super.key});

  final Future<MutationResult<ImportedPlaylist>> Function(
    String link,
    String name,
  )
  onSubmit;

  @override
  ConsumerState<ImportLinkSheet> createState() => _ImportLinkSheetState();
}

class _ImportLinkSheetState extends ConsumerState<ImportLinkSheet> {
  late final TextEditingController _link = TextEditingController()
    ..addListener(_changed);
  late final TextEditingController _name = TextEditingController(
    text: _defaultImportName,
  )..addListener(_changed);
  bool _submitting = false;
  ({String text, StatusTone tone})? _problem;

  bool get _ready =>
      !_submitting &&
      _link.text.trim().isNotEmpty &&
      _name.text.trim().isNotEmpty;

  void _changed() => setState(() {});

  @override
  void dispose() {
    _link.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_ready) return;
    setState(() {
      _submitting = true;
      _problem = null;
    });
    final result = await widget.onSubmit(_link.text, _name.text);
    if (!mounted) return;
    final ({String text, StatusTone tone}) problem;
    switch (result) {
      case MutationSucceeded(:final value):
        dismissSheet(context, value);
        return;
      case MutationFailed(:final message) || MutationNotSent(:final message):
        problem = (text: message, tone: StatusTone.danger);
      case MutationUnknown():
        problem = (text: unknownResultText, tone: StatusTone.warning);
    }
    setState(() {
      _submitting = false;
      _problem = problem;
    });
  }

  @override
  Widget build(BuildContext context) {
    dismissOnOwnerChange(ref, context);
    // 面板在根导航器上，可能比打开它的页面活得久；onSubmit 要用列表控制器，
    // 所以面板自己让它存活。
    ref.watch(myPlaylistsControllerProvider.select((list) => list.guest));
    final colors = AlistenColors.of(context);
    final problem = _problem;
    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '从链接导入',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          AlistenTextField(
            controller: _link,
            label: '歌单链接',
            hint: '粘贴网易云或 QQ 音乐的歌单链接',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AlistenSpacing.md),
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
            label: _submitting ? '正在导入…' : '导入',
            icon: AlistenIcons.downloadSimple,
            large: true,
            expand: true,
            busy: _submitting,
            onPressed: _ready ? () => unawaited(_submit()) : null,
          ),
          const SizedBox(height: AlistenSpacing.xs),
          PillButton(
            label: '取消',
            style: PillButtonStyle.ghost,
            expand: true,
            onPressed: _submitting ? null : () => dismissSheet(context),
          ),
        ],
      ),
    );
  }
}
