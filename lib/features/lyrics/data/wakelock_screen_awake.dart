import 'package:alisten/features/lyrics/application/screen_awake.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final class WakelockScreenAwake implements ScreenAwakeDevice {
  const WakelockScreenAwake();

  @override
  Future<void> setKeptOn({required bool on}) {
    return WakelockPlus.toggle(enable: on);
  }
}
