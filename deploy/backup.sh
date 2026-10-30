#!/usr/bin/env bash
# 使用随服务部署的现代SQLite，兼容阿里云旧系统sqlite3不支持STRICT表的情况。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="${NODE_BIN:-/opt/tv-parent-node-v24.20.0/bin/node}"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node)"
exec "$NODE_BIN" "$ROOT/server/backup.mjs"
