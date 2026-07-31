#!/bin/bash
# VoiceType 模型下载脚本 —— 通过 hf-mirror.com 直连下载 Whisper 模型
# 用法: ./scripts/download-model.sh [模型名]  默认 openai_whisper-tiny

set -e
MODEL="${1:-openai_whisper-tiny}"
MIRROR="https://hf-mirror.com"
REPO="argmaxinc/whisperkit-coreml"
DEST="$HOME/Documents/huggingface/models/$REPO/$MODEL"

echo "📥 下载模型: $MODEL → $DEST"
mkdir -p "$DEST"

# 从仓库 API 获取该模型目录下的全部文件列表
FILES=$(curl -s --max-time 30 "$MIRROR/api/models/$REPO/tree/main/$MODEL?recursive=true&expand=true" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for f in d:
    if f['type'] == 'file':
        print(f['path'])
")

COUNT=0
TOTAL=$(echo "$FILES" | wc -l | tr -d ' ')
echo "共 $TOTAL 个文件"

for f in $FILES; do
    REL="${f#$MODEL/}"
    OUT="$DEST/$REL"
    mkdir -p "$(dirname "$OUT")"
    echo "[$((COUNT+1))/$TOTAL] $REL"
    curl -sL --max-time 600 -o "$OUT" "$MIRROR/$REPO/resolve/main/$f"
    COUNT=$((COUNT+1))
done

echo "✅ 下载完成: $COUNT 个文件"
echo "模型位置: $DEST"
