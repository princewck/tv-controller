// 从单文件前端生成精确CSP哈希。修改HTML后必须重新生成/检查Nginx配置再发布。
import { readFileSync } from 'node:fs';
import { cspFor } from '../server/app.mjs';
const tls=process.argv.includes('--tls');
const html=readFileSync(new URL('../public/math_test.html',import.meta.url),'utf8')+readFileSync(new URL('../public/admin.html',import.meta.url),'utf8');
const body=`
    server_name tv.example.com;
    if ($host != tv.example.com) { return 444; }
    root /opt/tv-parent-control/public;
    index math_test.html;
    client_max_body_size 16k;
    client_body_timeout 5s;
    send_timeout 10s;
    server_tokens off;
    # 不记录URI：一次性票据仅在fragment，但仍避免未来查询参数意外进入访问日志。
    access_log /var/log/nginx/tv-parent-control.access.log tv_parent_safe;
    error_log /var/log/nginx/tv-parent-control.error.log warn;
    add_header Content-Security-Policy "${cspFor(html)}" always;
    add_header X-Content-Type-Options nosniff always;
    add_header X-Frame-Options DENY always;
    add_header Referrer-Policy no-referrer always;
    add_header Cache-Control no-store always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;
    # SSE长连接仅用于后台实时展示；关闭缓冲，否则动画会延迟成批出现。
    location = /admin/heartbeat_stream {
        limit_req zone=tv_parent_api burst=15 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host tv.example.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;
        proxy_cache off;
        proxy_connect_timeout 2s;
        proxy_read_timeout 75s;
        proxy_send_timeout 5s;
    }
    location ~ ^/(heartbeat|bootstrap|lock_status|answer|unlock|adult_verify|healthz|admin/(login|logout|session|stats|config|grant|users|devices|user_update|device_update|learning|displays|display_submit|display_publish|display_cancel|display_agent_token)|agent/displays)$ {
        limit_req zone=tv_parent_api burst=15 nodelay;
        limit_req_status 429;
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host tv.example.com;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 2s;
        proxy_read_timeout 5s;
        proxy_send_timeout 5s;
        proxy_hide_header Content-Security-Policy;
        proxy_hide_header X-Content-Type-Options;
        proxy_hide_header X-Frame-Options;
        proxy_hide_header Referrer-Policy;
        proxy_hide_header Cache-Control;
        proxy_hide_header Permissions-Policy;
    }
    location = /admin { try_files /admin.html =404; }
    location = /admin/ { return 301 /admin; }
    location = / { try_files /math_test.html =404; }
    location = /math_test.html { try_files $uri =404; }
    location / { return 404; }
`;
console.log(`# 置于http{}内，通过sites-enabled引入；不要重复包含。
limit_req_zone $binary_remote_addr zone=tv_parent_api:10m rate=3r/s;
log_format tv_parent_safe '$remote_addr [$time_local] $request_method $status $body_bytes_sent $request_time';
server {
    listen 80;
    listen [::]:80;
${tls?`    server_name tv.example.com;
    if ($host != tv.example.com) { return 444; }
    location /.well-known/acme-challenge/ { root /var/www/letsencrypt; }
    location / { return 301 https://tv.example.com$request_uri; }`:body}
}
${tls?`server {
    listen 443 ssl;
    listen [::]:443 ssl;
    ssl_certificate /etc/letsencrypt/live/tv.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/tv.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:TVTLS:10m;
    ssl_session_timeout 1d;
    add_header Strict-Transport-Security "max-age=31536000" always;
${body}
}`:''}`);
