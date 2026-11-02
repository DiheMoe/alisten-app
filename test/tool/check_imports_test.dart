import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_imports.dart';

const _processTimeout = Timeout(Duration(minutes: 2));

void main() {
  group('features', () {
    test('may import another feature only through its index', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "import 'package:alisten/features/b/application/b.dart';\n",
        'features/a/presentation/a_page.dart':
            "import 'package:alisten/features/b/index.dart';\n",
        'features/b/application/b.dart': '',
        'features/b/index.dart': "export 'application/b.dart';\n",
      });

      expect(violations, hasLength(1));
      expect(
        violations.single,
        startsWith('lib/features/a/application/a.dart:1'),
      );
      expect(violations.single, contains('features/b/application/b.dart'));
    });

    test('resolve relative paths before judging them', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "import '../../b/presentation/b_page.dart';\n",
        'features/a/presentation/a_page.dart':
            "import '../../b/index.dart';\n"
            "import '../application/a.dart';\n",
      });

      expect(violations, hasLength(1));
      expect(
        violations.single,
        startsWith('lib/features/a/application/a.dart:1'),
      );
    });

    test('may use their own layers, domain, core and shared freely', () async {
      final violations = await _check({
        'features/a/presentation/a_page.dart':
            "import 'package:alisten/features/a/application/a.dart';\n"
            "import 'package:alisten/domain/room/room.dart';\n"
            "import 'package:alisten/core/api/api.dart';\n"
            "import 'package:alisten/shared/widgets/w.dart';\n"
            "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
        'features/a/data/a_store.dart':
            "import 'package:alisten/features/a/application/a.dart';\n"
            "import '../../../domain/room/room.dart';\n",
      });

      expect(violations, isEmpty);
    });

    test('keep presentation and application off their own data layer, and '
        'data off presentation', () async {
      final violations = await _check({
        'features/a/presentation/a_page.dart':
            "import 'package:alisten/features/a/data/a_store.dart';\n"
            "import '../data/a_dto.dart';\n",
        'features/a/application/a.dart':
            "import 'package:alisten/features/a/data/a_store.dart';\n",
        'features/a/data/a_store.dart':
            "import 'package:alisten/features/a/application/a.dart';\n"
            "import '../presentation/a_page.dart';\n",
      });

      expect(violations, [
        allOf(
          startsWith('lib/features/a/application/a.dart:1'),
          contains('features/a/data/a_store.dart'),
        ),
        allOf(
          startsWith('lib/features/a/data/a_store.dart:2'),
          contains('features/a/presentation/a_page.dart'),
        ),
        allOf(
          startsWith('lib/features/a/presentation/a_page.dart:1'),
          contains('features/a/data/a_store.dart'),
        ),
        allOf(
          startsWith('lib/features/a/presentation/a_page.dart:2'),
          contains('features/a/data/a_dto.dart'),
        ),
      ]);
    });

    test('may not depend on app or the entry point', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "import 'package:alisten/app/assembly.dart';\n"
            "import '../../../app/router.dart';\n"
            "import 'package:alisten/main.dart';\n"
            "import 'package:alisten/features/a/index.dart';\n",
        'features/a/data/a_store.dart':
            "export 'package:alisten/app/deep_link_controller.dart';\n",
        'features/a/index.dart': "export '../../app/app.dart';\n",
      });

      expect(violations, [
        startsWith('lib/features/a/application/a.dart:1'),
        startsWith('lib/features/a/application/a.dart:2'),
        startsWith('lib/features/a/application/a.dart:3'),
        startsWith('lib/features/a/data/a_store.dart:1'),
        startsWith('lib/features/a/index.dart:1'),
      ]);
      expect(violations[0], contains('app/assembly.dart'));
      expect(violations[1], contains('app/router.dart'));
      expect(violations[2], contains('main.dart'));
    });

    test('also apply to exports', () async {
      final violations = await _check({
        'features/a/index.dart':
            "export 'package:alisten/features/b/data/b_store.dart';\n",
      });

      expect(violations, hasLength(1));
      expect(violations.single, startsWith('lib/features/a/index.dart:1'));
    });
  });

  group('app', () {
    test('may import feature indexes and data implementations', () async {
      final violations = await _check({
        'app/providers.dart':
            "import 'package:alisten/features/a/index.dart';\n"
            "import 'package:alisten/features/a/data/a_store.dart';\n"
            "import '../features/b/data/b_store.dart';\n"
            "import 'package:alisten/core/api/api.dart';\n",
      });

      expect(violations, isEmpty);
    });

    test('may not import application or presentation internals', () async {
      final violations = await _check({
        'app/providers.dart':
            "import 'package:alisten/features/a/application/a.dart';\n"
            "import 'package:alisten/features/a/presentation/a_page.dart';\n"
            "import 'package:alisten/features/a/index.dart';\n",
      });

      expect(violations, hasLength(2));
      expect(violations[0], startsWith('lib/app/providers.dart:1'));
      expect(violations[1], startsWith('lib/app/providers.dart:2'));
    });

    test('are enforced on the entry point as well', () async {
      final violations = await _check({
        'main.dart':
            "import 'package:alisten/features/a/data/a_handler.dart';\n"
            "import 'package:alisten/features/a/application/a.dart';\n",
      });

      expect(violations, hasLength(1));
      expect(violations.single, startsWith('lib/main.dart:2'));
    });
  });

  group('core', () {
    test('may not depend on features', () async {
      final violations = await _check({
        'core/realtime/transport.dart':
            "import 'package:alisten/features/a/index.dart';\n"
            "import 'package:alisten/domain/room/room.dart';\n"
            "import 'package:alisten/core/api/api.dart';\n",
      });

      expect(violations, hasLength(1));
      expect(
        violations.single,
        startsWith('lib/core/realtime/transport.dart:1'),
      );
    });

    test('may not depend on app or the entry point', () async {
      final violations = await _check({
        'core/api/api.dart':
            "import 'package:alisten/app/assembly.dart';\n"
            "import '../../main.dart';\n"
            "import 'package:flutter_riverpod/flutter_riverpod.dart';\n",
      });

      expect(violations, [
        startsWith('lib/core/api/api.dart:1'),
        startsWith('lib/core/api/api.dart:2'),
      ]);
    });

    test('may not depend on shared', () async {
      final violations = await _check({
        'core/cache/cover.dart':
            "import 'package:alisten/shared/ui/cover_art.dart';\n"
            "import '../../shared/theme/tokens.dart';\n"
            "import 'package:alisten/domain/track/track.dart';\n"
            "import 'package:flutter/widgets.dart';\n",
      });

      expect(violations, [
        allOf(
          startsWith('lib/core/cache/cover.dart:1'),
          contains('shared/ui/cover_art.dart'),
        ),
        allOf(
          startsWith('lib/core/cache/cover.dart:2'),
          contains('shared/theme/tokens.dart'),
        ),
      ]);
    });
  });

  group('shared', () {
    test('may not depend on core, features or app', () async {
      final violations = await _check({
        'shared/widgets/w.dart':
            "import 'package:alisten/core/api/api.dart';\n"
            "import 'package:alisten/features/a/index.dart';\n"
            "import 'package:alisten/app/providers.dart';\n"
            "import 'package:alisten/domain/room/room.dart';\n"
            "import 'package:flutter/material.dart';\n",
      });

      expect(violations, hasLength(3));
      for (var line = 1; line <= 3; line++) {
        expect(
          violations[line - 1],
          startsWith('lib/shared/widgets/w.dart:$line'),
        );
      }
    });
  });

  group('domain', () {
    test('may not use flutter, plugins, io or the other layers', () async {
      final violations = await _check({
        'domain/room/room.dart':
            "import 'package:flutter/foundation.dart';\n"
            "import 'package:flutter_riverpod/flutter_riverpod.dart';\n"
            "import 'package:shared_preferences/shared_preferences.dart';\n"
            "import 'dart:io';\n"
            "import 'dart:ui';\n"
            "import 'package:alisten/core/protocol/protocol.gen.dart';\n"
            "import 'package:alisten/features/a/index.dart';\n"
            "import 'package:alisten/app/assembly.dart';\n"
            "import '../../main.dart';\n",
      });

      expect(violations, hasLength(9));
      for (var line = 1; line <= 9; line++) {
        expect(
          violations[line - 1],
          startsWith('lib/domain/room/room.dart:$line'),
        );
      }
    });

    test('may use the Dart core libraries and other domain files', () async {
      final violations = await _check({
        'domain/history/stored.dart':
            "import 'dart:async';\n"
            "import 'dart:convert';\n"
            "import 'dart:math';\n"
            "import '../track/track.dart';\n"
            "import 'package:alisten/domain/room/room.dart';\n"
            "export 'package:alisten/domain/member/member.dart';\n",
      });

      expect(violations, isEmpty);
    });
  });

  group('parsing', () {
    test(
      'reads multi-line directives and reports the directive line',
      () async {
        final violations = await _check({
          'features/a/application/a.dart':
              '// header\n'
              "import 'package:alisten/features/a/index.dart'\n"
              '    show A;\n'
              'import\n'
              "    'package:alisten/features/b/application/b.dart'\n"
              '    as b;\n',
        });

        expect(violations, hasLength(1));
        expect(
          violations.single,
          startsWith('lib/features/a/application/a.dart:4'),
        );
      },
    );

    test('judges every URI of a conditional import or export', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "import 'a_stub.dart'\n"
            "    if (dart.library.io) 'package:alisten/app/assembly.dart'\n"
            '    if (dart.library.js_interop) "../../b/data/b_web.dart";\n'
            "export 'a_stub.dart' if (dart.library.io) 'a_io.dart';\n"
            "import 'package:alisten/features/b/index.dart'\n"
            "    if (dart.library.io == 'true') '../../../main.dart';\n",
        'domain/room/room.dart':
            "import 'room_stub.dart' if (dart.library.io) 'dart:io';\n",
      });

      expect(violations, [
        startsWith('lib/domain/room/room.dart:1'),
        allOf(
          startsWith('lib/features/a/application/a.dart:1'),
          contains('app/assembly.dart'),
        ),
        allOf(
          startsWith('lib/features/a/application/a.dart:1'),
          contains('features/b/data/b_web.dart'),
        ),
        allOf(
          startsWith('lib/features/a/application/a.dart:5'),
          contains('main.dart'),
        ),
      ]);
    });

    test('judges part directives, but not part of', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "part 'a.g.dart';\n"
            "part '../../../app/router.dart';\n"
            'part "package:alisten/features/b/application/b.dart";\n',
        'features/a/application/a.g.dart': "part of 'a.dart';\n",
        'features/b/application/b_part.dart':
            "part of '../../../app/router.dart';\n",
      });

      expect(violations, [
        startsWith('lib/features/a/application/a.dart:2'),
        startsWith('lib/features/a/application/a.dart:3'),
      ]);
    });

    test('ignores commented-out and quoted imports', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "// import 'package:alisten/features/b/application/b.dart';\n"
            "const s = \"import 'package:alisten/features/b/application/b.dart';\";\n"
            '/// import "package:alisten/features/b/application/b.dart";\n',
      });

      expect(violations, isEmpty);
    });

    test('only scans lib', () async {
      final violations = await _check(
        {},
        extra: {
          'test/features/a/a_test.dart':
              "import 'package:alisten/features/b/application/b.dart';\n",
          'tool/x.dart':
              "import 'package:alisten/features/b/application/b.dart';\n",
        },
      );

      expect(violations, isEmpty);
    });

    test('reads the package name from pubspec.yaml', () async {
      final violations = await _check({
        'features/a/application/a.dart':
            "import 'package:other_app/features/b/application/b.dart';\n"
            "import 'package:alisten/features/b/application/b.dart';\n",
      }, packageName: 'other_app');

      expect(violations, hasLength(1));
      expect(
        violations.single,
        startsWith('lib/features/a/application/a.dart:1'),
      );
    });
  });

  group('CLI', () {
    test('lists violations as file:line and exits 1', () async {
      final root = await _project({
        'features/a/application/a.dart':
            "import 'package:alisten/features/b/application/b.dart';\n",
      });

      final result = await _run(root);

      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr, contains('lib/features/a/application/a.dart:1'));
    }, timeout: _processTimeout);

    test('exits 0 when every import is allowed', () async {
      final root = await _project({
        'features/a/application/a.dart':
            "import 'package:alisten/features/b/index.dart';\n",
      });

      final result = await _run(root);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }, timeout: _processTimeout);
  });

  test('the repository itself complies', () async {
    expect(await checkImports(Directory.current), isEmpty);
  });
}

Future<List<String>> _check(
  Map<String, String> libFiles, {
  Map<String, String> extra = const {},
  String packageName = 'alisten',
}) async {
  final root = await _project(libFiles, extra: extra, packageName: packageName);
  return checkImports(root);
}

Future<Directory> _project(
  Map<String, String> libFiles, {
  Map<String, String> extra = const {},
  String packageName = 'alisten',
}) async {
  final root = await Directory.systemTemp.createTemp('alisten_check_imports_');
  addTearDown(() => root.delete(recursive: true));
  await File('${root.path}/pubspec.yaml')
      .writeAsString('name: $packageName\nenvironment:\n  sdk: ^3.0.0\n');
  final files = {
    for (final MapEntry(:key, :value) in libFiles.entries) 'lib/$key': value,
    ...extra,
  };
  for (final MapEntry(key: path, value: content) in files.entries) {
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }
  return root;
}

Future<ProcessResult> _run(Directory root) {
  return Process.run('dart', <String>[
    'run',
    'tool/check_imports.dart',
    '--root',
    root.path,
  ]);
}
