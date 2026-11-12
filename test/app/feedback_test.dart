import 'package:alisten/app/feedback.dart';
import 'package:alisten/features/identity/index.dart';
import 'package:alisten/features/room/index.dart';
import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/pill_button.dart';
import 'package:alisten/shared/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/lobby/lobby_test_doubles.dart';
import 'app_test_harness.dart';

const _outcomes = <({String name, IconData icon, String text})>[
  (name: 'confirmed', icon: AlistenIcons.checkCircleFill, text: '已点赞，共 3 个赞'),
  (name: 'refused', icon: AlistenIcons.warningCircleFill, text: '太快了'),
  (name: 'unknown', icon: AlistenIcons.warningFill, text: mutationUnknownText),
  (name: 'not sent', icon: AlistenIcons.warningFill, text: '未连接，未发送'),
];

MutationResult<int> _result(String name) {
  return switch (name) {
    'confirmed' => const MutationSucceeded(3),
    'refused' => const MutationFailed('RATE_LIMITED', '太快了'),
    'unknown' => const MutationUnknown(),
    _ => const MutationNotSent('未连接，未发送'),
  };
}

Future<ToastController> _pumpHost(
  WidgetTester tester, {
  required Widget home,
}) async {
  final toasts = ToastController();
  addTearDown(toasts.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [toastControllerProvider.overrideWithValue(toasts)],
      child: MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.dark)),
        builder: (context, child) =>
            ToastHost(controller: toasts, child: child!),
        home: Scaffold(body: home),
      ),
    ),
  );
  return toasts;
}

Finder _icon(IconData icon) =>
    find.descendant(of: find.byType(ToastHost), matching: find.byIcon(icon));

// 关闭当前提示，不留下仍在运行的定时器。
Future<void> _dismiss(WidgetTester tester, ToastController toasts) async {
  toasts.dismiss();
  await tester.pumpAndSettle();
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('each outcome of a change is shown with its own icon and words', (
    tester,
  ) async {
    final toasts = await _pumpHost(tester, home: const SizedBox.shrink());

    for (final outcome in _outcomes) {
      reportMutation<int>(
        toasts,
        _result(outcome.name),
        success: (likes) => '已点赞，共 $likes 个赞',
      );
      await _settle(tester);

      expect(find.text(outcome.text), findsOneWidget, reason: outcome.name);
      expect(_icon(outcome.icon), findsOneWidget, reason: outcome.name);
      for (final other in _outcomes.where((o) => o.text != outcome.text)) {
        expect(find.text(other.text), findsNothing, reason: outcome.name);
      }
    }
    // 结果未知和未发出共用警告图标，靠文字区分；确认和被拒绝各有图标。
    expect({for (final o in _outcomes) o.text}, hasLength(_outcomes.length));
    expect({for (final o in _outcomes) o.icon}, hasLength(3));
    await _dismiss(tester, toasts);
  });

  testWidgets('showMutationFeedback words a confirmed change as given and '
      'reports the others as they are', (tester) async {
    late MutationResult<void> result;
    final toasts = await _pumpHost(
      tester,
      home: Consumer(
        builder: (context, ref, _) => PillButton(
          label: '发送',
          onPressed: () => showMutationFeedback(ref, result, success: '已移除'),
        ),
      ),
    );

    result = const MutationSucceeded(null);
    await tester.tap(find.text('发送'));
    await _settle(tester);
    expect(toasts.current?.kind, ToastKind.success);
    expect(find.text('已移除'), findsOneWidget);

    result = const MutationFailed('FORBIDDEN', '不允许移除');
    await tester.tap(find.text('发送'));
    await _settle(tester);
    expect(toasts.current?.kind, ToastKind.failure);
    expect(find.text('不允许移除'), findsOneWidget);
    expect(find.text('已移除'), findsNothing);

    result = const MutationUnknown();
    await tester.tap(find.text('发送'));
    await _settle(tester);
    expect(toasts.current?.kind, ToastKind.warning);
    expect(find.text(mutationUnknownText), findsOneWidget);

    result = const MutationNotSent('已离开房间');
    await tester.tap(find.text('发送'));
    await _settle(tester);
    expect(toasts.current?.kind, ToastKind.warning);
    expect(find.text('已离开房间'), findsOneWidget);
    await _dismiss(tester, toasts);
  });

  testWidgets('a replaced identity is told as a warning, and its notice is '
      'cleared once shown', (tester) async {
    final api = FakeAlistenApi()
      ..rooms = [roomListing()]
      ..ticketError = unauthorized;
    // 票据请求被拒且成员接口也拒绝，身份因此被替换。
    api.onCreateTicket = () => api.getMeError = unauthorized;
    await pumpAlistenApp(
      tester,
      api: api,
      credentials: FakeCredentialStore()..memberToken = 'expired-token',
    );
    final container = appContainer(tester);

    await container.read(roomControllerProvider.notifier).openRoom('listen');
    await _settle(tester);

    expect(find.text(identityRenewedNotice), findsOneWidget);
    expect(
      container.read(toastControllerProvider).current?.kind,
      ToastKind.warning,
    );
    expect(container.read(identityControllerProvider).notice, isNull);
  });
}
