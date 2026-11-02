/// 变更请求不会自动重发：[MutationUnknown] 表示请求可能已生效、也可能没有，
/// 调用方必须重新读取权威状态，而不是再发一次。
sealed class MutationResult<T> {
  const MutationResult();
}

final class MutationSucceeded<T> extends MutationResult<T> {
  const MutationSucceeded(this.value);

  final T value;
}

/// 服务端明确拒绝了这次变更。
final class MutationFailed<T> extends MutationResult<T> {
  const MutationFailed(this.code, this.message);

  final String? code;

  final String message;
}

final class MutationUnknown<T> extends MutationResult<T> {
  const MutationUnknown();
}

/// 变更没有在当前房间生效：请求没有发出，或发给了已不再活跃的房间，
/// 不再跟踪其结果。
final class MutationNotSent<T> extends MutationResult<T> {
  const MutationNotSent(this.message);

  final String message;
}
