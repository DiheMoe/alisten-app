import 'package:alisten/domain/member/member.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
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
  const MemberList({required this.sessions, this.selfId, super.key});

  final List<Member> sessions;
  final String? selfId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (:member, :sessions) in membersOf(this.sessions))
          _MemberRow(
            key: ValueKey('member-${member.id}'),
            member: member,
            sessions: sessions,
            self: member.id == selfId,
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
    super.key,
  });

  final Member member;
  final int sessions;
  final bool self;

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
            MemberAvatar(
              name: member.name,
              imageUrl: member.avatarUrl(AlistenSizes.listAvatar),
              size: AlistenSizes.listAvatar,
            ),
            const SizedBox(width: AlistenSpacing.sm),
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
                style: AlistenTypography.bodyStrong.copyWith(
                  color: colors.onGlass,
                ),
              ),
            ),
            if (sessions > 1) ...[
              const SizedBox(width: AlistenSpacing.xs),
              Text('$sessions 台设备', style: muted),
            ],
          ],
        ),
      ),
    );
  }
}
