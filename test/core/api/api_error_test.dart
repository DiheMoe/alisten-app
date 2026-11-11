import 'package:alisten/core/api/api_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an answer is lost when the connection failed or a successful answer '
      'could not be decoded, and not when the server refused', () {
    final cases = <(String code, int? status, bool lost)>[
      (LocalErrorCodes.network, null, true),
      (LocalErrorCodes.network, 502, true),
      (LocalErrorCodes.protocolMismatch, 200, true),
      (LocalErrorCodes.protocolMismatch, 201, true),
      (LocalErrorCodes.protocolMismatch, 204, true),
      (LocalErrorCodes.protocolMismatch, 400, false),
      (LocalErrorCodes.protocolMismatch, 500, false),
      (LocalErrorCodes.protocolMismatch, null, false),
      ('UNAUTHORIZED', 401, false),
      ('CONFLICT', 409, false),
    ];

    for (final (code, status, lost) in cases) {
      expect(
        ApiException(code: code, message: '说明', status: status).answerLost,
        lost,
        reason: '$code $status',
      );
    }
  });

  group('rateLimitedText', () {
    ApiException limited(Duration? retryAfter) => ApiException(
      code: 'RATE_LIMITED',
      message: '请求太频繁，请稍后再试。',
      status: 429,
      retryAfter: retryAfter,
    );

    test('says how many seconds to wait when the server told', () {
      expect(
        rateLimitedText(limited(const Duration(seconds: 30))),
        '请求太频繁，请 30 秒后再试',
      );
    });

    test('falls back to the transport message without a wait', () {
      for (final wait in [null, Duration.zero, const Duration(seconds: -1)]) {
        expect(rateLimitedText(limited(wait)), '请求太频繁，请稍后再试。', reason: '$wait');
      }
    });
  });
}
