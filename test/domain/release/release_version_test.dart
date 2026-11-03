import 'package:alisten/domain/release/release_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a release tag', () {
    test('of the form vX.Y.Z is read as its three numbers', () {
      expect(ReleaseVersion.fromTag('v1.2.3'), const ReleaseVersion(1, 2, 3));
      expect(ReleaseVersion.fromTag('v0.0.0'), const ReleaseVersion(0, 0, 0));
      expect(
        ReleaseVersion.fromTag('v10.20.300'),
        const ReleaseVersion(10, 20, 300),
      );
    });

    test('that is malformed is no version', () {
      for (final tag in [
        '',
        'v',
        '1.2.3',
        'V1.2.3',
        'v1.2',
        'v1.2.3.4',
        'v1..3',
        'v1.2.x',
        'v01.2.3',
        'v1.2.3 ',
        ' v1.2.3',
        'vv1.2.3',
        'v1.2.3+4',
        'v-1.2.3',
        'v１.2.3',
        'v99999999999999999999.0.0',
      ]) {
        expect(ReleaseVersion.fromTag(tag), isNull, reason: tag);
      }
    });

    test('with a pre-release suffix is no version', () {
      for (final tag in ['v1.2.3-beta', 'v1.2.3-rc.1', 'v1.2.3-']) {
        expect(ReleaseVersion.fromTag(tag), isNull, reason: tag);
      }
    });
  });

  group('the app version', () {
    test('is compared without its build number', () {
      expect(
        ReleaseVersion.fromAppVersion('1.0.0+1'),
        const ReleaseVersion(1, 0, 0),
      );
      expect(
        ReleaseVersion.fromAppVersion('2.3.4+56'),
        const ReleaseVersion(2, 3, 4),
      );
      expect(
        ReleaseVersion.fromAppVersion('2.3.4'),
        const ReleaseVersion(2, 3, 4),
      );
    });

    test('of a pre-release is compared by its three numbers', () {
      expect(
        ReleaseVersion.fromAppVersion('1.3.0-beta.1+7'),
        const ReleaseVersion(1, 3, 0),
      );
    });

    test('that is malformed is no version', () {
      for (final version in ['', '1.0', '1.0.0.0+1', 'v1.0.0+1', '1.0.x+1']) {
        expect(ReleaseVersion.fromAppVersion(version), isNull, reason: version);
      }
    });
  });

  group('a release', () {
    const installed = ReleaseVersion(1, 2, 3);

    test('is newer when any of its numbers is higher, the first one first', () {
      for (final newer in const [
        ReleaseVersion(1, 2, 4),
        ReleaseVersion(1, 3, 0),
        ReleaseVersion(2, 0, 0),
        ReleaseVersion(1, 10, 0),
      ]) {
        expect(newer.isNewerThan(installed), isTrue, reason: '$newer');
      }
    });

    test('of the same version is not newer', () {
      expect(const ReleaseVersion(1, 2, 3).isNewerThan(installed), isFalse);
    });

    test('of an older version is not newer', () {
      for (final older in const [
        ReleaseVersion(1, 2, 2),
        ReleaseVersion(1, 1, 9),
        ReleaseVersion(0, 9, 9),
      ]) {
        expect(older.isNewerThan(installed), isFalse, reason: '$older');
      }
    });

    test('tagged vX.Y.Z is newer than the app built as X.Y.Z+N only when '
        'X.Y.Z is higher', () {
      final app = ReleaseVersion.fromAppVersion('1.2.3+99')!;

      expect(ReleaseVersion.fromTag('v1.2.3')!.isNewerThan(app), isFalse);
      expect(ReleaseVersion.fromTag('v1.2.4')!.isNewerThan(app), isTrue);
    });
  });

  test('is written as X.Y.Z', () {
    expect('${const ReleaseVersion(1, 20, 3)}', '1.20.3');
  });
}
