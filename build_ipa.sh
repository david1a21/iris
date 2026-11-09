#!/usr/bin/env bash
# ============================================================
#  Iris 调色盘 · iOS 打包（无需签名）
#  需要：macOS + Xcode（Command Line Tools 即可，提供 iphoneos SDK）
#  用法：bash build_ipa.sh            产出未签名 ipa
#        bash build_ipa.sh --adhoc    额外做一次 ad-hoc 签名（越狱 / TrollStore 用）
# ============================================================
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="IrisPalette"
VERSION="1.0.1"
IPA="Iris-Palette-iOS-${VERSION}.ipa"
ADHOC=0
[ "${1:-}" = "--adhoc" ] && ADHOC=1

echo "==> 环境"
xcrun --sdk iphoneos --show-sdk-version >/dev/null || {
  echo "找不到 iphoneos SDK：请先安装 Xcode 或 Command Line Tools"; exit 1; }
SDKVER="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "    iphoneos SDK ${SDKVER}"

echo "==> 清理"
rm -rf Build
mkdir -p "Build/Payload/${APP_NAME}.app"

echo "==> 编译（arm64 / iOS 16.0）"
xcrun -sdk iphoneos swiftc \
  -target arm64-apple-ios16.0 \
  -parse-as-library \
  -O -wmo \
  -framework UIKit -framework WebKit -framework Photos \
  -o "Build/Payload/${APP_NAME}.app/${APP_NAME}" \
  Sources/*.swift
echo "    $(du -h "Build/Payload/${APP_NAME}.app/${APP_NAME}" | cut -f1)"

echo "==> 装资源"
APP="Build/Payload/${APP_NAME}.app"
cp Resources/Info.plist                "$APP/Info.plist"
cp Resources/index.html                "$APP/index.html"
cp Resources/iris-ios-shim.js          "$APP/iris-ios-shim.js"
cp Resources/LaunchImage.png           "$APP/LaunchImage.png"
cp Resources/Icons/*.png               "$APP/"

echo "==> 校验 Info.plist"
plutil -lint "$APP/Info.plist"

if [ "$ADHOC" = "1" ]; then
  echo "==> ad-hoc 签名（真机仍需自签工具重签才能装）"
  codesign --force --sign - --timestamp=none "$APP"
  codesign -dv "$APP" 2>&1 | head -3 || true
fi

echo "==> 打包 ipa"
rm -f "$IPA"
(cd Build && zip -qry "../${IPA}" Payload)

echo "==> 结果"
echo "    ${IPA}  $(du -h "$IPA" | cut -f1)"
unzip -l "$IPA" | tail -6

echo
echo "未签名 ipa 不能直接装进普通 iPhone："
echo "  · 自签工具（Sideloadly / AltStore / 爱思助手）→ 用你自己的 Apple ID 重签后安装"
echo "  · 越狱 + TrollStore / AppSync → 可直接装"
echo "  · 想上架或 TestFlight → 需要 Apple Developer 账号做正式签名"
