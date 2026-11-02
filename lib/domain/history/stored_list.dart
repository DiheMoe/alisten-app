import 'dart:convert';

List<Object?> readStoredList(String? stored) {
  try {
    final value = jsonDecode(stored ?? '[]');
    return value is List<Object?> ? value : const [];
  } on FormatException {
    return const [];
  }
}
