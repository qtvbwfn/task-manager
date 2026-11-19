#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# 可选参数：目标架构（arm64 / x86_64）。缺省=本机架构。
# 指定架构时输出 "任务管理器-<arch>.app"，便于 CI 同时产出两个包。
ARCH="${1:-}"
BUILD_ARGS=()
SUFFIX=""
if [ -n "$ARCH" ]; then
    BUILD_ARGS=(--arch "$ARCH")
    SUFFIX="-${ARCH}"
fi

APP_NAME="任务管理器"
BUNDLE_DIR="${APP_NAME}${SUFFIX}.app"
EXECUTABLE="TaskManager"
ICON_SOURCE="Resources/logo.png"
ICON_NAME="AppIcon"

echo "==> 构建 release${ARCH:+ (${ARCH})}"
swift build -c release ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
BIN_DIR="$(swift build --show-bin-path -c release ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"})"

echo "==> 组装 ${BUNDLE_DIR}"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

echo "==> 生成图标 ${ICON_NAME}.icns（源 ${ICON_SOURCE}）"
ICONSET="$(mktemp -d)/${ICON_NAME}.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE_DIR/Contents/Resources/${ICON_NAME}.icns"

cat > "$BUNDLE_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>任务管理器</string>
    <key>CFBundleDisplayName</key>
    <string>任务管理器</string>
    <key>CFBundleIdentifier</key>
    <string>local.taskmanager</string>
    <key>CFBundleExecutable</key>
    <string>TaskManager</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$BUNDLE_DIR/Contents/PkgInfo"
cp "${BIN_DIR}/${EXECUTABLE}" "$BUNDLE_DIR/Contents/MacOS/${EXECUTABLE}"

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null 2>&1 || true

echo "==> 完成: ${BUNDLE_DIR}"
du -sh "$BUNDLE_DIR"
