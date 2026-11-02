import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/empty_state.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:flutter/material.dart';

class AsyncStateView extends StatelessWidget {
  const AsyncStateView({
    required this.loading,
    required this.errorMessage,
    required this.empty,
    required this.onRetry,
    required this.child,
    this.emptyLabel = '暂无可显示内容',
    this.emptyIcon = Icons.inbox_rounded,
    this.emptyAction,
    super.key,
  });

  final bool loading;
  final String? errorMessage;
  final bool empty;
  final VoidCallback onRetry;
  final Widget child;
  final String emptyLabel;
  final IconData emptyIcon;
  final Widget? emptyAction;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: BusyIndicator(size: AlistenSizes.iconLg, semanticLabel: '加载中'),
      );
    }
    final error = errorMessage;
    if (error != null) {
      return Semantics(
        liveRegion: true,
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: error,
          action: PillButton(
            label: '重试',
            icon: Icons.refresh_rounded,
            style: PillButtonStyle.secondary,
            onPressed: onRetry,
          ),
        ),
      );
    }
    if (empty) {
      return EmptyState(
        icon: emptyIcon,
        title: emptyLabel,
        action: emptyAction,
      );
    }
    return child;
  }
}
