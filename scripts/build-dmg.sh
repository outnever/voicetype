#!/bin/bash
# VoiceType DMG 安装包打包脚本
# 产物: dist/VoiceType.dmg（打开后把 VoiceType 拖入 Applications 即完成安装）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/VoiceType.app"
VOLUME="VoiceType"
DMG="$DIST/VoiceType.dmg"
TMP_DMG="/tmp/voicetype-stage/VoiceType.tmp.dmg"
STAGE="/tmp/voicetype-stage/volume"

echo "📦 生成 VoiceType.dmg 安装包"
echo "======================"

# 1. 确保 .app 存在
if [ ! -d "$APP" ]; then
    echo "▶ 未找到 $APP，先执行打包…"
    "$ROOT/scripts/build-app.sh" release
fi

# 2. 准备 staging 目录
echo "▶ 准备内容…"
rm -rf "/tmp/voicetype-stage"
mkdir -p "$STAGE/.background" "$STAGE/.Trashes" "$STAGE/.fseventsd"

# 复制应用 + Applications 快捷方式
cp -R "$APP" "$STAGE/VoiceType.app"
ln -s /Applications "$STAGE/Applications"
touch "$STAGE/.Trashes" "$STAGE/.fseventsd"

# 卷图标（Finder 里显示的 DMG 图标）——随 staging 一并写入
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
fi

# 3. 生成 DMG 窗口背景图（紫→青绿渐变 + 交叉线条 + 引导）
echo "▶ 生成背景图…"
BG_SWIFT="/tmp/voicetype-stage/bg_gen.swift"
cat > "$BG_SWIFT" << 'SWIFT'
import AppKit

let W: CGFloat = 700, H: CGFloat = 440
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

// 背景渐变（与应用图标同款：紫 → 青绿，对角）
let bg = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.96, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.28, green: 0.50, blue: 0.95, alpha: 1.0), 0.55),
    (NSColor(calibratedRed: 0.03, green: 0.84, blue: 0.63, alpha: 1.0), 1.0))!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -45)

// 交叉几何线条（科技感）
NSColor.white.withAlphaComponent(0.08).setStroke()
let grid = NSBezierPath()
grid.lineWidth = 1.5
for offset in stride(from: -200.0, through: 900.0, by: 48.0) {
    // 斜向 /
    grid.move(to: NSPoint(x: offset, y: 0))
    grid.line(to: NSPoint(x: offset + 200, y: H))
    // 斜向 \
    grid.move(to: NSPoint(x: offset + 200, y: 0))
    grid.line(to: NSPoint(x: offset, y: H))
}
grid.stroke()

func centerText(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: NSColor.white.withAlphaComponent(alpha),
        .paragraphStyle: para,
    ]
    (string as NSString).draw(in: NSRect(x: 0, y: y, width: W, height: size + 12), withAttributes: attrs)
}

// 标题
centerText("VoiceType", y: 350, size: 40, weight: .bold, alpha: 1.0)
centerText("语音输入 · AI 纠错", y: 312, size: 18, weight: .medium, alpha: 0.9)

// 拖拽指引箭头（左图标 → 右 Applications，青绿色）
let arrowY: CGFloat = 240
let arrow = NSBezierPath()
arrow.lineWidth = 7
arrow.lineCapStyle = .round
NSColor(calibratedRed: 0.98, green: 1.00, blue: 0.96, alpha: 1.0).setStroke()
arrow.move(to: NSPoint(x: 262, y: arrowY))
arrow.line(to: NSPoint(x: 416, y: arrowY))
arrow.stroke()

// 箭头头部（三角形 →）
let head = NSBezierPath()
head.move(to: NSPoint(x: 416, y: arrowY - 16))
head.line(to: NSPoint(x: 448, y: arrowY))
head.line(to: NSPoint(x: 416, y: arrowY + 16))
head.line(to: NSPoint(x: 416, y: arrowY - 16))
head.fill()

// 指引文字
centerText("将 VoiceType 拖入 Applications 文件夹", y: 148, size: 16, weight: .medium, alpha: 0.95)

// 版本信息
centerText("版本 0.1 · macOS 14+ · Apple Silicon", y: 22, size: 13, weight: .regular, alpha: 0.7)

image.unlockFocus()
if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("OK")
}
SWIFT
swift "$BG_SWIFT" "$STAGE/.background/bg.png"

# 4. 创建临时 DMG 并挂载
echo "▶ 创建磁盘镜像…"
hdiutil detach "/Volumes/$VOLUME" >/dev/null 2>&1 || true
rm -f "$TMP_DMG"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" -ov -format UDRW "$TMP_DMG" >/dev/null
hdiutil attach "$TMP_DMG" -nobrowse -mountpoint "/Volumes/$VOLUME" >/dev/null
# 等待卷在 Finder 中可见（否则 AppleScript 拿不到 disk）
sleep 2

# 5. 用 AppleScript 布置窗口（图标位置 + 背景）
echo "▶ 布置窗口布局…"
osascript << APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {300, 100, 1000, 540}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set background picture of theViewOptions to file ".background:bg.png"
        set position of item "VoiceType.app" of container window to {175, 205}
        set position of item "Applications" of container window to {475, 205}
        update without registering applications
        close
    end tell
end tell
APPLESCRIPT

# osascript 会删掉 .VolumeIcon.icns，因此布局完成后重新写入卷图标
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
    cp "$APP/Contents/Resources/AppIcon.icns" "/Volumes/$VOLUME/.VolumeIcon.icns"
    SetFile -a C "/Volumes/$VOLUME" 2>/dev/null || true
fi

# 6. 弹出并转换为压缩格式
hdiutil detach "/Volumes/$VOLUME" >/dev/null
echo "▶ 压缩打包…"
rm -f "$DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

# 清理
rm -rf "/tmp/voicetype-stage"

echo ""
echo "✅ DMG 生成完成: $DMG"
echo "   打开后把 VoiceType 拖入 Applications 即完成安装。"
