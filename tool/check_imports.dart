import 'dart:io';

const _usage = 'Usage: dart run tool/check_imports.dart [--root <package dir>]';

const _domainForbiddenDartLibraries = {
  'dart:developer',
  'dart:ffi',
  'dart:html',
  'dart:io',
  'dart:isolate',
  'dart:js',
  'dart:js_interop',
  'dart:js_util',
  'dart:ui',
};

// `part of` 指向所属库，不引入依赖，因此不匹配。
final _directive = RegExp(
  '''^[ \\t]*(?:import|export|part)\\s+(?:'([^']*)'|"([^"]*)")''',
  multiLine: true,
);

// 条件导入、导出中跟在默认 URI 之后的 `if (条件) '<uri>'` 子句，可有多个。
final _configuration = RegExp(
  '''\\s*if\\s*\\(\\s*[\\w.]+\\s*(?:==\\s*(?:'[^']*'|"[^"]*")\\s*)?\\)'''
  '''\\s*(?:'([^']*)'|"([^"]*)")''',
);

Future<List<String>> checkImports(Directory root) async {
  final packageName = await _packageName(root);
  final lib = Directory('${root.path}/lib');
  if (!await lib.exists()) return const [];
  final files = <File>[
    await for (final entity in lib.list(recursive: true, followLinks: false))
      if (entity is File && entity.path.endsWith('.dart')) entity,
  ]..sort((a, b) => a.path.compareTo(b.path));

  final violations = <String>[];
  for (final file in files) {
    final path = _libRelative(lib.path, file.path);
    final source = await file.readAsString();
    for (final match in _directive.allMatches(source)) {
      final uris = [match.group(1) ?? match.group(2)!];
      for (
        var clause = _configuration.matchAsPrefix(source, match.end);
        clause != null;
        clause = _configuration.matchAsPrefix(source, clause.end)
      ) {
        uris.add(clause.group(1) ?? clause.group(2)!);
      }
      final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
      for (final uri in uris) {
        final reason = _violation(packageName, path, uri);
        if (reason != null) violations.add('lib/$path:$line: $reason');
      }
    }
  }
  return violations;
}

Future<String> _packageName(Directory root) async {
  final pubspec = File('${root.path}/pubspec.yaml');
  final match = RegExp(
    r'^name:\s*([A-Za-z0-9_]+)',
    multiLine: true,
  ).firstMatch(await pubspec.readAsString());
  if (match == null) {
    throw FormatException('${pubspec.path} has no package name');
  }
  return match.group(1)!;
}

String _libRelative(String lib, String file) {
  return file.substring(lib.length + 1).replaceAll(r'\', '/');
}

String? _violation(String packageName, String from, String uri) {
  final fromLayer = _Layer.of(from.split('/'));
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return null;

  if (fromLayer.name == 'domain') {
    if (_domainForbiddenDartLibraries.contains(uri)) {
      return 'domain must stay pure Dart: $uri performs I/O or needs a '
          'platform runtime';
    }
    if (parsed.scheme == 'package' &&
        parsed.pathSegments.firstOrNull != packageName) {
      return 'domain must stay pure Dart: $uri is a package dependency';
    }
  }

  final target = _target(packageName, from, parsed);
  if (target == null) return null;
  final to = _Layer.of(target);
  final targetPath = target.join('/');

  switch (fromLayer.name) {
    case 'domain':
      if (to.name != 'domain') {
        return 'domain must not depend on $targetPath';
      }
    case 'shared':
      if (const {'core', 'features', 'app'}.contains(to.name)) {
        return 'shared must not depend on $targetPath';
      }
    case 'core':
      if (to.name == 'shared') {
        return 'core must not depend on shared: $targetPath';
      }
      if (to.name == 'features') {
        return 'core must not depend on features: $targetPath';
      }
      if (to.name == 'app') {
        return 'core must not depend on app: $targetPath';
      }
    case 'features':
      if (to.name == 'app') {
        return 'features must not depend on app: $targetPath';
      }
      if (to.name == 'features' &&
          to.feature != fromLayer.feature &&
          !to.isIndex) {
        return 'features may only import another feature through its '
            'index.dart: $targetPath';
      }
      if (to.feature == fromLayer.feature) {
        final from = fromLayer.section;
        if (to.isData && (from == 'application' || from == 'presentation')) {
          return '$from must not depend on its own data layer: $targetPath';
        }
        if (fromLayer.isData && to.section == 'presentation') {
          return 'data must not depend on presentation: $targetPath';
        }
      }
    default:
      if (to.name == 'features' && !to.isIndex && !to.isData) {
        return 'app may only import features through index.dart or data/: '
            '$targetPath';
      }
  }
  return null;
}

List<String>? _target(String packageName, String from, Uri uri) {
  if (uri.scheme == 'package') {
    if (uri.pathSegments.firstOrNull != packageName) return null;
    return uri.pathSegments.sublist(1);
  }
  if (uri.hasScheme) return null;
  final resolved = <String>[...from.split('/')]..removeLast();
  for (final segment in uri.pathSegments) {
    switch (segment) {
      case '.' || '':
        break;
      case '..':
        if (resolved.isEmpty) return null;
        resolved.removeLast();
      default:
        resolved.add(segment);
    }
  }
  return resolved;
}

final class _Layer {
  const _Layer(this.name, {this.feature, this.section, this.isIndex = false});

  // `lib/` 下其余文件（入口）属于组装根，按 `app` 处理。
  final String name;
  final String? feature;
  final String? section;
  final bool isIndex;

  bool get isData => section == 'data';

  factory _Layer.of(List<String> segments) {
    final first = segments.first;
    if (first == 'features' && segments.length >= 3) {
      return _Layer(
        'features',
        feature: segments[1],
        section: segments.length > 3 ? segments[2] : null,
        isIndex: segments.length == 3 && segments[2] == 'index.dart',
      );
    }
    if (const {'core', 'domain', 'shared'}.contains(first) &&
        segments.length > 1) {
      return _Layer(first);
    }
    return const _Layer('app');
  }
}

Future<void> main(List<String> arguments) async {
  try {
    String? rootPath;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--root':
          if (rootPath != null || index + 1 >= arguments.length) {
            throw const FormatException('--root requires one directory');
          }
          rootPath = arguments[++index];
        default:
          throw FormatException(
            'Unknown argument: ${arguments[index]}\n$_usage',
          );
      }
    }
    final root = rootPath == null
        ? Directory.fromUri(Platform.script.resolve('../'))
        : Directory(rootPath);
    final violations = await checkImports(root);
    if (violations.isEmpty) {
      stdout.writeln('Import boundaries check passed.');
      return;
    }
    stderr
      ..writeln(violations.join('\n'))
      ..writeln('${violations.length} import boundary violation(s).');
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 2;
  }
}
