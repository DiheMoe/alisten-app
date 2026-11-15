// 带超时和失速检测的流式播放依赖 just_audio 的实验性音源 API。
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:math' as math;
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

  /// 预加载取回的开头大小：320 kbps 约 26 秒，无损也够起播。
  static const preloadBytes = 1 << 20;

  final Dio _dio;
  final Duration _connectTimeout;
  final Duration _stallTimeout;
  final Set<CancelToken> _active = {};
  _Preload? _preload;

  /// 为 [uri] 预加载好的开头由这个音源接手；还没取完的预加载作废。
  StreamAudioSource source(Uri uri) {
    final preload = _preload;
    _Head? head;
    if (preload != null && preload.uri == uri) {
      _preload = null;
      head = preload.head;
      if (head == null) preload.token.cancel();
    }
    return _DioStreamAudioSource(uri, this, head);
  }

  /// 不受 [cancelAll] 影响：换音源时正在取的下一首开头仍然有用。
  void preload(Uri uri) {
    if (_preload?.uri == uri) return;
    dropPreload();
    final preload = _preload = _Preload(uri);
    unawaited(
      _fetchHead(uri, preload.token).then((head) {
        if (identical(_preload, preload)) preload.head = head;
      }),
    );
  }

  void dropPreload() {
    _preload?.token.cancel();
    _preload = null;
  }

  void cancelAll() {
    for (final token in _active) {
      token.cancel();
    }
    _active.clear();
  }

  void close() {
    cancelAll();
    dropPreload();
    _dio.close(force: true);
  }

  // 只收能接着按范围续取的开头，否则无法和之后的数据拼起来。
  Future<_Head?> _fetchHead(Uri uri, CancelToken token) async {
    try {
      final (response, location) = await _open(
        uri,
        0,
        preloadBytes,
        token: token,
      );
      final sourceLength = response.sourceLength;
      if (response.offset != 0 ||
          sourceLength == null ||
          !response.rangeRequestsSupported) {
        token.cancel();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length >= preloadBytes) break;
      }
      final all = bytes.takeBytes();
      final length = math.min(all.length, math.min(preloadBytes, sourceLength));
      if (length == 0 || (length < preloadBytes && length < sourceLength)) {
        return null;
      }
      return _Head(
        bytes: Uint8List.sublistView(all, 0, length),
        sourceLength: sourceLength,
        contentType: response.contentType,
        location: location,
      );
    } on Object {
      return null;
    }
  }

  // just_audio 的代理会打印音源抛出的错误，因此错误中不得包含签名播放地址，
  // 也不得包装含该地址的错误对象。返回的地址是跳转之后实际取数据的地址。
  // 传入 [token] 的请求不受 [cancelAll] 影响。
  Future<(StreamAudioResponse, Uri)> _open(
    Uri uri,
    int? start,
    int? end, {
    CancelToken? token,
  }) async {
    final cancel = token ?? CancelToken();
    if (token == null) _active.add(cancel);
    final Response<ResponseBody> response;
    try {
      response = await _dio.getUri<ResponseBody>(
        uri,
        cancelToken: cancel,
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
      _active.remove(cancel);
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
    final audio = StreamAudioResponse(
      rangeRequestsSupported:
          partial ||
          (headers.value('accept-ranges')?.contains('bytes') ?? false),
      sourceLength: sourceLength,
      contentLength: contentLength ?? _remaining(sourceLength, offset, end),
      contentType: headers.value('content-type') ?? 'application/octet-stream',
      offset: offset,
      stream: _body(response.data!.stream, cancel),
    );
    return (audio, uri.resolveUri(response.realUri));
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

/// 服务端的播放地址会跳转到音乐平台的限时地址。之后的分段请求（起播位置、seek、
/// 断流重连）直接发给跳转后的地址，否则每次都要经服务端重新解析，多等一两秒；
/// 限时地址失效时再经播放地址解析一次。
final class _DioStreamAudioSource extends StreamAudioSource {
  _DioStreamAudioSource(this.uri, this.factory, this._head)
    : _redirected = _head == null || _head.location == uri
          ? null
          : _head.location;

  final Uri uri;
  final AudioStreamFactory factory;
  final _Head? _head;
  Uri? _redirected;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final head = _head;
    final from = start ?? 0;
    if (head != null && from < head.bytes.length) {
      return _fromHead(head, from, end);
    }
    return _fetch(start, end);
  }

  // 开头直接从内存给出，之后的数据接着按范围请求。续取的必须是同一个文件，
  // 否则拼出来的音频是坏的。
  StreamAudioResponse _fromHead(_Head head, int start, int? end) {
    final stop = math.min(end ?? head.sourceLength, head.sourceLength);
    final inHead = math.min(stop, head.bytes.length);
    StreamSubscription<List<int>>? rest;
    var cancelled = false;
    late final StreamController<List<int>> body;
    Future<void> continueFromNetwork() async {
      try {
        final response = await _fetch(inHead, end);
        if (cancelled) {
          await response.stream.listen(null).cancel();
          return;
        }
        if (response.offset != inHead ||
            response.sourceLength != head.sourceLength) {
          await response.stream.listen(null).cancel();
          throw const AudioStreamException('changed');
        }
        rest = response.stream.listen(
          body.add,
          onError: body.addError,
          onDone: body.close,
          cancelOnError: true,
        );
      } on Object catch (error) {
        if (cancelled) return;
        body.addError(error);
        await body.close();
      }
    }

    body = StreamController<List<int>>(
      onListen: () {
        body.add(Uint8List.sublistView(head.bytes, start, inHead));
        if (inHead < stop) {
          unawaited(continueFromNetwork());
        } else {
          unawaited(body.close());
        }
      },
      onPause: () => rest?.pause(),
      onResume: () => rest?.resume(),
      onCancel: () {
        cancelled = true;
        return rest?.cancel();
      },
    );
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: head.sourceLength,
      contentLength: stop - start,
      offset: start,
      contentType: head.contentType,
      stream: body.stream,
    );
  }

  Future<StreamAudioResponse> _fetch(int? start, int? end) async {
    final redirected = _redirected;
    if (redirected != null) {
      try {
        return (await factory._open(redirected, start, end)).$1;
      } on AudioStreamException catch (error) {
        if (error.reason == DioExceptionType.cancel.name) rethrow;
        _redirected = null;
      }
    }
    final (response, location) = await factory._open(uri, start, end);
    if (location != uri) _redirected = location;
    return response;
  }
}

final class _Preload {
  _Preload(this.uri);

  final Uri uri;
  final token = CancelToken();
  _Head? head;
}

final class _Head {
  const _Head({
    required this.bytes,
    required this.sourceLength,
    required this.contentType,
    required this.location,
  });

  final Uint8List bytes;
  final int sourceLength;
  final String contentType;

  /// 跳转之后实际取数据的地址，续取时先用它。
  final Uri location;
}
