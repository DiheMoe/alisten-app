import 'dart:async';

import 'package:alisten/core/logging/app_log.dart';
import 'package:alisten/domain/release/release_version.dart';
import 'package:alisten/features/update/index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../update_test_doubles.dart';

final _launchedAt = DateTime.utc(2026, 11, 4, 9);

void main() {
  late FakeReleaseSource source;
  late FakeUpdateStore store;
  late FakeReleaseOpener opener;
  late DateTime now;
  late ProviderContainer container;

  setUp(() {
    source = FakeReleaseSource(release: testRelease(tag: 'v1.1.0'));
    store = FakeUpdateStore();
    opener = FakeReleaseOpener();
    now = _launchedAt;
    container = ProviderContainer(
      overrides: [
        releaseSourceProvider.overrideWithValue(source),
        updateStoreProvider.overrideWithValue(store),
        releaseOpenerProvider.overrideWithValue(opener),
        installedVersionProvider.overrideWithValue(
          const ReleaseVersion(1, 0, 0),
        ),
        updateNowProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
  });

  UpdateController controller() =>
      container.read(updateControllerProvider.notifier);

  Matcher offers(String version) => isA<UpdateAvailable>()
      .having((update) => '${update.version}', 'version', version)
      .having((update) => update.release.tag, 'tag', 'v$version');

  group('the check at launch', () {
    test('offers a newer release and records when it checked', () async {
      expect(await controller().checkOnLaunch(), offers('1.1.0'));

      expect(source.calls, 1);
      expect(store.lastAutoCheck, _launchedAt);
    });

    test('asks nothing within 24 hours of the last one', () async {
      store.lastAutoCheck = _launchedAt.subtract(
        const Duration(hours: 23, minutes: 59),
      );

      expect(await controller().checkOnLaunch(), isNull);

      expect(source.calls, 0);
      expect(
        store.lastAutoCheck,
        _launchedAt.subtract(const Duration(hours: 23, minutes: 59)),
      );
    });

    test('asks again once 24 hours have passed', () async {
      store.lastAutoCheck = _launchedAt.subtract(const Duration(hours: 24));

      expect(await controller().checkOnLaunch(), offers('1.1.0'));

      expect(source.calls, 1);
      expect(store.lastAutoCheck, _launchedAt);
    });

    test('is not held off by a last check later than now, as when the clock '
        'was set back', () async {
      store.lastAutoCheck = _launchedAt.add(const Duration(hours: 1));

      expect(await controller().checkOnLaunch(), offers('1.1.0'));

      expect(store.lastAutoCheck, _launchedAt);
    });

    test('that fails offers nothing, says so only in a debug log and keeps '
        'the time of the last check', () async {
      final records = <(int, String)>[];
      AppLog.onRecord = (name, level, message) => records.add((level, message));
      addTearDown(() => AppLog.onRecord = null);
      final earlier = _launchedAt.subtract(const Duration(days: 3));
      store.lastAutoCheck = earlier;
      source.error = const ReleaseUnavailable();

      expect(await controller().checkOnLaunch(), isNull);

      expect(source.calls, 1);
      expect(store.lastAutoCheck, earlier);
      expect(records, isNotEmpty);
      expect(records.map((record) => record.$1), everyElement(500));
    });

    test('offers nothing for the same or an older version, a malformed tag '
        'or a pre-release, and still records the check', () async {
      for (final tag in ['v1.0.0', 'v0.9.9', '1.1.0', 'v1.1', 'v1.1.0-beta']) {
        final container = ProviderContainer(
          overrides: [
            releaseSourceProvider.overrideWithValue(
              FakeReleaseSource(release: testRelease(tag: tag)),
            ),
            updateStoreProvider.overrideWithValue(store),
            installedVersionProvider.overrideWithValue(
              const ReleaseVersion(1, 0, 0),
            ),
            updateNowProvider.overrideWithValue(() => now),
          ],
        );
        addTearDown(container.dispose);
        store.lastAutoCheck = null;

        expect(
          await container
              .read(updateControllerProvider.notifier)
              .checkOnLaunch(),
          isNull,
          reason: tag,
        );
        expect(store.lastAutoCheck, _launchedAt, reason: tag);
      }
    });

    test('runs once per run', () async {
      expect(await controller().checkOnLaunch(), offers('1.1.0'));
      store.lastAutoCheck = null;

      expect(await controller().checkOnLaunch(), isNull);

      expect(source.calls, 1);
    });

    test('that cannot record its time still offers the release', () async {
      store.writeError = Exception('not saved');

      expect(await controller().checkOnLaunch(), offers('1.1.0'));
    });
  });

  group('a skipped version', () {
    test('is not offered at launch', () async {
      store.skippedVersion = '1.1.0';

      expect(await controller().checkOnLaunch(), isNull);

      expect(store.lastAutoCheck, _launchedAt);
    });

    test('is still offered by a manual check', () async {
      store.skippedVersion = '1.1.0';

      expect(await controller().checkNow(), offers('1.1.0'));
    });

    test('does not hold back a newer one', () async {
      store.skippedVersion = '1.1.0';
      source.release = testRelease(tag: 'v1.2.0');

      expect(await controller().checkOnLaunch(), offers('1.2.0'));
    });

    test('is kept in the store', () async {
      final update = (await controller().checkNow())! as UpdateAvailable;

      await controller().skip(update);

      expect(store.skippedVersion, '1.1.0');
    });

    test('that cannot be kept is logged, not thrown', () async {
      final records = <String>[];
      AppLog.onRecord = (name, level, message) => records.add(message);
      addTearDown(() => AppLog.onRecord = null);
      final update = (await controller().checkNow())! as UpdateAvailable;
      store.writeError = Exception('not saved');

      await controller().skip(update);

      expect(store.skippedVersion, isNull);
      expect(records, isNotEmpty);
    });
  });

  group('the launch panel, claimed just before it is shown,', () {
    test('is shown once per run', () async {
      final update = (await controller().checkOnLaunch())!;

      expect(controller().claimLaunchOffer(update), isTrue);
      expect(controller().claimLaunchOffer(update), isFalse);
    });

    test('is not shown for a version a manual check already showed, though '
        'a manual check still shows it again', () async {
      final launched = (await controller().checkOnLaunch())!;
      expect(await controller().checkNow(), offers('1.1.0'));

      expect(controller().claimLaunchOffer(launched), isFalse);
      expect(await controller().checkNow(), offers('1.1.0'));
    });

    test('is not shown for a version skipped while it waited', () async {
      final launched = (await controller().checkOnLaunch())!;

      await controller().skip(launched);

      expect(controller().claimLaunchOffer(launched), isFalse);
    });

    test('is still shown for a newer version than the one shown', () async {
      expect(await controller().checkNow(), offers('1.1.0'));
      source.release = testRelease(tag: 'v1.2.0');

      final newer = (await controller().checkOnLaunch())!;

      expect(controller().claimLaunchOffer(newer), isTrue);
    });
  });

  group('a manual check', () {
    test('asks even within 24 hours of the last launch check, and does not '
        'count as one', () async {
      final earlier = _launchedAt.subtract(const Duration(hours: 1));
      store.lastAutoCheck = earlier;

      expect(await controller().checkNow(), offers('1.1.0'));

      expect(source.calls, 1);
      expect(store.lastAutoCheck, earlier);
    });

    test('of the same version, a malformed tag or a pre-release is up to '
        'date', () async {
      for (final tag in ['v1.0.0', 'v0.9.0', 'latest', 'v1.1.0-rc.1']) {
        source.release = testRelease(tag: tag);

        expect(await controller().checkNow(), isA<UpToDate>(), reason: tag);
      }
    });

    test('that fails says so', () async {
      source.error = const ReleaseUnavailable();

      expect(await controller().checkNow(), isA<UpdateCheckFailed>());
    });

    test('that breaks unexpectedly says it failed', () async {
      source.error = Exception('broken');

      expect(await controller().checkNow(), isA<UpdateCheckFailed>());
    });

    test('is shown as in progress, and asking again meanwhile starts no '
        'second one', () async {
      final holding = source.holding = Completer<void>();

      final first = controller().checkNow();
      expect(container.read(updateControllerProvider), isTrue);
      expect(await controller().checkNow(), isNull);
      expect(source.calls, 1);

      holding.complete();
      expect(await first, offers('1.1.0'));
      expect(container.read(updateControllerProvider), isFalse);
    });

    test('that fails is no longer in progress', () async {
      source.error = const ReleaseUnavailable();

      await controller().checkNow();

      expect(container.read(updateControllerProvider), isFalse);
    });
  });

  group('opening a release', () {
    test('is left to the opener', () async {
      final update = (await controller().checkNow())! as UpdateAvailable;

      expect(await controller().open(update.release), isTrue);
      expect(opener.opened, [same(update.release)]);
    });

    test('that fails says so', () async {
      final update = (await controller().checkNow())! as UpdateAvailable;
      opener.opens = false;

      expect(await controller().open(update.release), isFalse);
    });
  });
}
