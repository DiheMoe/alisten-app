import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/server/invite_link.dart';
import 'package:alisten/domain/server/server_origin.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:alisten/features/server/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'invite';

// 形如房间的链接也可能只是 reddit 之类的网页，确认之前歌曲链接的识别要一直
// 等待。
const _siteProbeTimeout = Duration(seconds: 5);

/// 归类只在识别时成立，处理之前要用 [InviteRecognizer.refresh] 按此刻的当前
/// 服务器和目录重新归类。
sealed class InviteTarget {
  const InviteTarget({required this.link});

  /// 不含查询和片段。
  final InviteLink link;

  String get route => link.route;
}

final class InviteToCurrent extends InviteTarget {
  const InviteToCurrent({required super.link, required this.isActiveRoom});

  final bool isActiveRoom;
}

final class InviteToSaved extends InviteTarget {
  const InviteToSaved({required super.link, required this.server});

  final ServerProfile server;
}

final class InviteToNew extends InviteTarget {
  const InviteToNew({required super.link, required this.server});

  /// 尚未保存；只确认过网站是 Alisten，还没有检查协议版本。
  final ServerProfile server;
}

final inviteRecognizerProvider = Provider<InviteRecognizer>(
  InviteRecognizer.new,
);

final class InviteRecognizer {
  InviteRecognizer(this._ref);

  final Ref _ref;

  /// 不是邀请链接或未保存服务器的探测失败时返回 null，调用方继续按歌曲链接
  /// 识别。[cancel] 完成时中止探测。不抛出。
  Future<InviteTarget?> recognize(String text, {Future<void>? cancel}) async {
    try {
      final link = _ref.read(linkResolverProvider).recognize(text)?.link;
      if (link == null) return null;
      final environment = _ref.read(buildEnvironmentProvider);
      final invite = parseInviteLink(
        link,
        allowCleartext: environment.allowsCleartextServers,
      );
      if (invite == null) return null;
      return _classify(invite) ?? await _probe(invite, cancel: cancel);
    } on Object catch (error) {
      _failed(error);
      return null;
    }
  }

  /// 已不再是 Alisten 时返回 null。不抛出。
  Future<InviteTarget?> refresh(InviteTarget target) async {
    try {
      final local = _classify(target.link);
      if (local != null) return local;
      return switch (target) {
        InviteToNew() => target,
        // 已保存的服务器在等待期间被删除，重新添加时照样要检查协议版本。
        InviteToSaved(:final server) => InviteToNew(
          link: target.link,
          server: server,
        ),
        InviteToCurrent() => await _probe(target.link),
      };
    } on Object catch (error) {
      _failed(error);
      return null;
    }
  }

  // 默认服务器的网站可以不在 API 主机上（`ALISTEN_LINK_HOST`），两个主机上的
  // 房间链接都属于它。
  InviteTarget? _classify(InviteLink invite) {
    final directory = _ref.read(serverDirectoryProvider);
    final server =
        directory.byLinkAuthority(invite.authority) ??
        directory.byId(serverIdFor(invite.origin));
    if (invite.authority == _ref.read(appConfigProvider).linkHost ||
        server?.id == directory.currentId) {
      return InviteToCurrent(
        link: invite,
        isActiveRoom: _ref
            .read(roomControllerProvider.notifier)
            .names(invite.roomRef),
      );
    }
    if (server == null) return null;
    return InviteToSaved(link: invite, server: server);
  }

  Future<InviteTarget?> _probe(
    InviteLink invite, {
    Future<void>? cancel,
  }) async {
    final site = await _ref
        .read(serverProbeProvider)
        .probeSite(invite.origin, timeout: _siteProbeTimeout, cancel: cancel);
    if (!_ref.mounted) return null;
    switch (site) {
      case ProbeSucceeded(:final brandName):
        return InviteToNew(
          link: invite,
          server: ServerProfile(
            origin: invite.origin,
            brandName: brandName,
            addedAtMs: _ref.read(serverNowProvider)(),
          ),
        );
      case ProbeFailed(:final failure):
        AppLog.debug(_logSource, 'not an invite', outcome: failure);
        return null;
    }
  }

  void _failed(Object error) {
    AppLog.warn(
      _logSource,
      'invite not recognized',
      type: '${error.runtimeType}',
    );
  }

  /// 协议版本兼容时为 null。连接 WebSocket 比读取站点信息慢得多，所以只在用户
  /// 同意添加之后检查。[cancel] 完成时中止检查。
  Future<ProbeFailure?> checkVersion(
    InviteToNew invite, {
    Future<void>? cancel,
  }) {
    return _ref
        .read(serverProbeProvider)
        .probeHandshake(invite.server.origin, cancel: cancel);
  }
}

final class InviteOffer {
  const InviteOffer({required this.id, required this.target});

  /// 每次提供都递增，同一邀请提供两次也算两次。
  final int id;
  final InviteTarget target;
}

final inviteOfferControllerProvider =
    NotifierProvider<InviteOfferController, InviteOffer?>(
      InviteOfferController.new,
    );

final class InviteOfferController extends Notifier<InviteOffer?> {
  int _lastId = 0;

  @override
  InviteOffer? build() => null;

  void offer(InviteTarget target) {
    if (target case InviteToCurrent(isActiveRoom: true)) return;
    state = InviteOffer(id: ++_lastId, target: target);
  }

  /// 用于剪贴板和点歌页输入框等非用户主动打开的链接：已在房间里时不提供当前
  /// 服务器其他房间的邀请，因为打开它会退出正在听的房间，改为返回它的路由，由
  /// 用户点按进入。其余照常 [offer] 并返回 null。
  String? offerPassively(InviteTarget target) {
    if (target case InviteToCurrent(isActiveRoom: false)
        when ref.read(roomControllerProvider).activeRoomId != null) {
      return target.route;
    }
    offer(target);
    return null;
  }

  void dismiss(int id) {
    if (ref.mounted && state?.id == id) state = null;
  }
}
