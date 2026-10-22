# 验证记录与边界

记录日期：2026-10-22（北京时间）。本文件只保留教程需要的结果，不包含个人设备地址、电脑密钥、MAC、序列号或完整系统导出。

## 1. 原始成功记录：2026-10-21

在完成属性修改和一次 Android 框架重启后，电脑实际执行只读查询，返回：

```text
uid=2000(shell) ... context=u:r:shell:s0
model: XGIMI TV
hardware: m7221
Android: 8.0.0
global adb_enabled: 1
init.svc.adbd: running
persist.sys.usb.config: adb
sys.usb.config: adb
```

这是设备端命令返回，不只是端口连通或脚本自报成功。

## 2. 整理后脚本的普通应用终端复现：2026-10-22

本次先使用 ADB 将测试文件送入设备，再通过 App Manager 的界面操作启动本地终端。**文件传输使用了既有连接，实际执行开启脚本的身份是普通应用，不是电脑的 shell。**

私有测试准备脚本在该终端中检查普通应用身份，并把端口设为 `-1`、两个 USB 配置设为 `none`，确认 adbd 为 `stopped` 后调用公开脚本的 `enable`。这只构造了“服务已关闭”的状态，没有恢复出厂，也没有清除既有授权数据库或证明框架内存与全新开机完全相同。

实测摘录：

```text
Identity: uid=10040(u0_a40) ... context=u:r:untrusted_app:s0:c512,c768
Before public script: stopped
ADB: daemon=stopped persist=none usb=none port=-1
Before: persist=none usb=none port=-1 pid=16094
Restarting Android framework ONCE.
After: system_server pid=29475
```

框架进程 PID 已变化。随后在电脑教程目录生成一套**新的 ADB 密钥**，以独立服务端口 5047 连接成功：

```text
连接成功：已实际执行设备端命令。
uid=2000(shell) ... context=u:r:shell:s0
Xgimi/ironman/ironman:8.0.0/OPR5.170623.014/v12.15.214:user/dev-keys
```

没有手动接受授权弹窗。新密钥和旧密钥没有公开到本仓库。

实测电脑工具版本：ADB 1.0.41 / Platform Tools 37.0.1-15733141，Windows。后续电脑连接工具增加了 20 秒超时与错误分类，具体复查结果见本文件更新。

最终 Windows 工具通过 PowerShell 语法解析，并实测了非法 IP 拒绝、连接被拒绝时的错误输出；增加 20 秒超时包装后的最终版本，也在下述重新开机后完成连接、设备端 `id` 和系统指纹查询，退出码为 0。

## 3. 模拟检查

`tests/test_script.py` 的 18 项隔离模拟通过，结果见 [script-tests.json](script-tests.json)：

- 默认只读检查；成功路径；USB framework 缺失；Enforcing；SDK 与固件不符。
- 重复执行标记；端口和持久属性拒绝；守护进程启动失败。
- 框架重启拒绝、忽略、PID 暂不可见。
- 关闭；恢复；备份缺失；无效备份数据；未知模式。

模拟检查确认：失败分支不会无条件继续重启，最多一次重启请求，可恢复分支读回原属性，不执行备份中的文本。**模拟通过不能替代实机通过。**

## 4. 关闭与恢复

`off`、`restore` 已做隔离模拟，尚未完成这次公开版本的实机闭环。`off` 仅在确认 adbd 停止后重置本工具的一次性标记；`restore` 只恢复三个属性，不声称恢复框架内存或撤销历史授权。

## 5. 整机重启测试

开启成功后发起一次整机重启，设备暂时没有回网。用户确认当时为关机／黑屏，随后用遥控器按电源键开机。电脑无需再次运行投影仪开启脚本，即可通过最终版 `connect.ps1` 重新连接，并实际执行设备端命令。

检查发现：

- 内核 boot_id 与测试前不同，uptime 约 3 分钟，确认经历了新的系统启动，而非仅框架重启。
- `init.svc.adbd=running`、`persist.sys.usb.config=adb`、`sys.usb.config=adb`。
- `service.adb.tcp.port=5555`、`persist.adb.tcp.port=5555`。
- 设备端身份为 `uid=2000(shell)`，前台为已安装的 Arc 桌面。

**本机重新开机后的复连已通过；没有测试拔电再上电。** 需要保留一个重要条件：本机已有 `persist.adb.tcp.port=5555`，公开开启脚本不修改这个第四属性。因此不能把本次结果外推为“只运行公开脚本，任何同固件设备都必然保持网络端口”，也未验证持久端口为空时的开机行为。

## 6. 未验证的场景

- 全新／恢复出厂后设备。
- 其他机型、其他固件、Enforcing 系统。
- 拔电后重新上电，以及持久端口为空时的自动保持行为。
- 网络隔离、跨网或公网连接。

不要把本教程扩展为通用提权、刷机或全品牌一键开启工具。

## 7. 文档与发布检查

- 图文 HTML 在 1440 px 与 390 px 宽度检查：图片均加载，页面无整体横向溢出；宽表格可局部横向滚动。
- 原创说明图与两张设备截图已人工查看。说明图明确标为示意，不伪装成命令执行截图。
- App Manager APK 本地 SHA-256 与上游 Release digest 一致；仅发布官方链接，不打包 APK。
- 发布文件未包含 `.runtime` 密钥目录、设备私有地址、序列号、MAC 或系统导出。
