import 'package:alisten/shared/ui/side_fade.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the sides fade only while the pages are between two of '
      'them', (tester) async {
    final position = ValueNotifier(0.0);
    addTearDown(position.dispose);
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 400,
          height: 200,
          child: SideFade(
            position: position,
            extent: 24,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ),
    );
    Iterable<ShaderMaskLayer> masks() =>
        tester.layers.whereType<ShaderMaskLayer>();
    expect(masks(), isEmpty);

    position.value = 0.4;
    await tester.pump();
    final mask = masks().single;
    expect(mask.blendMode, BlendMode.dstIn);
    expect(mask.maskRect!.size, const Size(400, 200));

    position.value = 1;
    await tester.pump();
    expect(masks(), isEmpty);
  });

  testWidgets('a box no wider than the two faded sides is left as it is', (
    tester,
  ) async {
    final position = ValueNotifier(0.5);
    addTearDown(position.dispose);
    await tester.pumpWidget(
      Center(
        child: SizedBox(
          width: 40,
          height: 200,
          child: SideFade(
            position: position,
            extent: 24,
            child: const ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      ),
    );

    expect(tester.layers.whereType<ShaderMaskLayer>(), isEmpty);
  });
}
