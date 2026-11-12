import 'dart:async';
import 'dart:typed_data';

import 'package:alisten/app/assembly.dart';
import 'package:alisten/core/api/alisten_api.dart';
import 'package:alisten/core/api/api_error.dart';
import 'package:alisten/core/api/credential_store.dart';
import 'package:alisten/core/realtime/connectivity.dart';
import 'package:alisten/domain/member/account.dart';
import 'package:alisten/domain/member/pairing_code.dart';
import 'package:alisten/features/account/application/pairing_code_controller.dart';
import 'package:alisten/features/account/presentation/pairing_code_sheet.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lobby/lobby_test_doubles.dart';
import '../../room/room_test_doubles.dart';

const _startMs = 1700000000000;

void main() {
  late FakeAlistenApi api;
  late FakeCredentialStore credentials;
  late List<(ToastKind, String)> notices;
  late int now;

  setUp(() {
    api = FakeAlistenApi()
      ..me = accountMember
      ..account = const Account(username: 'mao', github: false)
      ..pairingCode = PairingCode(
        code: 'ABCD2345',
        expiresAtMs: _startMs + 300000,
        qrPng: Uint8List.fromList(const [1, 2, 3]),
      );
    credentials = FakeCredentialStore()..memberToken = 'account-token';
    notices = [];
    now = _startMs;
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    final preferences = await loadPreferences(const {});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...alistenWiring(preferences),
          alistenApiProvider.overrideWithValue(api),
          credentialStoreFactoryProvider.overrideWithValue((_) => credentials),
          roomTransportFactoryProvider.overrideWithValue(
            FakeRoomTransportFactory().call,
          ),
          connectivityStatusProvider.overrideWith(
            (ref) => const Stream.empty(),
          ),
          pairingNowProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
          theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => unawaited(
                    showPairingCodeSheet(
                      context,
                      onNotice: (kind, text) => notices.add((kind, text)),
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.text('打开')),
    );
    await container.read(identityControllerProvider.notifier).restore();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('a code shows its QR image, its two groups and the time it has '
      'left', (tester) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    expect(find.text('在新设备上登录'), findsOneWidget);
    expect(find.bySemanticsLabel('配对二维码'), findsOneWidget);
    expect(find.text('ABCD-2345'), findsOneWidget);
    expect(find.bySemanticsLabel('配对码 A B C D 2 3 4 5'), findsOneWidget);
    expect(find.bySemanticsLabel('ABCD-2345'), findsNothing);
    expect(find.text('5:00 后失效'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('5:00 后失效')),
      isSemantics(isLiveRegion: false),
    );
    expect(find.text('在新设备上扫描二维码，或者在登录页点“输入配对码”。配对码只能用一次。'), findsOneWidget);

    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('4:59 后失效'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a code without a readable QR image shows only the code', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    api.pairingCode = const PairingCode(
      code: 'ABCD2345',
      expiresAtMs: _startMs + 300000,
    );
    await open(tester);

    expect(find.bySemanticsLabel('配对二维码'), findsNothing);
    expect(find.text('ABCD-2345'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a code that ran out is announced and can be made again', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await open(tester);

    now = _startMs + 300000;
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('配对码已经失效。'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('配对码已经失效。')),
      isSemantics(isLiveRegion: true),
    );
    expect(find.text('ABCD-2345'), findsNothing);

    api.pairingCode = PairingCode(code: 'WXYZ6789', expiresAtMs: now + 300000);
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();

    expect(find.text('WXYZ-6789'), findsOneWidget);
    expect(api.createPairingCodeCalls, 2);
    semantics.dispose();
  });

  testWidgets('a code that cannot be made says so, and why', (tester) async {
    api.createPairingCodeError = const ApiException(
      code: LocalErrorCodes.network,
      message: '网络请求失败，请检查网络后重试。',
      status: null,
    );
    await open(tester);

    expect(find.text('暂时无法生成配对码。'), findsOneWidget);
    expect(find.text('重新生成'), findsOneWidget);
    expect(notices, [(ToastKind.failure, '网络请求失败，请检查网络后重试。')]);
  });

  testWidgets('a new session closes the panel, its code gone with the old '
      'one', (tester) async {
    final container = await open(tester);
    expect(find.byType(PairingCodeSheet), findsOneWidget);

    await container
        .read(identityControllerProvider.notifier)
        .signOut((api) async {});
    await tester.pumpAndSettle();

    expect(find.byType(PairingCodeSheet), findsNothing);
  });

  testWidgets('a server switch closes the panel even under another page', (
    tester,
  ) async {
    final container = await open(tester);
    final navigator = Navigator.of(
      tester.element(find.byType(PairingCodeSheet)),
    );
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const Text('邀请确认')),
      ),
    );
    await tester.pumpAndSettle();

    await container
        .read(identityControllerProvider.notifier)
        .resetForServerChange();
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('邀请确认'), findsNothing);
    expect(find.byType(PairingCodeSheet), findsNothing);
  });

  testWidgets('a failure with no reason still shows the failed state and a '
      'way to try again', (tester) async {
    api.createPairingCodeError = const FormatException('boom');
    await open(tester);

    expect(find.text('暂时无法生成配对码。'), findsOneWidget);
    expect(notices, isEmpty);

    api.createPairingCodeError = null;
    await tester.tap(find.text('重新生成'));
    await tester.pumpAndSettle();
    expect(find.text('ABCD-2345'), findsOneWidget);
  });

  testWidgets('QR bytes that cannot be decoded leave the code readable', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await open(tester);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump();

    expect(find.byIcon(AlistenIcons.imageBroken), findsOneWidget);
    expect(find.text('ABCD-2345'), findsOneWidget);
  });
}
