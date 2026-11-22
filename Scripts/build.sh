#!/bin/bash
# AIChat 本地打包脚本（在 macOS + Xcode 上运行）
# 用法：
#   1. 把静态 arm64 Mach-O 的 busybox 放到 Resources/busybox（可选）
#   2. 把 worse_query CLI 放到 Resources/wq（可选）
#   3. bash Scripts/build.sh
#
# 产物：AIChat-signed.ipa（带 no-sandbox / platform-application / app-group entitlements）

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 检查依赖"
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen

echo "==> 检查内置二进制"
if [ -f "Resources/busybox" ]; then
    chmod +x Resources/busybox
    echo "busybox: $(file -b Resources/busybox)"
else
    echo "⚠️ 没有 Resources/busybox，本次构建只有远程/模拟终端"
fi
if [ -f "Resources/wq" ]; then
    chmod +x Resources/wq
    echo "wq: $(file -b Resources/wq)"
else
    echo "没有 Resources/wq，WQ 通道留空"
fi

echo "==> 生成工程"
xcodegen generate

echo "==> 编译"
set -o pipefail
xcodebuild \
    -project AIChat.xcodeproj \
    -scheme AIChat \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath build \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    build 2>&1 | tail -40

APP="build/Build/Products/Release-iphoneos/AIChat.app"

echo "==> 打包"
rm -rf Payload
mkdir -p Payload
cp -R "$APP" Payload/

echo "==> 签名内置二进制"
for BIN in busybox wq; do
    if [ -f "Payload/AIChat.app/$BIN" ]; then
        chmod +x "Payload/AIChat.app/$BIN"
        codesign --force --sign - --timestamp=none "Payload/AIChat.app/$BIN" || true
    fi
done

echo "==> 注入 entitlements 并签名 App"
codesign --force --sign - --timestamp=none --entitlements AIChat.entitlements Payload/AIChat.app
codesign -dv --entitlements - Payload/AIChat.app 2>&1 || true

echo "==> 压缩"
zip -qry AIChat-signed.ipa Payload
ls -lh AIChat-signed.ipa
echo "完成：AIChat-signed.ipa"
