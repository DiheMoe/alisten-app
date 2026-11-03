const _core = r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)';

final _tag = RegExp('^v$_core\$');

final _appVersion = RegExp('^$_core(?:-[^+]*)?(?:\\+.*)?\$');

/// 只比较主、次、修订三个数字。
final class ReleaseVersion {
  const ReleaseVersion(this.major, this.minor, this.patch);

  /// 只认正式版的 `vX.Y.Z`，带预发布后缀时返回 null。
  static ReleaseVersion? fromTag(String tag) => _parse(_tag.firstMatch(tag));

  /// `X.Y.Z+N` 中的构建号和预发布后缀都不参与比较。
  static ReleaseVersion? fromAppVersion(String version) {
    return _parse(_appVersion.firstMatch(version));
  }

  static ReleaseVersion? _parse(RegExpMatch? match) {
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return ReleaseVersion(major, minor, patch);
  }

  final int major;
  final int minor;
  final int patch;

  bool isNewerThan(ReleaseVersion other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    return patch > other.patch;
  }

  @override
  bool operator ==(Object other) {
    return other is ReleaseVersion &&
        other.major == major &&
        other.minor == minor &&
        other.patch == patch;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
