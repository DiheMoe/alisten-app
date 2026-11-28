import 'dart:ui' as ui;

import 'package:alisten/shared/theme/alisten_colors.dart';
import 'package:alisten/shared/theme/alisten_theme.dart';
import 'package:alisten/shared/theme/tokens.dart';
import 'package:alisten/shared/ui/alisten_icons.dart';
import 'package:alisten/shared/ui/alisten_toggle.dart';
import 'package:alisten/shared/ui/chip_pill.dart';
import 'package:alisten/shared/ui/hover_glow.dart';
import 'package:alisten/shared/ui/icon_circle_button.dart';
import 'package:alisten/shared/ui/pressable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _shot = ValueKey('shot');
const _white = 255;

void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool reduced = false,
    PressableHover hover = PressableHover.tint,
    Widget? child,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAlistenTheme(AlistenColors.brandScheme(Brightness.light)),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: RepaintBoundary(
            key: _shot,
            child: ColoredBox(
              color: Colors.white,
              child: Center(
                child:
                    child ??
                    Pressable(
                      onPressed: enabled ? () {} : null,
                      dimWhenDisabled: false,
                      hover: hover,
                      child: const SizedBox(width: 400, height: 80),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // [at] 处的红色通道：白底是 255，被深色的光盖住的地方更小。
  Future<int> shade(WidgetTester tester, Offset at) async {
    final shot = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
    final value = await tester.runAsync(() async {
      final image = await shot.toImage();
      final bytes = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      final width = image.width;
      image.dispose();
      return bytes!.getUint8((at.dy.round() * width + at.dx.round()) * 4);
    });
    return value!;
  }

  Future<TestGesture> mouse(WidgetTester tester) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  final desktop = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets(
    'under the mouse a control lights up evenly, wherever the pointer is',
    (tester) async {
      await pump(tester);
      final box = tester.getRect(find.byType(Pressable));
      final left = box.centerLeft + const Offset(40, 0);
      final right = box.centerRight - const Offset(40, 0);
      expect(await shade(tester, left), _white);

      final gesture = await mouse(tester);
      await gesture.moveTo(left);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final lit = await shade(tester, left);
      expect(lit, lessThan(_white));
      expect(await shade(tester, right), lit);
    },
    variant: desktop,
  );

  testWidgets(
    'a card lights up strongest at the pointer, and the light follows it',
    (tester) async {
      await pump(tester, hover: PressableHover.glow);
      final box = tester.getRect(find.byType(Pressable));
      final left = box.centerLeft + const Offset(40, 0);
      final right = box.centerRight - const Offset(40, 0);

      final gesture = await mouse(tester);
      await gesture.moveTo(left);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final nearLeft = await shade(tester, left);
      final farRight = await shade(tester, right);
      expect(nearLeft, lessThan(farRight));
      expect(farRight, lessThan(_white));

      await gesture.moveTo(right);
      await tester.pump();
      expect(await shade(tester, right), lessThan(await shade(tester, left)));
    },
    variant: desktop,
  );

  testWidgets('the light fades in and out', (tester) async {
    await pump(tester);
    final at = tester.getCenter(find.byType(Pressable));
    final gesture = await mouse(tester);
    await gesture.moveTo(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final rising = await shade(tester, at);
    await tester.pump(const Duration(milliseconds: 400));
    final full = await shade(tester, at);
    expect(rising, lessThan(_white));
    expect(full, lessThan(rising));

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    final falling = await shade(tester, at);
    expect(falling, greaterThan(full));
    expect(falling, lessThan(_white));
    await tester.pump(const Duration(milliseconds: 600));
    expect(await shade(tester, at), _white);
  }, variant: desktop);

  testWidgets('with motion reduced the light is there at once', (tester) async {
    await pump(tester, reduced: true);
    final at = tester.getCenter(find.byType(Pressable));
    final gesture = await mouse(tester);
    await gesture.moveTo(at);
    await tester.pump();
    await tester.pump();
    final first = await shade(tester, at);
    await tester.pump(const Duration(milliseconds: 400));
    expect(first, lessThan(_white));
    expect(await shade(tester, at), first);
  }, variant: desktop);

  testWidgets('a control that cannot be pressed stays dark', (tester) async {
    await pump(tester, enabled: false);
    final at = tester.getCenter(find.byType(Pressable));
    final gesture = await mouse(tester);
    await gesture.moveTo(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await shade(tester, at), _white);
  }, variant: desktop);

  testWidgets('on a phone a mouse lights nothing up', (tester) async {
    await pump(tester);
    final at = tester.getCenter(find.byType(Pressable));
    final gesture = await mouse(tester);
    await gesture.moveTo(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await shade(tester, at), _white);
  });

  testWidgets('the icon of an icon button grows a little under the mouse', (
    tester,
  ) async {
    await pump(
      tester,
      child: IconCircleButton(
        icon: AlistenIcons.gearSix,
        semanticLabel: '设置',
        style: IconCircleButtonStyle.plain,
        onPressed: () {},
      ),
    );
    final icon = find.byIcon(AlistenIcons.gearSix);
    final resting = tester.getRect(icon);
    final gesture = await mouse(tester);
    await gesture.moveTo(resting.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final lifted = tester.getRect(icon);
    expect(lifted.width, greaterThan(resting.width));
    expect(lifted.width, lessThan(resting.width * 1.2));
    expect(lifted.center, resting.center);

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getRect(icon), resting);
  }, variant: desktop);

  testWidgets('toggle hover hugs the track instead of the 48px touch target', (
    tester,
  ) async {
    await pump(
      tester,
      child: AlistenToggle(
        value: false,
        onChanged: (_) {},
        semanticLabel: '开关',
      ),
    );
    final touch = tester.getRect(find.byType(Pressable));
    final glow = tester.getRect(find.byType(HoverGlow));
    expect(touch.height, greaterThanOrEqualTo(AlistenSizes.minTouchTarget));
    expect(glow.size, AlistenSizes.toggleTrack);

    final marginAbove = Offset(touch.center.dx, touch.top + 2);
    final gesture = await mouse(tester);
    await gesture.moveTo(glow.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await shade(tester, marginAbove), _white);
  }, variant: desktop);

  testWidgets(
    'icon circle button hover hugs its disc while keeping a 48px target',
    (tester) async {
      await pump(
        tester,
        child: IconCircleButton(
          icon: AlistenIcons.trash,
          semanticLabel: '删除',
          style: IconCircleButtonStyle.plain,
          diameter: AlistenSizes.rowAction,
          onPressed: () {},
        ),
      );
      final touch = tester.getRect(find.byType(Pressable));
      final glow = tester.getRect(find.byType(HoverGlow));
      expect(touch.size, const Size.square(AlistenSizes.minTouchTarget));
      expect(glow.size, const Size.square(AlistenSizes.rowAction));

      final insideDisc = glow.center + const Offset(10, 0);
      final outsideDisc = Offset(touch.center.dx, touch.top + 2);
      final gesture = await mouse(tester);
      await gesture.moveTo(glow.center);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(await shade(tester, insideDisc), lessThan(_white));
      expect(await shade(tester, outsideDisc), _white);
    },
    variant: desktop,
  );

  testWidgets('chip pill hover hugs the chip instead of the 48px target', (
    tester,
  ) async {
    await pump(
      tester,
      child: ChipPill(label: '全部', onPressed: () {}),
    );
    final touch = tester.getRect(find.byType(Pressable));
    final glow = tester.getRect(find.byType(HoverGlow));
    expect(touch.height, greaterThanOrEqualTo(AlistenSizes.minTouchTarget));
    expect(glow.height, lessThan(touch.height));

    final marginAbove = Offset(touch.center.dx, touch.top + 2);
    final gesture = await mouse(tester);
    await gesture.moveTo(glow.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await shade(tester, marginAbove), _white);
  }, variant: desktop);

  testWidgets('a long-press-only control does not light up under the mouse', (
    tester,
  ) async {
    await pump(
      tester,
      child: Pressable(
        onPressed: null,
        onLongPress: () {},
        child: const SizedBox(width: 140, height: 140),
      ),
    );
    final at = tester.getCenter(find.byType(Pressable));
    final gesture = await mouse(tester);
    await gesture.moveTo(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await shade(tester, at), _white);
  }, variant: desktop);

  testWidgets('HoverCover highlights only the cover and leaves text clean', (
    tester,
  ) async {
    const coverKey = ValueKey('cover');
    const captionKey = ValueKey('caption');
    await pump(
      tester,
      child: Pressable(
        onPressed: () {},
        ink: false,
        hover: PressableHover.none,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HoverCover(
              radius: AlistenRadii.md,
              child: ColoredBox(
                key: coverKey,
                color: Colors.black,
                child: SizedBox(width: 120, height: 120),
              ),
            ),
            SizedBox(height: 8),
            SizedBox(key: captionKey, width: 120, height: 32),
          ],
        ),
      ),
    );
    final cover = tester.getRect(find.byKey(coverKey));
    final caption = tester.getRect(find.byKey(captionKey));
    expect(await shade(tester, cover.center), 0);
    expect(await shade(tester, caption.center), _white);

    final gesture = await mouse(tester);
    await gesture.moveTo(caption.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(await shade(tester, cover.center), greaterThan(0));
    expect(await shade(tester, caption.center), _white);
  }, variant: desktop);
}
