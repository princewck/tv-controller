# 逐步安装与验收

本指南由电脑端 Agent 阅读并执行。电脑需要 Python 3.9 或以上；先运行 `python3 --version`。没有 Python 时，让家长从 https://www.python.org/downloads/ 安装适合电脑系统的 Python 3，再重新打开终端验证；未准备好就暂停，不能让家长盲目继续命令。标注“家长”的动作需要遥控器或手机；其他操作由 Agent 完成。家长不需要认识命令。一次讲当前一步，成功后再继续。

适用 Android 8.0 及以上、支持首次 ADB 配置的 Android TV；包名 `org.example.tvchallenge`。不管理 Apple TV、HDMI 输入或外接播放器。不承诺未经实机验收的型号。源码入口：https://github.com/princewck/tv-controller 。

## 1. 在手机准备安装页

**家长操作：** 打开观有度 → 连接我的家庭 → 创建家庭或登录 → 我的 → 添加电视。选择“官方服务”无需填写服务器地址；将第二步安装页交给自己信任的电脑端助手。

**Agent 检查：** 取得设备标识、一次性安装码及电视 IP。安装码有效 15 分钟，只能兑换一次；不要索要密码、恢复码或 Apple 账号。官方服务对应 `https://familytv-api.princewck.workers.dev`。截图只写“官方服务”时，使用这个地址。

**遇到问题：** 手机只有演示数据，先退出演示再登录；安装码过期或已经兑换且凭证丢失，回到手机生成新的安装页。不要猜设备标识或继续用旧截图。自定义部署需使用相同每日协议和配套受信任域名的 APK；本包 APK 只接受官方地址和 `https://tv.chengkai.wang`。旧 Node 服务的手机适配接口不能代替每日协议，自定义维护者须提供与其域名匹配的 APK 和技能发行包，Agent 不修改本包信任列表或现场换签名编译。若地址不在本包支持范围，停在这一步，取得维护者发行包后按其指南继续，不执行后面的官方示例。

## 2. 让电脑和电视互通

**家长操作：** 将电脑和电视连接同一个家庭网络。电视“设置 → 网络 → 当前连接”中查看 IP，发给助手。电视自带网口也可以，只要能与电脑互通。

**Agent 检查：** 只连接该 IP，不扫描整个局域网。询问 USB 口接了什么，并单独确认是否通过 USB 网卡联网：部分机型开启调试会切断 USB 供电。若开启调试后 USB 网卡立即掉线，先停止安装，关闭调试并重新插拔网卡恢复网络；经家长确认改用电视内置 Wi-Fi／自带网口，或固件支持且不影响 USB 供电的 TLS 无线调试，再继续。不能等断网完成安装。最终关闭调试后，再确认原有线连接恢复。

**遇到问题：** 同一 Wi-Fi 名称不保证可互通。若是访客网络或开启了“设备隔离／AP 隔离”，让家长改接普通家庭网络；电脑有 VPN 时先检查其是否禁止局域网。不要要求重置路由器或永久关闭防护。

## 3. 打开开发者选项和 ADB

先找电视现成的 ADB 开关，已有就不用再开启开发者模式。

**小米／HyperOS 常见路径：** 设置 → 账号与安全 → ADB 调试，打开。名称可能是“USB 调试”或“网络调试”；按电视实际菜单确认，不保证每款位置相同。

**Android TV／Google TV 通用路径：** 设置 → 系统或设备偏好设置 → 关于 → Android TV OS 版本号／Build，连续按遥控器确认键 7 次，看到“您已处于开发者模式”；返回 → 开发者选项 → USB 调试，打开。若另有“网络／ADB 调试”开关，也打开。

**成功标志：** 调试开关为开启。仅打开开发者模式不等于 ADB 已开启。

**遇到问题：** 没有出现开发者选项，确认按的是系统版本号，不是序列号或内核版本；已提示“已经是开发者”就返回找调试开关。仍找不到时，让家长提供当前菜单文字或照片，按实际路径继续，不引导进入工厂／工程菜单。

## 4. 连接并允许这台电脑

Agent 使用已安装的 Google 官方 Platform Tools；没有则从 https://developer.android.com/tools/releases/platform-tools 下载。以下所有 `电视IP:连接端口` 都替换成本次连接地址；传统网络 ADB 通常是 5555，无线调试则以电视显示的连接端口为准。

```sh
adb connect 电视IP:连接端口
adb -s 电视IP:连接端口 get-state
```

**家长操作：** 电视出现“允许 USB 调试？”时，确认是自己的电脑，勾选“始终允许此计算机”，再选择“允许”。

**成功标志：** `get-state` 返回 `device`。随后读取厂商、型号及 SDK，并让家长确认是本次电视：

```sh
adb -s 电视IP:连接端口 shell getprop ro.product.manufacturer
adb -s 电视IP:连接端口 shell getprop ro.product.model
adb -s 电视IP:连接端口 shell getprop ro.build.version.sdk
```

**遇到问题：** `unauthorized`、`offline`、拒绝连接、macOS 权限或无线配对问题，按 [连接故障](compatibility.md#连接故障) 处理。未到 `device` 不执行安装，不把端口可连接当成授权成功。

## 5. 下载并兑换安装码

在解压后的技能目录运行。示例的设备标识、安装码替换成手机本页值，输出文件放在自己电脑的私有目录。先在不受 iCloud／网盘同步且不属于 Git 仓库的位置创建工作目录，解压技能后进入其 `family-tv-setup` 目录，执行以下命令；脚本也会以 0700 建目录、0600 写凭证，但不会纠正已有宽权限目录：

```sh
umask 077
mkdir -p ./private
chmod 700 ./private
```

下面示例使用官方服务；如果手机本页是本包支持且已确认运行每日协议的测试地址，所有 `--origin`、`--expect-origin` 都必须统一替换为本页地址，不得混用。然后下载和兑换：

```sh
python3 scripts/download-apk.py --output ./family-tv-5.0.1.apk
python3 scripts/redeem-installation.py \
  --origin https://familytv-api.princewck.workers.dev \
  --code 手机本页安装码 --device 手机本页设备标识 \
  --output ./private/device-provision.json
```

**成功标志：** 下载脚本确认版本与 SHA-256；兑换脚本确认凭证已保存。长期设备令牌只保存在权限 0600 的文件，不打印、不放命令参数或 URL、不提交 Git。

**遇到问题：** 下载失败、403、校验不符或兑换失败，按 [下载和安装故障](compatibility.md#下载和安装故障) 处理。已有文件时核对 `origin` 和 `device`；完全相同才复用，不能覆盖不同设备凭证。文件丢失时回手机生成新页，用新的私有路径，后续命令也改用该路径。

## 6. 安装并配置权限

Agent 先在上述私有目录备份当前无障碍服务列表（已设 `umask 077`）：

```sh
adb -s 电视IP:连接端口 shell settings get secure enabled_accessibility_services > ./private/accessibility-before.txt
```

只增减观有度自己的服务，保留其他应用和电视桌面。确认家长未要求暂缓安装后，运行：

```sh
python3 scripts/native-manage.py install --tv 电视IP:连接端口 \
  --apk ./family-tv-5.0.1.apk --config-file ./private/device-provision.json \
  --expect-origin https://familytv-api.princewck.workers.dev \
  --expect-device 手机本页设备标识
```

脚本先检查本页设备、地址、APK 哈希与 Android 版本，再安装并配置 DUMP、WRITE_SECURE_SETTINGS、适用版本的通知、后台和电池许可，以及本 App 的无障碍服务。每个 `pm` 命令单独执行。默认进入**观察模式**：只记录，不拦截。

**未知来源安装：** 先让 ADB 安装，成功就不让家长额外改开关。如果电视明确弹出“禁止安装未知应用”，家长进入设置 → 应用 → 特殊应用权限 → 安装未知应用，选择实际负责安装的文件管理器／安装器并允许。小米也可能放在设置 → 账号与安全 → 允许安装未知来源应用。仅对屏幕明确指出的来源授权，不能猜一个包名全局放行。ADB 安装与文件管理器安装是不同入口；没有提示就不扩大来源权限。

**成功标志：** 脚本返回成功，随后运行：

```sh
python3 scripts/native-manage.py status --tv 电视IP:连接端口
python3 scripts/device-health.py --config-file ./private/device-provision.json --require-ready
```

`status` 中 `enabled`、`native_service_running`、`accessibility_bound`、`dump_granted` 为 true，地址和设备与本页一致，出现配置之后的新心跳。配置脚本最多等待 25 秒；超时按“新心跳不出现”处理，修复后只重试一次，仍失败保留未完成。手机刷新可另等最多 45 秒，不无限等待。`device-health.py` 要求协议 2、`mode: daily`、规则快照和当前执行版本均有效。脚本返回成功仍不代表真实播放通过。

**遇到问题：** 看电视是否等待“允许安装”确认。签名不一致、SDK 过低、权限拒绝或受限设置的处理见 [下载和安装故障](compatibility.md#下载和安装故障) 和 [权限与运行故障](compatibility.md#权限与运行故障)。不要为通过安装而卸载旧数据、Root 或禁用系统包。

## 7. 先确认记录准确

**家长操作：** 实际播放腾讯视频、哔哩哔哩 TV、YouTube TV 等受管应用；保持播放至少三次采样，约 30 秒。手机按分钟显示时，应等待超过一分钟。再暂停、进入桌面，确认没有继续累计。

**成功标志：** 播放时产生新心跳与时长，暂停或非受管应用不计时。不能用脚本发假心跳代替视频。

**受管包名：** 腾讯视频 `com.ktcp.video`、哔哩哔哩 TV `com.xiaodianshi.tv.yst`、央视频 `com.newtv.cboxtv`、YouTube TV `com.google.android.youtube.tv`、FongMi `com.fongmi.android.tv`、影视客户端 `com.gitvdemo.video`、芒果 TV `com.hunantv.license`。Agent 用 `adb -s 电视IP:连接端口 shell pm list packages` 对照，不能只看应用显示名称。没有任何受管应用时，先报告当前无法做播放验收，由家长选择要用的应用；不自动安装来路不明的播放器或视频线路。

**遇到问题：** 时长不增加，先对照上述包名、确认实际出声，再检查 DUMP／无障碍权限。HDMI、外接盒子和未列入的应用不在统计范围。仍识别不到则报告该应用未通过，不能把屏幕点亮时间充当播放时间。

## 8. 开启管控并测试暂停与恢复

测试前记录当前手动暂停、原规则和已有临时额度。只有家长同意暂时允许播放、且当前不受原禁看时段或耗尽额度阻止时，才能验证“恢复播放”；不能建立这个前提就标注该项未测试，不能持续改设置凑出 `allowed`。观察通过后，Agent 执行：

```sh
python3 scripts/native-manage.py start --tv 电视IP:连接端口 \
  --config-file ./private/device-provision.json \
  --expect-origin https://familytv-api.princewck.workers.dev \
  --expect-device 手机本页设备标识
```

家长在手机选中同一电视，依次完成：实际播放 → 手机暂停 → 确认画面和声音都停止 → 手机解除暂停 → 手动恢复视频 → 确认播放、声音与计时恢复。休息时段对同一家庭全部电视生效，先征得家长同意并确认其他电视不在使用；无法安排时记录此项未测，不擅自改规则。再做一个最小禁看测试：手机“规则 → 编辑规则”记录原值，在“休息时段 · 北京时间”点“添加休息时段”，添加当前北京时间开始、持续 5 分钟、包含今天星期的临时时段，保存；保持受管视频播放，最多等 45 秒，确认停止与当前版本的 `stopped` 回执。随后删除这条临时时段并保存，最多等 45 秒，确认 `allowed`，手动恢复视频。不要修改其他家庭规则。若界面字段不支持这个时段，按实际字段设包含当前时刻的短时段，不猜 UTC 时间。

先向家长说明会增加真实可观看的 1 分钟，并取得这次发放的同意；不同意就跳过并记录未测。仅在首次配置、确认没有需要保留的临时额度时，再验证一次临时额度；已有额度就不覆盖，记录该项暂未测试。验证方法：保持手机暂停开启，临时发放 1 分钟，确认仍暂停；再解除暂停，确认可以手动恢复播放。测试额度本身属于真实授权，会被消费或过期，不把这 1 分钟当观看记录；其余测试改动必须恢复。整个验收结束后，恢复测试前记录的手动暂停状态、原规则和网络；若恢复原状态后应当禁止观看，正确结果就是 `stopped`，不要强求 `allowed`。

Agent 每次读取本设备 `device-health.py`。仅在 `applied_revision == control_revision` 时判断结果：观察为 `observing`、暂停为 `stopped`、允许为 `allowed`；`failed` 或版本不相等不通过。云端保存不等于电视执行，`allowed` 不等于播放器已自动开始。

**遇到问题：** 页面出现但声音继续、按 Home 返回后能继续偷播，或服务不支持该协议，均为未通过。按 [权限与运行故障](compatibility.md#权限与运行故障) 检查；保持系统设置和遥控器维护入口，不关闭系统按键来掩盖失败。

## 9. 验证断网和恢复

仅在已有规则快照后，先在手机暂停，联网确认 `stopped` 及当前规则快照；家长短暂断开**电视**网络，再试进入受管视频，确认仍被阻止。恢复电视网络后最多等 45 秒确认新心跳，再解除暂停，手动恢复播放并确认允许与计时。电脑网络保持可用，方便助手查看服务。

**成功标志：** 断网时执行旧规则，重连后恢复报告。离线时手机的新指令不能实时送到电视；客户端最多补传最近两天的样本。

**遇到问题：** 缓存未建立，先联网确认规则快照再测；断网后放行或时长错误，记录未通过，不改服务端健康数据。测试后恢复原网络和规则。

## 10. 关闭 ADB，再完整重启

**家长操作：** 回到第 3 步的菜单，关闭 USB／ADB／网络调试；若使用 TLS 无线调试，也关闭无线调试。`adb disconnect` 只断开电脑连接，不能代替电视关开关。如果 USB 网卡因调试中断，先在关闭调试后重新插拔网卡并确认有线网络恢复，再等新心跳。手机最多等待 45 秒；超时按“最后验收”检查网络，保持未完成。随后在系统菜单选“重启”，不是短按电源或仅熄屏。重启完成且网络恢复后，最多等 90 秒确认新心跳；仍无新心跳按“最后验收”处理，不靠反复重启通过。随后再次验证播放与暂停。

**成功标志：** 手机第三步的连接、播放拦截与恢复、权限、ADB 关闭、完整重启全部通过。Agent 最后执行：

```sh
python3 scripts/device-health.py --config-file ./private/device-provision.json --require-complete
```

只有全部通过，才让家长进入“配置完成”。不能为检查重新开启 ADB，再把它当成已关闭验收。USB 网卡用户关闭调试后重新插拔网卡，确认电视恢复有线连接。

**遇到问题：** 重启后不连、ADB 关闭项不通过或仅做了待机唤醒，见 [最后验收](compatibility.md#最后验收)。保留未完成状态，说明具体哪一项缺失。

## 撤销配置

家长要求暂缓时立即停在当前步骤。要停用已安装管控，家长重新开启调试并授权后，运行 `python3 scripts/native-manage.py stop --tv 电视IP:连接端口`，再运行相同地址的 `status`，最多等 45 秒确认 `enabled=false`、`native_service_running=false`，且无障碍列表中已无 `org.example.tvchallenge/.ControlAccessibilityService`；其他服务须与备份一致。未停用时按“停用未完成”核对一次；仍失败就明确告知家长管控可能仍在运行并交维护者处理，不声称已停用；此动作保留 APK 和私有凭证。删除家庭不能代替停用离线客户端。卸载或清数据会丢失本机状态，需家长明确要求后另行备份处理。结束时说明是否仍留调试开关，指导关闭。
