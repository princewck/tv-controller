# 电视时间 · Android TV 家长管理

电视主动连接公网 HTTPS 服务，记录受管视频应用的播放采样，在观看额度用完时暂停视频并显示算术题。支持一个站点服务多个独立家庭，由超级管理员创建普通用户。家长可以在手机或电脑的 `/admin` 查看今日和最近 30 天统计、调整规则、临时放行或设置禁看时段。

仓库包含 Android 原生客户端、Express + SQLite 后端、电视答题页、管理后台及 Nginx/systemd/Certbot 部署脚本。**不包含自定义桌面，不更换默认 Home，不禁用系统包。**没有后台 ADB、反向隧道或内网穿透。

## 复制这一句话给安装助手

需要能操作你电脑终端的 AI 助手；你仍需在电视上确认授权、操作遥控器。普通用户使用已有服务时只配置电视端，自建服务时才部署服务器。

```text
请按 https://github.com/princewck/tv-controller 的 README 和 docs/AI-INSTALL.md，先只读检查我的 Android TV，再按现有服务或自建服务完成配置、构建安装、ADB首次授权及观察/拦截验收，重点验证关闭ADB和完整重启；保护凭证、不改桌面，无法解决的固件限制请明确说明。
```

[完整安装提示词与迁移限制](docs/AI-INSTALL.md)。**只装 APK 不等于完成安装**：每台电视需重新授权 DUMP、WRITE_SECURE_SETTINGS、无障碍及后台运行相关设置；这些不是 root 提权，也不随 APK 迁移。仓库工具能完成常规首次配置，但不能绕过固件禁装、强停或无障碍撤权；未通过完整重启验收时，必须按人工恢复方案使用，不能承诺“永久防杀”。

## 能力与边界

- 默认观看阶段：30 分钟 → 连续答对 3 题 → 20 分钟 → 再答题 → 5 分钟 → 此后每 2 分钟仍需三连对验证。答错一次，连续正确数归零。
- 连续停止观看 5 小时恢复初始阶段，跨午夜不会自行重置。临时放行默认 30 分钟，可配置；它会替换旧临时额度，并以本次放行及后续最新观看时间重新计算休息起点。
- 禁看时段支持按星期、跨午夜，开始与结束相同表示所选星期全天。有效临时放行优先于禁看时段。优先顺序为：故障放行 → 临时额度 → 禁看成人确认 → 正常观看额度。
- 成人确认码由**服务端北京时间**组成：`YYYYMMDDHHmm`，各位补零，只接受当前分钟。例如 2030 年 1 月 2 日 08:05 为 `203001020805`。它是可推算的弱确认，不证明操作者成年；管理员登录另用独立口令。
- 约每 10 秒一次 HTTPS POST 心跳；后台实时展示使用 SSE，不是 WebSocket。网页答题期间继续控制通信，但服务端不计入观看时间；记录首次打开、完成及耗时，耗时包含中途离开网页的时间。
- 只有受管应用在前台，且能确认归属该应用的 MEDIA 音轨处于 started 状态时才采样。首次有效采样记 10 秒，后续按接收间隔封顶 10 秒；掉线不补记。统计有采样误差，不是逐秒视频计量，不覆盖外接 HDMI 设备。
- 网络、云端、必要权限或检测异常时放行，不使用过期 lock。离线观看无法完整统计。返回/菜单键可在答题页拦截，但普通应用无法可靠封锁系统 Home、设置、卸载或强行停止，因此本项目不是设备所有者/Kiosk 锁机方案。

Android 最低版本 8.0（SDK 26），编译/目标 SDK 34。不同 HyperOS 固件对后台启动和无障碍权限处理不同：**不附带桌面启动辅助后，不能保证完整重启后自启。必须在自己的固件上验收**；固件将应用强停或清除无障碍启用项时，需要家长重新启用。待机唤醒与系统菜单里的完整重启要分别测试。未通过自启验收时，只能把它作为需人工启动的提醒工具。

## 目录

| 路径 | 用途 |
| --- | --- |
| `android-webview/app` | 无桌面图标的原生监测、暂停及 WebView 答题容器 |
| `tv/native-manage.py` | 家长电脑上的首次安装、授权、观察/执行切换和诊断 |
| `server` | 认证、服务端判题、阶段策略、审计与 SQLite 存储 |
| `public` | 单文件电视答题页、响应式家长后台及 SVG 产品流程图 |
| `deploy` | Ubuntu/Debian、阿里云 Linux、Nginx、证书续期与备份 |
| `sql` | 建表、答题审计、上一完整周及最近 7 天 Grafana 查询 |
| `test` | 隔离数据库测试、浏览器交互测试、原生音轨解析测试 |

公开模板统一使用 `tv.example.com`，没有可用的默认管理员密码、设备令牌或已签名 APK。Android 包名为 `org.example.tvchallenge`，与私有部署的包名不同；本模板构建的 APK 不用于直接覆盖其他包名的既有安装。

## 账号、家庭与设备隔离

一个部署使用一个 HTTPS 域名，所有家庭共享入口，按账号隔离数据，而不是每个家庭部署一个域名。`admin` 是超级管理员，口令来自部署者在服务器配置的哈希文件；没有公开默认密码。旧版仅填密码的管理员登录及已有合法管理员 Cookie 可以继续使用。

| 身份 | 能力 |
| --- | --- |
| 超级管理员 `admin` | 创建/启停普通用户、重置其密码；切换家庭管理设备、规则、统计和放行 |
| 普通用户 | 只管理自己家庭的电视、阶段/禁看配置、统计、设备令牌及临时放行；不能创建用户或切换其他家庭 |
| 电视客户端 | 每台电视使用自己的设备标识和令牌；不能访问家长后台，不能自选家庭 |

每个普通账号对应一个家庭，家庭内各台电视**分别消耗额度、分别统计**，阶段和禁看配置在该家庭共享。超级管理员自己的旧设备自动归入默认家庭，已有令牌与观看流水不重建。普通家庭默认采用内置初始规则，不继承管理员自己的个性化规则。受管视频包名白名单仍是部署级设置，不支持每个家庭单独新增 APK 包名。

在 `/admin` 的“设备与账号”里：

1. 超级管理员填写普通用户名（3—32位小写字母、数字、点、横线或下划线）、家庭名称和至少10位初始密码，点击“创建普通用户”。没有开放注册或邮件发送。
2. 普通用户使用分配的用户名/密码登录同一 `/admin`，只能看到自己的家庭。超级管理员也可以从顶部选择该家庭代为配置。
3. 在目标家庭填写电视名称并“创建设备”。名称可以重复，服务器分配的设备标识不重复。
4. 下载**只显示一次**的安装凭证，移入家长电脑的 `secrets/device-provision.json`。其中包含设备令牌，不要提交或公开截图。使用配置好同一服务域名、并由家长自己签名的客户端安装：

```sh
python3 tv/native-manage.py install --tv TV_IP:5555 \
  --apk tv/dist/tv-challenge-release.apk --config-file secrets/device-provision.json
python3 tv/native-manage.py start --tv TV_IP:5555 --config-file secrets/device-provision.json
```

先按后文在 observe 核对采样和基础通信，再 start 验证暂停、答题和完整重启。凭证里的 origin 供核对，不会把 APK 自动改成其他域名；APK 仍需先正确配置域名并构建。普通用户可停用自己的设备、轮换令牌；轮换后旧令牌和旧答题会话失效，需重新交付新凭证。

停用普通用户会立即撤销其后台和答题会话，拒绝该家庭所有设备令牌，电视按故障放行处理；启用账号后设备原令牌可再次使用，后台需重新登录。重置普通用户密码会撤销其旧后台登录，**不会轮换电视令牌**。超级管理员可管理所有家庭，因此隔离保护针对普通用户之间，不限制部署者读取自己的数据库。

迁移会新增所有权、账号、家庭规则和审计表，保留旧业务表。升级前先一致性备份；先在生产库副本验证迁移，再切换服务。旧版程序不知道家庭隔离，创建普通家庭后不要直接回滚成单租户后端；如必须回滚，先停用新家庭设备并保留升级后的完整数据库，制定数据恢复方案。

## 1. 本地准备与域名配置

需要 Node.js **24.13+ 且低于 25**、Python 3.9+；Android 构建另外需要 JDK 17、Gradle **8.9**、Android SDK Platform 34 与 Build Tools 34.0.0。CI 使用 Node 24.20.0。Linux 服务器需要 systemd、Nginx，证书申请需公网域名。

```sh
git clone https://github.com/princewck/tv-controller.git
cd tv-controller
npm ci --ignore-scripts
python3 scripts/configure-domain.py tv.your-domain.com
npm test
```

把 `tv.your-domain.com` 换成自己控制的域名。本脚本只用于干净模板的首次配置，同时替换后端、网页、Android 域名校验与 Nginx/证书模板；运行一次后，不支持直接用它再次换域名。脚本不碰 `.env` 或凭证。需要改域名时，从干净模板重新配置，或逐项审核变更后重建 APK。

系统每次部署仅接受配置的这一个 HTTPS origin（协议、域名和端口组合），不接受其他域名、无 HTTPS 的服务地址或客户端提供的新地址。域名配置后，重新构建 APK 并生成 Nginx 配置。不要在电视和服务端使用不同域名。

## 2. 部署服务端

以下以 Ubuntu 24.04 / Debian 系统为例。先将配置后的源码上传到服务器的 `/opt/tv-parent-control`，不要上传个人运行目录。通过可信来源安装 Node 24.13+ 至 `/usr/bin/node` 和 `/usr/bin/npm`。域名 A 记录指向服务器；如设置 AAAA，IPv6 也必须可达。防火墙/云安全组开放 80、443，SSH 仅向管理地址开放；3000 端口只监听回环地址。

```sh
cd /opt/tv-parent-control
sudo env CERTBOT_EMAIL=your-email@example.com bash deploy/install-server.sh
```

脚本安装 `nginx certbot python3-certbot-nginx sqlite3 rsync ca-certificates curl`，创建 `tvcontrol` 运行用户，安装依赖与 systemd 服务，先生成 HTTP 站点，再自动申请证书和配置 HTTP→HTTPS 301。证书相关命令等价于：

```sh
sudo apt-get update
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx --non-interactive --agree-tos \
  --email your-email@example.com -d tv.your-domain.com --redirect
sudo certbot renew --dry-run
```

申请命令要求你已同意证书服务条款，并提供真实联系邮箱。脚本修改的是该域名的站点文件；同名旧配置会先备份。阿里云 Linux 3 可阅读 `deploy/install-aliyun.sh` 后使用：它要求源码已位于 `/opt/tv-parent-control`，机器为 x86_64，Nginx、Certbot 已安装，并通过 `CERTBOT_ACCOUNT` 指定已有 ACME 账户；独立安装 Node 24.20.0，不覆盖系统 Node。

### 管理员凭证与设备令牌

服务首次启动不会生成默认口令或设备，管理员登录在未配置时返回 503。管理员口令最少 10 字符，通过标准输入交给脚本，避免写入 shell 历史或进程参数。以下命令在服务器 **Bash** 中执行：

```bash
cd /opt/tv-parent-control
read -rsp '设置新的管理员密码: ' TV_ADMIN_PASSWORD; printf '\n'
printf '%s' "$TV_ADMIN_PASSWORD" | sudo /usr/bin/node \
  server/set-admin-password.mjs /etc/tv-parent-admin.json
unset TV_ADMIN_PASSWORD
sudo chown root:tvcontrol /etc/tv-parent-admin.json
sudo chmod 640 /etc/tv-parent-admin.json

sudo install -d -o tvcontrol -g tvcontrol -m 700 /var/lib/tv-parent-control/provision
sudo -u tvcontrol env DATABASE_PATH=/var/lib/tv-parent-control/control.sqlite \
  /usr/bin/node server/admin.mjs create-device Xiaomi_HyperOS_TV \
  /var/lib/tv-parent-control/provision/device.token
```

阿里云独立运行时需把上述 `/usr/bin/node` 换成 `/opt/tv-parent-node-v24.20.0/bin/node`。这条本地运维命令为超级管理员自己的默认家庭创建设备，兼容旧版的 `Xiaomi_HyperOS_TV`。普通用户的设备应在后台创建，会得到全局唯一标识；不要为所有家庭复用这条固定名称命令。令牌仅在本地输出文件生成一次，脚本拒绝覆盖已有文件，服务端保存其哈希。使用受信任的 SSH/SCP 将令牌取回家长电脑的 `secrets/device.token`，目录设 700、文件设 600，不在聊天、Issue、截图或 Git 中粘贴内容。

配置文件为 `/etc/tv-parent-control.env`；数据库为 `/var/lib/tv-parent-control/control.sqlite`。管理员密码文件为加盐 scrypt 哈希，不是明文，但同样不要公开。后台 Cookie 有效 120 天，Secure、HttpOnly、SameSite=Strict，写操作需要同源和 CSRF 令牌；登出撤销会话。

```sh
curl --fail https://tv.your-domain.com/healthz
sudo systemctl status tv-parent-control
sudo journalctl -u tv-parent-control --since today
```

在手机/电脑打开 `https://tv.your-domain.com/admin`，用户名填 `admin`，用刚设置的口令登录。日常修改规则、临时放行和查阅统计都在这里完成。

## 3. 构建 Android 客户端

通过 Android Studio SDK Manager 安装 Platform 34 和 Build Tools 34.0.0；安装 Gradle 8.9 并加入 PATH。设置 `ANDROID_HOME` 为本机 SDK 路径、`JAVA_HOME` 为 JDK 17 路径。也可以用 `GRADLE=/path/to/gradle` 指定 Gradle 可执行文件。本仓库不依赖其他桌面仓库或其 Gradle Wrapper。

```sh
bash android-webview/build.sh
# 输出 tv/dist/tv-challenge-debug.apk，仅供本地测试
```

正式使用应生成自己的 release 签名密钥并离线备份，保留密钥才能覆盖升级，不能用公开的统一私钥：

```sh
mkdir -p secrets
chmod 700 secrets
keytool -genkeypair -keystore secrets/tv-release.jks -alias tv-control \
  -keyalg RSA -keysize 3072 -validity 3650
# keytool 会交互询问密码，不要把密码直接写到命令行。
export TV_RELEASE_STORE_FILE="$PWD/secrets/tv-release.jks"
export TV_RELEASE_KEY_ALIAS=tv-control
read -rsp 'Keystore password: ' TV_RELEASE_STORE_PASSWORD; printf '\n'
export TV_RELEASE_STORE_PASSWORD
# 若 keytool 中设置了不同的 key 密码，这里改用单独的安全输入。
export TV_RELEASE_KEY_PASSWORD="$TV_RELEASE_STORE_PASSWORD"
bash android-webview/build.sh --release
unset TV_RELEASE_STORE_PASSWORD TV_RELEASE_KEY_PASSWORD
```

构建脚本只生成客户端 APK，不自动安装、不修改电视。`secrets/` 和 `tv/dist/` 已被忽略。debug 与 release 签名通常不同，不能直接互相覆盖；请在测试设备上选定签名，勿为升级盲目卸载或清数据。

## 4. 安装与授权：先观察，再拦截

**普通家庭请使用后台下载的安装凭证。**以下为其完整命令，`--config-file` 同时交付正确的唯一设备标识与令牌：

```sh
python3 tv/native-manage.py install --tv TV_IP:5555 --apk tv/dist/tv-challenge-release.apk --config-file secrets/device-provision.json
python3 tv/native-manage.py observe --tv TV_IP:5555 --config-file secrets/device-provision.json
# 先在 observe 核对播放/暂停采样和通信，再启用拦截测试答题：
python3 tv/native-manage.py start --tv TV_IP:5555 --config-file secrets/device-provision.json
```

本节后续的 `--token-file secrets/device.token` 示例**只针对通过服务器本地命令创建的默认家庭旧设备 `Xiaomi_HyperOS_TV`**。新家庭不得直接套用这些 token-only 示例，否则可能遗漏设备标识；改用上述凭证参数即可。`status`、`logs` 和 `stop` 都不需要凭证。

家长电脑与电视位于可互访的同一局域网。安装 Android platform-tools，将 `adb` 加入 PATH。在电视开发者选项开启 ADB/网络调试，接受授权弹窗。部分机型 USB 调试会影响 USB 音响/网卡供电，先检查这些设备。将下列 `TV_IP` 替换成电视网络设置中的当前 IP，不要使用示例文字原样运行。

```sh
adb connect TV_IP:5555
python3 tv/native-manage.py install --tv TV_IP:5555 \
  --apk tv/dist/tv-challenge-release.apk --token-file secrets/device.token
# debug 构建时将 --apk 换为 tv/dist/tv-challenge-debug.apk
python3 tv/native-manage.py status --tv TV_IP:5555
python3 tv/native-manage.py logs --tv TV_IP:5555
```

`install` 覆盖安装**一个**管控 APK，授权后默认进入 **observe 观察模式**：向后台上报，但不弹题。客户端没有桌面图标；通过上述管理工具启停。脚本授予 DUMP（读取播放状态）、WRITE_SECURE_SETTINGS（保留其他服务、恢复仍在启用列表内但崩溃的自身无障碍服务）、Android 13+ 通知权限，以及后台运行、省电白名单、Android 12+ 精确闹钟权限。无障碍用于识别前台应用、执行系统返回；不请求页面文字内容或全局按键过滤。凭证通过受限 Binder 配置入口进入应用私有目录，不放 URL、命令参数或日志。

先播放受管视频、暂停、切回首页和使用不受管应用，核对后台只有真正播放才增加观看时间。默认受管应用为腾讯视频、B站电视版、央视频、YouTube TV、OK 影视、银河奇异果、芒果 TV；音乐与桌面不计入。包名因版本而异，新增应用需同时检查 `server/config.mjs`/`MONITORED_APPS` 与 Android `NativeState.java` 的 APPS、Manifest queries，重建后验收。

安装工具会自动启用自身无障碍项；若电视弹出系统确认，请由家长确认。`status` 应显示 `enabled:true`、`mode:observe`、`dump_granted:true`、`accessibility_bound:true`，随后 `last_heartbeat_ms` 更新。观察模式同样记录观看并消耗阶段额度；切到 start 不会清零，必要时先在后台临时放行。

确认采样正常后，再显式启用拦截：

```sh
python3 tv/native-manage.py start --tv TV_IP:5555 --token-file secrets/device.token
# 仅观察，不拦截：
python3 tv/native-manage.py observe --tv TV_IP:5555 --token-file secrets/device.token
# 停止上报/拦截，移除自身无障碍项并取消恢复任务，保留数据：
python3 tv/native-manage.py stop --tv TV_IP:5555
```

`start`/`observe` 会重新交付凭证并授权，`status`/`logs`/`stop` 不需要令牌文件。DUMP 等权限被固件拒绝时应停止安装排查，不要关闭系统验证或禁用核心包。

### macOS 直连失败

如果系统 adb 因本地网络隐私限制而失败，工具会尝试 Python `adb-shell` 适配器。先创建虚拟环境，并从该环境运行管理命令：

```sh
python3 -m venv .venv
.venv/bin/pip install -r tv/requirements.txt
.venv/bin/python tv/native-manage.py status --tv TV_IP:5555
# 显式使用 Python 适配器：
.venv/bin/python tv/native-manage.py status --tv TV_IP:5555 --adb "$PWD/tv/native-adb.py"
```

适配器复用 `~/.android/adbkey`，没有时生成私有密钥，APK/配置经私有临时目录的 base64 分块上传并校验后安装；不依赖原项目。它只支持 IPv4 的普通 ADB 端口，不支持无线调试 TLS 配对端口。若普通终端也超时，检查当前 IP、路由器客户端隔离、电视 VPN、网线与 Wi-Fi 双连接；本地中转无法修复电视端不可达的问题。

### 上线前实机验收

1. 后台出现新心跳；播放时累计、暂停不累计，未监控应用不累计。心跳在线不等于正在观看。
2. 调低测试阶段额度后确认暂停、答题、三连对、答错归零及管理员放行。答题期间播放统计不增加，完成后能恢复视频。
3. 断开网络确认故障放行，恢复后能收到新指令；确认输入源、设置、音量与真实遥控器 Home 正常。
4. 分别测试待机唤醒、完整系统重启、断电开机。**此仓库没有桌面启动辅助，固件强停限制可能导致自启失败。**后台 `client_boot_seen` 表示该次开机首次收到客户端诊断，不代表准确开机时间或桌面正常。
5. 最后关闭电视 ADB/USB 调试，再播放并观察后台是否继续收到心跳；关闭后失效即未通过验收，不能以关闭前的截图代替。完成维护后撤销不再使用的 ADB 授权，不把明文 5555 端口暴露公网。

## 5. 运维、统计与故障排查

后端 `/heartbeat` 使用设备 Bearer 令牌和 `event_id` 防重复计时；`/bootstrap` 用 90 秒一次性票据换取安全 Cookie，设备长期令牌不进入网页。题目和答案在服务端产生及校验，网页自己累加“三连对”不能获得奖励。

禁看时段的成人确认成功后，会按当前配置生成临时额度（初始默认值为 30 分钟），在耗尽前覆盖禁看和正常阶段额度；耗尽后若仍在禁看时段，再次要求成人确认。

断网时，原生循环约每 10 秒检测一次，HTTPS 连接和读取各设 2 秒超时；请求失败后释放暂停用音频焦点并停止新的拦截。系统 DNS/调度可能额外延迟，不能承诺瞬时放行。已显示的答题页不会自动关闭或续播：空闲时每 2 秒轮询，单次请求最多等待 4.5 秒，失败后显示“可按返回或主页键离开”；正在提交时需先等待当前请求结束。恢复后继续轮询，以新服务端状态为准，额度耗尽仍会要求验证。验收应确认能退出网页并手动恢复播放，而非要求网页自动消失。后台 35 秒离线提示仅为展示阈值，与电视端放行超时无关。

后台显示最近心跳的服务端接收时间，精确到秒；超过 35 秒没有新心跳提示中断。可以查看 `client_boot_seen`、答题与管理员操作审计；不要公开包含观看习惯的数据库或日志。后台当前只展示启用系统之后收集的统计，不会回填 30 天历史。

```sh
# 在服务器源码目录，使用配置中的数据库路径运行：
sudo -u tvcontrol env DATABASE_PATH=/var/lib/tv-parent-control/control.sqlite \
  /usr/bin/node server/status.mjs Xiaomi_HyperOS_TV
sudo -u tvcontrol env DATABASE_PATH=/var/lib/tv-parent-control/control.sqlite \
  /usr/bin/node server/query.mjs sql/math-audit.sql
sudo bash deploy/backup.sh
```

备份使用 Node 内置 SQLite 的一致性 backup API。首次启用自动备份：复制 `deploy/tv-parent-backup.service` 和 `.timer` 到 `/etc/systemd/system/`，执行 `systemctl daemon-reload`、`systemctl enable --now tv-parent-backup.timer`。备份目录与数据一样需要私有权限；不要直接复制正在写入的单个 SQLite 文件或遗漏 WAL。

修改 HTML 后，生成器自动读取两份 HTML 并计算全部 CSP 哈希，无需手工算哈希。生成临时文件、检查差异并备份后，替换首次部署的同域名站点文件：Ubuntu/Debian 为 `/etc/nginx/sites-available/tv.your-domain.com`，阿里云 Linux 为 `/etc/nginx/conf.d/tv.your-domain.com.conf`，其中域名替换成自己的。运行 `nginx -t` 后 reload：

```sh
cd /opt/tv-parent-control
node deploy/render-nginx.mjs --tls > /tmp/tv-parent-nginx.conf
# 人工核对并备份后，将其替换到首次部署生成的同域名站点文件。
sudo nginx -t
sudo systemctl restart tv-parent-control
sudo systemctl reload nginx
```

常见问题：

| 现象 | 检查 |
| --- | --- |
| 登录 503 | 管理员哈希文件是否存在、`tvcontrol` 能否读取 |
| 403 / 页面打不开 | 域名是否一致、Nginx CSP 是否随 HTML 更新、系统时钟与证书是否正常 |
| 心跳在线但不弹题 | 是否仍在 observe、视频包名是否匹配、无障碍是否绑定、是否在故障放行 |
| 重启后无心跳 | 区分完整重启与待机；开 ADB 后查 `status`/`logs` 和无障碍项，手动 `observe`/`start` 恢复，不能声称固件已支持自启 |
| Android 14 安装卡住 | 查看电视确认弹窗；使用 Python 适配器的上传后 `pm install` 流程；不要反复卸载 |
| 观看时长不准确 | 核对音轨归属与 10 秒采样边界；外接 HDMI、静音视频或固件不提供解析信息时可能无法可靠检测 |

停止服务端或撤销设备令牌会按故障放行策略停止拦截，**不是锁死电视**。丢失 APK 签名密钥会影响后续覆盖升级。

普通家庭遇到令牌泄露时，先在“设备与账号”中停用该设备，再点击该行“轮换令牌”，下载新的安装凭证；轮换本身不会自动重新启用已停用设备。将新凭证安全存为 `secrets/device-provision.json`，然后在后台启用该设备，使用本节的 `--config-file` 命令先 observe 核对心跳，再 start。唯一设备标识用于授权，不要把可重复的电视显示名称当标识。

下列服务器本地 CLI 示例仅适用于默认家庭的旧设备 `Xiaomi_HyperOS_TV`。普通家庭统一使用上述后台流程，不套用下面的固定设备命令。先撤销，再轮换到一个尚不存在的新文件：

```sh
cd /opt/tv-parent-control
sudo -u tvcontrol env DATABASE_PATH=/var/lib/tv-parent-control/control.sqlite \
  /usr/bin/node server/admin.mjs revoke-device Xiaomi_HyperOS_TV
sudo -u tvcontrol env DATABASE_PATH=/var/lib/tv-parent-control/control.sqlite \
  /usr/bin/node server/admin.mjs rotate-token Xiaomi_HyperOS_TV \
  /var/lib/tv-parent-control/provision/device-rotated.token
```

轮换会重新启用设备，旧令牌和相关旧答题会话失效；不要用 create-device 覆盖旧设备。经 SSH 取回新令牌后，在家长电脑运行 `python3 tv/native-manage.py observe --tv TV_IP:5555 --token-file secrets/device-rotated.token`，确认新心跳后，用同一文件运行 start。重新交付前不会拦截。阿里云独立 Node 路径仍按前文替换。

Grafana 为可选独立部署：`sql/grafana-week.sql` 查询上一完整周（周一至周日），`sql/grafana-last-7-days.sql` 查询最近 7 天，均按北京时间、应用分组，分钟为秒/60.0。只读脱敏副本见 `server/export-grafana.mjs` 与 `deploy/grafana-datasource.yaml`，不要把含令牌哈希/会话的生产库直接提供给统计服务。

## 从单租户版本升级

数据库迁移由新版 `Store` 首次打开数据库时自动执行，不需要另跑 SQL；重复启动会跳过已存在的表和所有权映射。迁移保留设备、令牌哈希、观看流水与管理员 Cookie，把旧设备归入 default 家庭，数据库 `user_version` 更新为 4。

先用旧版本的 `server/backup.mjs` 对仍在运行的服务做一致性备份，再用**新版本源码**在与生产隔离的目录验证。以下环境变量只指向副本，不能改成生产路径：

```sh
# 在已安装依赖的新版本源码目录，使用 Node 24：
# 将可信备份复制为 /private-test/control-copy.sqlite，并设为600；目录不对公网开放。
DATABASE_PATH=/private-test/control-copy.sqlite node --input-type=module -e '
 const {loadConfig}=await import("./server/config.mjs");
 const {Store}=await import("./server/store.mjs");
 const store=new Store(loadConfig());
 console.log(store.get("PRAGMA user_version"));
 console.log(store.get("SELECT count(*) n FROM device_ownership"));
 store.close();'
```

版本应为 4；所有旧设备都应有 default 所有权，设备、流水数量和既有令牌哈希应与备份相同。运行 `npm test` 中的迁移与越权测试，再验证副本上的正常登录和设备流程。只有通过后，才在维护窗口短暂停止生产服务，做一次最终备份，替换源码与生成的同域名 Nginx 配置，再启动服务触发生产迁移并核对健康、老电视新心跳和后台登录。不要对正在写入的 SQLite 文件直接复制/覆盖，备份完整性及所有权按前文检查。旧版本不能作为已创建普通家庭后的直接回滚目标。

## 容量与限流

本项目为单 Node 进程 + SQLite，同步事务和 FULL 持久化保护一致性，但没有给出通用“支持多少台电视”的压测承诺。以下是代码中的保护限制，不是吞吐量保证：

| 限制 | 当前值 |
| --- | --- |
| 普通用户数量 / 家庭设备数 | 1000 个账号；每家庭最多10台设备，均为产品配额 |
| 实时后台 SSE | 全进程50条；普通用户每账号4条、超级管理员10条（一个标签页通常一条） |
| 密码计算并发 | 登录/创建用户/重置密码合计最多3个 scrypt 任务 |
| 登录失败保护 | 同一公网IP最多6次尝试/15分钟，成功后清该IP计数 |
| 通用请求限流 | Nginx 同公网IP 3次/秒、burst 15；应用同IP每分钟180次请求 |
| 进程保护 | systemd MemoryMax=256 MB，TasksMax=64，文件描述符4096 |

每台电视名义上每10秒发健康检查与心跳各一次，即每分钟12个请求。因此同一公网IP仅看稳定心跳，理论上约15台就会碰到每分钟180次限制，打开后台或答题轮询会进一步降低此数；这不是推荐接入量或压测结果。不同家庭若共用一个出口（运营商NAT/集中VPN）也共享IP限流。不能只调高设备配额就声称支持大规模服务。

播放流水最坏每台每天8640个采样，观看4小时约1440条；心跳去重回执保留24小时，不随观看时间减少。数据库、索引、WAL、备份和系统日志均占空间，需用实际样本测每条字节数，不能只按主 SQLite 文件估算。管理员数据库备份默认不自动清理，必须配置保留周期。时间索引避免每分钟清理时全表扫描，但同步 SQLite 的写延迟仍会影响所有家庭。

容量评估应在独立测试环境模拟真实10秒节奏、答题及后台SSE，观察成功率、心跳p95/p99、数据库提交时延、事件循环延迟、内存、磁盘IO和剩余空间。生产客户端连接/读取各2秒超时，超过后可能故障放行；平均响应很快不能代替长尾检查。不要在有真实观看数据的数据库中制造压测心跳。

## 开发验证与公开发布

```sh
npm ci --ignore-scripts
npm test
bash android-webview/build.sh
python3 -m py_compile tv/*.py scripts/*.py
git add .
python3 scripts/check-public.py
```

浏览器测试默认查找 macOS Chrome；其他系统可通过 `BROWSER_EXECUTABLE` 指定 Chromium/Chrome 路径，否则对应测试会显示 skip。原生解析测试需要 JDK，`JAVA_HOME` 指向 JDK 17；缺少 JDK 时也会明确 skip。CI 的 Android 作业执行 lint 与 debug 构建；不会发布 APK 或使用任何真实密钥。

`.gitignore` 拦截常见凭证、运行数据、APK、数据库和日志，检查脚本再扫描跟踪文件中的常见密钥格式与设备地址。这些措施不替代发布前人工审核，尤其不要使用 `git add -f` 提交凭证。测试里的密码均为隔离临时库的假数据，不是默认登录口令。

MIT 许可见 [LICENSE](LICENSE)。本项目面向家长授权的家庭电视，请向家庭成员说明采集范围，妥善保护观看记录。
