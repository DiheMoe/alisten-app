import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

/// 把 [scheme] 协议登记给正在运行的这个程序：浏览器跳到这个协议的地址时，由系统
/// 把地址交给 App。AppImage 和免安装的 Windows 包都没有安装步骤，所以由 App 在
/// 用到之前自己登记；程序换了位置，下一次登记会跟着更新。
Future<void> registerUrlScheme(String scheme) async {
  if (Platform.isWindows) {
    registerWindowsUrlScheme(scheme, Platform.resolvedExecutable);
  } else {
    await registerLinuxUrlScheme(
      scheme,
      environment: Platform.environment,
      executable: Platform.resolvedExecutable,
    );
  }
}

void registerWindowsUrlScheme(String scheme, String executable) {
  final key = CURRENT_USER.create('Software\\Classes\\$scheme');
  try {
    key
      ..setValue('', RegistryValue.string('URL:$scheme'))
      ..setValue('URL Protocol', const RegistryValue.string(''));
    final command = key.create('shell\\open\\command');
    try {
      command.setValue('', RegistryValue.string('"$executable" "%1"'));
    } finally {
      command.close();
    }
  } finally {
    key.close();
  }
}

/// 登记用的桌面入口不出现在应用列表里（`NoDisplay`），也不与安装包自带的入口
/// 同名，免得把后者盖住。
Future<void> registerLinuxUrlScheme(
  String scheme, {
  required Map<String, String> environment,
  required String executable,
  Future<ProcessResult> Function(String command, List<String> arguments) run =
      Process.run,
}) async {
  final home = environment['HOME'];
  final dataHome =
      environment['XDG_DATA_HOME'] ??
      (home == null ? null : '$home/.local/share');
  if (dataHome == null) throw StateError('no home directory');
  // AppImage 每次运行都挂载到不同的临时目录，要登记的是 AppImage 文件本身。
  final program = environment['APPIMAGE'] ?? executable;
  final entry = '$scheme.url-handler.desktop';
  final file = File('$dataHome/applications/$entry');
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '[Desktop Entry]\n'
    'Type=Application\n'
    'Name=Alisten\n'
    'Exec=${desktopExecArgument(program)} %u\n'
    'MimeType=x-scheme-handler/$scheme;\n'
    'NoDisplay=true\n'
    'Terminal=false\n',
  );
  final type = 'x-scheme-handler/$scheme';
  Future<bool> succeeds(String command, List<String> arguments) async {
    try {
      return (await run(command, arguments)).exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  // 只设成默认还不够：入口不在这个协议的已登记应用里时，系统打开链接会说没有
  // 可用的应用。`gio mime` 两件事一起做；没有它时先刷新 MIME 缓存再设默认。
  if (await succeeds('gio', ['mime', type, entry])) return;
  await succeeds('update-desktop-database', [file.parent.path]);
  if (!await succeeds('xdg-mime', ['default', entry, type])) {
    throw const ProcessException('xdg-mime', []);
  }
}

/// 桌面入口 `Exec` 里的一个参数：整体加双引号，引号里的 `"`、`` ` ``、`$`、`\`
/// 前加反斜杠；`%` 是字段代码的前缀，写成 `%%`；最后反斜杠在键值里还要再转义
/// 一次。
String desktopExecArgument(String value) {
  final quoted = value
      .replaceAllMapped(RegExp(r'["`$\\]'), (match) => '\\${match[0]}')
      .replaceAll('%', '%%');
  return '"${quoted.replaceAll(r'\', r'\\')}"';
}
