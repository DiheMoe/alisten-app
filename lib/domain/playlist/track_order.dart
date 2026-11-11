/// 与服务端的 `playlist.Move` 规则相同：把 [moved] 按给出的先后收拢，放在
/// [before] 之前，没有 [before] 时放到最后。[moved] 里不在 [order] 中的忽略，重复
/// 的只算一次；都不在时原样返回，此时不检查 [before]。
List<String> moveTracks(
  List<String> order,
  Iterable<String> moved,
  String? before,
) {
  final moving = moved.toSet();
  if (before != null && moving.contains(before)) {
    throw ArgumentError.value(before, 'before', '不能是要移动的歌');
  }
  final present = order.toSet();
  final block = [
    for (final key in moving)
      if (present.contains(key)) key,
  ];
  if (block.isEmpty) return List.of(order);
  final rest = [
    for (final key in order)
      if (!moving.contains(key)) key,
  ];
  final at = before == null ? rest.length : rest.indexOf(before);
  if (at < 0) throw ArgumentError.value(before, 'before', '已经不在歌单里');
  return [...rest.take(at), ...block, ...rest.skip(at)];
}

/// 一次移动请求：把 [moved] 放到 [before] 之前，结果是 [order]。
final class MovePlan {
  const MovePlan({
    required this.order,
    required this.moved,
    required this.before,
  });

  final List<String> order;

  /// 按原来的先后。
  final List<String> moved;
  final String? before;
}

/// 把 [moved] 收拢成一段，放在其余的歌中第 [at] 首之前；[at] 不小于其余的首数时
/// 放到最后。顺序不变时返回 null，不必发请求。
MovePlan? moveTo(List<String> order, Set<String> moved, int at) {
  RangeError.checkNotNegative(at, 'at');
  final block = [
    for (final key in order)
      if (moved.contains(key)) key,
  ];
  if (block.isEmpty) return null;
  final rest = [
    for (final key in order)
      if (!moved.contains(key)) key,
  ];
  final before = at < rest.length ? rest[at] : null;
  final next = moveTracks(order, block, before);
  var unchanged = true;
  for (var index = 0; index < order.length; index++) {
    if (next[index] != order[index]) unchanged = false;
  }
  if (unchanged) return null;
  return MovePlan(order: next, moved: block, before: before);
}
