import 'dart:async';

import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/application/account_failures.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _logSource = 'account';

final pairingNowProvider = Provider<int Function()>((ref) {
  return () => DateTime.now().millisecondsSinceEpoch;
});

sealed class PairingCodeState {
  const PairingCodeState();
}

final class PairingCodeLoading extends PairingCodeState {
  const PairingCodeLoading();
}

final class PairingCodeReady extends PairingCodeState {
  const PairingCodeReady(this.code, this.secondsLeft);

  final PairingCode code;

  /// 按设备时钟计算，只用于显示；配对码是否有效以服务端为准。
  final int secondsLeft;
}

final class PairingCodeExpired extends PairingCodeState {
  const PairingCodeExpired();
}

final class PairingCodeFailed extends PairingCodeState {
  const PairingCodeFailed();
}

final pairingCodeControllerProvider =
    NotifierProvider.autoDispose<PairingCodeController, PairingCodeState>(
      PairingCodeController.new,
    );

/// 配对码只保存在状态里，面板关闭时随控制器一起丢弃，不写日志。
final class PairingCodeController extends Notifier<PairingCodeState> {
  int _attempt = 0;
  Timer? _tick;

  @override
  PairingCodeState build() {
    ref.onDispose(() {
      _attempt++;
      _tick?.cancel();
    });
    return const PairingCodeLoading();
  }

  /// 失败时返回要提示的原因；成功、被新的一次取代或面板已经关闭时返回 null。
  Future<String?> generate() async {
    final attempt = ++_attempt;
    bool current() => ref.mounted && attempt == _attempt;
    _tick?.cancel();
    state = const PairingCodeLoading();
    // 面板关闭后控制器随之释放，那之后不能再读 provider。
    final identity = ref.read(identityControllerProvider.notifier);
    final credentials = ref.read(credentialStoreProvider);
    final api = ref.read(alistenApiProvider);
    final token = await credentials.readMemberTokenOrNull();
    final PairingCode code;
    try {
      code = await api.createPairingCode();
    } on ApiException catch (error) {
      final reason = await _reasonFor(error, identity, credentials, token);
      if (!current()) return null;
      state = const PairingCodeFailed();
      return reason;
    } on Object catch (error) {
      AppLog.warn(
        _logSource,
        'pairing code not created',
        type: '${error.runtimeType}',
      );
      if (current()) state = const PairingCodeFailed();
      return null;
    }
    if (current()) _show(code, attempt);
    return null;
  }

  void _show(PairingCode code, int attempt) {
    final seconds = _secondsLeft(code);
    if (seconds == 0) {
      state = const PairingCodeExpired();
      return;
    }
    state = PairingCodeReady(code, seconds);
    _tick = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (attempt != _attempt) {
        timer.cancel();
        return;
      }
      final left = _secondsLeft(code);
      if (left == 0) {
        timer.cancel();
        state = const PairingCodeExpired();
        return;
      }
      final shown = state;
      if (shown is! PairingCodeReady || shown.secondsLeft != left) {
        state = PairingCodeReady(code, left);
      }
    });
  }

  int _secondsLeft(PairingCode code) =>
      pairingSecondsLeft(code.expiresAtMs, ref.read(pairingNowProvider)());

  static Future<String> _reasonFor(
    ApiException error,
    IdentityController identity,
    CredentialStore credentials,
    String? token,
  ) async {
    if (error.rateLimited) return rateLimitedText(error);
    switch (error.code) {
      // 只有账号能生成配对码：本机以为是账号，其实已经是游客。
      case 'FORBIDDEN':
        refreshIdentity(identity);
        return error.message;
      case 'UNAUTHORIZED':
        return identity.recoverFromRefusal(credentials, token);
    }
    return error.message;
  }
}
