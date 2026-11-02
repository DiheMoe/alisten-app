import 'package:alisten/features/admin/data/gal_image_gallery.dart';
import 'package:alisten/features/admin/index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('gal');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late bool hasAccess;
  late bool granted;
  late PlatformException? saveError;

  setUp(() {
    calls = [];
    hasAccess = true;
    granted = true;
    saveError = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'hasAccess':
                return hasAccess;
              case 'requestAccess':
                return granted;
              case 'putImageBytes':
                if (saveError case final error?) throw error;
                return null;
            }
            return null;
          });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  });

  Iterable<MethodCall> saves() =>
      calls.where((call) => call.method == 'putImageBytes');

  test('an image is saved under its name once access is there', () async {
    await const GalImageGallery().saveImage(
      Uint8List.fromList(const [1, 2, 3]),
      'alisten-netease-login',
    );

    final save = saves().single;
    final arguments = save.arguments as Map<Object?, Object?>;
    expect(arguments['bytes'], [1, 2, 3]);
    expect(arguments['name'], 'alisten-netease-login');
    expect(arguments['album'], isNull);
  });

  test('access is asked for when missing, and an image is saved once '
      'given', () async {
    hasAccess = false;

    await const GalImageGallery().saveImage(
      Uint8List.fromList(const [1]),
      'alisten-qq-login',
    );

    expect(calls.first.method, 'hasAccess');
    expect(calls.map((call) => call.method), contains('requestAccess'));
    expect(saves(), hasLength(1));
  });

  test('access refused is told apart, and nothing is saved', () async {
    hasAccess = false;
    granted = false;

    await expectLater(
      const GalImageGallery().saveImage(Uint8List.fromList(const [1]), 'x'),
      throwsA(isA<GalleryAccessDenied>()),
    );
    expect(saves(), isEmpty);
  });

  test('access the platform refuses while saving is told apart', () async {
    saveError = PlatformException(code: 'ACCESS_DENIED');

    await expectLater(
      const GalImageGallery().saveImage(Uint8List.fromList(const [1]), 'x'),
      throwsA(isA<GalleryAccessDenied>()),
    );
  });

  test('other failures while saving are passed on', () async {
    saveError = PlatformException(code: 'NOT_ENOUGH_SPACE');

    await expectLater(
      const GalImageGallery().saveImage(Uint8List.fromList(const [1]), 'x'),
      throwsA(isNot(isA<GalleryAccessDenied>())),
    );
  });
}
