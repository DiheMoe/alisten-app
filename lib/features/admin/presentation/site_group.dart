import 'dart:async';

import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/application/admin_site_controller.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
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
  bool _saving = false;
  String? _problem;

  AdminSiteController get _site =>
      ref.read(adminSiteControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() async {
        if (mounted) await _site.load();
      }),
    );
  }

  @override
  void dispose() {
    _brandName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _problem = null;
    });
    final MutationResult<String> result;
    try {
      result = await _site.save(_brandName.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    // 会话已结束时本页会换成 token 页，由那里说明原因。
    if (!mounted || !ref.read(adminSessionProvider).active) return;
    switch (result) {
      case MutationSucceeded(:final value):
        _brandName.text = value;
        widget.onNotice(ToastKind.success, '品牌名已保存');
      case MutationFailed(:final message) || MutationNotSent(:final message):
        setState(() => _problem = message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '结果未知，请确认品牌名后再决定是否重试。');
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
    final site = ref.watch(adminSiteControllerProvider);
    final loadError = site.error;
    final problem = _problem;
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlistenTextField(
            controller: _brandName,
            label: '品牌名',
            textInputAction: TextInputAction.done,
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
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
          const SizedBox(height: AlistenSpacing.md),
          PillButton(
            label: '保存',
            icon: Icons.check_rounded,
            expand: true,
            busy: _saving,
            onPressed: site.loading ? null : () => unawaited(_save()),
          ),
        ],
      ),
    );
  }
}
