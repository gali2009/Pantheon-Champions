# 验证 GeckoLib 在运行时真的被 NeoForge 装载。
#
# 为什么单独做这一步：`gradlew build` 成功只证明编译期能解析依赖，
# 不证明游戏启动时 GeckoLib 作为一个 mod 被装载。这两件事的失败方式
# 完全不同，所以必须分开验证，不能拿 build 成功冒充加载成功。
#
# 做法：启动 runClient，轮询日志等 mod 列表出现，然后杀掉 java。
# 不依赖人工盯着窗口看。

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $root "run\logs\latest.log"

# 先清掉旧日志，否则可能读到上一次的残留结果。
if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }

# java 的 stderr 会被 PowerShell 包装成 NativeCommandError，
# 看起来像失败但实际不是。判断成败一律看退出码，不看红色输出。
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue

Write-Output "启动 runClient（最多等 6 分钟）..."
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runClient", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddMinutes(6)
$loadedOk = $false
$sawGecko = $false
$sawMod   = $false

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($t) {
            if ($t -match 'geckolib')      { $sawGecko = $true }
            if ($t -match 'Pantheon: Champions') { $sawMod = $true }
            # 两个都出现，说明 mod 列表已经打印完毕。
            if ($sawGecko -and $sawMod) { $loadedOk = $true; break }
        }
    }
    if ($proc.HasExited -and -not $loadedOk) { break }
}

# 收尾：关掉游戏。gradlew.bat 的子进程 java 不会被父进程带走，
# 所以要按进程名再杀一次，否则会留下一个占着 run 目录的 java。
Write-Output "关闭游戏进程..."
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
# 只收掉「本项目」的 DevLaunch 游戏进程。
# ⚠️ 这里**绝对不能**写成 `Get-Process java | Stop-Process -Force`：
#     那条命令会连带杀掉 (1) Gradle 守护进程，
#     (2) **用户自己正在跑的其他项目**的游戏客户端。
#     实测踩过：它把用户另一个项目的 runClient 给杀了。
#     改为按命令行过滤——DevLaunch 的命令行里一定带本项目的绝对路径
#     （-Dfml.modFolders=pantheon_champions%%<项目路径>\build\... ）。
Get-CimInstance Win32_Process -Filter "Name='java.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.CommandLine -and
        $_.CommandLine -match 'devlaunch' -and
        $_.CommandLine -match [regex]::Escape($root)
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 3

Write-Output ""
if (Test-Path $log) {
    Write-Output "=== 日志中的 mod 列表相关行 ==="
    Select-String -Path $log -Pattern 'geckolib|Pantheon: Champions' -ErrorAction SilentlyContinue |
        Select-Object -First 12 |
        ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
}

Write-Output ""
if ($loadedOk) {
    Write-Output "结果: 通过 —— GeckoLib 与本 mod 均已在运行时装载"
    exit 0
} else {
    Write-Output ("结果: 失败 —— geckolib 出现={0}  本mod出现={1}" -f $sawGecko, $sawMod)
    exit 1
}
