# 家庭云

Cloudflare Worker 与 D1 为观有度提供家庭账号、设备绑定、每日额度、控制回执、安装健康检查及 Apple 订阅权限。`tv.chengkai.wang` 为原测试服务；本 Worker 使用独立的 `familytv-production` D1 数据库。生产 API 地址为 `https://familytv-api.princewck.workers.dev`；资源已创建，应用代码是否部署以 `../release/cloud-environment.json` 的验证记录为准。

## 开发与验证

以下 npm 与 Wrangler 命令均从 `family-tv-ios/cloud/` 目录执行。

```sh
npm ci
npm test
npx wrangler d1 migrations apply DB --local
npx wrangler dev
```

`src/index.mjs` 是生产入口。Apple 凭证使用官方 App Store Server Library、Apple G3 根证书、在线 OCSP、应用与商品标识及家庭 appAccountToken 校验。永久删除家庭后的恢复还会核对新获取的 Apple AppTransaction，规则见 [订阅恢复](docs/subscription-restore.md)。库在请求内加载，OCSP 的 node-fetch v2 调用由 `src/apple-fetch.mjs` 适配。`test/verifier-worker.mjs` 是单独的本地测试入口，使用 Apple 公共测试素材验证签名与篡改拒绝，并验证真实 Apple 证书链及在线 OCSP；它不导入生产入口，也不能作为生产购买成功的证据。

普通业务测试在内存 SQLite 中模拟 D1；完整 Worker 运行时检查仍需 `wrangler dev`。本地 OCSP 检查可用 `--local-upstream familytv-api.princewck.workers.dev` 避免开发代理默认 CF-Worker 标头被 Apple 拒绝。

## 发布

从 `family-tv-ios/` 目录运行[打包脚本](../scripts/package-distribution.py)，生成本目录的 `public/downloads`。输入路径、签名构建和完整命令见[开发与候选发布](../docs/DEVELOPMENT.md#技能-zip-与版本化下载)。同一版本不得替换内容；修改已发布产物应递增 APK 或技能版本。技能清单包含精确 APK URL、哈希、大小与证书指纹，外部清单另外包含 ZIP 哈希。

首次发布需要先部署一个候选版本，才能验证手机、Apple 与电视的实际连接。部署前先通过本机测试、签名与清单检查，核对 App Store Connect 商品标识、价格以及数据处理说明。此时真实端到端检查可以尚未完成，但不得宣布服务正式可用或提交 App 审核。

从干净 checkout 开始，维护者先检查 [wrangler.jsonc](wrangler.jsonc)：`account_id`、Worker 名称与 D1 的名称／ID 必须对应自己的目标环境，`DB` 绑定需指向指定库；不要把生产库绑定到不受控预览。`PUBLIC_ORIGIN` 要与实际 HTTPS 入口及客户端信任列表相同；`APP_APPLE_ID` 是 App Store 数字 ID，`BUNDLE_ID`、`PRODUCT_ID` 须分别匹配 iOS 工程和正式订阅商品。缺少 Apple 应用 ID 时不能通过生产购买校验；来源、绑定或商品不匹配时先修正配置，不把错误当成已部署成功。本文验证路径使用 Apple 公共信任证书，不在 Worker 中配置 Apple 账号密码。

确认现有 Wrangler 登录权限对应目标账号后，回到 `family-tv-ios/cloud/` 目录执行下列命令：先应用远程 D1 迁移，再部署候选 API 与静态资源。

```sh
npx wrangler d1 migrations apply DB --remote
npx wrangler deploy
```

这些操作会改变目标服务，应在确认账号和绑定后执行。候选版本部署完成后，检查 `/healthz`、注册／登录／删除以及实际 CDN 下载字节、哈希与不可变缓存标头。检查均使用明确标注的独立测试家庭。

在 App Store Connect 为此 App 配置生产与沙盒的 App Store Server Notifications **V2**，URL 为已部署 HTTPS 入口加 `/apple/notifications`；可参照 [Apple 官方配置步骤](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications/)。当前 Worker 会验证两种环境的 Apple 签名并处理续订及撤销；测试入口 `test/verifier-worker.mjs` 不能部署为业务入口。

随后完成真实 Apple Sandbox 购买、恢复、通知、到期或退款撤权，以及手机到真实电视的播放、离线、关闭 ADB 和完整重启验收。全部 [发布检查](../release/release-gates.json) 通过后，才可以宣布正式可用、补齐实际公开支持／隐私 URL 和提审资料；候选部署或本地测试均不等于这些门槛已经通过。

D1 按家庭隔离会话、设备和观看记录。非订阅账号只读取当天数据；清理任务删除非订阅历史和超过 30 天的记录。设备的离线播放样本以唯一 ID 去重，最多接收最近两天的记录。十秒心跳会影响 Worker 和 D1 用量，正式运营前需核对账户限额与实际负载；本项目不会自动升级付费计划。

“商品配置完成”只表示后台已保存商品、周期和价格；“沙盒交易闭环”须从真实 App Store Sandbox 购买或恢复，经 Apple 签名校验到云端解锁，再验证到期或退款撤权。本地 StoreKit 文件与公共签名测试不代替此闭环。生产环境须核验部署目标、Apple 应用标识、通知处理、访问隔离和下载字节，不能为了验收发起未经授权的真实付费购买。

日期与免费“当天”按北京时间；离线上报按样本日期和时间校验，最早接受服务器当前时刻前两天的样本。已经清理的免费期历史不会因后来订阅恢复。电视缓存规则不会仅因离线自动失效；跨日和重启继续使用缓存的行为及其时钟限制见 `../service/README.md`，实机证据仍需单独完成。
