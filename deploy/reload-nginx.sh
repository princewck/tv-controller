#!/usr/bin/env bash
set -euo pipefail
/usr/sbin/nginx -t
systemctl reload nginx
