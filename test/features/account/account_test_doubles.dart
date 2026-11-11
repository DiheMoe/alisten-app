import 'dart:async';

import 'package:alisten/features/account/index.dart';

/// [gate] 不为 null 时，记下打开的地址之后等它完成才返回。
final class FakeGithubAuthorizer implements GithubAuthorizer {
  final List<Uri> opened = [];
  Uri? callback = Uri.parse('moe.dihe.alisten:/auth/github#code=github-code');
  Exception? error;
  Completer<void>? gate;

  @override
  Future<Uri?> authorize(Uri url) async {
    opened.add(url);
    await gate?.future;
    if (error case final error?) throw error;
    return callback;
  }
}
