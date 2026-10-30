#!/usr/bin/env bash
# 仅构建家长管理客户端，不构建或安装任何 HOME/桌面应用。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GRADLE="${GRADLE:-gradle}"
command -v "$GRADLE" >/dev/null || { echo '请安装 Gradle 8.9，或用 GRADLE 指定其可执行文件'; exit 1; }
"$GRADLE" --version | grep -q '^Gradle 8.9$' || { echo '此工程使用 Gradle 8.9'; exit 1; }
VARIANT=Debug
if [ "${1:-}" = --release ]; then
 : "${TV_RELEASE_STORE_FILE:?需要独立签名文件}"
 : "${TV_RELEASE_STORE_PASSWORD:?需要签名密码}"
 : "${TV_RELEASE_KEY_ALIAS:?需要密钥别名}"
 : "${TV_RELEASE_KEY_PASSWORD:?需要密钥密码}"
 VARIANT=Release
fi
"$GRADLE" -p "$ROOT/android-webview" --no-daemon ":app:lint$VARIANT" ":app:assemble$VARIANT" --console=plain
LOWER=$(printf '%s' "$VARIANT" | tr '[:upper:]' '[:lower:]')
mkdir -p "$ROOT/tv/dist"
cp "$ROOT/android-webview/app/build/outputs/apk/$LOWER/app-$LOWER.apk" "$ROOT/tv/dist/tv-challenge-$LOWER.apk"
echo "构建完成：tv/dist/tv-challenge-$LOWER.apk；未安装到电视。"
