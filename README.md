# Alisten

[Alisten](https://github.com/DiheMoe/alisten) 的安卓 / iOS 客户端。

## 安装

在 [Releases](https://github.com/DiheMoe/alisten-app/releases) 下载：

| 文件 | 适用 |
|---|---|
| `Alisten-<版本>-arm64-v8a.apk` | 绝大多数 Android 手机和平板 |
| `Alisten-<版本>-armeabi-v7a.apk` | 32 位 Android 设备，例如部分电视 |
| `Alisten-<版本>-ios-unsigned.ipa` | iOS 15 及以上，未签名，需要用 AltStore、SideStore 或 Sideloadly 以自己的 Apple ID 重签后安装 |

Android 安装包使用正式签名，证书指纹写在每个版本的发布说明里。

App 启动时会向 GitHub 查询本仓库的最新正式版，发现新版本时提示更新，也可以在“设置 › 关于”里手动检查。这个请求不带任何凭据，但 GitHub 会看到设备的 IP 地址。

## 开发

需要 Flutter 3.47.9（版本固定在 `.fvmrc`）。

```bash
flutter pub get
flutter run \
  --dart-define=ALISTEN_API_URL=http://<本机地址>:<端口> \
  --dart-define=ALISTEN_ALLOW_CLEARTEXT=true
```

构建参数：

| 参数 | 说明 |
|---|---|
| `ALISTEN_API_URL` | 默认连接的服务器地址。正式构建只接受 HTTPS |
| `ALISTEN_ALLOW_CLEARTEXT` | 设为 `true` 时允许连接 HTTP 地址，只用于本地开发 |
| `ALISTEN_LINK_HOST` | 邀请链接和分享链接的域名，默认取 `ALISTEN_API_URL` 的域名 |

提交前的检查，与 CI 相同：

```bash
dart run tool/protocol_generator.dart --check
dart run tool/check_imports.dart
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-warnings --fatal-infos
flutter test
```

### 协议

`lib/core/protocol/` 下的 `*.gen.dart` 由服务端的 `protocol/idl.json` 生成，不手工修改。`protocol.lock` 固定了 IDL 的下载地址和校验值：

```bash
dart run tool/protocol_generator.dart                    # 按 protocol.lock 重新生成
dart run tool/protocol_generator.dart --source idl.json  # 用本地的 IDL 生成，联调时使用
```

### 目录

```text
lib/
  app/        应用壳：路由、主题、依赖组装
  core/       协议、实时连接、存储、日志等基础设施
  domain/     纯 Dart 的业务模型与规则
  features/   按功能划分：大厅、房间、播放、点歌、歌单、历史、设置等
  shared/     与业务无关的界面组件和设计 token
test/         与 lib 对应的测试
tool/         协议生成器和导入边界检查
```

功能之间只通过各自的 `index.dart` 引用；`domain` 不依赖 Flutter 和任何 I/O；`shared` 不依赖 `core` 和 `features`。这些边界由 `tool/check_imports.dart` 检查。

## 许可

[MIT](LICENSE)。
