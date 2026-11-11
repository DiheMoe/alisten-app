import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/settings/application/image_cache.dart';
import 'package:alisten/features/settings/application/settings_controller.dart';
import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_scaffold.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/alisten_top_bar.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/glass_panel.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/member_avatar.dart';
import 'package:alisten/shared/ui/page_glow.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/tap_rhythm.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _themes = [
  PillSegment(
    value: AppTheme.system,
    label: '跟随系统',
    icon: Icons.brightness_auto_rounded,
  ),
  PillSegment(value: AppTheme.dark, label: '深色', icon: Icons.dark_mode_rounded),
  PillSegment(
    value: AppTheme.light,
    label: '浅色',
    icon: Icons.light_mode_rounded,
  ),
];

const _weWillRockYou = [
  TapBeat.long,
  TapBeat.long,
  TapBeat.short,
  TapBeat.long,
  TapBeat.long,
  TapBeat.short,
];

const _fateMotif = [
  TapBeat.short,
  TapBeat.short,
  TapBeat.short,
  TapBeat.long,
  TapBeat.short,
  TapBeat.short,
  TapBeat.short,
  TapBeat.long,
];

enum _ProfileRead { reading, read, failed }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({
    required this.appVersion,
    required this.protocolVersion,
    required this.onProfileResult,
    required this.onNotice,
    required this.onOpenLicenses,
    required this.onOpenServers,
    required this.onOpenAdmin,
    this.accountActions,
    super.key,
  });

  final String appVersion;
  final String protocolVersion;
  final ValueChanged<MutationResult<Member>> onProfileResult;
  final void Function(ToastKind kind, String text) onNotice;
  final VoidCallback onOpenLicenses;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenAdmin;
  final Widget? accountActions;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nickname;
  late final TextEditingController _email;
  bool _saving = false;
  bool _clearingImages = false;

  // 设置页自己发起的成员读取。没有成员时据此区分正在读取、没有读到和这个服务器
  // 上还没有身份。
  _ProfileRead _profileRead = _ProfileRead.reading;

  // 请求期间开关显示的新值；结束后丢掉，开关回到身份状态里的值，失败时自然
  // 回滚。
  bool? _recordListens;

  SettingsController get _settings =>
      ref.read(settingsControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(
      text: ref.read(identityControllerProvider).member?.name ?? '',
    );
    _email = TextEditingController(text: ref.read(profileEmailProvider));
    // 每次打开都重新读取：启动时可能因离线没取到成员，记录开关也可能已在别处
    // 改过。
    unawaited(
      Future.microtask(() async {
        if (mounted) await _readProfile();
      }),
    );
  }

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _readProfile() async {
    if (_profileRead != _ProfileRead.reading) {
      setState(() => _profileRead = _ProfileRead.reading);
    }
    final read = await _settings.loadProfile();
    if (!mounted) return;
    setState(
      () => _profileRead = read ? _ProfileRead.read : _ProfileRead.failed,
    );
  }

  // 用户改过的输入框不再跟随存储的值，以免覆盖正在编辑的内容。
  void _follow(TextEditingController field, String? previous, String? next) {
    if (field.text == (previous ?? '')) field.text = next ?? '';
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final result = await _settings.saveProfile(
        nickname: _nickname.text,
        email: _email.text,
      );
      widget.onProfileResult(result);
      // 服务端可能规整过昵称，以返回值为准。
      if (result case MutationSucceeded(:final value) when mounted) {
        _nickname.text = value.name;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openNotificationSettings() async {
    final opened = await _settings.openNotificationSettings();
    if (!opened && mounted) {
      widget.onNotice(ToastKind.failure, '没能打开系统设置，请在系统设置里找到 Alisten 的通知。');
    }
  }

  // 离开设置页后仍要提示结果。
  Future<void> _clearImageCache() async {
    setState(() => _clearingImages = true);
    final cleared = await ref
        .read(imageCacheControllerProvider.notifier)
        .clear();
    if (mounted) setState(() => _clearingImages = false);
    if (cleared) {
      widget.onNotice(ToastKind.success, '已清除图片缓存');
    } else {
      widget.onNotice(ToastKind.failure, '没能清除图片缓存，请稍后再试。');
    }
  }

  Future<void> _setRecordListens(bool on) async {
    if (_recordListens != null) return;
    setState(() => _recordListens = on);
    final result = await _settings.setRecordListens(on);
    if (mounted) setState(() => _recordListens = null);
    switch (result) {
      case MutationSucceeded():
        break;
      case MutationFailed(:final message) || MutationNotSent(:final message):
        widget.onNotice(ToastKind.failure, message);
      case MutationUnknown():
        widget.onNotice(ToastKind.warning, '结果未知，已重新读取这项设置。');
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      identityControllerProvider.select((state) => state.member?.name),
      (previous, next) => _follow(_nickname, previous, next),
    );
    ref.listen(
      profileEmailProvider,
      (previous, next) => _follow(_email, previous, next),
    );
    // 登录页等是设置页的子页面，返回时不会重新打开设置页；身份换了就重新读取，
    // 登录后没读到的记录开关才不会一直显示默认值。
    ref.listen(
      identityControllerProvider.select((state) => state.session),
      (_, _) => unawaited(_readProfile()),
    );
    final state = ref.watch(settingsControllerProvider);
    final settings = state.value;
    final identity = ref.watch(identityControllerProvider);
    final member = identity.member;
    return AlistenScaffold(
      background: const PageGlow(),
      topBar: AlistenTopBar(
        leading: IconCircleButton(
          icon: Icons.arrow_back_rounded,
          semanticLabel: '返回',
          style: IconCircleButtonStyle.plain,
          onPressed: () => unawaited(Navigator.maybePop(context)),
        ),
        title: '设置',
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
            title: '账号',
            children: [
              _profile(member, identity.account),
              ?widget.accountActions,
            ],
          ),
          _Group(
            title: '外观',
            children: [
              Padding(
                padding: const EdgeInsets.all(AlistenSpacing.sm),
                child: Semantics(
                  container: true,
                  label: '主题',
                  child: SegmentedPills<AppTheme>(
                    segments: _themes,
                    selected: settings.theme,
                    onChanged: _settings.setTheme,
                  ),
                ),
              ),
            ],
          ),
          _Group(
            title: '通知',
            children: [
              _SettingRow(
                title: '开播提醒',
                description: '自己点的歌等待至少 30 秒后开播时提醒',
                trailing: AlistenToggle(
                  value: settings.reminders,
                  semanticLabel: '开播提醒',
                  onChanged: _settings.setReminders,
                ),
              ),
              _SettingRow(
                title: '系统通知',
                description: 'App 不在前台时，用系统通知提醒',
                trailing: AlistenToggle(
                  value: settings.systemNotifications,
                  semanticLabel: '系统通知',
                  onChanged: settings.reminders
                      ? _settings.setSystemNotifications
                      : null,
                ),
              ),
              _Permission(
                permission: state.permission,
                onOpenSettings: () => unawaited(_openNotificationSettings()),
              ),
            ],
          ),
          _Group(
            title: '隐私',
            children: [
              _SettingRow(
                title: '记录最近搜索',
                description: '在点歌页显示最近搜过的词',
                trailing: AlistenToggle(
                  value: settings.recordSearch,
                  semanticLabel: '记录最近搜索',
                  onChanged: _settings.setRecordSearch,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AlistenSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsetsDirectional.only(
                        start: AlistenSpacing.xxs,
                        bottom: AlistenSpacing.xs,
                      ),
                      child: ExcludeSemantics(child: _RowTitle('最近搜索保留条数')),
                    ),
                    Semantics(
                      container: true,
                      label: '最近搜索保留条数',
                      child: SegmentedPills<int>(
                        segments: [
                          for (final limit in searchHistoryLimits)
                            PillSegment(value: limit, label: '$limit 条'),
                        ],
                        selected: settings.searchHistoryLimit,
                        onChanged: _settings.setSearchHistoryLimit,
                      ),
                    ),
                  ],
                ),
              ),
              _recordListensRow(identity),
            ],
          ),
          _Group(
            title: '存储',
            children: [
              _ImageCache(
                size: ref.watch(imageCacheControllerProvider),
                clearing: _clearingImages,
                onClear: () => unawaited(_clearImageCache()),
              ),
            ],
          ),
          _Group(
            title: '关于',
            children: [
              // 服务器页与站点管理是隐藏入口，不改变版本行的读屏语义；
              // 邀请链接是切换服务器的另一条路径。
              TapRhythm(
                patterns: [
                  RhythmPattern(
                    beats: _weWillRockYou,
                    onMatched: widget.onOpenServers,
                  ),
                  RhythmPattern(
                    beats: _fateMotif,
                    holdAfter: const Duration(seconds: 2),
                    onMatched: widget.onOpenAdmin,
                  ),
                ],
                child: _InfoRow(title: '版本', value: widget.appVersion),
              ),
              _InfoRow(title: '协议版本', value: widget.protocolVersion),
              _LinkRow(
                title: '检查更新',
                busy: ref.watch(updateControllerProvider),
                onPressed: () => unawaited(
                  checkForUpdate(context, ref, onNotice: widget.onNotice),
                ),
              ),
              _LinkRow(title: '开源许可', onPressed: widget.onOpenLicenses),
            ],
          ),
        ],
      ),
    );
  }

  // 正在读取或没有读到时不显示开关，以免显示一个没读到的值。没有身份时按新游客
  // 的默认值显示；切换要保存在成员上，这时才建游客。
  Widget _recordListensRow(IdentityState identity) {
    const title = '记录播放历史';
    if (identity.member == null && _profileRead != _ProfileRead.read) {
      final reading = _profileRead == _ProfileRead.reading;
      return _SettingRow(
        title: title,
        description: reading ? '正在读取…' : '没有读到这项设置',
        labelled: false,
        trailing: reading
            // 占住开关的宽度，读到之后说明不会重新折行。
            ? SizedBox(width: AlistenSizes.toggleTrack.width)
            : PillButton(
                label: '重试',
                icon: Icons.refresh_rounded,
                style: PillButtonStyle.secondary,
                onPressed: () => unawaited(_readProfile()),
              ),
      );
    }
    return _SettingRow(
      title: title,
      description: identity.account == null ? '保存在服务器上' : '保存在服务器上，登录这个账号的设备共用',
      trailing: AlistenToggle(
        value: _recordListens ?? identity.recordListens,
        semanticLabel: title,
        onChanged: (on) => unawaited(_setRecordListens(on)),
      ),
    );
  }

  Widget _profile(Member? member, Account? account) {
    final colors = AlistenColors.of(context);
    final typed = _nickname.text.trim();
    final name = typed.isEmpty ? member?.name ?? '' : typed;
    final changed =
        _nickname.text != (member?.name ?? '') ||
        _email.text != ref.read(profileEmailProvider);
    return Padding(
      padding: const EdgeInsets.all(AlistenSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                      _identityLabel(member, account),
                      style: AlistenTypography.secondary.copyWith(
                        color: colors.onGlassMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AlistenSpacing.lg),
          AlistenTextField(
            controller: _nickname,
            label: '昵称',
            maxLength: 80,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AlistenSpacing.md),
          AlistenTextField(
            controller: _email,
            label: 'Gravatar 邮箱',
            maxLength: 320,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AlistenSpacing.lg),
          PillButton(
            label: '保存资料',
            icon: Icons.check_rounded,
            expand: true,
            busy: _saving,
            onPressed: changed && !_saving
                ? () => unawaited(_saveProfile())
                : null,
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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

class _RowTitle extends StatelessWidget {
  const _RowTitle(this.text);

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
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.description,
    required this.trailing,
    this.labelled = true,
  });

  final String title;
  final String description;
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
                      child: _RowTitle(title),
                    ),
                    const SizedBox(height: AlistenSpacing.xxs / 2),
                    Text(
                      description,
                      style: AlistenTypography.secondary.copyWith(
                        color: AlistenColors.of(context).onGlassMuted,
                      ),
                    ),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value});

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
              _RowTitle(title),
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

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.title,
    required this.onPressed,
    this.busy = false,
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
              Expanded(child: _RowTitle(title)),
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
                  Icons.chevron_right_rounded,
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

class _ImageCache extends StatelessWidget {
  const _ImageCache({
    required this.size,
    required this.clearing,
    required this.onClear,
  });

  final AsyncValue<int> size;
  final bool clearing;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final text = switch (size) {
      AsyncData(:final value) => _megabytes(value),
      AsyncError() => '无法计算',
      _ => '计算中…',
    };
    return Padding(
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
                  const _RowTitle('图片缓存'),
                  const SizedBox(height: AlistenSpacing.xxs / 2),
                  Text(
                    text,
                    style: AlistenTypography.secondary.copyWith(
                      color: AlistenColors.of(context).onGlassMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AlistenSpacing.sm),
          PillButton(
            label: '清除缓存',
            icon: Icons.delete_outline_rounded,
            style: PillButtonStyle.secondary,
            busy: clearing,
            onPressed: clearing ? null : onClear,
          ),
        ],
      ),
    );
  }

  // 与缓存上限一样按 1024 进位；不足 0.1 MB 也显示 0.1 MB，以免看似已清空。
  static String _megabytes(int bytes) {
    if (bytes == 0) return '0 MB';
    final megabytes = math.max(bytes / (1024 * 1024), 0.1);
    return '${megabytes.toStringAsFixed(1)} MB';
  }
}

// 被系统拒绝后应用不一定还能再次请求，所以未允许时提供去系统设置的入口。
class _Permission extends StatelessWidget {
  const _Permission({required this.permission, required this.onOpenSettings});

  final NotificationPermission permission;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final (label, icon, tone) = switch (permission) {
      NotificationPermission.granted => (
        '已允许',
        Icons.check_circle_rounded,
        StatusTone.success,
      ),
      NotificationPermission.denied => (
        '已被系统拒绝',
        Icons.block_rounded,
        StatusTone.danger,
      ),
      NotificationPermission.unknown => (
        '尚未确认',
        Icons.help_rounded,
        StatusTone.neutral,
      ),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AlistenSpacing.md,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
        AlistenSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _RowTitle('系统通知权限'),
              const SizedBox(width: AlistenSpacing.sm),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: StatusPill(label: label, icon: icon, tone: tone),
                ),
              ),
            ],
          ),
          if (permission == NotificationPermission.denied) ...[
            const SizedBox(height: AlistenSpacing.xxs),
            Text(
              '系统拒绝后，要在系统设置里重新允许。',
              style: AlistenTypography.secondary.copyWith(
                color: colors.onGlassMuted,
              ),
            ),
          ],
          if (permission != NotificationPermission.granted) ...[
            const SizedBox(height: AlistenSpacing.sm),
            PillButton(
              label: '去系统设置',
              icon: Icons.open_in_new_rounded,
              style: PillButtonStyle.secondary,
              onPressed: onOpenSettings,
            ),
          ],
        ],
      ),
    );
  }
}

String _identityLabel(Member? member, Account? account) {
  if (member == null) return '还没有身份';
  if (account == null) return '游客';
  final username = account.username;
  return username == null ? '用 GitHub 登录的账号' : '@$username';
}
