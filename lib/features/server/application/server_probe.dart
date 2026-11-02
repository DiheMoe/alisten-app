import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ProbeFailure { unreachable, notAlisten, incompatible, unverified }

String probeFailureText(ProbeFailure failure) {
  return switch (failure) {
    ProbeFailure.unreachable => '连不上这个服务器',
    ProbeFailure.notAlisten => '这不是 Alisten 服务器',
    ProbeFailure.incompatible => '这个服务器与当前 App 版本不兼容',
    ProbeFailure.unverified => '无法确认这个服务器的版本',
  };
}

sealed class ProbeResult {
  const ProbeResult();
}

final class ProbeSucceeded extends ProbeResult {
  const ProbeSucceeded({required this.origin, required this.brandName});

  final String origin;
  final String brandName;

  @override
  bool operator ==(Object other) {
    return other is ProbeSucceeded &&
        other.origin == origin &&
        other.brandName == brandName;
  }

  @override
  int get hashCode => Object.hash(origin, brandName);
}

final class ProbeFailed extends ProbeResult {
  const ProbeFailed(this.failure);

  final ProbeFailure failure;

  @override
  bool operator ==(Object other) {
    return other is ProbeFailed && other.failure == failure;
  }

  @override
  int get hashCode => failure.hashCode;
}

/// `origin` 必须已规整。各方法都不抛出，也不创建成员或留下会话。
abstract interface class ServerProbe {
  /// 先 [probeSite]，确认是 Alisten 之后再 [probeHandshake]。
  Future<ProbeResult> probe(String origin);

  /// 只请求 `/api/site`，失败只会是 `unreachable` 或 `notAlisten`。[timeout]
  /// 为 null 时用实现的默认时限；[cancel] 完成时中止请求，结果为
  /// `unreachable`。
  Future<ProbeResult> probeSite(
    String origin, {
    Duration? timeout,
    Future<void>? cancel,
  });

  /// 只做 WebSocket 握手的版本试探，版本兼容时返回 null。[cancel] 完成时中止
  /// 试探并关闭连接，结果为 `unverified`。
  Future<ProbeFailure?> probeHandshake(String origin, {Future<void>? cancel});

  /// 只请求 `/api/site`，任何失败都返回 null。
  Future<String?> fetchBrandName(String origin);
}

final serverProbeProvider = Provider<ServerProbe>((ref) {
  throw UnimplementedError('serverProbe 未注入');
});
