import 'package:alisten/shared/ui/tap_rhythm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _long = Duration(milliseconds: 500);
const _short = Duration(milliseconds: 100);

const _weWillRockYou = [
  TapBeat.long,
  TapBeat.long,
  TapBeat.short,
  TapBeat.long,
  TapBeat.long,
  TapBeat.short,
];

const _fate = [
  TapBeat.short,
  TapBeat.short,
  TapBeat.short,
  TapBeat.long,
  TapBeat.short,
  TapBeat.short,
  TapBeat.short,
  TapBeat.long,
];

Finder get _ring => find.byKey(TapRhythm.holdProgressKey);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> haptics;

  setUp(() {
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpRhythm(
    WidgetTester tester,
    List<RhythmPattern> patterns, {
    bool disableAnimations = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: TapRhythm(patterns: patterns, child: const Text('版本')),
          ),
        ),
      ),
    );
  }

  Offset target(WidgetTester tester) => tester.getCenter(find.text('版本'));

  Future<void> beat(WidgetTester tester, Duration hold) async {
    final gesture = await tester.startGesture(target(tester));
    await tester.pump(hold);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> play(WidgetTester tester, List<TapBeat> beats) async {
    for (final value in beats) {
      await beat(tester, value == TapBeat.long ? _long : _short);
      expect(_ring, findsNothing);
    }
  }

  testWidgets('long long short long long short is recognized once, with one '
      'haptic and nothing shown', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(beats: _weWillRockYou, onMatched: () => matched++),
    ]);

    await play(tester, _weWillRockYou);

    expect(matched, 1);
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    expect(_ring, findsNothing);
  });

  testWidgets('a beat held from 350 ms is long, shorter is short, and one '
      'held for 1.5 s counts for nothing', (tester) async {
    var shorts = 0;
    var longs = 0;
    await pumpRhythm(tester, [
      RhythmPattern(beats: const [TapBeat.short], onMatched: () => shorts++),
      RhythmPattern(beats: const [TapBeat.long], onMatched: () => longs++),
    ]);

    await beat(tester, const Duration(milliseconds: 349));
    expect((shorts, longs), (1, 0));

    await beat(tester, const Duration(milliseconds: 350));
    expect((shorts, longs), (1, 1));

    await beat(tester, const Duration(milliseconds: 1500));
    expect((shorts, longs), (1, 1));
  });

  testWidgets('a pause of more than 1.5 s starts over, and a beat too many '
      'starts the rhythm again from that beat', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(beats: _weWillRockYou, onMatched: () => matched++),
    ]);

    await play(tester, const [TapBeat.long, TapBeat.long]);
    await tester.pump(const Duration(milliseconds: 1600));
    await play(tester, _weWillRockYou);
    expect(matched, 1);

    await tester.pump(const Duration(milliseconds: 1600));
    await play(tester, const [
      TapBeat.long,
      TapBeat.long,
      TapBeat.long,
      TapBeat.long,
      TapBeat.short,
      TapBeat.long,
      TapBeat.long,
      TapBeat.short,
    ]);
    expect(matched, 2);
  });

  testWidgets('beats too many before the rhythm do not keep it from being '
      'recognized, and other rhythms are not taken for it', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(beats: _weWillRockYou, onMatched: () => matched++),
    ]);

    for (final extra in const [
      [TapBeat.long],
      [TapBeat.long, TapBeat.long, TapBeat.short, TapBeat.long],
      [TapBeat.short, TapBeat.long, TapBeat.long, TapBeat.long],
    ]) {
      await play(tester, [...extra, ..._weWillRockYou]);
      expect(matched, 1, reason: '$extra');
      matched = 0;
      await tester.pump(const Duration(milliseconds: 1600));
    }

    for (final other in const [
      [TapBeat.short, TapBeat.short, TapBeat.short, TapBeat.short],
      [TapBeat.long, TapBeat.short, TapBeat.long, TapBeat.short],
      [TapBeat.long, TapBeat.long, TapBeat.short, TapBeat.long, TapBeat.short],
      [TapBeat.long, TapBeat.long, TapBeat.long, TapBeat.long, TapBeat.long],
    ]) {
      await play(tester, [...other, ...other]);
      await tester.pump(const Duration(milliseconds: 1600));
    }
    expect(matched, 0);
    expect(haptics, hasLength(3));
  });

  testWidgets('a rhythm interrupted by a pause of more than 1.5 s is not '
      'recognized', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(beats: _weWillRockYou, onMatched: () => matched++),
    ]);

    await play(tester, const [TapBeat.long, TapBeat.long, TapBeat.short]);
    await tester.pump(const Duration(milliseconds: 1600));
    await play(tester, const [TapBeat.long, TapBeat.long, TapBeat.short]);

    expect(matched, 0);
    expect(haptics, isEmpty);
  });

  testWidgets('a rhythm that asks to be held shows a ring on the next press '
      'and is recognized once held long enough', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(
        beats: _fate,
        holdAfter: const Duration(seconds: 2),
        onMatched: () => matched++,
      ),
    ]);

    await play(tester, _fate);
    expect(haptics, hasLength(1));
    expect(_ring, findsNothing);
    expect(matched, 0);

    final gesture = await tester.startGesture(target(tester));
    await tester.pump();
    expect(_ring, findsOneWidget);
    expect(tester.hasRunningAnimations, isTrue);

    await tester.pump(const Duration(seconds: 2));
    expect(matched, 1);
    expect(haptics, hasLength(2));
    expect(_ring, findsNothing);

    await gesture.up();
    await tester.pump();
    expect(matched, 1);
    expect(haptics, hasLength(2));
  });

  testWidgets('letting go before the hold is over cancels it, and the next '
      'hold starts from nothing', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(
        beats: _fate,
        holdAfter: const Duration(seconds: 2),
        onMatched: () => matched++,
      ),
    ]);

    await play(tester, _fate);
    await beat(tester, const Duration(seconds: 1));
    expect(_ring, findsNothing);
    expect(matched, 0);

    final gesture = await tester.startGesture(target(tester));
    await tester.pump();
    expect(_ring, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    expect(matched, 0);
    expect(haptics, hasLength(1));
  });

  testWidgets('a hold started more than 1.5 s after the rhythm is not '
      'awaited any more', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(
        beats: _fate,
        holdAfter: const Duration(seconds: 2),
        onMatched: () => matched++,
      ),
    ]);

    await play(tester, _fate);
    await tester.pump(const Duration(milliseconds: 1600));
    final gesture = await tester.startGesture(target(tester));
    await tester.pump();
    expect(_ring, findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await gesture.up();
    await tester.pump();

    expect(matched, 0);
  });

  testWidgets('a press that moves counts for nothing and starts the rhythm '
      'over', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(
        beats: const [TapBeat.long, TapBeat.long],
        onMatched: () => matched++,
      ),
    ]);

    await beat(tester, _long);
    final gesture = await tester.startGesture(target(tester));
    await tester.pump(_long);
    await gesture.moveBy(const Offset(30, 0));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    await beat(tester, _long);
    expect(matched, 0);

    await beat(tester, _long);
    expect(matched, 1);
  });

  testWidgets('a cancelled press counts for nothing and starts the rhythm '
      'over', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(
        beats: const [TapBeat.long, TapBeat.long],
        onMatched: () => matched++,
      ),
    ]);

    await beat(tester, _long);
    final gesture = await tester.startGesture(target(tester));
    await tester.pump(_long);
    await gesture.cancel();
    await tester.pump(const Duration(milliseconds: 200));
    await beat(tester, _long);
    expect(matched, 0);

    await beat(tester, _long);
    expect(matched, 1);
  });

  testWidgets('only the first finger is followed', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, [
      RhythmPattern(
        beats: const [TapBeat.short, TapBeat.long],
        onMatched: () => matched++,
      ),
    ]);

    // 第二根手指的短按若也算一拍，加上第一根手指的长按就凑成了节奏。
    final first = await tester.startGesture(target(tester));
    final second = await tester.startGesture(target(tester), pointer: 7);
    await tester.pump(_short);
    await second.up();
    await tester.pump(_long);
    await first.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(matched, 0);

    await play(tester, const [TapBeat.short, TapBeat.long]);
    expect(matched, 1);
  });

  testWidgets('with animations removed the ring is shown full and still, and '
      'the hold is still timed', (tester) async {
    var matched = 0;
    await pumpRhythm(tester, disableAnimations: true, [
      RhythmPattern(
        beats: _fate,
        holdAfter: const Duration(seconds: 2),
        onMatched: () => matched++,
      ),
    ]);

    await play(tester, _fate);
    final gesture = await tester.startGesture(target(tester));
    await tester.pump();
    expect(_ring, findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pump(const Duration(seconds: 2));
    expect(matched, 1);
    await gesture.up();
  });

  testWidgets('the rhythm adds no tap action to what it wraps', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpRhythm(tester, [
      RhythmPattern(beats: _weWillRockYou, onMatched: () {}),
    ]);

    expect(
      tester.getSemantics(find.text('版本')),
      isSemantics(label: '版本', hasTapAction: false),
    );
    semantics.dispose();
  });
}
