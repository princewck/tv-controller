#!/usr/bin/env bash
# 针对此次已确认的Alibaba Cloud Linux 3主机；复用已有Nginx/Certbot，不更改其余站点与系统Node22。
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo '需要root'; exit 1; }
SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
: "${CERTBOT_ACCOUNT:?使用服务器现有production ACME account ID，不新建未知邮箱账户}"
[ "$(uname -m)" = x86_64 ] || { echo '此脚本的Node构建只适配x86_64'; exit 1; }
NODE_VERSION=v24.20.0
NODE_ROOT="/opt/tv-parent-node-$NODE_VERSION"
if [ ! -x "$NODE_ROOT/bin/node" ]; then
 STAGE=$(mktemp -d)
 trap 'rm -rf "$STAGE"' EXIT
 curl --fail --silent --show-error --connect-timeout 5 --max-time 120 "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.xz" -o "$STAGE/node-$NODE_VERSION-linux-x64.tar.xz"
 curl --fail --silent --show-error --connect-timeout 5 --max-time 30 "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt" -o "$STAGE/SHASUMS256.txt"
 (cd "$STAGE"; awk -v f="node-$NODE_VERSION-linux-x64.tar.xz" '$2==f' SHASUMS256.txt > CHECKSUM; test -s CHECKSUM; sha256sum -c CHECKSUM)
 install -d -m 0755 "$NODE_ROOT"
 tar -xJf "$STAGE/node-$NODE_VERSION-linux-x64.tar.xz" -C "$NODE_ROOT" --strip-components=1
 install -m 0644 "$STAGE/CHECKSUM" "$NODE_ROOT/SOURCE-SHA256.txt"
 rm -rf "$STAGE";trap - EXIT
fi
export PATH="$NODE_ROOT/bin:$PATH"
node -e 'if(process.versions.node!=="24.20.0")process.exit(1)'
command -v nginx >/dev/null
command -v certbot >/dev/null
id tvcontrol >/dev/null 2>&1 || useradd --system --home-dir /var/lib/tv-parent-control --shell /sbin/nologin tvcontrol
install -d -o tvcontrol -g tvcontrol -m 0750 /var/lib/tv-parent-control
cd "$SOURCE"
npm ci --omit=dev --ignore-scripts
chown -R root:root "$SOURCE"
if [ ! -f /etc/tv-parent-control.env ]; then install -o root -g tvcontrol -m 0640 .env.example /etc/tv-parent-control.env; fi
sed "s|/usr/bin/node /opt/tv-parent-control/server/index.mjs|$NODE_ROOT/bin/node /opt/tv-parent-control/server/index.mjs|" deploy/tv-parent-control.service > /etc/systemd/system/tv-parent-control.service
systemctl daemon-reload
systemctl enable --now tv-parent-control
for i in $(seq 1 10); do curl -fsS --max-time 2 http://127.0.0.1:3000/healthz && break; sleep 1; done
curl -fsS --max-time 3 http://127.0.0.1:3000/healthz
CONF=/etc/nginx/conf.d/tv.example.com.conf
[ ! -f "$CONF" ] || cp -p "$CONF" "$CONF.backup-$(date +%Y%m%d%H%M%S)"
node deploy/render-nginx.mjs > "$CONF"
nginx -t
systemctl reload nginx
certbot --nginx --non-interactive --agree-tos --account "$CERTBOT_ACCOUNT" -d tv.example.com --redirect
node deploy/render-nginx.mjs --tls > "$CONF"
nginx -t
systemctl reload nginx
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
install -m 0755 deploy/reload-nginx.sh /etc/letsencrypt/renewal-hooks/deploy/tv-parent-control-nginx
# Alibaba Cloud现有Certbot未必使用Debian的certbot.timer，建立本项目独立timer。
install -m 0644 deploy/tv-certbot-renew.service /etc/systemd/system/tv-certbot-renew.service
install -m 0644 deploy/tv-certbot-renew.timer /etc/systemd/system/tv-certbot-renew.timer
systemctl daemon-reload
systemctl enable --now tv-certbot-renew.timer
curl -fsS --connect-timeout 3 --max-time 6 https://tv.example.com/healthz
