#!/bin/bash
# VoiceType .app 打包脚本
# 用法: ./scripts/build-app.sh [release|debug]
# 产物: dist/VoiceType.app

set -e
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/VoiceType.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "📦 VoiceType .app 打包（$CONFIG）"
echo "======================"

# 1. 构建
echo "▶ 构建中..."
cd "$ROOT"
swift build -c "$CONFIG" 2>&1 | tail -3

# 2. 组装目录结构
echo "▶ 组装 app bundle..."
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

# 3. 复制可执行文件
BIN="$(swift build -c "$CONFIG" --show-bin-path)/VoiceType"
cp "$BIN" "$MACOS/VoiceType"
echo "  可执行文件: $MACOS/VoiceType"

# 4. 复制 Info.plist（补全运行时需要的键）
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>VoiceType</string>
	<key>CFBundleIdentifier</key>
	<string>com.voicetype.app</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>VoiceType</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>VoiceType 需要用麦克风将你说的转化成文字。录音仅在按住热键时进行。</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>VoiceType 使用系统语音识别将你说的话转成文字。语音会发送到 Apple 服务器进行识别。</string>
</dict>
</plist>
PLIST
echo "  Info.plist 已写入"

# 5. 生成图标（SF Symbol 转 PNG → iconset → icns）
echo "▶ 生成应用图标..."
ICON_PY="$ROOT/scripts/gen-icon.py"
if [ -f "$ICON_PY" ]; then
    python3 "$ICON_PY" "$RESOURCES"
    echo "  图标: $RESOURCES/AppIcon.icns"
else
    echo "  ⚠ 无图标脚本，跳过（可后续补充）"
fi

# 6. ad-hoc 签名（本机运行 + 测试机右键打开即可）
echo "▶ 签名（ad-hoc）..."
codesign --force --deep --sign - "$APP" 2>&1 | tail -1
codesign --verify --deep "$APP" && echo "  签名验证通过 ✓"

echo ""
echo "✅ 打包完成: $APP"
echo "   测试机安装: 拷贝到 /Applications 后右键打开（或 xattr -cr）"
