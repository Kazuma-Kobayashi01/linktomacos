#!/usr/bin/env bash
# 把 adb 放进 Mac App 包（Contents/Helpers/adb），用户不必另外安装 Android 平台工具。
# 由 Xcode 的构建阶段调用：scripts/bundle-adb.sh "<App 包路径>"
#
# adb 的来源，按顺序找：
#   1. 环境变量 ADB_SOURCE（指向一个 adb 可执行文件）
#   2. ANDROID_HOME / ANDROID_SDK_ROOT / ~/Library/Android/sdk 里的 platform-tools/adb
#   3. Homebrew 的 adb
# 都没有就报错并说明怎么办（脚本不会自己下载东西）。adb 本身不进 git，每次构建时从本机复制，
# 只取 arm64 部分并重新签名；许可证（Apache-2.0）文本一并放进 Resources。
set -euo pipefail

APP="${1:?用法：bundle-adb.sh <App 包路径>}"
HELPERS="$APP/Contents/Helpers"
RESOURCES="$APP/Contents/Resources"

find_adb() {
  local candidate
  for candidate in \
    "${ADB_SOURCE:-}" \
    "${ANDROID_HOME:+$ANDROID_HOME/platform-tools/adb}" \
    "${ANDROID_SDK_ROOT:+$ANDROID_SDK_ROOT/platform-tools/adb}" \
    "$HOME/Library/Android/sdk/platform-tools/adb" \
    "/opt/homebrew/bin/adb" \
    "/usr/local/bin/adb"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if ! SOURCE="$(find_adb)"; then
  echo "error: 没有找到 adb，无法放进 App 包。请先安装 Android 平台工具（Android Studio 自带，或 brew install android-platform-tools），" >&2
  echo "       或用环境变量 ADB_SOURCE 指定一个 adb 可执行文件。" >&2
  exit 1
fi

mkdir -p "$HELPERS" "$RESOURCES"
rm -f "$HELPERS/adb"
if lipo -archs "$SOURCE" 2>/dev/null | grep -q arm64 && [ "$(lipo -archs "$SOURCE" | wc -w | tr -d ' ')" -gt 1 ]; then
  lipo -thin arm64 "$SOURCE" -output "$HELPERS/adb"
else
  cp "$SOURCE" "$HELPERS/adb"
fi
chmod 755 "$HELPERS/adb"
codesign --force --sign - "$HELPERS/adb"

# platform-tools 自带的许可证说明（和 adb 在同一个目录）
NOTICE="$(dirname "$SOURCE")/NOTICE.txt"
if [ -f "$NOTICE" ]; then
  cp "$NOTICE" "$RESOURCES/adb-NOTICE.txt"
fi
echo "bundled adb: $("$HELPERS/adb" version | sed -n 2p)"
