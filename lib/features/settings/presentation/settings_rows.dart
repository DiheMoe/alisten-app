import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:flutter/material.dart';

export 'package:alisten/shared/ui/settings_list.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({required this.member, required this.account, super.key});

  final Member? member;
  final Account? account;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final member = this.member;
    final name = member?.name ?? '';
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Row(
        children: [
          MemberAvatar(
            name: name,
            imageUrl: member?.avatarUrl(AlistenSizes.profileAvatar),
            size: AlistenSizes.profileAvatar,
          ),
          const SizedBox(width: AlistenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '还没有昵称' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AlistenTypography.weighted(
                    AlistenTypography.title,
                    FontWeight.w700,
                  ).copyWith(color: colors.onGlass),
                ),
                Text(
                  identityLabel(member, account),
                  style: AlistenTypography.secondary.copyWith(
                    color: colors.onGlassMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String identityLabel(Member? member, Account? account) {
  if (member == null) return '还没有身份';
  if (account == null) return '游客';
  final username = account.username;
  return username == null ? '用 GitHub 登录的账号' : '@$username';
}
