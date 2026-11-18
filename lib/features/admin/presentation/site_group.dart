import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/admin_site_controller.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/inline_message.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SiteGroup extends ConsumerStatefulWidget {
  const SiteGroup({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<SiteGroup> createState() => _SiteGroupState();
}

class _SiteGroupState extends ConsumerState<SiteGroup> {
  final _brandName = TextEditingController();
  final _focus = FocusNode();
  Timer? _savedTimer;
  bool _saving = false;
  bool _saved = false;
  bool _adoptReread = false;
  String? _problem;

  AdminSiteController get _site =>
      ref.read(adminSiteControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // 首页可能已经读到品牌名，此时不会再有变化通知。
    _brandName.text = ref.read(adminSiteControllerProvider).brandName ?? '';
    _focus.addListener(_onFocus);
    unawaited(
      Future.microtask(() async {
        if (mounted) await _site.load();
      }),
    );
  }

  void _onFocus() {
    if (!_focus.hasFocus) unawaited(_saveIfChanged());
  }

  @override
  void dispose() {
    _savedTimer?.cancel();
    _focus
      ..removeListener(_onFocus)
      ..dispose();
    _brandName.dispose();
    super.dispose();
  }

  Future<void> _saveIfChanged() async {
    if (_saving) return;
    final saved = ref.read(adminSiteControllerProvider).brandName ?? '';
    if (_brandName.text.trim() == saved.trim()) return;
    await _save();
  }

  Future<void> _save() async {
    _savedTimer?.cancel();
    setState(() {
      _saving = true;
      _saved = false;
      _problem = null;
      // 重新读取可能在 save 返回之前就结束，所以先立标记，结果明确时再取消。
      _adoptReread = true;
    });
    final MutationResult<String> result;
    try {
      result = await _site.save(_brandName.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    if (result is! MutationUnknown<String>) _adoptReread = false;
    switch (result) {
      case MutationSucceeded(:final value):
        _brandName.text = value;
        setState(() => _saved = true);
        _savedTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _saved = false);
        });
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '没能确认是否保存，已重新读取');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 用户改过的输入框不再跟随读到的名字，以免覆盖正在编辑的内容。
    ref.listen(adminSiteControllerProvider.select((site) => site.brandName), (
      previous,
      next,
    ) {
      if (_brandName.text == (previous ?? '')) _brandName.text = next ?? '';
    });
    // 结果未知后控制器会重新读取，读完后输入框要显示服务端当前的名字。
    ref.listen(adminSiteControllerProvider, (previous, next) {
      if (!_adoptReread || !(previous?.loading ?? false) || next.loading) {
        return;
      }
      _adoptReread = false;
      final name = next.brandName;
      if (next.error == null && name != null) _brandName.text = name;
    });
    final site = ref.watch(adminSiteControllerProvider);
    final loadError = site.error;
    final problem = _problem;
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AlistenTextField(
                  controller: _brandName,
                  label: '品牌名',
                  focusNode: _focus,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_saveIfChanged()),
                  onChanged: (_) {
                    if (_problem != null) setState(() => _problem = null);
                  },
                ),
              ),
              if (_saving) ...[
                const SizedBox(width: AlistenSpacing.sm),
                const BusyIndicator(semanticLabel: '正在保存'),
              ],
            ],
          ),
          if (loadError != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(
              text: loadError,
              action: PillButton(
                label: '重试',
                style: PillButtonStyle.ghost,
                onPressed: site.loading ? null : () => unawaited(_site.load()),
              ),
            ),
          ],
          if (problem != null) ...[
            const SizedBox(height: AlistenSpacing.sm),
            InlineMessage(text: problem),
          ],
          AnimatedSwitcher(
            duration: AlistenDurations.of(
              context,
              const Duration(milliseconds: 200),
            ),
            child: _saved
                ? Padding(
                    key: const ValueKey('saved'),
                    padding: const EdgeInsets.only(top: AlistenSpacing.sm),
                    child: Text(
                      '✓ 已保存',
                      style: AlistenTypography.secondary.copyWith(
                        color: AlistenColors.of(context).success,
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('idle')),
          ),
        ],
      ),
    );
  }
}
