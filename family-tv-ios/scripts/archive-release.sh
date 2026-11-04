#!/bin/bash
# 先核验线上安装文件，再生成可提审的归档；网络失败也停止。
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-distribution.py --online
xcodebuild -project FamilyTV.xcodeproj -scheme FamilyTV -configuration Release -destination 'generic/platform=iOS' -archivePath build/FamilyTV.xcarchive archive "$@"
