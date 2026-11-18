import 'dart:async';

import 'package:alisten/features/admin/application/admin_media_controller.dart';
import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/admin_registration_controller.dart';
import 'package:alisten/features/admin/application/admin_rooms_controller.dart';
import 'package:alisten/features/admin/application/admin_site_controller.dart';
import 'package:alisten/features/admin/application/github_app_controller.dart';
import 'package:alisten/features/admin/application/source_accounts_controller.dart';
import 'package:alisten/features/admin/presentation/admin_sections.dart';
import 'package:alisten/features/admin/presentation/media_format.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _reading = '读取中';
const _failed = '读取失败';

String _siteSummary(AdminSiteState site) =>
    site.brandName ?? (site.error != null ? _failed : _reading);

String _accessSummary(
  AdminRegistrationState registration,
  GithubAppState github,
) {
  final open = registration.open;
  final status = github.status;
  if (open == null || status == null) {
    return registration.error != null || github.error != null
        ? _failed
        : _reading;
  }
  final signUp = open ? '开放注册' : '已关闭注册';
  final gitHub = status.clientId == null ? 'GitHub 未开启' : 'GitHub 已开启';
  return '$signUp · $gitHub';
}

String _roomsSummary(AdminRoomsState rooms) {
  if (rooms.error != null && rooms.rooms.isEmpty) return _failed;
  if (!rooms.loaded && rooms.rooms.isEmpty) return _reading;
  return rooms.rooms.isEmpty ? '还没有常驻房间' : '${rooms.rooms.length} 个常驻房间';
}

// 网页端的规则：没识别出账号就算没登录；YouTube Cookie 不算。还有音源没读出来
// 时不知道一共几个，为 null。
int? _unsignedCount(Map<LoginSource, SourceEntry> sources) {
  if (sources.values.any((e) => e.status == null)) return null;
  return sources.values.where((e) => e.status!.account == null).length;
}

String _sourcesSummary(Map<LoginSource, SourceEntry> sources) {
  final unsigned = _unsignedCount(sources);
  if (unsigned == null) {
    return sources.values.any((e) => e.error != null) ? _failed : _reading;
  }
  return unsigned == 0 ? '都已登录' : '$unsigned 个未登录';
}

// 读第 1 页、不带搜索：媒体页里的搜索不影响这里的数量。
String _mediaSummary(AsyncValue<({int total, int totalBytes})> summary) =>
    switch (summary) {
      AsyncData(value: (total: 0, totalBytes: _)) => '还没有存储歌曲',
      AsyncData(:final value) =>
        '${value.total} 首 · 占用 ${formatBytes(value.totalBytes)}',
      AsyncError() => _failed,
      _ => _reading,
    };

class AdminHome extends ConsumerStatefulWidget {
  const AdminHome({
    required this.onExit,
    required this.onOpenSection,
    super.key,
  });

  final VoidCallback onExit;
  final void Function(AdminSection section) onOpenSection;

  @override
  ConsumerState<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends ConsumerState<AdminHome> {
  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() {
        if (!mounted) return;
        unawaited(ref.read(adminSiteControllerProvider.notifier).load());
        unawaited(
          ref.read(adminRegistrationControllerProvider.notifier).load(),
        );
        unawaited(ref.read(githubAppControllerProvider.notifier).load());
        unawaited(ref.read(adminRoomsControllerProvider.notifier).load());
        unawaited(
          ref.read(sourceAccountsControllerProvider.notifier).loadAll(),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final server = ref.watch(currentServerProvider);
    final site = ref.watch(adminSiteControllerProvider);
    final registration = ref.watch(adminRegistrationControllerProvider);
    final github = ref.watch(githubAppControllerProvider);
    final rooms = ref.watch(adminRoomsControllerProvider);
    final sources = ref.watch(sourceAccountsControllerProvider);
    final media = ref.watch(adminMediaSummaryProvider);
    String summaryOf(AdminSection section) => switch (section) {
      AdminSection.site => _siteSummary(site),
      AdminSection.access => _accessSummary(registration, github),
      AdminSection.users => '查找与重置密码',
      AdminSection.rooms => _roomsSummary(rooms),
      AdminSection.sources => _sourcesSummary(sources),
      AdminSection.media => _mediaSummary(media),
    };
    return AlistenScaffold(
      topBar: AlistenTopBar(
        title: '站点管理',
        subtitle: server.authority,
        actions: [
          PillButton(
            label: '退出后台',
            icon: AlistenIcons.signOut,
            style: PillButtonStyle.secondary,
            onPressed: widget.onExit,
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AlistenSpacing.page,
          0,
          AlistenSpacing.page,
          MediaQuery.paddingOf(context).bottom + AlistenSpacing.xl,
        ),
        children: [
          SettingsGroup(
            children: [
              for (final section in AdminSection.values)
                CategoryRow(
                  icon: section.icon,
                  title: section.title,
                  summary: summaryOf(section),
                  // 红点只跟着“n 个未登录”出现。
                  alert:
                      section == AdminSection.sources &&
                      (_unsignedCount(sources) ?? 0) > 0,
                  onPressed: () => widget.onOpenSection(section),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
