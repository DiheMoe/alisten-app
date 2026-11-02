import 'dart:async';

import 'package:alisten/features/admin/application/admin_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const adminCooldown = Duration(seconds: 30);
const adminFailuresBeforeCooldown = 3;

const _counted = {'UNAUTHORIZED', 'FORBIDDEN'};

final class AdminSignInState {
  const AdminSignInState({
    this.busy = false,
    this.error,
    this.cooldownSeconds = 0,
  });

  final bool busy;
  final String? error;
  final int cooldownSeconds;
}

final adminSignInControllerProvider =
    NotifierProvider.autoDispose<AdminSignInController, AdminSignInState>(
      AdminSignInController.new,
    );

// 冷却只防误触，不防猜测，离开 token 页再回来就重新计数。
final class AdminSignInController extends Notifier<AdminSignInState> {
  int _failures = 0;
  Timer? _cooldown;

  @override
  AdminSignInState build() {
    ref.onDispose(() => _cooldown?.cancel());
    return const AdminSignInState();
  }

  Future<bool> submit(String token) async {
    if (state.busy || state.cooldownSeconds > 0 || token.trim().isEmpty) {
      return false;
    }
    final session = ref.read(adminSessionProvider.notifier)..clearNotice();
    state = const AdminSignInState(busy: true);
    final AdminSignIn result;
    try {
      result = await session.signIn(token);
    } on AdminSessionEnded {
      if (ref.mounted) state = const AdminSignInState();
      return false;
    }
    if (!ref.mounted) return result is AdminSignedIn;
    switch (result) {
      case AdminSignedIn():
        _failures = 0;
        state = const AdminSignInState();
        return true;
      case AdminSignInRejected(:final code, :final message):
        if (_counted.contains(code)) _failures++;
        if (_failures >= adminFailuresBeforeCooldown) {
          _startCooldown(message);
        } else {
          state = AdminSignInState(error: message);
        }
        return false;
    }
  }

  void _startCooldown(String error) {
    state = AdminSignInState(
      error: error,
      cooldownSeconds: adminCooldown.inSeconds,
    );
    _cooldown?.cancel();
    _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = state.cooldownSeconds - 1;
      if (left <= 0) {
        timer.cancel();
        _failures = 0;
      }
      state = AdminSignInState(error: state.error, cooldownSeconds: left);
    });
  }
}
