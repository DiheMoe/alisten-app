import 'dart:async';

import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/cover_art.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 队列页第一次划进来时才建，它的封面那时才去取图、解码，会一张张晚出来。
/// 这里在房间里就先把待播和排在前面的几首按队列行的大小备好。
class QueueCoverWarmup extends ConsumerStatefulWidget {
  const QueueCoverWarmup({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<QueueCoverWarmup> createState() => _QueueCoverWarmupState();
}

/// 大约是队列页一屏的行数。
const _ahead = 10;

List<String> _upcoming(RoomState room) {
  final snapshot = room.snapshot;
  if (snapshot == null) return const [];
  return [
    ?snapshot.pending,
    ...snapshot.items.take(_ahead),
  ].map((entry) => entry.meta.coverUrl).where((url) => url.isNotEmpty).toList();
}

class _QueueCoverWarmupState extends ConsumerState<QueueCoverWarmup> {
  final _warmed = <String>{};

  void _warm(List<String> urls) {
    for (final url in urls) {
      if (!_warmed.add(url)) continue;
      unawaited(precacheCoverArt(context, url, AlistenSizes.rowCover));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warm(_upcoming(ref.read(roomControllerProvider)));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      roomControllerProvider.select(_upcoming),
      (_, urls) => _warm(urls),
    );
    return widget.child;
  }
}
