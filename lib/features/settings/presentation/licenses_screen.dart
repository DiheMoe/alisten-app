import 'dart:async';

import 'package:alisten/features/settings/application/open_source_licenses.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/async_state_view.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef _Row = ({PackageLicenses package, int? license});

class LicensesScreen extends ConsumerStatefulWidget {
  const LicensesScreen({super.key});

  @override
  ConsumerState<LicensesScreen> createState() => _LicensesScreenState();
}

class _LicensesScreenState extends ConsumerState<LicensesScreen> {
  final _expanded = <String>{};

  void _toggle(String package) {
    setState(() {
      if (!_expanded.remove(package)) _expanded.add(package);
    });
  }

  @override
  Widget build(BuildContext context) {
    final licenses = ref.watch(openSourceLicensesProvider);
    final packages = licenses.value ?? const [];
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '开源许可',
      ),
      body: AsyncStateView(
        loading: licenses.isLoading,
        errorMessage: licenses.hasError ? '没能读取开源许可' : null,
        empty: packages.isEmpty,
        emptyLabel: '没有可显示的许可',
        emptyIcon: AlistenIcons.fileText,
        onRetry: () => ref.invalidate(openSourceLicensesProvider),
        child: _list(packages),
      ),
    );
  }

  // 每份许可单独作为列表项以便按需构建：有的包有几百份许可。
  Widget _list(List<PackageLicenses> packages) {
    final rows = <_Row>[
      for (final package in packages) ...[
        (package: package, license: null),
        if (_expanded.contains(package.package))
          for (var index = 0; index < package.licenses.length; index++)
            (package: package, license: index),
      ],
    ];
    final colors = AlistenColors.of(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AlistenSpacing.page,
            0,
            AlistenSpacing.page,
            MediaQuery.paddingOf(context).bottom + AlistenSpacing.xl,
          ),
          sliver: SliverList.builder(
            itemCount: rows.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlistenSpacing.xxs,
                    vertical: AlistenSpacing.xs,
                  ),
                  child: Text(
                    'Alisten 使用了下列开源软件和字体，点按名称查看许可全文。',
                    style: AlistenTypography.secondary.copyWith(
                      color: colors.onGlassMuted,
                    ),
                  ),
                );
              }
              final (:package, :license) = rows[index - 1];
              if (license == null) {
                return _PackageHeader(
                  key: ValueKey('package ${package.package}'),
                  package: package,
                  expanded: _expanded.contains(package.package),
                  onToggle: () => _toggle(package.package),
                );
              }
              return _LicenseText(
                key: ValueKey('license ${package.package} $license'),
                license: package.licenses[license],
                divided: license > 0,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PackageHeader extends StatelessWidget {
  const _PackageHeader({
    required this.package,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final PackageLicenses package;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AlistenSpacing.xs),
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: Pressable(
          onPressed: onToggle,
          expanded: expanded,
          focusRadius: BorderRadius.circular(AlistenRadii.md),
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.package,
                          style: AlistenTypography.bodyStrong.copyWith(
                            color: colors.onGlass,
                          ),
                        ),
                        Text(
                          '${package.licenses.length} 份许可',
                          style: AlistenTypography.secondary.copyWith(
                            color: colors.onGlassMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AlistenSpacing.sm),
                  Icon(
                    expanded
                        ? AlistenIcons.caretUpBold
                        : AlistenIcons.caretDownBold,
                    size: AlistenSizes.icon,
                    color: colors.onGlassMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LicenseText extends StatelessWidget {
  const _LicenseText({required this.license, required this.divided, super.key});

  final LicenseEntry license;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final style = AlistenTypography.secondary.copyWith(color: colors.onGlass);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (divided)
            SizedBox(
              height: AlistenSizes.hairline,
              child: ColoredBox(color: colors.glassStroke),
            ),
          const SizedBox(height: AlistenSpacing.md),
          for (final paragraph in license.paragraphs)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: paragraph.indent == LicenseParagraph.centeredIndent
                    ? 0
                    : AlistenSpacing.md * paragraph.indent,
                bottom: AlistenSpacing.xs,
              ),
              child: Text(
                paragraph.text,
                textAlign: paragraph.indent == LicenseParagraph.centeredIndent
                    ? TextAlign.center
                    : TextAlign.start,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}
