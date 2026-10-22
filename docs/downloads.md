# 下载与校验

本仓库只发布原创脚本、文字和必要配图，不重新打包第三方 APK 或厂商系统文件。

| 工具 | 版本 / 下载 | 用途 |
|---|---|---|
| App Manager | [4.1.1 发布页](https://github.com/MuntashirAkon/AppManager/releases/tag/v4.1.1)；[单 APK](https://github.com/MuntashirAkon/AppManager/releases/download/v4.1.1/AppManager_v4.1.1.apk) | 投影仪本地终端与文件管理 |
| Android SDK Platform Tools | [Android 官方下载页](https://developer.android.com/tools/releases/platform-tools) | 电脑端 ADB；Windows 用户选 Windows 版 |
| 本教程工具包 | [GitHub Releases](https://github.com/Lpaipai/xgimi-adb-guide/releases) | 脚本、电脑连接工具、图文说明 |

App Manager 单 APK 的 SHA-256（2026-10-22 对照上游 Release digest 与本地文件一致）：

```text
2540d6d9352acd8b04d6210140630a380abb1bc46ad4745c89ad97603dee3c40
```

PowerShell 检查示例：

```powershell
Get-FileHash .\AppManager_v4.1.1.apk -Algorithm SHA256
```

如果为投影仪识别改名为 `.apk1`，哈希应保持相同。`.apks` 则是另一种打包格式，不能靠改名当作单 APK 使用。

Platform Tools 的最新版可能变化，因此不把某个过期下载包冒充当前版本。请使用官网；本次实测的具体 ADB 版本记录在验证记录中。

安装脚本不需要 Activity Launcher、Termux 或额外“ADB 开关 APK”。Activity Launcher 曾用于探索隐藏入口，不是最终连接流程的必要依赖。
