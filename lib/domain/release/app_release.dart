import 'package:alisten/domain/release/release_version.dart';

final class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final Uri downloadUrl;
}

final class AppRelease {
  const AppRelease({
    required this.tag,
    required this.notes,
    required this.page,
    required this.assets,
  });

  final String tag;

  /// 发布说明的纯文本，原样显示给用户。
  final String notes;

  final Uri page;
  final List<ReleaseAsset> assets;

  /// tag 不合格或是预发布版时为 null，不算新版本。
  ReleaseVersion? get version => ReleaseVersion.fromTag(tag);
}
