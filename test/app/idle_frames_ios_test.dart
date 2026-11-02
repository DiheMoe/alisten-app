import 'package:alisten/app/room/room_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/search/search_test_doubles.dart';
import 'idle_frames.dart';

void main() {
  testWidgets('a focused search field does not draw every frame', (
    tester,
  ) async {
    await SearchPage.open(tester);
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(Theme.of(focused!).platform, TargetPlatform.iOS);

    expect(await idleFrames(tester), lessThanOrEqualTo(periodicFrames));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('a focused chat field does not draw every frame', (tester) async {
    final room = await enterBusyRoom(tester);
    room.router.go(RoomMode.chat.routeIn('listen'));
    await room.settle();
    await tester.tap(find.byType(TextField));
    await room.settle();
    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused, isNotNull);
    expect(Theme.of(focused!).platform, TargetPlatform.iOS);

    expect(await idleFrames(tester), lessThanOrEqualTo(roomPageFrames));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
