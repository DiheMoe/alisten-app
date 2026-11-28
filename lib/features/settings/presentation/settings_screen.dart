import 'dart:async';

import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/settings/application/image_cache.dart';
import 'package:alisten/features/settings/application/settings_controller.dart';
import 'package:alisten/features/settings/presentation/settings_rows.dart';
import 'package:alisten/features/settings/presentation/settings_sections.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'settings_sections.dart'
    show
        AboutSettingsScreen,
        AccountSettingsScreen,
        AppearanceSettingsScreen,
        NotificationSettingsScreen,
        PrivacySettingsScreen,
        SettingsSection,
        StorageSettingsScreen;

/// 设置首页：上面是自己的资料，点开是账号；下面每一类一行，右边是它当前的
/// 状态，点进子页面。
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    required this.appVersion,
    required this.onOpen,
    this.selected,
    super.key,
  });

  final String appVersion;
  final ValueChanged<SettingsSection> onOpen;

  /// 桌面窗口的两栏里，旁边打开着的那一类。
  final SettingsSection? selected;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // 每次打开都重新读取：启动时可能因离线没取到成员，资料卡片和记录状态才
    // 不会一直停在旧的。
    unawaited(
      Future.microtask(() async {
        if (mounted) {
          await ref.read(settingsControllerProvider.notifier).loadProfile();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final settings = ref.watch(settingsControllerProvider).value;
    final identity = ref.watch(identityControllerProvider);
    final cache = ref.watch(imageCacheControllerProvider);
    final listens = identity.member != null && identity.recordListens;
    final privacy = switch ((listens, settings.recordSearch)) {
      (true, true) => '记录播放和搜索',
      (true, false) => '只记录播放',
      (false, true) => '只记录搜索',
      (false, false) => '都不记录',
    };
    void open(SettingsSection section) => widget.onOpen(section);
    bool? selected(SettingsSection section) =>
        widget.selected == null ? null : widget.selected == section;
    return AlistenScaffold(
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: AlistenIcons.arrowLeft,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '设置',
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
            child: Pressable(
              onPressed: () => open(SettingsSection.account),
              semanticLabel: SettingsSection.account.title,
              focusRadius: BorderRadius.circular(AlistenRadii.md),
              selected: widget.selected == null
                  ? null
                  : widget.selected == SettingsSection.account,
              child: Row(
                children: [
                  Expanded(
                    child: ProfileHeader(
                      member: identity.member,
                      account: identity.account,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      end: AlistenSpacing.sm,
                    ),
                    child: Icon(
                      AlistenIcons.caretRight,
                      size: AlistenSizes.icon,
                      color: colors.onGlassMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SettingsGroup(
            children: [
              CategoryRow(
                icon: AlistenIcons.palette,
                title: SettingsSection.appearance.title,
                summary: themeLabel(settings.theme),
                onPressed: () => open(SettingsSection.appearance),
                selected: selected(SettingsSection.appearance),
              ),
              CategoryRow(
                icon: AlistenIcons.bell,
                title: SettingsSection.notifications.title,
                summary: settings.reminders ? '开播提醒已开' : '已关闭',
                onPressed: () => open(SettingsSection.notifications),
                selected: selected(SettingsSection.notifications),
              ),
              CategoryRow(
                icon: AlistenIcons.shieldCheck,
                title: SettingsSection.privacy.title,
                summary: privacy,
                onPressed: () => open(SettingsSection.privacy),
                selected: selected(SettingsSection.privacy),
              ),
              CategoryRow(
                icon: AlistenIcons.hardDrives,
                title: SettingsSection.storage.title,
                summary: imageCacheText(cache),
                onPressed: () => open(SettingsSection.storage),
                selected: selected(SettingsSection.storage),
              ),
              CategoryRow(
                icon: AlistenIcons.info,
                title: SettingsSection.about.title,
                summary: widget.appVersion,
                onPressed: () => open(SettingsSection.about),
                selected: selected(SettingsSection.about),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
