import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/features/admin/application/qr_image_loader.dart';
import 'package:dio/dio.dart';

const _logSource = 'admin';

/// `data:` URI 就地解码，https 地址下载且不带 Referer，跳转的每一跳都必须是
/// https；其他地址（包括明文 http）一律不请求。地址不写入日志。
final class DioQrImageLoader implements QrImageLoader {
  DioQrImageLoader(
    this._dio, {
    this.timeout = const Duration(seconds: 15),
    this.maxBytes = 1 << 20,
  });

  final Dio _dio;
  final Duration timeout;
  final int maxBytes;

  @override
  Future<Uint8List> load(String qrImage) async {
    final bytes = switch (Uri.tryParse(qrImage)?.scheme) {
      'data' => _decode(qrImage),
      'https' => await _download(qrImage),
      _ => _unavailable('qr image address not accepted'),
    };
    if (bytes.isEmpty) _unavailable('qr image empty');
    return bytes;
  }

  Uint8List _decode(String qrImage) {
    try {
      return UriData.parse(qrImage).contentAsBytes();
    } on FormatException {
      _unavailable('qr image not decoded');
    }
  }

  Future<Uint8List> _download(String url) async {
    final cancel = CancelToken();
    var tooLarge = false;
    final Response<List<int>> response;
    try {
      response = await _dio
          .get<List<int>>(
            url,
            cancelToken: cancel,
            options: Options(responseType: ResponseType.bytes),
            // 长度未知时 total 为 -1。
            onReceiveProgress: (received, total) {
              if (tooLarge || (received <= maxBytes && total <= maxBytes)) {
                return;
              }
              tooLarge = true;
              cancel.cancel();
            },
          )
          .timeout(timeout);
    } on TimeoutException {
      cancel.cancel();
      _unavailable('qr image download timed out');
    } on DioException catch (error) {
      if (tooLarge) _unavailable('qr image too large');
      AppLog.debug(
        _logSource,
        'qr image not downloaded',
        code: error.response?.statusCode?.toString(),
        outcome: error.type,
      );
      throw const QrImageUnavailable();
    }
    // dart:io 会跟随跳转到明文 http，不受系统明文限制：只要有一跳是 http，
    // 中间人就能把后续跳转改到自己的地址，换上自己的登录二维码。Location 可能
    // 是相对地址，要按上一跳解析。
    var hop = response.requestOptions.uri;
    for (final redirect in response.redirects) {
      hop = hop.resolveUri(redirect.location);
      if (!hop.isScheme('https')) _unavailable('qr image redirected off https');
    }
    if (response.statusCode != 200) {
      AppLog.debug(
        _logSource,
        'qr image not downloaded',
        code: '${response.statusCode}',
      );
      throw const QrImageUnavailable();
    }
    final data = response.data ?? const [];
    // 取消可能晚于完整响应到达，所以再检查一次。
    if (data.length > maxBytes) _unavailable('qr image too large');
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  static Never _unavailable(String event) {
    AppLog.debug(_logSource, event);
    throw const QrImageUnavailable();
  }
}
