import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

/// 解码和文件读写在引擎里按真实时间进行：每轮让出一点真实时间，再处理到期的
/// 计时器，直到 [done]。5 秒内等不到就失败，而不是带着没成立的前提继续。
Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
  final waited = Stopwatch()..start();
  while (!done()) {
    if (waited.elapsed > const Duration(seconds: 5)) {
      fail('Still waiting after 5 seconds.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(Duration.zero);
  }
}

/// 加载失败的图片一直算作加载中，所以只能用来等加载成功。
Future<void> finishLoadingImages(WidgetTester tester) async {
  await pumpUntil(tester, () => imageCache.pendingImageCount == 0);
  await tester.pump();
}
