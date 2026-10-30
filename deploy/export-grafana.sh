#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_BIN="${NODE_BIN:-/opt/tv-parent-node-v24.20.0/bin/node}"
[ -x "$NODE_BIN" ] || NODE_BIN="$(command -v node)"
exec "$NODE_BIN" "$ROOT/server/export-grafana.mjs"
