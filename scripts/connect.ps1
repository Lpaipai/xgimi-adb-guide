# 2026/10/22 19:10:00 by liaoweipeng1
# 仅连接与读取状态；不安装软件、不更改投影仪配置、不修改系统执行策略。
param(
    [string]$Address,
    [string]$AdbPath,
    [ValidateRange(1024, 65535)][int]$ServerPort = 5047
)
try {
    $ErrorActionPreference = 'Stop'
    $root = Split-Path $PSScriptRoot -Parent
    if (-not $Address) { $Address = Read-Host '输入投影仪 Wi-Fi 详情中的 IPv4 地址（不加端口）' }
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or
        $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
        $Address -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        throw '请输入完整的 IPv4 地址，例如 192.168.1.50。'
    }
    if (-not $AdbPath) { $AdbPath = Join-Path $root 'platform-tools\adb.exe' }
    if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
        throw '未找到 adb.exe。请从 Android 官网下载 Windows Platform Tools，解压到教程根目录的 platform-tools 文件夹。'
    }
    $AdbPath = (Resolve-Path -LiteralPath $AdbPath).Path
    function Invoke-GuideAdb {
        param([string[]]$AdbArguments)
        # 不调用 shell；所有参数均作为 adb 参数传入，并设置有界等待。
        $quoted = foreach ($item in $AdbArguments) {
            if ($item -match '["\r\n]') { throw '参数中包含不支持的字符。' }
            '"' + $item + '"'
        }
        $start = New-Object System.Diagnostics.ProcessStartInfo
        $start.FileName = $AdbPath
        $start.Arguments = $quoted -join ' '
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $start
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) {
            $process.Kill()
            $process.Dispose()
            throw 'ADB 等待超过 20 秒。核对设备开机、网络和 IP，再重新连接；无需重跑投影仪开启脚本。'
        }
        $result = [PSCustomObject]@{
            Code = $process.ExitCode
            Text = ($stdout.Result + $stderr.Result).Trim()
        }
        $process.Dispose()
        return $result
    }
    $runtime = Join-Path $root '.runtime'
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    $env:ANDROID_USER_HOME = $runtime
    $env:ANDROID_SDK_HOME = $runtime
    $env:ANDROID_ADB_LOG_PATH = Join-Path $runtime 'adb-server.log'
    $env:TEMP = $runtime
    $env:TMP = $runtime
    $key = Join-Path $runtime 'adbkey'
    if (-not (Test-Path -LiteralPath $key)) {
        # 已有服务可能使用别处密钥。避免误以为新密钥已被用于连接。
        $busy = Get-NetTCPConnection -State Listen -LocalPort $ServerPort -ErrorAction SilentlyContinue
        if ($busy) { throw "端口 $ServerPort 已占用且本目录无密钥，请改用其他 ServerPort，不要停止其他任务的 ADB。" }
        $generated = Invoke-GuideAdb -AdbArguments @('keygen', $key)
        if ($generated.Code -ne 0) { throw "生成本地 ADB 密钥失败：$($generated.Text)" }
    }
    $env:ANDROID_VENDOR_KEYS = $key
    $serial = "${Address}:5555"
    Write-Host "连接目标：$serial；电脑端服务端口：$ServerPort"
    $connected = Invoke-GuideAdb -AdbArguments @('-P', "$ServerPort", 'connect', $serial)
    Write-Host $connected.Text
    $state = (Invoke-GuideAdb -AdbArguments @('-P', "$ServerPort", '-s', $serial, 'get-state')).Text
    if ($state -ne 'device') {
        if ($state -match 'unauthorized') {
            throw '电脑尚未授权。查看教程“unauthorized”一节；本固件不一定弹出确认框。不要反复重启。'
        }
        throw "未连接成功：$state。检查设备 IP、同一局域网、网络隔离，以及投影仪端脚本输出。"
    }
    $identityResult = Invoke-GuideAdb -AdbArguments @('-P', "$ServerPort", '-s', $serial, 'shell', 'id')
    $identity = $identityResult.Text
    if ($identityResult.Code -ne 0 -or $identity -notmatch 'uid=2000\(shell\)') {
        throw "连接存在，但未得到预期 shell 身份：$identity"
    }
    $versionResult = Invoke-GuideAdb -AdbArguments @('-P', "$ServerPort", '-s', $serial, 'shell', 'getprop', 'ro.build.fingerprint')
    $fingerprint = $versionResult.Text
    if ($versionResult.Code -ne 0) { throw '无法读取设备版本。' }
    Write-Host '连接成功：已实际执行设备端命令。' -ForegroundColor Green
    Write-Host $identity
    Write-Host $fingerprint
    if ($fingerprint -ne 'Xgimi/ironman/ironman:8.0.0/OPR5.170623.014/v12.15.214:user/dev-keys') {
        Write-Warning '当前固件不属于本教程已验证版本；连接成功不代表开启脚本适用。'
    }
    Write-Host '密钥保存在本目录 .runtime 中，请勿上传或分享。此工具没有改变投影仪设置。'

} catch {
    Write-Host ("连接未完成：" + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
