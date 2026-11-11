import 'dart:math' as math;

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/features/admin/application/admin_rooms_controller.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/room_form.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _everyoneVerifiesAgainText = '房间里的所有人都需要重新验证。';
const _youDisconnectTooText = '你也会断开，需要重新输入密码。';
const _unknownText = '结果未知，请查看列表确认后再决定是否重试。';

/// [room] 为 null 时新建常驻房间。
Future<void> showRoomFormSheet(
  BuildContext context, {
  required void Function(ToastKind kind, String text) onNotice,
  RoomListing? room,
}) {
  return showSheetPanel<void>(
    context,
    builder: (_) => RoomFormSheet(room: room, onNotice: onNotice),
  );
}

enum _PasswordMode { keep, set, remove }

// 提交期间面板不能关闭：结果要在这里说明，关掉再打开容易重复创建同一个房间。
// 结果未知时关闭面板并重新读取列表，由用户看过列表再决定是否重试。
class RoomFormSheet extends ConsumerStatefulWidget {
  const RoomFormSheet({required this.onNotice, this.room, super.key});

  final RoomListing? room;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<RoomFormSheet> createState() => _RoomFormSheetState();
}

class _RoomFormSheetState extends ConsumerState<RoomFormSheet> {
  late final _name = TextEditingController(text: widget.room?.name);
  late final _description = TextEditingController(
    text: widget.room?.description,
  );
  late final _slug = TextEditingController(text: widget.room?.slug);
  final _password = TextEditingController();
  _PasswordMode _passwordMode = _PasswordMode.keep;
  bool _submitting = false;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _slug.dispose();
    _password.dispose();
    super.dispose();
  }

  PasswordChoice get _passwordChoice {
    if (widget.room == null) {
      return _password.text.isEmpty
          ? const KeepPassword()
          : SetPassword(_password.text);
    }
    return switch (_passwordMode) {
      _PasswordMode.keep => const KeepPassword(),
      _PasswordMode.set => SetPassword(_password.text),
      _PasswordMode.remove => const RemovePassword(),
    };
  }

  void _edited(String _) {
    if (_problem != null) setState(() => _problem = null);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final form = RoomForm(
      name: _name.text,
      description: _description.text,
      slug: _slug.text,
      password: _passwordChoice,
    );
    final rooms = ref.read(adminRoomsControllerProvider.notifier);
    final room = widget.room;
    setState(() {
      _submitting = true;
      _problem = null;
    });
    final MutationResult<Object?> result;
    try {
      result = room == null
          ? await rooms.create(form)
          : await rooms.update(room, form);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    // 会话已结束时面板随路由一起关闭，由 token 页说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded():
        _close(ToastKind.success, '已保存');
      case MutationUnknown():
        _close(ToastKind.warning, _unknownText);
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
    }
  }

  void _close(ToastKind kind, String text) {
    dismissSheet(context);
    widget.onNotice(kind, text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final config = ref.watch(appConfigProvider);
    final room = widget.room;
    final problem = _problem;
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    // 别名的问题已显示在别名输入框下方，不再重复显示。
    final shownProblem = problem == roomSlugProblem(_slug.text)
        ? null
        : problem;
    return PopScope(
      canPop: !_submitting,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              room == null ? '新建常驻房间' : '编辑常驻房间',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          // 不自动聚焦：键盘和面板同时滑入会让面板的入场掉帧。
          AlistenTextField(
            controller: _name,
            label: '房间名称',
            inputFormatters: const [_RoomNameLimit()],
            textInputAction: TextInputAction.next,
            onChanged: _edited,
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _description,
            label: '简介',
            maxLength: 500,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            onChanged: _edited,
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _slug,
            label: '别名（可选）',
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            onChanged: _edited,
          ),
          const SizedBox(height: AlistenSpacing.xs),
          ListenableBuilder(
            listenable: _slug,
            builder: (context, _) {
              final slug = _slug.text;
              if (roomSlugProblem(slug) case final slugProblem?) {
                return InlineMessage(text: slugProblem);
              }
              return Text(
                slug.isEmpty
                    ? '不填别名时，邀请链接使用房间 ID'
                    : '邀请链接：${config.inviteLinkFor(slug)}',
                style: muted,
              );
            },
          ),
          const SizedBox(height: AlistenSpacing.md),
          if (room == null)
            AlistenTextField(
              controller: _password,
              label: '密码（可选）',
              obscureText: true,
              textInputAction: TextInputAction.done,
              onChanged: _edited,
            )
          else
            ..._passwordChange(room, muted),
          if (shownProblem != null) ...[
            const SizedBox(height: AlistenSpacing.md),
            InlineMessage(text: shownProblem),
          ],
          const SizedBox(height: AlistenSpacing.xl),
          PillButton(
            label: '保存',
            icon: Icons.check_rounded,
            large: true,
            expand: true,
            busy: _submitting,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  List<Widget> _passwordChange(RoomListing room, TextStyle muted) {
    final here =
        ref.watch(
          roomControllerProvider.select((state) => state.activeRoomId),
        ) ==
        room.id;
    return [
      Padding(
        padding: const EdgeInsetsDirectional.only(
          start: AlistenSpacing.xxs,
          bottom: AlistenSpacing.xs,
        ),
        child: ExcludeSemantics(
          child: Text(
            '密码',
            style: AlistenTypography.weighted(
              AlistenTypography.secondary,
              FontWeight.w600,
            ).copyWith(color: muted.color),
          ),
        ),
      ),
      Semantics(
        container: true,
        label: '密码',
        child: SegmentedPills<_PasswordMode>(
          segments: [
            const PillSegment(value: _PasswordMode.keep, label: '保持'),
            const PillSegment(value: _PasswordMode.set, label: '设置或修改'),
            if (room.hasPassword)
              const PillSegment(value: _PasswordMode.remove, label: '取消'),
          ],
          selected: _passwordMode,
          onChanged: _submitting
              ? null
              : (mode) => setState(() {
                  _passwordMode = mode;
                  _problem = null;
                }),
        ),
      ),
      if (_passwordMode == _PasswordMode.set) ...[
        const SizedBox(height: AlistenSpacing.md),
        AlistenTextField(
          controller: _password,
          label: '新密码',
          obscureText: true,
          textInputAction: TextInputAction.done,
          onChanged: _edited,
        ),
        const SizedBox(height: AlistenSpacing.sm),
        InlineMessage(
          tone: StatusTone.warning,
          text: here
              ? '$_everyoneVerifiesAgainText$_youDisconnectTooText'
              : _everyoneVerifiesAgainText,
        ),
      ],
    ];
  }
}

// 按 [roomNameLength] 限长，其余行为与 `LengthLimitingTextInputFormatter`
// 一致：已满时不再接受输入，超出时从末尾按字截短，组字期间是否截短按平台默认。
final class _RoomNameLimit extends TextInputFormatter {
  const _RoomNameLimit();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (roomNameLength(newValue.text) <= roomNameMaxLength) return newValue;
    final full = roomNameLength(oldValue.text) == roomNameMaxLength;
    switch (LengthLimitingTextInputFormatter.getDefaultMaxLengthEnforcement()) {
      case MaxLengthEnforcement.none:
        return newValue;
      case MaxLengthEnforcement.enforced:
        if (full && oldValue.selection.isCollapsed) return oldValue;
      case MaxLengthEnforcement.truncateAfterCompositionEnds:
        if (full && !oldValue.composing.isValid) return oldValue;
        if (newValue.composing.isValid) return newValue;
    }
    final kept = _fittingPrefix(newValue.text).length;
    final selection = newValue.selection;
    final composing = newValue.composing;
    return TextEditingValue(
      text: newValue.text.substring(0, kept),
      selection: selection.copyWith(
        baseOffset: math.min(selection.start, kept),
        extentOffset: math.min(selection.end, kept),
      ),
      composing: !composing.isCollapsed && kept > composing.start
          ? TextRange(
              start: composing.start,
              end: math.min(composing.end, kept),
            )
          : TextRange.empty,
    );
  }

  // 前缀越长，去掉首尾空白后的码点数只增不减，所以可以二分。
  static String _fittingPrefix(String text) {
    final characters = text.characters;
    var low = 0;
    var high = characters.length;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (roomNameLength(characters.take(middle).string) <= roomNameMaxLength) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return characters.take(low).string;
  }
}
