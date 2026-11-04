# 开发、构建与候选发布

本文的命令均从 `family-tv-ios/` 目录执行；仓库根目录是它的上一层。安装家长电视时使用[完整安装技能](../distribution/family-tv-setup/SKILL.md)，不需要重新构建或部署服务器。以下流程供源码维护者复现构建与测试。

## iPhone 工程

本机验证环境为 Xcode 27、iOS 27 模拟器与 XcodeGen；App 最低支持 iOS 17。先安装 Xcode 命令行工具、可用的 iOS 模拟器和 XcodeGen，然后执行：

```sh
xcodegen generate
xcodebuild -project FamilyTV.xcodeproj -scheme FamilyTV \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
xcrun simctl list devices available
```

从最后一条命令中选择已安装的 iPhone 模拟器，用其实际标识替换 `可用模拟器标识`，执行两个测试目标：

```sh
xcodebuild -project FamilyTV.xcodeproj -scheme FamilyTV \
  -destination 'platform=iOS Simulator,id=可用模拟器标识' \
  -only-testing:FamilyTVTests -only-testing:FamilyTVUITests test
```

打开工程选择 FamilyTV scheme 也可运行测试。Scheme 带本地 StoreKit 配置；订阅测试使用随测试目标打包的 `Tests/FamilyTV.storekit`，不发生真实扣款，也不能证明 Apple 沙盒交易已通过。运行参数 `--demo` 进入明确标注的示例模式。Debug 默认连接测试域名，Release 默认连接独立家庭云；域名可用不代表协议兼容。

归档前在 Xcode 的 Signing & Capabilities 选择实际发布团队和合法的 bundle ID。当前团队与 App Store 商品标识属于本应用；其他维护者部署自己的应用时必须同步调整工程、商店和服务标识，不能沿用不属于自己的证书。

```sh
bash scripts/archive-release.sh
```

用 Xcode Organizer 的 Distribute App 导出或上传 App Store Connect 构建。上传后仍要核对商店验证、隐私信息、商品、截图和审核资料；归档成功不等于已经通过审核。签名密钥、证书登录凭证、IPA 和本机日志不进入 Git。

## 通用电视 APK

已验证的构建组合是 JDK 21、Gradle 8.9、Android SDK Platform 34 与 Build Tools 34.0.0。设置 `JAVA_HOME`、`ANDROID_HOME`，将 Gradle 8.9 与 SDK 工具加入 PATH；Android 编译目标仍为 Java 17。不要直接使用不匹配的 Android Studio 内置 JDK。版本兼容性见 [Gradle 官方说明](https://docs.gradle.org/8.9/userguide/compatibility.html)。

```sh
bash service/android-webview/build.sh
```

Debug APK 位于 `service/android-webview/app/build/outputs/apk/debug/app-debug.apk`，脚本还会复制到 `service/tv/dist/tv-challenge-debug.apk`。这是开发签名，不能覆盖使用正式签名的同包名安装；不为测试而卸载用户已有客户端或清除数据。

正式构建前，由持有原签名证书的维护者在本机安全注入以下环境变量：`TV_RELEASE_STORE_FILE`（私有签名文件绝对路径）、`TV_RELEASE_STORE_PASSWORD`、`TV_RELEASE_KEY_ALIAS`、`TV_RELEASE_KEY_PASSWORD`。密码不写进命令参数、文档、Git 或终端日志。然后执行：

```sh
bash service/android-webview/build.sh --release
apksigner verify --print-certs service/android-webview/app/build/outputs/apk/release/app-release.apk
```

`apksigner` 位于 Android Build Tools。Release APK 的固定输入路径是 `service/android-webview/app/build/outputs/apk/release/app-release.apk`。核对证书指纹与[技能清单](../distribution/family-tv-setup/assets/release.json)一致；不更换原签名来绕过升级冲突。APK 不含按 CPU 区分的原生库，不按电视 CPU 或型号分别构建。

Android 运行测试需要另备可丢弃的模拟器。构建 `:app:assembleDebug` 与 `:app:assembleDebugAndroidTest` 后安装两个测试 APK，以 `org.example.tvchallenge.test/androidx.test.runner.AndroidJUnitRunner` 运行 instrumentation。测试包含对模拟器无障碍设置的修改，不能在用户电视上运行。它不代替真实电视的播放、离线、关闭 ADB 与完整重启验收。

## 技能 ZIP 与版本化下载

打包脚本没有参数。它从上述 Release APK 路径和 `distribution/family-tv-setup/` 读取输入，以清单中的 SHA-256 与大小检查 APK，再按 `skill_version`、APK `version` 写入 `cloud/public/downloads/`：

```sh
python3 scripts/package-distribution.py
```

当前清单对应 APK 5.0.1、技能 1.0.2，输出是：

- `cloud/public/downloads/tv/5.0.1/family-tv.apk`
- `cloud/public/downloads/install/1.0.2/family-tv-setup.zip`
- `cloud/public/downloads/install/1.0.2/manifest.json`

源码仓库不携带已签名 APK 或 ZIP。当前 APK 哈希属于维护者已经构建的正式签名文件；Debug 构建或使用其他密钥的构建不会通过该清单。若要发布修改后的版本，先增加 APK 的 `versionName`／`versionCode` 和技能版本，更新发布清单及对应文档；构建后用 `shasum -a 256`、文件字节数及 `apksigner` 输出更新新清单，再打包。不得改写已发布版本的内容。文件已存在但字节不同时，脚本报错，应使用新版本。

打包成功只是本地产物准备完成。公网发布和真实端到端验收遵循[家庭云发布流程](../cloud/README.md#发布)，全部发布检查通过前不宣布正式可用。


## 下载版本检查

Xcode 每次构建都会执行 `scripts/check-distribution.py`。它核对 Android 源码版本、发布清单、安装工具源码、已打包文件的大小与 SHA-256，以及 App 使用的下载地址。App 的地址由清单生成，四种语言的提示词只插入该地址，不再分别保存版本号。仅修改 iPhone 界面不要求增加电视 APK 或工具版本。

首次从源码仓库构建时，先运行 `python3 scripts/check-distribution.py --fetch`，按仓库中 `distribution/downloads.json` 固定的校验值下载缺失文件。校验不通过不会保存文件；该命令不会安装到电视。

更新 APK 或安装工具后，先增加对应版本并更新 `distribution/family-tv-setup/assets/release.json`，运行 `python3 scripts/package-distribution.py`，再运行 `python3 scripts/check-distribution.py --write` 生成 App 地址和 Xcode 输入清单。已有版本不允许覆盖。运行 `python3 scripts/test-distribution.py` 可验证检查器会拒绝版本、地址或文件不一致的情况。

云端使用 `npm run deploy`：部署前检查本地文件，部署后用 `--online` 下载并核对线上文件。正式 iOS 归档使用 `bash scripts/archive-release.sh`，它先检查线上 ZIP、APK 和清单；网络不可用、文件未发布或校验不符都会停止归档。直接调用 `wrangler deploy` 或 Xcode Organizer 归档不会执行这两条命令的线上检查，但 Xcode 的本地构建检查仍然执行。
