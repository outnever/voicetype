#!/bin/bash
# 从任意 1024x1024 母版 PNG 生成 AppIcon.icns
# 用法: ./scripts/make-icns-from-png.sh <master.png> <out_dir>
set -e
MASTER="$1"
OUT_DIR="$2"
ICONSET="$OUT_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

# 归一化为真正的 PNG（AI 输出的文件可能是 JPEG 内容，需先转码）
TMP_PNG="$(mktemp -d)/master.png"
if command -v magick >/dev/null 2>&1; then
    magick "$MASTER" -strip -background none PNG24:"$TMP_PNG" >/dev/null 2>&1
else
    sips -s format png "$MASTER" --out "$TMP_PNG" >/dev/null
fi
MASTER="$TMP_PNG"

# macOS 标准 iconset 命名（icon_16x16 ... icon_512x512@2x）
gen() { # name px
    sips -z "$2" "$2" "$MASTER" --out "$ICONSET/$1" >/dev/null
}
gen icon_16x16.png         16
gen icon_16x16@2x.png      32
gen icon_32x32.png         32
gen icon_32x32@2x.png      64
gen icon_128x128.png       128
gen icon_128x128@2x.png    256
gen icon_256x256.png       256
gen icon_256x256@2x.png    512
gen icon_512x512.png       512
gen icon_512x512@2x.png    1024

iconutil -c icns "$ICONSET" -o "$OUT_DIR/AppIcon.icns"
rm -rf "$ICONSET"
echo "AppIcon.icns generated from $MASTER"
