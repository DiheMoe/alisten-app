// 带超时和失速检测的流式播放依赖 just_audio 的实验性音源 API。
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';

/// dio 的接收超时按数据块计算，用作失速检测，不限制整首曲目的播放时长。
final class AudioStreamFactory {
  factory AudioStreamFactory(
    Dio dio, {
    Duration connectTimeout = const Duration(seconds: 10),
    Duration stallTimeout = const Duration(seconds: 20),
  }) {
    return AudioStreamFactory._(dio, connectTimeout, stallTimeout);
  }

  AudioStreamFactory._(this._dio, this._connectTimeout, this._stallTimeout);

  final Dio _dio;
  final Duration _connectTimeout;
  final Duration _stallTimeout;
  final Set<CancelToken> _active = {};

  StreamAudioSource source(Uri uri) => _DioStreamAudioSource(uri, this);

  void cancelAll() {
    for (final token in _active) {
      token.cancel();
    }
    _active.clear();
  }

  void close() {
    cancelAll();
    _dio.close(force: true);
  }

  // just_audio 的代理会打印音源抛出的错误，因此错误中不得包含签名播放地址，
  // 也不得包装含该地址的错误对象。
  Future<StreamAudioResponse> _open(Uri uri, int? start, int? end) async {
    final token = CancelToken();
    _active.add(token);
    final Response<ResponseBody> response;
    try {
      response = await _dio.getUri<ResponseBody>(
        uri,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          connectTimeout: _connectTimeout,
          receiveTimeout: _stallTimeout,
          validateStatus: (status) => status == 200 || status == 206,
          headers: {
            if (start != null || end != null)
              'range': 'bytes=${start ?? 0}-${end == null ? '' : end - 1}',
          },
        ),
      );
    } on Object catch (error) {
      _active.remove(token);
      throw AudioStreamException.from(error);
    }
    final headers = response.headers;
    final partial = response.statusCode == 206;
    final contentLength = int.tryParse(headers.value('content-length') ?? '');
    final contentRange = headers.value('content-range');
    final range = contentRange == null
        ? null
        : RegExp(r'bytes (\d+)-(\d+)/(\d+|\*)').firstMatch(contentRange);
    final int? sourceLength;
    final int offset;
    if (partial) {
      sourceLength = range == null || range.group(3) == '*'
          ? null
          : int.tryParse(range.group(3)!);
      offset = range == null ? start ?? 0 : int.parse(range.group(1)!);
    } else {
      // 服务端忽略了 Range，返回完整媒体。
      sourceLength = contentLength;
      offset = 0;
    }
    return StreamAudioResponse(
      rangeRequestsSupported:
          partial ||
          (headers.value('accept-ranges')?.contains('bytes') ?? false),
      sourceLength: sourceLength,
      contentLength: contentLength ?? _remaining(sourceLength, offset, end),
      contentType: headers.value('content-type') ?? 'application/octet-stream',
      offset: offset,
      stream: _body(response.data!.stream, token),
    );
  }

  static int? _remaining(int? sourceLength, int offset, int? end) {
    final stop = end ?? sourceLength;
    return stop == null ? null : stop - offset;
  }

  Stream<List<int>> _body(Stream<Uint8List> source, CancelToken token) {
    StreamSubscription<Uint8List>? subscription;
    late final StreamController<List<int>> body;
    void finish() => _active.remove(token);
    body = StreamController<List<int>>(
      onListen: () {
        subscription = source.listen(
          body.add,
          onError: (Object error) {
            finish();
            body.addError(AudioStreamException.from(error));
          },
          onDone: () {
            finish();
            unawaited(body.close());
          },
          cancelOnError: true,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () {
        finish();
        token.cancel();
        return subscription?.cancel();
      },
    );
    return body.stream;
  }
}

/// 只描述失败方式，从不包含地址。
final class AudioStreamException implements Exception {
  const AudioStreamException(this.reason, {this.statusCode});

  factory AudioStreamException.from(Object error) {
    return switch (error) {
      DioException(:final type, :final response) => AudioStreamException(
        type.name,
        statusCode: response?.statusCode,
      ),
      _ => AudioStreamException(error.runtimeType.toString()),
    };
  }

  final String reason;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' $statusCode';
    return 'AudioStreamException: $reason$status';
  }
}

final class _DioStreamAudioSource extends StreamAudioSource {
  _DioStreamAudioSource(this.uri, this.factory);

  final Uri uri;
  final AudioStreamFactory factory;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) {
    return factory._open(uri, start, end);
  }
}
