import 'dart:io';

import 'package:alisten/features/account/data/url_scheme_registrar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory home;
  late List<(String, List<String>)> commands;

  Future<ProcessResult> run(String command, List<String> arguments) async {
    commands.add((command, arguments));
    return ProcessResult(0, 0, '', '');
  }

  File entry([String dataHome = '.local/share']) => File(
    '${home.path}/$dataHome/applications/'
    'moe.dihe.alisten.url-handler.desktop',
  );

  setUp(() {
    home = Directory.systemTemp.createTempSync('alisten-scheme');
    commands = [];
  });
  tearDown(() => home.deleteSync(recursive: true));

  test(
    'on Linux a hidden desktop entry names this program as the handler, '
    'and gio both registers it for the scheme and makes it the default',
    () async {
      await registerLinuxUrlScheme(
        'moe.dihe.alisten',
        environment: {'HOME': home.path},
        executable: '/opt/alisten/alisten',
        run: run,
      );

      final lines = entry().readAsLinesSync();
      expect(lines.first, '[Desktop Entry]');
      expect(lines, contains('Exec="/opt/alisten/alisten" %u'));
      expect(lines, contains('MimeType=x-scheme-handler/moe.dihe.alisten;'));
      expect(lines, contains('NoDisplay=true'));
      final (command, arguments) = commands.single;
      expect(command, 'gio');
      expect(arguments, [
        'mime',
        'x-scheme-handler/moe.dihe.alisten',
        'moe.dihe.alisten.url-handler.desktop',
      ]);
    },
  );

  test('an AppImage registers the image file, not where it is mounted this '
      'time, under XDG_DATA_HOME when that is set', () async {
    await registerLinuxUrlScheme(
      'moe.dihe.alisten',
      environment: {
        'HOME': home.path,
        'XDG_DATA_HOME': '${home.path}/data',
        'APPIMAGE': '/home/me/Apps/Alisten 1.7.0.AppImage',
      },
      executable: '/tmp/.mount_AlisteXYZ/alisten',
      run: run,
    );

    expect(
      entry('data').readAsLinesSync(),
      contains('Exec="/home/me/Apps/Alisten 1.7.0.AppImage" %u'),
    );
  });

  test('a path is quoted the way a desktop entry asks for', () {
    expect(desktopExecArgument('/a b/alisten'), '"/a b/alisten"');
    expect(desktopExecArgument(r'/a$b/"c"'), r'"/a\\$b/\\"c\\""');
    expect(desktopExecArgument('/50%/alisten'), '"/50%%/alisten"');
  });

  test(
    'without gio the entry is put in the MIME cache before xdg-mime makes '
    'it the default: a default the cache does not list finds no app',
    () async {
      await registerLinuxUrlScheme(
        'moe.dihe.alisten',
        environment: {'HOME': home.path},
        executable: '/opt/alisten/alisten',
        run: (command, arguments) {
          if (command == 'gio') throw const ProcessException('gio', []);
          return run(command, arguments);
        },
      );

      expect(commands.map((call) => call.$1), [
        'update-desktop-database',
        'xdg-mime',
      ]);
      expect(commands.first.$2, [entry().parent.path]);
      expect(commands.last.$2, [
        'default',
        'moe.dihe.alisten.url-handler.desktop',
        'x-scheme-handler/moe.dihe.alisten',
      ]);
    },
  );

  test(
    'when neither gio nor xdg-mime takes the entry it is an error',
    () async {
      await expectLater(
        registerLinuxUrlScheme(
          'moe.dihe.alisten',
          environment: {'HOME': home.path},
          executable: '/opt/alisten/alisten',
          run: (_, _) async => ProcessResult(0, 3, '', ''),
        ),
        throwsA(isA<ProcessException>()),
      );
    },
  );

  test('without a home directory there is nowhere to register', () async {
    await expectLater(
      registerLinuxUrlScheme(
        'moe.dihe.alisten',
        environment: const {},
        executable: '/opt/alisten/alisten',
        run: run,
      ),
      throwsStateError,
    );
    expect(commands, isEmpty);
  });
}
