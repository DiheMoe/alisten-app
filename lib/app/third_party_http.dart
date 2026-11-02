import 'dart:io';

import 'package:alisten/app/app_version.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 网易云国内 CDN 对 dart:io 默认的 `Dart/…` User-Agent 返回 403，
/// 因此改为表明应用自身。User-Agent 须设在 `HttpClient` 上：dart:io
/// 跟随重定向时会为新请求补回默认值，请求头里的值带不到 302 之后的 CDN。
Dio newThirdPartyDio() => Dio()
  ..httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..userAgent = appUserAgent,
  );
