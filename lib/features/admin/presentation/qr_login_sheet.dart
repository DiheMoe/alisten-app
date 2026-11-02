import 'dart:async';

import 'package:alisten/features/admin/application/admin_models.dart';
import 'package:alisten/features/admin/application/qr_login_controller.dart';
import 'package:alisten/features/admin/application/source_account_view.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/busy_indicator.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/segmented_pills.dart';
import 'package:alisten/shared/ui/sheet_panel.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 登录成功时返回 true。
Future<bool> showQrLoginSheet(
  BuildContext context, {
  required LoginSource source,
  required void Function(ToastKind kind, String text) onNotice,
}) async {
  final signedIn = await showSheetPanel<bool>(
    context,
    builder: (_) => QrLoginSheet(source: source, onNotice: onNotice),
  );
  return signedIn ?? false;
}

class QrLoginSheet extends ConsumerStatefulWidget {
  const QrLoginSheet({required this.source, required this.onNotice, super.key});

  final LoginSource source;
  final void Function(ToastKind kind, String text) onNotice;

  @override
  ConsumerState<QrLoginSheet> createState() => _QrLoginSheetState();
}

class _QrLoginSheetState extends ConsumerState<QrLoginSheet> {
  late final AppLifecycleListener _lifecycle;
  bool _saving = false;

  QrLoginController get _login =>
      ref.read(qrLoginControllerProvider(widget.source).notifier);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _follow);
    unawaited(
      Future.microtask(() async {
        if (mounted) await _login.start();
      }),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  // 用户要切到音乐 App 从相册扫码，期间应用在后台：暂停查询，回到前台立即查询
  // 一次。
  void _follow(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _login.resume();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        _login.pause();
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final onNotice = widget.onNotice;
    setState(() => _saving = true);
    final result = await _login.saveImage();
    if (mounted) setState(() => _saving = false);
    switch (result) {
      case QrSaveResult.saved:
        onNotice(ToastKind.success, '已保存到相册');
      case QrSaveResult.denied:
        onNotice(ToastKind.warning, '没有相册权限，可在系统设置中开启');
      case QrSaveResult.failed:
        onNotice(ToastKind.failure, '没能保存到相册');
    }
  }

  void _closeSignedIn() {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(true);
    } else {
      Navigator.of(context).removeRoute(route, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final provider = qrLoginControllerProvider(source);
    ref.listen(provider.select((login) => login.phase), (_, phase) {
      if (phase == QrPhase.success) _closeSignedIn();
    });
    final colors = AlistenColors.of(context);
    final login = ref.watch(provider);
    final image = login.image;
    final muted = AlistenTypography.secondary.copyWith(
      color: colors.onGlassMuted,
    );
    final scanApp = switch (source) {
      LoginSource.netease => '网易云音乐',
      LoginSource.qq => login.qqType == QqLoginType.qq ? 'QQ' : '微信',
      LoginSource.bilibili => '哔哩哔哩',
    };
    final retry =
        login.phase == QrPhase.expired || login.phase == QrPhase.failed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(
            '扫码登录${afterChinese(platformName(source))}',
            style: AlistenTypography.title.copyWith(color: colors.onGlass),
          ),
        ),
        if (source == LoginSource.qq) ...[
          const SizedBox(height: AlistenSpacing.md),
          Semantics(
            container: true,
            label: '扫码方式',
            child: SegmentedPills<QqLoginType>(
              segments: const [
                PillSegment(value: QqLoginType.qq, label: 'QQ 扫码'),
                PillSegment(value: QqLoginType.wx, label: '微信扫码'),
              ],
              selected: login.qqType,
              onChanged: (type) {
                if (type != login.qqType) {
                  unawaited(_login.start(qqType: type));
                }
              },
            ),
          ),
        ],
        const SizedBox(height: AlistenSpacing.lg),
        Center(child: _QrCode(login: login)),
        const SizedBox(height: AlistenSpacing.md),
        Semantics(
          liveRegion: true,
          child: Text(
            login.statusText,
            textAlign: TextAlign.center,
            style: AlistenTypography.bodyStrong.copyWith(color: colors.onGlass),
          ),
        ),
        if (login.scanning) ...[
          const SizedBox(height: AlistenSpacing.xxs),
          Text(
            '剩余 ${login.remainingSeconds} 秒',
            textAlign: TextAlign.center,
            style: muted,
          ),
        ],
        const SizedBox(height: AlistenSpacing.lg),
        if (retry)
          PillButton(
            label: '重新获取',
            icon: Icons.refresh_rounded,
            expand: true,
            onPressed: () => unawaited(_login.start()),
          )
        else
          PillButton(
            label: '保存到相册',
            icon: Icons.download_rounded,
            expand: true,
            busy: _saving,
            onPressed: image != null && login.scanning
                ? () => unawaited(_save())
                : null,
          ),
        const SizedBox(height: AlistenSpacing.md),
        for (final step in [
          '1. 点“保存到相册”。',
          '2. 打开${afterChinese(scanApp)}，进入“扫一扫”。',
          '3. 在扫一扫里选择相册中的这张二维码。',
        ])
          Padding(
            padding: const EdgeInsets.only(top: AlistenSpacing.xxs),
            child: Text(step, style: muted),
          ),
      ],
    );
  }
}

class _QrCode extends StatelessWidget {
  const _QrCode({required this.login});

  final QrLoginState login;

  @override
  Widget build(BuildContext context) {
    final colors = AlistenColors.of(context);
    final image = login.image;
    if (image != null && login.scanning) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: AlistenColors.scanSurface,
          borderRadius: BorderRadius.circular(AlistenRadii.sm),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AlistenSpacing.sm),
          child: SizedBox.square(
            dimension: AlistenSizes.qrCode,
            child: Image.memory(
              image,
              gaplessPlayback: true,
              semanticLabel: '登录二维码',
              filterQuality: FilterQuality.none,
              errorBuilder: (context, error, stackTrace) => const Center(
                child: Icon(
                  Icons.broken_image_rounded,
                  size: AlistenSizes.iconLg,
                  color: AlistenColors.scanInk,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final placeholder = switch (login.phase) {
      QrPhase.starting => BusyIndicator(
        size: AlistenSizes.iconLg,
        color: colors.onGlass,
      ),
      QrPhase.success => Icon(
        Icons.check_circle_rounded,
        size: AlistenSizes.iconLg,
        color: colors.success,
      ),
      QrPhase.failed => Icon(
        Icons.error_rounded,
        size: AlistenSizes.iconLg,
        color: colors.danger,
      ),
      _ => Icon(
        Icons.timer_off_rounded,
        size: AlistenSizes.iconLg,
        color: colors.onGlassMuted,
      ),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.glassFill,
        borderRadius: BorderRadius.circular(AlistenRadii.sm),
        border: Border.all(color: colors.glassStroke),
      ),
      child: SizedBox.square(
        dimension: AlistenSizes.qrCode + 2 * AlistenSpacing.sm,
        child: Center(child: ExcludeSemantics(child: placeholder)),
      ),
    );
  }
}
