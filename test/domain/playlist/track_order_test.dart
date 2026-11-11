import 'package:alisten/domain/playlist/track_order.dart';
import 'package:flutter_test/flutter_test.dart';

const _order = ['a', 'b', 'c', 'd'];

// Flutter 的 onReorderItem(from, to) 里，to 是移除原位置之后的位置。下面的
// 例子取自 SliverReorderableList：读屏“下移”给出 (i, i + 1)，“上移”给出
// (i, i - 1)，“移到开头”给出 (i, 0)，“移到末尾”给出 (i, length - 1)。
MovePlan? _drag(int from, int to) => moveTo(_order, {_order[from]}, to);

void main() {
  group('moveTracks', () {
    test('gathers the moved songs in the order given before the given '
        'one', () {
      expect(moveTracks(_order, ['d', 'b'], 'a'), ['d', 'b', 'a', 'c']);
      expect(moveTracks(_order, ['a'], 'd'), ['b', 'c', 'a', 'd']);
    });

    test('a song given twice is moved once', () {
      expect(moveTracks(_order, ['b', 'b'], 'a'), ['b', 'a', 'c', 'd']);
    });

    test('without a song to go before, the moved ones go last', () {
      expect(moveTracks(_order, ['a', 'c'], null), ['b', 'd', 'a', 'c']);
    });

    test('songs not in the order are ignored; none left changes nothing', () {
      expect(moveTracks(_order, ['x', 'b'], 'a'), ['b', 'a', 'c', 'd']);
      expect(moveTracks(_order, ['x'], 'gone'), _order);
    });

    test('a song to go before that is gone, or is being moved, is an '
        'error', () {
      expect(() => moveTracks(_order, ['a'], 'gone'), throwsArgumentError);
      expect(() => moveTracks(_order, ['a', 'b'], 'b'), throwsArgumentError);
    });
  });

  group('moveTo', () {
    test('matches the indexes of onReorderItem', () {
      for (final (from, to, order, before) in [
        (0, 2, ['b', 'c', 'a', 'd'], 'd'),
        (3, 0, ['d', 'a', 'b', 'c'], 'a'),
        (1, 3, ['a', 'c', 'd', 'b'], null),
        (1, 2, ['a', 'c', 'b', 'd'], 'd'),
        (2, 1, ['a', 'c', 'b', 'd'], 'b'),
      ]) {
        final plan = _drag(from, to)!;
        expect(plan.order, order, reason: '$from → $to');
        expect(plan.moved, [_order[from]], reason: '$from → $to');
        expect(plan.before, before, reason: '$from → $to');
      }
    });

    test('songs apart are gathered into one block', () {
      final top = moveTo(_order, {'b', 'd'}, 0)!;
      expect(top.order, ['b', 'd', 'a', 'c']);
      expect(top.moved, ['b', 'd']);
      expect(top.before, 'a');

      final bottom = moveTo(_order, {'a', 'c'}, 2)!;
      expect(bottom.order, ['b', 'd', 'a', 'c']);
      expect(bottom.before, isNull);
    });

    test('a place past the rest goes last, and a negative one is an '
        'error', () {
      final last = moveTo(_order, {'a'}, 9)!;
      expect(last.order, ['b', 'c', 'd', 'a']);
      expect(last.before, isNull);

      expect(() => moveTo(_order, {'a'}, -1), throwsRangeError);
    });

    test('an order that would not change needs no request', () {
      expect(moveTo(_order, {'a'}, 0), isNull);
      expect(moveTo(_order, {'c', 'd'}, 2), isNull);
      expect(moveTo(_order, {'x'}, 0), isNull);
      expect(moveTo(_order, const {}, 1), isNull);
    });
  });
}
