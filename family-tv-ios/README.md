# 观有度 / Family TV

支持中文、English、한국어、日本語，默认跟随系统，也可在“我的 → 语言”中选择。安排规则前，请阅读[减少打扰与使用说明](docs/responsible-use.md)。

原生 iPhone 家长管理端，为安装配套客户端的 Android TV 设置每日观看额度、休息时段、暂停和临时额度。基础设备管理与控制免费；家庭云 Plus 通过 Apple 月度自动续订提供最近 30 天云端历史、跨设备记录与趋势分析，目标美国定价 US$9.90／月，以商店配置的本地价格为准。需要 iOS 17 或以上。

没有账号也可体验明确标注的本机演示模式。正式服务支持创建家庭、保存恢复码、找回密码以及删除家庭与云端数据；开发用旧服务可能不支持这些接口。密码不保存在手机，登录凭证存于钥匙串。

手机“添加电视”仅包含四步：同一 Wi-Fi、截图交给 Agent、连接健康检查、配置完成。Agent 下载带版本号的完整技能 ZIP，先读 `SKILL.md`，再下载清单指定的通用 APK，完成安装、权限配置和实际播放测试，最后关闭 ADB，由 Agent 指导家长完成真正的系统重启并复测。安装流程与兼容性要求集中在 [distribution/family-tv-setup/SKILL.md](distribution/family-tv-setup/SKILL.md)。没有已验证的真实机型时，不承诺型号兼容。

生产服务源码在 `cloud/`，使用 Cloudflare Worker 与 D1。APK 和技能 ZIP 使用 Worker Static Assets，通过 Cloudflare CDN 提供。每个下载 URL 包含版本号、使用不可变缓存，并配套 SHA-256；`scripts/package-distribution.py` 拒绝用不同字节覆盖已有版本。`tv.chengkai.wang` 是测试环境；生产地址为 `familytv-api.princewck.workers.dev`。创建云端资源不代表应用代码已部署，部署情况以发布证据为准。

`service/` 保留原 Node 网页服务作为测试适配器，以及新版原生电视源码。新 APK 采用每日额度与离线规则，不运行旧网页服务的学习挑战流程。协议不能直接混用。完整源码维护入口为 https://github.com/princewck/tv-controller 。

在本目录执行 `xcodegen generate`，打开 `FamilyTV.xcodeproj`，选择 FamilyTV scheme。App 使用系统 SwiftUI、Charts、URLSession、StoreKit 2 和钥匙串，无第三方运行依赖。构建、两个测试目标和签名归档的完整命令见[开发与候选发布](docs/DEVELOPMENT.md)。测试目标为 FamilyTVTests 与 FamilyTVUITests；`--demo` 不连接真实电视，也不发起真实购买。

发布前完成 [release/release-gates.json](release/release-gates.json)。本地测试、签名构建与可提交的商店版本分别记录，不互相代替。商店文案草案在 [release/store-metadata.zh-Hans.json](release/store-metadata.zh-Hans.json)，签名、CDN、公网 API、商品与价格配置、真实沙盒交易闭环和实机验收未通过前不提审。
