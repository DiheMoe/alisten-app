import 'dart:async';

import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/room/room.dart';
import 'package:alisten/domain/server/invite_link.dart';
import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/pickable_link.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LinkPlatform { netease, qq, bilibili, web }

enum LinkProblem {
  /// 网易云或 QQ 音乐上歌单、专辑、歌手等非单曲页面。
  notSong,

  /// 网易云或 QQ 音乐的短链接没能展开，或者认不出歌曲页面上是哪首歌。
  unrecognized,

  /// 任意服务器的 Alisten 房间链接。
  roomLink,
}

/// 文本中第一个链接的识别结果。
@immutable
final class ResolvedShare {
  const ResolvedShare({
    required this.link,
    required this.platform,
    this.track,
    this.title,
    this.problem,
    this.unfollowed = false,
    this.otherRoom,
  });

  /// 已规范化。
  final String link;
  final LinkPlatform platform;

  /// 网易云或 QQ 音乐的歌，或链接本身（B 站链接由服务端识别成 B 站音源的歌）。
  /// 点不了时为 null，原因见 [problem]。
  final Track? track;

  /// 分享文本中的歌名，只用于显示。
  final String? title;
  final LinkProblem? problem;

  /// 尚不知道指向什么：网易云或 QQ 音乐的短链接还没有经
  /// [LinkResolver.resolve] 展开，或形如房间的链接还没有询问它的服务器。
  final bool unfollowed;

  /// 当前服务器上另一个房间的路由，由用户点按进入；只在 [problem] 为
  /// [LinkProblem.roomLink] 时可能存在。
  final String? otherRoom;

  ResolvedShare asRoomLink({String? otherRoom}) {
    return ResolvedShare(
      link: link,
      platform: platform,
      title: title,
      problem: LinkProblem.roomLink,
      otherRoom: otherRoom,
    );
  }
}

abstract interface class LinkResolver {
  /// 不联网识别，音乐平台的短链接标为 [ResolvedShare.unfollowed]。文本里没有
  /// http(s) 链接时返回 null。
  ResolvedShare? recognize(String text);

  /// 联网展开短链接，文本里没有 http(s) 链接时返回 null。不抛出：短链接展开
  /// 失败或因 [cancel] 完成而放弃时，结果为 [LinkProblem.unrecognized]。
  Future<ResolvedShare?> resolve(String text, {Future<void>? cancel});
}

/// 其他应用分享来的文本，包括启动本应用的分享。
abstract interface class SharedTextSource {
  Stream<String> get texts;
}

final linkResolverProvider = Provider<LinkResolver>((ref) {
  throw UnimplementedError('linkResolver 未注入');
});

final sharedTextSourceProvider = Provider<SharedTextSource>((ref) {
  throw UnimplementedError('sharedTextSource 未注入');
});

const typedShortLinkDelay = Duration(milliseconds: 400);

/// 普通链接立即识别；短链接和形如房间的链接等输入停顿后再联网确认，是邀请时
/// 改为房间链接并提供邀请。输入框内容一变就放弃，并取消进行中的请求。
final typedLinkProvider = NotifierProvider.autoDispose
    .family<TypedLinkController, ResolvedShare?, String>(
      TypedLinkController.new,
    );

final class TypedLinkController extends Notifier<ResolvedShare?> {
  TypedLinkController(this._text);

  final String _text;

  @override
  ResolvedShare? build() {
    final resolver = ref.watch(linkResolverProvider);
    final share = resolver.recognize(_text);
    if (share == null) return null;
    final maybeInvite =
        parseInviteLink(
          share.link,
          allowCleartext: ref
              .read(buildEnvironmentProvider)
              .allowsCleartextServers,
        ) !=
        null;
    if (!maybeInvite && !share.unfollowed) return share;
    final cancel = Completer<void>();
    final delay = Timer(
      typedShortLinkDelay,
      () => unawaited(
        _settle(resolver, share, cancel.future, maybeInvite: maybeInvite),
      ),
    );
    ref.onDispose(() {
      delay.cancel();
      if (!cancel.isCompleted) cancel.complete();
    });
    if (!maybeInvite) return share;
    return ResolvedShare(
      link: share.link,
      platform: share.platform,
      title: share.title,
      unfollowed: true,
    );
  }

  Future<void> _settle(
    LinkResolver resolver,
    ResolvedShare share,
    Future<void> cancel, {
    required bool maybeInvite,
  }) async {
    if (maybeInvite) {
      final invite = await ref
          .read(inviteRecognizerProvider)
          .recognize(_text, cancel: cancel);
      if (!ref.mounted) return;
      if (invite != null) {
        final otherRoom = ref
            .read(inviteOfferControllerProvider.notifier)
            .offerPassively(invite);
        state = share.asRoomLink(otherRoom: otherRoom);
        return;
      }
      state = share;
    }
    if (!share.unfollowed) return;
    final followed = await resolver.resolve(_text, cancel: cancel);
    if (ref.mounted && followed != null) state = followed;
  }
}

const noLinkText = '分享的内容里没有链接';
const notSongText = '只支持单曲链接';
const unrecognizedText = '没能识别这个链接';
const ephemeralLinkText = '临时房间只能点 B 站链接';
const roomLinkText = '这是房间链接，不能用来点歌。';

/// 能点时返回 null。链接曲目能否点取决于房间类型，[kind] 未知时不给出原因。
String? unpickableReason(ResolvedShare share, RoomKind? kind) {
  switch (share.problem) {
    case LinkProblem.notSong:
      return notSongText;
    case LinkProblem.unrecognized:
      return unrecognizedText;
    case LinkProblem.roomLink:
      return roomLinkText;
    case null:
      break;
  }
  final track = share.track;
  if (track == null) return unrecognizedText;
  if (track.source != TrackSource.link || kind == null) return null;
  return pickableLink(share.link, kind) == null ? ephemeralLinkText : null;
}
