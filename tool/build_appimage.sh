#!/usr/bin/env bash
# 把 `flutter build linux --release` 的产物装成 AppImage。
# 用法：tool/build_appimage.sh <版本号>；appimagetool 不在 PATH 里时用 APPIMAGETOOL 指定。
set -euo pipefail

version=$1
root=$(cd "$(dirname "$0")/.." && pwd)
bundle=$root/build/linux/x64/release/bundle
appdir=$root/build/linux/AppDir
output=$root/build/linux/Alisten-$version-x86_64.AppImage

test -x "$bundle/alisten" || { echo "先运行 flutter build linux --release" >&2; exit 1; }

rm -rf "$appdir"
mkdir -p "$appdir"
cp -a "$bundle/." "$appdir/"
cp "$root/linux/packaging/AppRun" "$root/linux/packaging/moe.dihe.alisten.desktop" \
  "$root/linux/packaging/moe.dihe.alisten.png" "$appdir/"
ln -s moe.dihe.alisten.png "$appdir/.DirIcon"

# 不依赖 FUSE：CI 的容器里没有它。
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "${APPIMAGETOOL:-appimagetool}" "$appdir" "$output"
echo "$output"
