import 'dart:async';

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';

class SettingsGroup extends StatelessWidget {
  const SettingsGroup({required this.children, this.title, super.key});

  /// 为 null 时不显示组标题，比如首页的分类列表。
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AlistenSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title case final title?)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AlistenSpacing.xxs,
                bottom: AlistenSpacing.xs,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: AlistenTypography.weighted(
                    AlistenTypography.secondary,
                    FontWeight.w700,
                  ).copyWith(color: colors.onGlassMuted),
                ),
              ),
            ),
          GlassPanel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, child) in children.indexed) ...[
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
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsRowTitle extends StatelessWidget {
  const SettingsRowTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AlistenTypography.bodyStrong.copyWith(
        color: AlistenColors.of(context).onGlass,
      ),
    );
  }
}

// [labelled] 时可见标题不进语义树：[trailing] 控件已以标题为名，否则读屏会读
// 两遍。不是时标题和说明合成一个节点读出。
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.title,
    required this.trailing,
    this.description,
    this.labelled = true,
    super.key,
  });

  final String title;

  /// 只在标题说不清时写，比如要满足的条件。
  final String? description;
  final Widget trailing;
  final bool labelled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AlistenSizes.largeTouchTarget,
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          AlistenSpacing.md,
          AlistenSpacing.sm,
          AlistenSpacing.sm,
          AlistenSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: MergeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      excluding: labelled,
                      child: SettingsRowTitle(title),
                    ),
                    if (description case final description?) ...[
                      const SizedBox(height: AlistenSpacing.xxs / 2),
                      Text(
                        description,
                        style: AlistenTypography.secondary.copyWith(
                          color: AlistenColors.of(context).onGlassMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: AlistenSpacing.sm),
            trailing,
          ],
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({required this.title, required this.value, super.key});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.largeTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlistenSpacing.md,
            vertical: AlistenSpacing.sm,
          ),
          child: Row(
            children: [
              SettingsRowTitle(title),
              const SizedBox(width: AlistenSpacing.sm),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: AlistenTypography.timecode.copyWith(
                    color: AlistenColors.of(context).onGlassMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LinkRow extends StatelessWidget {
  const LinkRow({
    required this.title,
    required this.onPressed,
    this.busy = false,
    super.key,
  });

  final String title;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final muted = AlistenColors.of(context).onGlassMuted;
    return Pressable(
      onPressed: busy ? null : onPressed,
      // 进行中不等于不可用，不变淡。
      dimWhenDisabled: !busy,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.largeTouchTarget,
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            AlistenSpacing.md,
            AlistenSpacing.sm,
            AlistenSpacing.sm,
            AlistenSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(child: SettingsRowTitle(title)),
              const SizedBox(width: AlistenSpacing.sm),
              if (busy)
                Semantics(
                  value: busySemanticValue,
                  child: SizedBox.square(
                    dimension: AlistenSizes.icon,
                    child: Center(
                      child: BusyIndicator(
                        size: AlistenSizes.iconSm * 0.8,
                        color: muted,
                      ),
                    ),
                  ),
                )
              else
                Icon(
                  AlistenIcons.caretRight,
                  size: AlistenSizes.icon,
                  color: muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置首页的分类：左边图标，右边是这一类当前的状态，点进子页面。
class CategoryRow extends StatelessWidget {
  const CategoryRow({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onPressed,
    this.alert = false,
    this.selected,
    super.key,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onPressed;

  /// 两栏布局里这一类是否正打开着；不是两栏时为 null。
  final bool? selected;

  /// 为 true 时摘要前显示红点，比如有音源没登录。
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Pressable(
      onPressed: onPressed,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: AlistenSizes.largeTouchTarget,
        ),
        child: ColoredBox(
          color: selected ?? false
              ? colors.selectedFill
              : colors.selectedFill.withValues(alpha: 0),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AlistenSpacing.md,
              AlistenSpacing.sm,
              AlistenSpacing.sm,
              AlistenSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(icon, size: AlistenSizes.icon, color: colors.onGlass),
                const SizedBox(width: AlistenSpacing.md),
                SettingsRowTitle(title),
                const SizedBox(width: AlistenSpacing.sm),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (alert) ...[
                        ExcludeSemantics(
                          child: DecoratedBox(
                            key: const ValueKey('category-alert'),
                            decoration: BoxDecoration(
                              color: colors.danger,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 8),
                          ),
                        ),
                        const SizedBox(width: AlistenSpacing.xs),
                      ],
                      Flexible(
                        child: Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.end,
                          style: AlistenTypography.secondary.copyWith(
                            color: colors.onGlassMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AlistenSpacing.xxs),
                Icon(
                  AlistenIcons.caretRight,
                  size: AlistenSizes.icon,
                  color: colors.onGlassMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 设置的子页面：标题、返回按钮和一列分组。
class SectionPage extends StatelessWidget {
  const SectionPage({required this.title, required this.children, super.key});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: title,
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          0,
          AlistenSpacing.page,
          MediaQuery.paddingOf(context).bottom + AlistenSpacing.xl,
        ),
        children: children,
      ),
    );
  }
}
