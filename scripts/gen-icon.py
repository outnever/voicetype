#!/usr/bin/env python3
"""生成 VoiceType 应用图标（SF Symbol mic.fill → iconset → icns）"""
import os
import subprocess
import sys

OUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
ICONSET = os.path.join(OUT_DIR, "AppIcon.iconset")
os.makedirs(ICONSET, exist_ok=True)

SWIFT_SRC = """
import AppKit
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let bg = NSGradient(colors: [NSColor.systemBlue, NSColor.systemIndigo])!
bg.draw(in: NSRect(x: 0, y: 0, width: size, height: size), angle: -60)
let config = NSImage.SymbolConfiguration(pointSize: 480, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "VoiceType")?.withSymbolConfiguration(config) {
    let rect = NSRect(x: (size - 480) / 2, y: (size - 480) / 2, width: 480, height: 480)
    symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
}
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

# 清理临时文件
for f in [swift_src_path, png_1024]:
    os.remove(f)
subprocess.run(["rm", "-rf", ICONSET])
print("icns generated")
