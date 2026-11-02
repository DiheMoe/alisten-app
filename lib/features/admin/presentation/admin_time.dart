String formatAdminTime(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs);
  String two(int value) => value.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
