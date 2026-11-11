/// 按本地时间输出。天数用两个时刻的本地年月日构造 UTC 日期再相减，不受夏令时
/// 影响。[nowMs] 取列表最近一次读到的时间，跨过午夜重新读取后文字随之更新。
String formatPlaylistDate(int ms, int nowMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final days = _day(now) - _day(time);
  String two(int value) => value.toString().padLeft(2, '0');
  final clock = '${two(time.hour)}:${two(time.minute)}';
  if (days == 0) return '今天 $clock';
  if (days == 1) return '昨天 $clock';
  if (time.year == now.year) return '${time.month}月${time.day}日';
  return '${time.year}年${time.month}月${time.day}日';
}

int _day(DateTime local) =>
    DateTime.utc(local.year, local.month, local.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;
