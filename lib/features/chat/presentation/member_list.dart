import 'dart:math' as math;

import 'package:alisten/domain/member/member.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/edge_fade.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:flutter/widgets.dart';

/// 房间为每台连接的设备保留一个会话，同一成员可能有多个会话。
List<({Member member, int sessions})> membersOf(List<Member> sessions) {
  final counts = <String, int>{};
  final members = <Member>[];
  for (final session in sessions) {
    final count = counts[session.id];
    if (count == null) members.add(session);
    counts[session.id] = (count ?? 0) + 1;
  }
  return [
    for (final member in members)
      (member: member, sessions: counts[member.id]!),
  ];
}

/// 一次布局所有行：列表由面板自己的滚动视图滚动，且房间成员只有几十个。
class MemberList extends StatelessWidget {
  const MemberList({
    required this.sessions,
    this.selfId,
    this.avatar,
    this.details,
    super.key,
  });

  final List<Member> sessions;
  final String? selfId;

  /// 按行号包住头像和头像右边的内容，面板展开、收起时由它决定怎么显出。
  final Widget Function(int row, Widget avatar)? avatar;
  final Widget Function(int row, Widget details)? details;

  /// 一行的高度：头像和名字中较高的那个，加上下留白。成员面板按它算出最多
  /// 露出几行。
  static double rowExtent(BuildContext context) {
    final name = AlistenTypography.bodyStrong;
    final line =
        MediaQuery.textScalerOf(context).scale(name.fontSize!) * name.height!;
    return math.max(AlistenSizes.listAvatar, line) + 2 * AlistenSpacing.xs;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, (:member, :sessions)) in membersOf(
          this.sessions,
        ).indexed)
          // 列表放在 EdgeFade 里时，滚到边上的行渐隐。
          EdgeFadeItem(
            key: ValueKey('member-${member.id}'),
            child: _MemberRow(
              member: member,
              sessions: sessions,
              self: member.id == selfId,
              avatar: (child) => avatar?.call(index, child) ?? child,
              details: (child) => details?.call(index, child) ?? child,
            ),
          ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.sessions,
    required this.self,
    required this.avatar,
    required this.details,
  });

  final Member member;
  final int sessions;
  final bool self;
  final Widget Function(Widget) avatar;
  final Widget Function(Widget) details;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AlistenSpacing.xs),
      child: MergeSemantics(
        child: Row(
          children: [
            avatar(
              MemberAvatar(
                name: member.name,
                imageUrl: member.avatarUrl(AlistenSizes.listAvatar),
                size: AlistenSizes.listAvatar,
              ),
            ),
            const SizedBox(width: AlistenSpacing.sm),
            Expanded(child: details(_details(muted, colors))),
          ],
        ),
      ),
    );
  }

  Widget _details(TextStyle muted, AlistenColors colors) {
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              text: member.name,
              children: [
                if (self)
                  TextSpan(
                    text: '（我）',
                    style: AlistenTypography.weighted(
                      TextStyle(color: colors.onGlassMuted),
                      FontWeight.w500,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AlistenTypography.bodyStrong.copyWith(color: colors.onGlass),
          ),
        ),
        if (sessions > 1) ...[
          const SizedBox(width: AlistenSpacing.xs),
          Text('$sessions 台设备', style: muted),
        ],
      ],
    );
  }
}
