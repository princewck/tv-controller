#!/usr/bin/env bash
# Ubuntu24.04/Debian系服务器首次部署。仅部署此独立站点，不覆盖其他域名配置。
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "请以root运行"; exit 1; }
: "${CERTBOT_EMAIL:?请设置真实证书到期联系邮箱CERTBOT_EMAIL}"
SOURCE="$(cd "$(dirname "$0")/.." && pwd)"
[ -x /usr/bin/node ] && [ -x /usr/bin/npm ] || { echo "请先通过可信方式安装Node24 LTS到/usr/bin/node及/usr/bin/npm"; exit 1; }
/usr/bin/node -e 'const [m,n]=process.versions.node.split(".").map(Number);if(m!==24||n<13)process.exit(1)' || { echo "需要Node24.13+ LTS"; exit 1; }
# 要求DNS A指向此ECS，若有AAAA也必须可达；安全组入站仅需80/443，SSH限制家长IP。
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx sqlite3 rsync ca-certificates curl
id tvcontrol >/dev/null 2>&1 || useradd --system --home-dir /var/lib/tv-parent-control --shell /usr/sbin/nologin tvcontrol
install -d -m 0755 /opt/tv-parent-control
install -d -o tvcontrol -g tvcontrol -m 0750 /var/lib/tv-parent-control
# 专用站点目录；exclude保护运行数据与密钥，不复制原始电视档案到公网目录。
rsync -a --exclude=node_modules --exclude=.env --exclude=runtime --exclude=secrets --exclude=work --exclude=test "$SOURCE/" /opt/tv-parent-control/
cd /opt/tv-parent-control
npm ci --omit=dev --ignore-scripts
chown -R root:root /opt/tv-parent-control
if [ ! -f /etc/tv-parent-control.env ]; then install -o root -g tvcontrol -m 0640 .env.example /etc/tv-parent-control.env; fi
install -o root -g root -m 0644 deploy/tv-parent-control.service /etc/systemd/system/tv-parent-control.service
systemctl daemon-reload
systemctl enable --now tv-parent-control
curl --fail --max-time 5 http://127.0.0.1:3000/healthz
CONF=/etc/nginx/sites-available/tv.example.com
[ ! -f "$CONF" ] || cp -p "$CONF" "$CONF.backup-$(date +%Y%m%d%H%M%S)"
node deploy/render-nginx.mjs > "$CONF"
ln -sfn "$CONF" /etc/nginx/sites-enabled/tv.example.com
nginx -t
systemctl reload nginx
# 必须先有可访问的80站点才能运行nginx插件。失败时不伪称已经部署HTTPS。
certbot --nginx --non-interactive --agree-tos --email "$CERTBOT_EMAIL" -d tv.example.com --redirect
# 固化最终双端口配置及CSP；证书仍由Certbot管理。
node deploy/render-nginx.mjs --tls > "$CONF"
nginx -t
systemctl reload nginx
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
install -m 0755 deploy/reload-nginx.sh /etc/letsencrypt/renewal-hooks/deploy/tv-parent-control-nginx
systemctl enable --now certbot.timer
certbot renew --dry-run
curl --fail --max-time 5 https://tv.example.com/healthz
printf '\nHTTPS服务部署完成；尚未配发设备令牌，尚未启用电视拦截。\n'
