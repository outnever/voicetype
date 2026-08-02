#!/usr/bin/env python3
"""生成 VoiceType 应用图标（自定义设计：麦克风 + AI 火花 → iconset → icns）

设计概念：
- 蓝→靛→紫渐变背景（科技/AI 感）
- 白色麦克风（语音输入）
- 右上金色四芒星火花叠在麦克风胶囊上（AI 修订/智能）
"""
import os
import subprocess
import sys

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
ICONSET = os.path.join(OUT_DIR, "AppIcon.iconset")
os.makedirs(ICONSET, exist_ok=True)

SWIFT_SRC = r"""
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// 1. 背景：对角渐变 紫 → 蓝 → 青绿
let bg = NSGradient(colorsAndLocations:
    (NSColor(calibratedRed: 0.55, green: 0.36, blue: 0.96, alpha: 1.0), 0.0),
    (NSColor(calibratedRed: 0.25, green: 0.50, blue: 0.98, alpha: 1.0), 0.55),
    (NSColor(calibratedRed: 0.03, green: 0.84, blue: 0.63, alpha: 1.0), 1.0))!
bg.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -45)

// 2. 白色圆形底板（约 70% 面积）
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 512 - 370, y: 512 - 370, width: 740, height: 740)).fill()

let micBlue = NSColor(calibratedRed: 0.00, green: 0.48, blue: 1.00, alpha: 1.0)
let aiGreen = NSColor(calibratedRed: 0.06, green: 0.72, blue: 0.51, alpha: 1.0)

// 3. 蓝色麦克风（居中偏下）
let micConfig = NSImage.SymbolConfiguration(pointSize: 250, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [micBlue]))
if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceType")?.withSymbolConfiguration(micConfig) {
    mic.draw(in: NSRect(x: 512 - 125, y: 512 - 145, width: 250, height: 250),
             from: .zero, operation: .sourceOver, fraction: 1.0)
}

// 4. 声波条（左右各 3 条，内高外低）
func waveBar(x: CGFloat, y: CGFloat, h: CGFloat) {
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 26, height: h), xRadius: 13, yRadius: 13)
    micBlue.setFill()
    path.fill()
}
waveBar(x: 238, y: 448, h: 66)
waveBar(x: 294, y: 428, h: 106)
waveBar(x: 350, y: 412, h: 138)
waveBar(x: 648, y: 412, h: 138)
waveBar(x: 704, y: 428, h: 106)
waveBar(x: 760, y: 448, h: 66)

// 5. AI 徽章（青绿圆 + 白色 AI）
aiGreen.setFill()
NSBezierPath(ovalIn: NSRect(x: 700, y: 700, width: 190, height: 190)).fill()
let aiText = "AI" as NSString
let aiAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 84, weight: .bold),
    .foregroundColor: NSColor.white,
]
let aiSize = aiText.size(withAttributes: aiAttrs)
aiText.draw(at: NSPoint(x: 795 - aiSize.width / 2, y: 795 - aiSize.height / 2), withAttributes: aiAttrs)

// 6. ↗ 箭头（青绿，右下指向 AI 徽章）
let arrowConfig = NSImage.SymbolConfiguration(pointSize: 108, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [aiGreen]))
if let arrow = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)?.withSymbolConfiguration(arrowConfig) {
    arrow.draw(in: NSRect(x: 636, y: 222, width: 108, height: 108),
               from: .zero, operation: .sourceOver, fraction: 1.0)
}

// 7. 顶部斜向光泽高光
let gloss = NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), NSColor.white.withAlphaComponent(0.0)])!
gloss.draw(in: NSRect(x: 0, y: 512, width: size, height: 512), angle: -45)

image.unlockFocus()

if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("OK")
}
"""
swift_src_path = os.path.join(OUT_DIR, "_icon_gen.swift")
with open(swift_src_path, "w") as f:
    f.write(SWIFT_SRC)

png_1024 = os.path.join(OUT_DIR, "_icon_1024.png")
subprocess.run(["swift", swift_src_path, png_1024], check=True, capture_output=True)

sizes = [16, 32, 64, 128, 256, 512]
for s in sizes:
    for scale in [1, 2]:
        px = s * scale
        name = f"icon_{s}x{s}" if scale == 1 else f"icon_{s}x{s}@2x"
        out = os.path.join(ICONSET, f"{name}.png")
        subprocess.run([
            "sips", "-z", str(px), str(px), png_1024, "--out", out
        ], check=True, capture_output=True)

subprocess.run([
    "iconutil", "-c", "icns", ICONSET, "-o", os.path.join(OUT_DIR, "AppIcon.icns")
], check=True, capture_output=True)

# 预览图（512，方便用户直接查看）
subprocess.run([
    "sips", "-z", "512", "512", png_1024, "--out", os.path.join(OUT_DIR, "icon-preview.png")
], check=True, capture_output=True)

# 清理临时文件
for f in [swift_src_path, png_1024]:
    os.remove(f)
subprocess.run(["rm", "-rf", ICONSET])
print("icns + preview generated")
