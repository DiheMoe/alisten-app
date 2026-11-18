import 'dart:async';
import 'dart:math' as math;

import 'package:alisten/domain/history/search_record.dart';
import 'package:alisten/domain/member/member.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/settings/application/image_cache.dart';
import 'package:alisten/features/settings/application/settings_controller.dart';
import 'package:alisten/features/settings/application/settings_state.dart';
import 'package:alisten/features/settings/presentation/settings_rows.dart';
import 'package:alisten/features/update/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_text_field.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/select_menu.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/status_pill.dart';
import 'package:alisten/shared/ui/tap_rhythm.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置的分类，各有一个子页面。
enum SettingsSection {
  account('account', '账号'),
  appearance('appearance', '外观'),
  notifications('notifications', '通知'),
  privacy('privacy', '隐私与记录'),
  storage('storage', '存储'),
  about('about', '关于');

  const SettingsSection(this.path, this.title);

  /// 在 `/settings` 下的路径。
  final String path;
  final String title;
}

class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({
    required this.onProfileResult,
    this.accountActions,
    super.key,
  });

  final ValueChanged<MutationResult<Member>> onProfileResult;
  final Widget? accountActions;

  // 设置控制器在面板打开前取出：面板在根导航器上，子页面可能先于它离开。
  void _editProfile(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsControllerProvider.notifier);
    unawaited(
      showSheetPanel<void>(
        context,
        builder: (_) => _ProfileSheet(
          onSave: settings.saveProfile,
          onResult: onProfileResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityControllerProvider);
    return SectionPage(
      title: SettingsSection.account.title,
      children: [
        SettingsGroup(
          children: [
            ProfileHeader(member: identity.member, account: identity.account),
            LinkRow(title: '编辑资料', onPressed: () => _editProfile(context, ref)),
            ?accountActions,
          ],
        ),
      ],
    );
  }
}

const _themes = [
  SelectOption(
    value: AppTheme.system,
    label: '跟随系统',
    icon: AlistenIcons.circleHalf,
  ),
  SelectOption(value: AppTheme.dark, label: '深色', icon: AlistenIcons.moon),
  SelectOption(value: AppTheme.light, label: '浅色', icon: AlistenIcons.sun),
];

/// 主题选项的名称。
String themeLabel(AppTheme theme) =>
    _themes.firstWhere((option) => option.value == theme).label;

class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(
      settingsControllerProvider.select((state) => state.value.theme),
    );
    return SectionPage(
      title: SettingsSection.appearance.title,
      children: [
        SettingsGroup(
          children: [
            SettingRow(
              title: '主题',
              description: '跟随系统时，随手机的深浅色切换',
              trailing: SelectMenuButton<AppTheme>(
                label: '主题',
                options: _themes,
                selected: theme,
                onChanged: ref
                    .read(settingsControllerProvider.notifier)
                    .setTheme,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  Future<void> _openSystemSettings(WidgetRef ref) async {
    final opened = await ref
        .read(settingsControllerProvider.notifier)
        .openNotificationSettings();
    if (!opened) {
      onNotice(ToastKind.failure, '没能打开系统设置，请在系统设置里找到 Alisten 的通知。');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(settingsControllerProvider);
    final settings = state.value;
    final controller = ref.read(settingsControllerProvider.notifier);
    return SectionPage(
      title: SettingsSection.notifications.title,
      children: [
        SettingsGroup(
          children: [
            SettingRow(
              title: '开播提醒',
              description: '自己点的歌等待至少 30 秒后开播时提醒',
              trailing: AlistenToggle(
                value: settings.reminders,
                semanticLabel: '开播提醒',
                onChanged: controller.setReminders,
              ),
            ),
            SettingRow(
              title: '系统通知',
              description: 'App 不在前台时，用系统通知提醒',
              trailing: AlistenToggle(
                value: settings.systemNotifications,
                semanticLabel: '系统通知',
                onChanged: settings.reminders
                    ? controller.setSystemNotifications
                    : null,
              ),
            ),
            _Permission(
              permission: state.permission,
              onOpenSettings: () => unawaited(_openSystemSettings(ref)),
            ),
          ],
        ),
      ],
    );
  }
}

enum _ProfileRead { reading, read, failed }

class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({
    required this.onNotice,
    required this.onOpenHistory,
    super.key,
  });

  final void Function(ToastKind kind, String text) onNotice;
  final VoidCallback onOpenHistory;

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends ConsumerState<PrivacySettingsScreen> {
  // 这一页自己发起的成员读取。没有成员时据此区分正在读取、没有读到和这个
  // 服务器上还没有身份。
  _ProfileRead _profileRead = _ProfileRead.reading;

  // 请求期间开关显示的新值；结束后丢掉，开关回到身份状态里的值，失败时自然
  // 回滚。
  bool? _recordListens;

  SettingsController get _settings =>
      ref.read(settingsControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    // 每次打开都重新读取：启动时可能因离线没取到成员，记录开关也可能已在别处
    // 改过。
    unawaited(
      Future.microtask(() async {
        if (mounted) await _readProfile();
      }),
    );
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
    // 登录页等在别的子页面下，返回时这一页不会重新打开；身份换了就重新读取，
    // 登录后没读到的记录开关才不会一直显示默认值。
    ref.listen(
      identityControllerProvider.select((state) => state.session),
      (_, _) => unawaited(_readProfile()),
    );
    final settings = ref.watch(settingsControllerProvider).value;
    final identity = ref.watch(identityControllerProvider);
    return SectionPage(
      title: SettingsSection.privacy.title,
      children: [
        SettingsGroup(
          title: '播放历史',
          children: [
            _recordListensRow(identity),
            LinkRow(title: '查看播放历史', onPressed: widget.onOpenHistory),
          ],
        ),
        SettingsGroup(
          title: '最近搜索',
          children: [
            SettingRow(
              title: '记录最近搜索',
              description: '在点歌页显示最近搜过的词',
              trailing: AlistenToggle(
                value: settings.recordSearch,
                semanticLabel: '记录最近搜索',
                onChanged: _settings.setRecordSearch,
              ),
            ),
            if (settings.recordSearch)
              SettingRow(
                title: '最近搜索保留条数',
                description: '只存在这台设备上',
                trailing: SelectMenuButton<int>(
                  label: '最近搜索保留条数',
                  options: [
                    for (final limit in searchHistoryLimits)
                      SelectOption(value: limit, label: '$limit 条'),
                  ],
                  selected: settings.searchHistoryLimit,
                  onChanged: _settings.setSearchHistoryLimit,
                ),
              ),
          ],
        ),
      ],
    );
  }

  // 正在读取或没有读到时不显示开关，以免显示一个没读到的值。没有身份时按新游客
  // 的默认值显示；切换要保存在成员上，这时才建游客。
  Widget _recordListensRow(IdentityState identity) {
    const title = '记录播放历史';
    if (identity.member == null && _profileRead != _ProfileRead.read) {
      final reading = _profileRead == _ProfileRead.reading;
      return SettingRow(
        title: title,
        description: reading ? '正在读取…' : '没有读到这项设置',
        labelled: false,
        trailing: reading
            // 占住开关的宽度，读到之后说明不会重新折行。
            ? SizedBox(width: AlistenSizes.toggleTrack.width)
            : PillButton(
                label: '重试',
                icon: AlistenIcons.arrowClockwise,
                style: PillButtonStyle.secondary,
                onPressed: () => unawaited(_readProfile()),
              ),
      );
    }
    return SettingRow(
      title: title,
      description: identity.account == null ? '保存在服务器上' : '存在服务器上，同一账号的设备共用',
      trailing: AlistenToggle(
        value: _recordListens ?? identity.recordListens,
        semanticLabel: title,
        onChanged: (on) => unawaited(_setRecordListens(on)),
      ),
    );
  }
}

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({required this.onNotice, super.key});

  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<StorageSettingsScreen> createState() =>
      _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  bool _clearingImages = false;

  // 离开这一页后仍要提示结果。
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

  @override
  Widget build(BuildContext context) {
    return SectionPage(
      title: SettingsSection.storage.title,
      children: [
        SettingsGroup(
          children: [
            _ImageCache(
              size: ref.watch(imageCacheControllerProvider),
              clearing: _clearingImages,
              onClear: () => unawaited(_clearImageCache()),
            ),
          ],
        ),
      ],
    );
  }
}

const _weWillRockYou = [
  TapBeat.long,
  TapBeat.long,
  TapBeat.short,
  TapBeat.long,
  TapBeat.long,
  TapBeat.short,
];

const _weWillRockYouInverted = [
  TapBeat.short,
  TapBeat.short,
  TapBeat.long,
  TapBeat.short,
  TapBeat.short,
  TapBeat.long,
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

class AboutSettingsScreen extends ConsumerWidget {
  const AboutSettingsScreen({
    required this.appVersion,
    required this.protocolVersion,
    required this.onNotice,
    required this.onOpenLicenses,
    required this.onOpenServers,
    required this.onOpenAdmin,
    super.key,
  });

  final String appVersion;
  final String protocolVersion;
  final void Function(ToastKind kind, String text) onNotice;
  final VoidCallback onOpenLicenses;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SectionPage(
      title: SettingsSection.about.title,
      children: [
        SettingsGroup(
          children: [
            // 服务器页与站点管理是隐藏入口，不改变版本行的读屏语义；
            // 邀请链接是切换服务器的另一条路径。
            TapRhythm(
              patterns: [
                RhythmPattern(beats: _weWillRockYou, onMatched: onOpenServers),
                RhythmPattern(
                  beats: _weWillRockYouInverted,
                  onMatched: onOpenServers,
                ),
                RhythmPattern(
                  beats: _fateMotif,
                  holdAfter: const Duration(seconds: 2),
                  onMatched: onOpenAdmin,
                ),
              ],
              child: InfoRow(title: '版本', value: appVersion),
            ),
            InfoRow(title: '协议版本', value: protocolVersion),
            LinkRow(
              title: '检查更新',
              busy: ref.watch(updateControllerProvider),
              onPressed: () =>
                  unawaited(checkForUpdate(context, ref, onNotice: onNotice)),
            ),
            LinkRow(title: '开源许可', onPressed: onOpenLicenses),
          ],
        ),
      ],
    );
  }
}

/// 图片缓存的大小，首页的摘要和存储页共用。
String imageCacheText(AsyncValue<int> size) => switch (size) {
  AsyncData(:final value) => _megabytes(value),
  AsyncError() => '无法计算',
  _ => '计算中…',
};

// 与缓存上限一样按 1024 进位；不足 0.1 MB 也显示 0.1 MB，以免看似已清空。
String _megabytes(int bytes) {
  if (bytes == 0) return '0 MB';
  final megabytes = math.max(bytes / (1024 * 1024), 0.1);
  return '${megabytes.toStringAsFixed(1)} MB';
}

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({required this.onSave, required this.onResult});

  final Future<MutationResult<Member>> Function({
    required String nickname,
    required String email,
  })
  onSave;
  final ValueChanged<MutationResult<Member>> onResult;

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late final TextEditingController _nickname;
  late final TextEditingController _email;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nickname = TextEditingController(
      text: ref.read(identityControllerProvider).member?.name ?? '',
    );
    _email = TextEditingController(text: ref.read(profileEmailProvider));
  }

  @override
  void dispose() {
    _nickname.dispose();
    _email.dispose();
    super.dispose();
  }

  // 用户改过的输入框不再跟随存储的值，以免覆盖正在编辑的内容。
  void _follow(TextEditingController field, String? previous, String? next) {
    if (field.text == (previous ?? '')) field.text = next ?? '';
  }

  Future<void> _save() async {
    final onResult = widget.onResult;
    setState(() => _saving = true);
    try {
      final result = await widget.onSave(
        nickname: _nickname.text,
        email: _email.text,
      );
      onResult(result);
      if (result is MutationSucceeded<Member> && mounted) {
        dismissSheet(context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
    // 资料只存到填写时的身份上：登录、退出或换了服务器就关闭。从没有成员到
    // 读出或建出成员（保存本身也会先建游客）时，输入框跟着更新，不关闭。
    ref.listen(
      identityControllerProvider.select(
        (state) => (state.session, state.member?.id),
      ),
      (previous, next) {
        final (session, member) = previous ?? next;
        if (_saving) return;
        if (session != next.$1 || (member != null && member != next.$2)) {
          dismissSheet(context);
        }
      },
    );
    final colors = AlistenColors.of(context);
    final name = ref.watch(
      identityControllerProvider.select((state) => state.member?.name),
    );
    final changed =
        _nickname.text != (name ?? '') ||
        _email.text != ref.watch(profileEmailProvider);
    return PopScope(
      canPop: !_saving,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              '编辑资料',
              style: AlistenTypography.title.copyWith(color: colors.onGlass),
            ),
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
            icon: AlistenIcons.checkBold,
            expand: true,
            busy: _saving,
            onPressed: changed && !_saving ? () => unawaited(_save()) : null,
          ),
        ],
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
    final text = imageCacheText(size);
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
                  const SettingsRowTitle('图片缓存'),
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
            icon: AlistenIcons.trash,
            style: PillButtonStyle.secondary,
            busy: clearing,
            onPressed: clearing ? null : onClear,
          ),
        ],
      ),
    );
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
        AlistenIcons.checkCircleFill,
        StatusTone.success,
      ),
      NotificationPermission.denied => (
        '已被系统拒绝',
        AlistenIcons.prohibit,
        StatusTone.danger,
      ),
      NotificationPermission.unknown => (
        '尚未确认',
        AlistenIcons.questionFill,
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
              const SettingsRowTitle('系统通知权限'),
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
              icon: AlistenIcons.arrowSquareOut,
              style: PillButtonStyle.secondary,
              onPressed: onOpenSettings,
            ),
          ],
        ],
      ),
    );
  }
}
