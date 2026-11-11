import 'package:alisten/features/admin/presentation/accounts_group.dart';
import 'package:alisten/features/admin/presentation/registration_group.dart';
import 'package:alisten/features/admin/presentation/rooms_group.dart';
import 'package:alisten/features/admin/presentation/site_group.dart';
import 'package:alisten/features/admin/presentation/sources_group.dart';
import 'package:alisten/features/admin/presentation/youtube_group.dart';
import 'package:alisten/features/server/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminHome extends ConsumerWidget {
  const AdminHome({
    required this.onNotice,
    required this.onExit,
    required this.onOpenRoom,
    super.key,
  });

  final void Function(ToastKind kind, String text) onNotice;
  final VoidCallback onExit;
  final void Function(String roomRef) onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final server = ref.watch(currentServerProvider);
    return AlistenScaffold(
      background: const PageGlow(),
      topBar: AlistenTopBar(
        title: '站点管理',
        subtitle: server.authority,
        actions: [
          PillButton(
            label: '退出后台',
            icon: Icons.logout_rounded,
            style: PillButtonStyle.secondary,
            onPressed: onExit,
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
          _Group(
            title: '站点',
            child: SiteGroup(onNotice: onNotice),
          ),
          _Group(
            title: '注册',
            child: RegistrationGroup(onNotice: onNotice),
          ),
          _Group(
            title: '账号',
            child: AccountsGroup(onNotice: onNotice),
          ),
          _Group(
            title: '常驻房间',
            child: RoomsGroup(onNotice: onNotice, onOpenRoom: onOpenRoom),
          ),
          _Group(
            title: '音源账号',
            child: SourcesGroup(onNotice: onNotice),
          ),
          _Group(
            title: 'YouTube Cookie',
            child: YoutubeGroup(onNotice: onNotice),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AlistenSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          GlassPanel(padding: EdgeInsets.zero, child: child),
        ],
      ),
    );
  }
}
