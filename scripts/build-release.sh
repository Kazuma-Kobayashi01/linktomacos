#!/usr/bin/env bash
# 构建 release 包，放进 output/，按“应用名-平台-架构”命名：
#   output/Link-to-macOS-macos-arm64.zip
#   output/Link-to-macOS-android-arm64-v8a.apk          手机上的界面 App（有桌面图标）
#   output/Link-to-macOS-service-android-arm64-v8a.apk  手机上的后台服务 App（没有图标，必须一起装）
#   output/SHA256SUMS.txt
#
# 用法：scripts/build-release.sh [mac|android|all]   （默认 all）
# 需要：Xcode、XcodeGen（brew install xcodegen）、Android Studio 自带的 JDK（或设置 JAVA_HOME）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/output"
NAME="Link-to-macOS"
TARGET="${1:-all}"
MAC_ARCH="arm64"
ANDROID_ABI="arm64-v8a"

mkdir -p "$OUT"

build_mac() {
  echo "==> Mac release ($MAC_ARCH)"
  cd "$ROOT/macos"
  xcodegen generate -q
  xcodebuild -project LinkToMacOS.xcodeproj -scheme LinkToMacOS -configuration Release \
    -destination 'generic/platform=macOS' ARCHS="$MAC_ARCH" ONLY_ACTIVE_ARCH=NO \
    -derivedDataPath build -clonedSourcePackagesDirPath Packages/.spm build | tail -n 3
  local app="build/Products/Release/Link to macOS.app"
  codesign --verify --deep --strict "$app"
  rm -f "$OUT/$NAME-macos-$MAC_ARCH.zip"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$OUT/$NAME-macos-$MAC_ARCH.zip"
}

build_android() {
  echo "==> Android release ($ANDROID_ABI)"
  cd "$ROOT/android"
  export JAVA_HOME="${JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}"
  ./gradlew --console=plain :app:assembleRelease :service:assembleRelease | tail -n 3
  cp app/build/outputs/apk/release/app-release.apk "$OUT/$NAME-android-$ANDROID_ABI.apk"
  cp service/build/outputs/apk/release/service-release.apk "$OUT/$NAME-service-android-$ANDROID_ABI.apk"
}

case "$TARGET" in
  mac) build_mac ;;
  android) build_android ;;
  all) build_mac; build_android ;;
  *) echo "用法：$0 [mac|android|all]" >&2; exit 2 ;;
esac

cd "$OUT"
shasum -a 256 "$NAME"-* > SHA256SUMS.txt
echo "==> 完成"
ls -lh "$OUT"
