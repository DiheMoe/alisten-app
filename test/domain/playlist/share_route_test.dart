import 'package:alisten/domain/playlist/share_route.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'abc-DEF_ghi-JKL_mno-PQ';

void main() {
  test('a share id is 22 base64url characters', () {
    expect(_id.length, 22);
    expect(isShareId(_id), isTrue);
    expect(isShareId('AbCdEfGhIjKlMnOpQrStUv'), isTrue);
    expect(isShareId(_id.substring(1)), isFalse);
    expect(isShareId('${_id}x'), isFalse);
    expect(isShareId('${_id.substring(1)}='), isFalse);
    expect(isShareId('${_id.substring(1)}+'), isFalse);
  });

  test('only exactly /s/<share id> is a shared playlist', () {
    expect(sharedPlaylistRoute(['s', _id]), '/s/$_id');
    expect(sharedPlaylistRoute(['s', _id.substring(1)]), isNull);
    expect(sharedPlaylistRoute(['s', _id, 'x']), isNull);
    expect(sharedPlaylistRoute(['s']), isNull);
    expect(sharedPlaylistRoute(['r', _id]), isNull);
    expect(sharedPlaylistRoute(const []), isNull);
  });
}
