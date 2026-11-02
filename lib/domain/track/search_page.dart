final class SearchPage<T> {
  const SearchPage({required this.items, required this.total});

  final List<T> items;
  final int total;
}
