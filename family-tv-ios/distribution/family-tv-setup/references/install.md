# 安装与验收

## 先核对输入

本技能适用于 Android 8.0 及以上、具有 ADB 初次配置能力的 Android TV。APK 包名为 `org.example.tvchallenge`，协议为每日观看额度与休息时段。需要手机安装页中的服务地址、设备标识和十五分钟内有效的一次性安装码，以及本次电视的 IP。电脑与电视需连接同一 Wi-Fi；若网络启用了客户端隔离，先解决连接问题，不扫描整个局域网。家长需要在电视上开启初次调试并接受授权。

截图中的服务地址必须是 `https://familytv-api.princewck.workers.dev` 或测试地址 `https://tv.chengkai.wang`。测试服务仍需支持本技能协议；仅有相同域名不代表版本兼容。先请求该地址的 `/healthz`，确认服务可用。兑换安装码后使用下文的 `device-health.py` 检查协议；旧协议要报告服务需升级。

本技能没有全局安装要求。解压后直接读取并执行脚本即可；如果用户希望长期安装为技能，再使用该 Agent 支持的技能安装方式，不覆盖它已有的同名技能。仓库源码与维护入口为 https://github.com/princewck/tv-controller 。

## 下载和绑定

在技能目录运行：

```sh
python3 scripts/download-apk.py --output ./family-tv-5.0.1.apk
python3 scripts/redeem-installation.py \
  --origin https://familytv-api.princewck.workers.dev \
  --code 手机本页安装码 \
  --device 手机本页设备标识 \
  --output ./private/device-provision.json
```

示例中的完整服务地址、安装码和设备标识要替换为截图中的值；服务地址包含一次 `https://`。兑换脚本仅发送短效安装码，并将长期令牌保存为权限 0600 的私有文件。不要打印该文件、提交 Git、把令牌放在命令行或 URL 中。兑换失败不会输出响应里的秘密。

安装码只能兑换一次。电脑已有凭证时，先在本机核对其中的 `origin` 和 `device` 与此次截图完全一致，只有匹配时才复用。已兑换但文件丢失、已过期或不匹配时，让家长回到手机生成新的安装页；不覆盖旧凭证，也不反复尝试兑换。新凭证使用新的私有路径，例如 `./private/device-provision-2.json`，后续命令也使用同一路径。生成新页可能改变设备标识，后续操作要使用新页。

下载脚本使用 `assets/release.json` 中包含版本号的 HTTPS URL，拒绝重定向并校验 SHA-256。标准 Android SDK 的 `apksigner verify --print-certs` 可进一步核对清单里的签名证书指纹。已安装同包名应用时，升级必须保持签名一致；遇到签名冲突时停下说明，不通过卸载、清数据或换签名绕过。

使用本机已安装的 Android SDK `adb`。没有时从 Google 官方 Android SDK Platform Tools 安装。本技能只使用官方工具，凭证通过 stdin 写入电视，不通过含有可还原凭证的命令字符串传输。若本机无法访问局域网，先由家长检查电脑的局域网访问许可、电视授权和 Wi-Fi 隔离，再继续；不要换用不明 ADB 二进制。

```sh
python3 scripts/native-manage.py install --tv 电视IP:5555 \
  --apk ./family-tv-5.0.1.apk --config-file ./private/device-provision.json \
  --expect-origin https://familytv-api.princewck.workers.dev --expect-device 手机本页设备标识
```

`install` 默认观察模式，只监测；先保留该模式完成下文观察测试。`start` 才启用执行模式，若已提前启用，可用 `observe` 动作和相同参数回到观察模式。脚本会授予已声明的 DUMP、WRITE_SECURE_SETTINGS、适用版本的通知权限，启用此 App 的无障碍服务及适用的后台许可。保留其他无障碍服务和电视桌面。脚本返回成功后执行：

```sh
python3 scripts/native-manage.py status --tv 电视IP:5555
python3 scripts/device-health.py --config-file ./private/device-provision.json --require-ready
```

`status` 输出的 `enabled`、`native_service_running`、`accessibility_bound`、`dump_granted` 应为 true，`device` 和 `origin` 必须匹配截图，`last_heartbeat_ms` 应在 45 秒内更新。`device-health.py` 通过私有文件中的令牌访问本设备 `/device/status`，不需要家庭账号密码；它检查协议版本 2、`mode: daily` 和规则快照。它打印的 `control_revision` 是云端控制版本，`applied_revision` 是电视收到的版本，`enforcement_result` 是执行结果。只有版本相同且结果符合测试动作，才能说明电视执行了本次指令。首次没有新心跳或权限尚未报告时保持等待，不单凭授权命令判断。

回执按以下值判断，均需 `applied_revision == control_revision`：

| 测试动作 | `enforcement_result` | 还需观察 |
| --- | --- | --- |
| 观察模式 | `observing` | 计时正确，不执行拦截 |
| 手机暂停、额度耗尽或进入休息时段 | `stopped` | 受管视频画面和声音确实停止 |
| 手机解除暂停或规则恢复允许 | `allowed` | 家长手动恢复播放后，画面、声音和计时恢复 |
| 任何动作返回 `failed`，或版本不同 | 不通过 | 检查权限和实际播放器行为后重测 |

云端允许观看不等于播放器已经自动开始；`allowed` 与手动恢复后的新播放心跳结合，才可认定恢复测试通过。手机“今天”页的执行状态显示当前回执，“添加电视”的第三步汇总健康检查；本脚本的 `boot_count` 可用于核对真正重启后的启动计数。

示例中的 `电视IP:5555` 是电视上启用的连接地址，端口可以替换为实际端口。TLS 无线调试先用官方 `adb pair IP:配对端口` 完成家长确认，再将电视显示的**连接端口**传给 `--tv`，不要使用配对端口。用 `--adb /绝对路径/adb` 指定官方工具。TLS 配对与连接必须先由家长在电视上授权，本技能不自动降级调试方式。

`--expect-origin` 和 `--expect-device` 必须填写本次截图中的完整值；脚本在连接电视前核对私有文件。`install` 还会核对 APK 哈希，并在写权限或安装前检查 Android 版本。脚本记录配置前的心跳，并等待状态匹配及配置后更新的心跳才返回成功；这仍不代替实际播放测试。

`device-health.py` 不带门禁参数时只读取诊断；协议请求成功不表示健康通过。`--require-ready` 在规则快照、权限、新心跳或当前执行版本不正常时返回非零；完整验收最后使用 `--require-complete`，要求全部手机检查都通过。


## 实际播放测试

先在观察模式播放一个受管视频，确认计时增加；暂停、待机或打开未受管应用时，确认不误计。受管应用包括腾讯视频、哔哩哔哩 TV、YouTube TV、芒果 TV 等已列入客户端的包；HDMI、外接设备及其他应用不在统计范围内。

观察测试至少等待三次采样，约 30 秒；界面按分钟显示时应等待超过一分钟。采样误差约为一个采样间隔，不能把短暂的计时延迟当成通过或失败。

观察测试通过后启用执行模式：

```sh
python3 scripts/native-manage.py start --tv 电视IP:5555 \
  --config-file ./private/device-provision.json \
  --expect-origin https://familytv-api.princewck.workers.dev --expect-device 手机本页设备标识
```

让家长在手机选中同一台电视：

1. 在电视上实际播放受管视频，记录手机的新心跳和观看计时。
2. 手机点击暂停，确认视频画面和声音都停止，并收到当前控制版本的停止回执。只看到休息页而声音仍播放，不通过。
3. 手机解除暂停，家长手动恢复视频，确认播放和计时恢复。临时额度不能绕过家长的手动暂停。
4. 测试一次每日额度或休息时段；临时更改规则前记录原值，测试后恢复。不要调整其他家庭或其他设备。
5. 在已经收到规则快照后短暂断开电视网络，验证缓存规则仍执行。恢复网络后确认新心跳和补传计时；离线期间手机无法实时下发新规则。客户端最多补传最近两天的记录，采样存在误差。

随后让家长在手机进入“看看连接是否健康”。它根据本次设备的新心跳校验连接、权限、实际拦截与恢复、ADB 关闭和完整重启。助手不能直接写服务数据把检查改成通过。接口缺失、必要字段缺失或固件无法支持时，说明未通过的项目和下一步。

## 关闭 ADB，然后真正重启

先完成播放测试，再引导家长关闭电视 ADB／USB 调试。`adb disconnect` 只断开电脑连接，不等于关闭电视 ADB。等待手机收到关闭后的新心跳，确认 ADB 检查通过，播放控制仍正常。

然后让家长选择系统菜单中的**重启**，不要点“关机”：某些电视的关机只是熄屏或待机。关闭 ADB 后，不再假定能从电脑发重启命令；由家长用遥控器执行系统重启，必要时明确断电再开机。

在手机等待启动计数增加、新心跳和全部健康检查通过，再复测一次播放暂停与恢复。此时电脑无需 ADB，仍可用 HTTPS 对本次绑定读取最终结果：

```sh
python3 scripts/device-health.py --config-file ./private/device-provision.json --require-complete
```

此命令与手机健康检查使用相同的服务端判据，不能代替家长对实际画面与声音的观察。不能用待机唤醒、旧在线状态或已注册开机广播代替重启验收。全部通过后告知家长在手机完成配置；未通过则保持未完成状态，说明具体原因。

如需撤销安装配置，可在家长重新开启调试并授权后运行 `python3 scripts/native-manage.py stop --tv 电视IP:5555`，停用本 App 管控和恢复任务；这保留客户端及私有凭证。删除家庭会使设备失去云端管理，不能据此假定缓存规则已清除，需停用客户端后再交还电视。
