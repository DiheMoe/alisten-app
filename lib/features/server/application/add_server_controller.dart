import 'package:alisten/core/api/app_config.dart';
import 'package:alisten/domain/server/server_origin.dart';
import 'package:alisten/domain/server/server_profile.dart';
import 'package:alisten/features/server/application/server_directory.dart';
import 'package:alisten/features/server/application/server_probe.dart';
import 'package:alisten/features/server/application/server_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const serverAddressMalformedText = '请输入服务器地址，例如 https://example.com';
const serverAddressCleartextText = '只支持 https 地址';
const serverAlreadySavedText = '已经添加过这个服务器，可以在列表中切换';

final class AddServerState {
  const AddServerState({this.checking = false, this.found, this.problem});

  final bool checking;
  final ServerProfile? found;
  final String? problem;
}

final addServerControllerProvider =
    NotifierProvider.autoDispose<AddServerController, AddServerState>(
      AddServerController.new,
    );

final class AddServerController extends Notifier<AddServerState> {
  int _attempt = 0;

  @override
  AddServerState build() => const AddServerState();

  Future<void> check(String input) async {
    final attempt = ++_attempt;
    final environment = ref.read(buildEnvironmentProvider);
    final String origin;
    switch (parseServerOrigin(
      input,
      allowCleartext: environment.allowsCleartextServers,
    )) {
      case InvalidOrigin(problem: OriginProblem.malformed):
        state = const AddServerState(problem: serverAddressMalformedText);
        return;
      case InvalidOrigin(problem: OriginProblem.cleartext):
        state = const AddServerState(problem: serverAddressCleartextText);
        return;
      case ValidOrigin(origin: final valid):
        origin = valid;
    }
    if (ref.read(serverDirectoryProvider).byId(serverIdFor(origin)) != null) {
      state = const AddServerState(problem: serverAlreadySavedText);
      return;
    }
    state = const AddServerState(checking: true);
    final result = await ref.read(serverProbeProvider).probe(origin);
    if (!ref.mounted || attempt != _attempt) return;
    state = switch (result) {
      ProbeSucceeded(:final brandName) => AddServerState(
        found: ServerProfile(
          origin: origin,
          brandName: brandName,
          addedAtMs: ref.read(serverNowProvider)(),
        ),
      ),
      ProbeFailed(:final failure) => AddServerState(
        problem: probeFailureText(failure),
      ),
    };
  }

  void edited() {
    _attempt++;
    state = const AddServerState();
  }
}
