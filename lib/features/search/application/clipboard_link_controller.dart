import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/features/search/application/invite_link.dart';
import 'package:alisten/features/search/application/shared_link.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 读取剪贴板内容可能让系统提示用户，所以只在剪贴板变化之后才读取。
abstract interface class ClipboardSource {
  /// 剪贴板内容每次变化都会改变，获取它无需读取内容。剪贴板上没有文本或平台
  /// 不提供时为 null，此时不读取剪贴板。
  Future<int?> stamp();

  Future<String?> read();
}

final clipboardSourceProvider = Provider<ClipboardSource>((ref) {
  throw UnimplementedError('clipboardSource 未注入');
});

// 只有文本中有链接时才保留文本本身。
typedef _ClipboardRead = ({int stamp, String? text, ResolvedShare? share});

// 只保存在内存中：同一内容只读取一次，换房间后按新房间重新判断；同一文本只
// 提示一次。
final _clipboardMemoryProvider =
    NotifierProvider<
      _ClipboardMemory,
      ({_ClipboardRead? read, String? offered})
    >(_ClipboardMemory.new);

final class _ClipboardMemory
    extends Notifier<({_ClipboardRead? read, String? offered})> {
  @override
  ({_ClipboardRead? read, String? offered}) build() =>
      (read: null, offered: null);

  void read(_ClipboardRead read) =>
      state = (read: read, offered: state.offered);

  void offer(String text) => state = (read: state.read, offered: text);
}

final clipboardLinkControllerProvider =
    NotifierProvider.autoDispose<ClipboardLinkController, ResolvedShare?>(
      ClipboardLinkController.new,
    );

final class ClipboardLinkController extends Notifier<ResolvedShare?> {
  @override
  ResolvedShare? build() => null;

  Future<void> check() async {
    final clipboard = ref.read(clipboardSourceProvider);
    final stamp = await clipboard.stamp();
    if (!ref.mounted || stamp == null) return;
    final memory = ref.read(_clipboardMemoryProvider.notifier);
    var read = ref.read(_clipboardMemoryProvider).read;
    if (read?.stamp != stamp) {
      final text = await clipboard.read();
      final invite = text == null
          ? null
          : await ref.read(inviteRecognizerProvider).recognize(text);
      final share = text == null || invite != null
          ? null
          : await ref.read(linkResolverProvider).resolve(text);
      // 点歌页已在等待期间关闭，用户没看到这次的内容，下次重新读取。
      if (!ref.mounted) return;
      read = (stamp: stamp, text: share == null ? null : text, share: share);
      if (invite != null &&
          text != null &&
          ref.read(_clipboardMemoryProvider).offered != text) {
        final otherRoom = ref
            .read(inviteOfferControllerProvider.notifier)
            .offerPassively(invite);
        if (otherRoom == null) {
          memory.offer(text);
        } else {
          final link = ref.read(linkResolverProvider).recognize(text);
          read = (
            stamp: stamp,
            text: text,
            share: link?.asRoomLink(otherRoom: otherRoom),
          );
        }
      }
      memory.read(read);
    }
    final (:text, :share, stamp: _) = read!;
    if (text == null || share == null) return;
    if (ref.read(_clipboardMemoryProvider).offered == text) return;
    final kind = ref.read(roomControllerProvider).snapshot?.room.kind;
    // 链接曲目能否点取决于房间类型：类型未知时不做判断，留给下一次检查。
    final link = share.track?.source == TrackSource.link;
    if (share.otherRoom == null &&
        (unpickableReason(share, kind) != null || (link && kind == null))) {
      return;
    }
    memory.offer(text);
    state = share;
  }

  void dismiss() {
    if (ref.mounted) state = null;
  }
}
