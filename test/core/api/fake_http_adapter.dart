import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

final class ConnectionRefused implements Exception {
  const ConnectionRefused();
}

final class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.path,
    required this.uri,
    required this.authorization,
    required this.headers,
    required this.contentType,
    required this.jsonBody,
  });

  final String method;
  final String path;
  final Uri uri;
  final String? authorization;
  final Map<String, Object?> headers;
  final String? contentType;
  final Object? jsonBody;
}

final class FakeHttpAdapter implements HttpClientAdapter {
  final List<RecordedRequest> requests = [];
  Future<ResponseBody> Function(RequestOptions options)? _handler;
  bool cancelled = false;

  void respond(int status, Object body) {
    respondRaw(status, jsonEncode(body), null);
  }

  /// [headers] 与默认的 JSON 内容类型合并，同名时以它为准。
  void respondRaw(
    int status,
    String body,
    String? statusMessage, {
    Map<String, List<String>> headers = const {},
  }) {
    _handler = (_) async => ResponseBody.fromString(
      body,
      status,
      statusMessage: statusMessage,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...headers,
      },
    );
  }

  /// [redirects] 是得到这个回复之前跟随的跳转，最后一条的地址即最终地址。
  void respondBytes(
    int status,
    List<int> bytes, {
    List<RedirectRecord> redirects = const [],
  }) {
    _handler = (_) async => ResponseBody.fromBytes(
      bytes,
      status,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
      },
      isRedirect: redirects.isNotEmpty,
    )..redirects = redirects;
  }

  void fail() {
    _handler = (_) async => throw const ConnectionRefused();
  }

  void neverRespond() {
    _handler = (options) {
      final completer = Completer<ResponseBody>();
      return completer.future;
    };
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = requestStream == null
        ? null
        : jsonDecode(await utf8.decoder.bind(requestStream).join());
    requests.add(
      RecordedRequest(
        method: options.method,
        path: options.path,
        uri: options.uri,
        authorization: options.headers['authorization'] as String?,
        headers: Map.of(options.headers),
        contentType: options.contentType,
        jsonBody: body,
      ),
    );
    unawaited(cancelFuture?.then((_) => cancelled = true));
    return _handler!(options);
  }

  @override
  void close({bool force = false}) {}
}
