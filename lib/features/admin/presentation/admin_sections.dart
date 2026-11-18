import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:alisten/features/admin/presentation/accounts_group.dart';
import 'package:alisten/features/admin/presentation/ephemeral_rooms_group.dart';
import 'package:alisten/features/admin/presentation/github_app_group.dart';
import 'package:alisten/features/admin/presentation/media_page.dart';
import 'package:alisten/features/admin/presentation/registration_group.dart';
import 'package:alisten/features/admin/presentation/rooms_group.dart';
import 'package:alisten/features/admin/presentation/site_group.dart';
import 'package:alisten/features/admin/presentation/sources_group.dart';
import 'package:alisten/features/admin/presentation/youtube_group.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AdminSection {
  site('site', '站点', AlistenIcons.globe),
  access('access', '登录与注册', AlistenIcons.key),
  users('users', '用户', AlistenIcons.users),
  rooms('rooms', '房间', AlistenIcons.door),
  sources('sources', '音源', AlistenIcons.musicNote),
  media('media', '媒体', AlistenIcons.hardDrives);

  const AdminSection(this.path, this.title, this.icon);

  final String path;
  final String title;
  final IconData icon;
}

/// 会话不在时调用 [onEnded]（回到令牌页），不显示 [child]。
class AdminSectionGate extends ConsumerWidget {
  const AdminSectionGate({
    required this.onEnded,
    required this.child,
    super.key,
  });

  final VoidCallback onEnded;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      adminSessionProvider.select((session) => session.active),
    );
    if (active) return child;
    // 直接打开子页面地址、或会话在这里结束：回令牌页，由那里说明原因。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) onEnded();
    });
    return const SizedBox.shrink();
  }
}

/// 路由和测试共用：按 [section] 建子页面，外面已包好 [AdminSectionGate]。
Widget adminSectionScreen(
  AdminSection section, {
  required void Function(ToastKind kind, String text) onNotice,
  required void Function(String roomRef) onOpenRoom,
  required VoidCallback onEnded,
}) {
  return AdminSectionGate(
    onEnded: onEnded,
    child: switch (section) {
      AdminSection.site => SectionPage(
        title: section.title,
        children: [
          SettingsGroup(children: [SiteGroup(onNotice: onNotice)]),
        ],
      ),
      AdminSection.access => SectionPage(
        title: section.title,
        children: [
          SettingsGroup(
            title: '注册',
            children: [RegistrationGroup(onNotice: onNotice)],
          ),
          SettingsGroup(
            title: 'GitHub 登录',
            children: [GithubAppGroup(onNotice: onNotice)],
          ),
        ],
      ),
      AdminSection.users => SectionPage(
        title: section.title,
        children: [
          SettingsGroup(children: [AccountsGroup(onNotice: onNotice)]),
        ],
      ),
      AdminSection.rooms => SectionPage(
        title: section.title,
        children: [
          SettingsGroup(
            title: '临时房间',
            children: [EphemeralRoomsGroup(onNotice: onNotice)],
          ),
          SettingsGroup(
            title: '常驻房间',
            children: [RoomsGroup(onNotice: onNotice, onOpenRoom: onOpenRoom)],
          ),
        ],
      ),
      AdminSection.sources => SectionPage(
        title: section.title,
        children: [
          SettingsGroup(
            title: '音源账号',
            children: [SourcesGroup(onNotice: onNotice)],
          ),
          SettingsGroup(
            title: 'YouTube Cookie',
            children: [YoutubeGroup(onNotice: onNotice)],
          ),
        ],
      ),
      AdminSection.media => AdminMediaScreen(onNotice: onNotice),
    },
  );
}
