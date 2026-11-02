import 'package:alisten/shared/ui/pull_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final atEnd = FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 500,
    pixels: 500,
    viewportDimension: 600,
    axisDirection: AxisDirection.down,
    devicePixelRatio: 3,
  );
  const physics = PullRefreshScrollPhysics();

  test('the top of the list can be pulled past, to show the indicator', () {
    final atTop = atEnd.copyWith(pixels: 0);

    expect(physics.applyBoundaryConditions(atTop, -40), 0);
    expect(physics.applyBoundaryConditions(atTop, 30), 0);
  });

  test('the end of the list stops the scroll, as the platform does', () {
    expect(physics.applyBoundaryConditions(atEnd, 520), 20);
    expect(
      physics.applyBoundaryConditions(atEnd.copyWith(pixels: 490), 510),
      10,
    );
    expect(physics.applyBoundaryConditions(atEnd, 480), 0);
  });

  // 在平台默认物理效果上加下拉刷新，返回甩到末端时的最大越界距离。
  Future<double> overscrollAtEnd(WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    late ScrollPhysics physics;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(
          builder: (context) {
            physics = pullRefreshPhysics(context);
            return CustomScrollView(
              controller: controller,
              physics: physics,
              slivers: [
                SliverList.builder(
                  itemCount: 30,
                  itemBuilder: (context, index) =>
                      SizedBox(height: 50, child: Text('$index')),
                ),
              ],
            );
          },
        ),
      ),
    );
    var furthest = 0.0;
    controller.addListener(() {
      if (controller.offset > furthest) furthest = controller.offset;
    });

    await tester.fling(find.text('3'), const Offset(0, -2000), 8000);
    await tester.pumpAndSettle();

    final end = controller.position.maxScrollExtent;
    expect(controller.offset, end);
    expect(
      physics.applyBoundaryConditions(
        controller.position.copyWith(pixels: 0),
        -40,
      ),
      0,
      reason: 'the top can always be pulled past',
    );
    return furthest - end;
  }

  testWidgets('where lists bounce, as on iOS, the end bounces too', (
    tester,
  ) async {
    expect(await overscrollAtEnd(tester), greaterThan(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('where lists stop at their end, as on Android, the end stops', (
    tester,
  ) async {
    expect(await overscrollAtEnd(tester), lessThanOrEqualTo(0));
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
