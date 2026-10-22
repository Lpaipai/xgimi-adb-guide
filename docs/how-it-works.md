# 为什么最后能连上：把实测与解释分开

## 已经观察到的事实

1. 最初的本地终端以普通应用 UID 运行，直接读写部分全局设置会遇到权限拒绝。
2. 本机原有 SELinux 为 Permissive，相关 `setprop` 请求被系统接受；脚本每次修改后都会读回核对。不能把 Permissive 单独当作“所有命令都有权限”。
3. 只启动原生 adbd 时，电脑曾停在 `unauthorized`。
4. 设置持久 ADB 配置并重启框架后，电脑实际执行了只读命令，得到 `uid=2000(shell)`。
5. 整理后的公开脚本又由普通应用终端执行，从 adbd 已停止的状态开启成功，电脑用新密钥完成连接。

## 本机厂商代码提供的解释

从设备导出的 `services.jar` 对应代码中，USB 管理部分存在如下关系：

- `UsbDeviceManager` 在初始化时依据 `persist.sys.usb.config` 是否含 `adb` 建立内部 ADB 状态。
- `UsbDebuggingManager.setAdbEnabled(true)` 控制授权 socket 监听。
- 本机有效公钥处理分支调用 `allowUsbDebugging(true, key)`，没有走普通 Android 的确认弹窗流程。

因此，“原生 adbd 已启动，但框架仍使用旧的关闭状态”能解释当时 `running` 与 `unauthorized` 并存的现象。补上持久配置，再重启框架，能够使这两部分一致。**我们没有抓取当时 system_server 的内部内存；根因解释来自代码和干预前后现象，不应写成直接观察到了所有内部状态。**

厂商包的反编译整体存在工具报错；本文只依据可读的特定分支，不声称完整源码恢复。仓库不分发厂商 JAR、ODEX、VDEX、APK 或反编译代码。

## 三个属性各做什么

| 属性 | 本次设置 | 作用 |
|---|---|---|
| `service.adb.tcp.port` | `5555` | 告诉 adbd 使用哪个网络端口；它本身不完成电脑授权 |
| `sys.usb.config` | `adb` | 本机 init 根据当前 USB 功能配置启动 adbd |
| `persist.sys.usb.config` | `adb` | 让框架初始化时读取到 ADB 启用状态 |

`ctl.restart zygote` 请求 init 重启 Android 运行框架。它会退出应用，不能把它当作无感操作，也不应在循环中执行。公开脚本使用一次性标记、读回检查、失败时尝试恢复属性；返回值不能代替电脑端连接验收。

## 为什么 RemoteDebug 没有解决问题

分析到的 `com.xgimi.remote` 路径是厂商服务器协调的 SSH 诊断流程。按钮名字里有“调试”，并不代表它启动本地 `adbd:5555`。所以服务器繁忙的问题和这次最终成功的局域网 ADB 流程，应分开理解。

## 权限与适用范围

没有刷机、安装 su、关闭 ADB 认证或注入他人的授权密钥。最终是 shell UID 2000，仍受 Android 权限限制。原厂的自动授权行为也意味着同一可达网络中的其他电脑可能获得连接，因此必须限制使用网络并在不用时关闭。

公开脚本的固件检查是精确匹配，不意味着相同硬件代号的所有产品都适用。恢复出厂的新机器、别的固件、持续断电后是否自动保持网络 ADB，都只能在相应测试后再声明。

## 原始资料

- [Android 官方 ADB 文档](https://developer.android.com/tools/adb)：客户端、服务端、设备守护进程和连接验收的通用说明；不能据其默认授权弹窗描述推定本机厂商实现。
- [Android 8 init 属性服务](https://github.com/aosp-mirror/platform_system_core/blob/android-8.0.0_r1/init/property_service.cpp)：`ctl.*` 控制消息背景。
- [Android 8 zygote 服务配置](https://github.com/aosp-mirror/platform_system_core/blob/android-8.0.0_r1/rootdir/init.zygote64_32.rc)：框架服务背景。
- 本机验证摘要：[evidence/validation.md](../evidence/validation.md)。AOSP 仅作背景，本机行为以实际记录为准。
