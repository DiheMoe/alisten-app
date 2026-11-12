import 'package:alisten/domain/track/track.dart';
import 'package:alisten/features/playlists/presentation/save_platform_playlist_button.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../playlists_page_harness.dart';
import '../playlists_test_doubles.dart';

void main() {
  late FakePlaylistApi server;
  late List<(ToastKind, String)> notices;
  late int accountOpened;

  setUp(() {
    server = FakePlaylistApi();
    notices = [];
    accountOpened = 0;
  });

  Future<void> open(
    WidgetTester tester, {
    bool signedIn = true,
    TrackSource source = TrackSource.netease,
  }) async {
    await pumpPlaylistsPage(
      tester,
      Scaffold(
        body: Center(
          child: SavePlatformPlaylistButton(
            source: source,
            playlistId: '1001',
            name: '华语流行',
            onOpenAccount: () => accountOpened++,
            onNotice: (kind, text) => notices.add((kind, text)),
          ),
        ),
      ),
      playlists: server,
      signedIn: signedIn,
    );
    await tester.tap(find.widgetWithText(PillButton, '保存为我的歌单'));
    await settlePage(tester);
  }

  testWidgets('saves the NetEase playlist under the name it is given', (
    tester,
  ) async {
    await open(tester);

    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      '华语流行',
    );
    await tester.tap(find.widgetWithText(PillButton, '保存'));
    await settlePage(tester);

    expect(server.calls, contains('importPlatform 华语流行 netease:1001'));
    expect(notices, [(ToastKind.success, '已保存为“华语流行”，共 12 首')]);
  });

  testWidgets('saves a QQ Music playlist from QQ Music', (tester) async {
    await open(tester, source: TrackSource.qq);

    await tester.tap(find.widgetWithText(PillButton, '保存'));
    await settlePage(tester);

    expect(server.calls, contains('importPlatform 华语流行 qq:1001'));
    expect(notices, [(ToastKind.success, '已保存为“华语流行”，共 12 首')]);
  });

  testWidgets('a guest is asked to sign in', (tester) async {
    await open(tester, signedIn: false);

    expect(find.text('注册或登录之后就能保存这个歌单。'), findsOneWidget);
    expect(server.calls, isEmpty);
    await tester.tap(find.text('去账号设置'));
    await settlePage(tester);
    expect(accountOpened, 1);
  });

  testWidgets('the sheet still saves once the page under it is gone', (
    tester,
  ) async {
    final showing = ValueNotifier(true);
    addTearDown(showing.dispose);
    await pumpPlaylistsPage(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: showing,
        builder: (_, shown, _) => shown
            ? Scaffold(
                body: Center(
                  child: SavePlatformPlaylistButton(
                    source: TrackSource.netease,
                    playlistId: '1001',
                    name: '华语流行',
                    onOpenAccount: () {},
                    onNotice: (kind, text) => notices.add((kind, text)),
                  ),
                ),
              )
            : const SizedBox(),
      ),
      playlists: server,
    );
    await tester.tap(find.widgetWithText(PillButton, '保存为我的歌单'));
    await settlePage(tester);

    showing.value = false;
    await settlePage(tester);
    await tester.tap(find.widgetWithText(PillButton, '保存'));
    await settlePage(tester);

    expect(tester.takeException(), isNull);
    expect(server.calls, contains('importPlatform 华语流行 netease:1001'));
    expect(notices, [(ToastKind.success, '已保存为“华语流行”，共 12 首')]);
    expect(find.byType(EditableText), findsNothing);
  });
}
