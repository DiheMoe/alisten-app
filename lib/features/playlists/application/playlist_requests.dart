import 'dart:async';

import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/mutation/mutation_result.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/playlists/application/playlist_api.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const unexpectedFailureText = '出了点问题，请稍后再试。';
const _unauthorized = 'UNAUTHORIZED';
const _forbidden = 'FORBIDDEN';
const _logSource = 'playlists';

sealed class Fetched<T> {
  const Fetched();
}

final class FetchedValue<T> extends Fetched<T> {
  const FetchedValue(this.value);

  final T value;
}

final class FetchFailed<T> extends Fetched<T> {
  const FetchFailed(this.message, {this.code});

  final String message;
  final String? code;
}

/// memberToken 被拒，身份已经按被拒处理。读取不提示 [message]：会话代号的变化
/// 会让歌单状态重新开始。
final class FetchRefused<T> extends Fetched<T> {
  const FetchRefused(this.message);

  final String message;
}

/// 一次操作发出的全部请求。创建时一次性取定服务器的 API、凭据和身份控制器：
/// 即使途中换了服务器，请求、memberToken 和被拒之后的处理都留在原来的服务器上。
/// 都不抛出。
final class PlaylistRequests {
  PlaylistRequests(Ref ref)
    : _container = ref.container,
      _credentials = ref.read(credentialStoreProvider),
      _api = ref.read(playlistApiProvider),
      _identity = ref.read(identityControllerProvider.notifier);

  final ProviderContainer _container;
  final CredentialStore _credentials;
  final PlaylistApi _api;
  final IdentityController _identity;

  /// 结果未知时返回 [MutationUnknown]，调用方负责重新读取，不重发。换了服务器
  /// 时返回 [MutationNotSent]：结果属于原来的服务器，文字说明它在那里是否生效。
  Future<MutationResult<T>> change<T>(
    Future<T> Function(PlaylistApi api) send,
  ) async {
    final rejectedToken = await _credentials.readMemberTokenOrNull();
    // 用户已经离开了这个服务器，不再向它发出变更。
    if (serverChanged) return MutationNotSent<T>(serverChangedNotice);
    try {
      final value = await send(_api);
      if (serverChanged) return MutationNotSent<T>(doneOnOldServerText);
      return MutationSucceeded(value);
    } on ApiException catch (error) {
      if (error.code == _unauthorized) {
        return MutationFailed(
          _unauthorized,
          await _identity.recoverFromRefusal(_credentials, rejectedToken),
        );
      }
      if (serverChanged) {
        return MutationNotSent<T>(
          error.answerLost ? unsureOnOldServerText : serverChangedNotice,
        );
      }
      if (_notSent(error) case final message?) return MutationNotSent(message);
      if (error.code == _forbidden) _refreshIdentity();
      if (error.answerLost) return MutationUnknown<T>();
      return MutationFailed(error.code, error.message);
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'request ended unexpectedly',
        type: '${error.runtimeType}',
      );
      if (serverChanged) return MutationNotSent<T>(unsureOnOldServerText);
      return MutationUnknown<T>();
    }
  }

  Future<Fetched<T>> fetch<T>(Future<T> Function(PlaylistApi api) send) async {
    final rejectedToken = await _credentials.readMemberTokenOrNull();
    try {
      return FetchedValue(await send(_api));
    } on ApiException catch (error) {
      if (error.code == _unauthorized) {
        return FetchRefused(
          await _identity.recoverFromRefusal(_credentials, rejectedToken),
        );
      }
      if (_notSent(error) case final message?) {
        return FetchFailed(message, code: error.code);
      }
      if (error.code == _forbidden) _refreshIdentity();
      return FetchFailed(error.message, code: error.code);
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'read ended unexpectedly',
        type: '${error.runtimeType}',
      );
      return FetchFailed<T>(unexpectedFailureText);
    }
  }

  // 换服务器时 playlistApiProvider 换成新的实例。发起时的 Ref 在控制器重建或
  // 释放之后就不能再读取，所以从容器读取。排着的编辑可能在容器释放之后才轮到，
  // 这时读取抛出 StateError：什么都不该再发出，当作已经换了服务器。
  bool get serverChanged {
    try {
      return !identical(_container.read(playlistApiProvider), _api);
    } on StateError {
      return true;
    }
  }

  static String? _notSent(ApiException error) {
    if (error.rateLimited) return rateLimitedText(error);
    if (error.code == LocalErrorCodes.noToken) return error.message;
    return null;
  }

  // 本机以为是账号，服务端却当作游客：重新读一次身份，不等待。
  void _refreshIdentity() {
    unawaited(
      _identity.restore().then<void>(
        (_) {},
        onError: (Object error) => AppLog.debug(
          _logSource,
          'identity not refreshed',
          code: error is ApiException ? error.code : null,
        ),
      ),
    );
  }
}
