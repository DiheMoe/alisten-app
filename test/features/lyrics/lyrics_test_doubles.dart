import 'package:alisten/features/lyrics/application/screen_awake.dart';

final class FakeScreenAwakeDevice implements ScreenAwakeDevice {
  final List<bool> requests = [];
  Error? failure;

  bool get keptOn => requests.isNotEmpty && requests.last;

  @override
  Future<void> setKeptOn({required bool on}) async {
    requests.add(on);
    if (failure case final failure?) throw failure;
  }
}
