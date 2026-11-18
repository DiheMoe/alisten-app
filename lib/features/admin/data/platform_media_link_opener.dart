import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/admin/application/media_link_opener.dart';
import 'package:url_launcher/url_launcher.dart';

final class PlatformMediaLinkOpener implements MediaLinkOpener {
  PlatformMediaLinkOpener({this._launch = launchUrl});

  final Future<bool> Function(Uri url, {LaunchMode mode}) _launch;

  @override
  Future<bool> open(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
      return false;
    }
    try {
      return await _launch(uri, mode: LaunchMode.externalApplication);
    } on Object catch (error) {
      AppLog.warn(
        'admin',
        'media link not opened',
        type: '${error.runtimeType}',
      );
      return false;
    }
  }
}
