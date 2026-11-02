import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final class PackageLicenses {
  const PackageLicenses(this.package, this.licenses);

  final String package;
  final List<LicenseEntry> licenses;
}

List<PackageLicenses> groupLicensesByPackage(Iterable<LicenseEntry> entries) {
  final byPackage = <String, List<LicenseEntry>>{};
  for (final entry in entries) {
    for (final package in entry.packages) {
      (byPackage[package] ??= []).add(entry);
    }
  }
  final packages = byPackage.keys.toList()
    ..sort((a, b) {
      final order = a.toLowerCase().compareTo(b.toLowerCase());
      return order != 0 ? order : a.compareTo(b);
    });
  return [
    for (final package in packages)
      PackageLicenses(package, byPackage[package]!),
  ];
}

// 许可全文超过 1 MB，离开许可页后要释放。
final openSourceLicensesProvider =
    AsyncNotifierProvider.autoDispose<
      OpenSourceLicenses,
      List<PackageLicenses>
    >(OpenSourceLicenses.new, retry: (_, _) => null);

const _readTimeout = Duration(seconds: 15);

/// 依赖的许可由 Flutter 工具在构建时收集；内置字体和 commons-imaging 的许可
/// 须由 `registerBundledLicenses` 登记才会列出。
class OpenSourceLicenses extends AsyncNotifier<List<PackageLicenses>> {
  @override
  Future<List<PackageLicenses>> build() async {
    final entries = await LicenseRegistry.licenses.toList().timeout(
      _readTimeout,
    );
    return groupLicensesByPackage(entries);
  }
}
