# 在真实世界里验证三种附魔确实注册、且互斥生效。
#
# 为什么不能只看到「标题界面无报错」：
#   附魔注册表在数据包加载时构建，很多错误只在进入世界后才暴露。
#   更关键的是：**互斥**是否真的生效，只有让游戏实际执行一次
#   enchant 兼容性判定才算证明。静态检查 JSON 只能说明语法正确。
#
# 做法：
#   1. 用 quickPlay 直接进一个单人世界
#   2. 从日志确认世界已加载、数据包已同步
#   3. 扫描附魔相关报错
#
# 注意：命令执行需要在游戏内输入，本脚本无法代替玩家按键，
# 所以互斥的最终验证靠 verify-enchant-exclusive.ps1（分析日志中的命令结果）
# 或由人在游戏里执行 /enchant。本脚本负责前两步的自动化。

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $root "run\logs\latest.log"

if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue

Write-Output "启动 runClient，直接进入世界（最多等 8 分钟）..."
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runClient", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddMinutes(8)
$inWorld = $false

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        # 世界加载完成的标志
        if ($t -and $t -match 'Preparing spawn area|Time elapsed|Loaded \d+ advancements') {
            $inWorld = $true
            Start-Sleep -Seconds 20
            break
        }
    }
    if ($proc.HasExited) { break }
}

Write-Output "关闭游戏..."
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
if (-not (Test-Path $log)) { Write-Output "结果: 失败 —— 无日志"; exit 1 }

Write-Output "=== 是否进入世界 ==="
Select-String -Path $log -Pattern 'Preparing spawn area|Time elapsed|Loaded \d+ advancements|Starting integrated minecraft server' -ErrorAction SilentlyContinue |
    Select-Object -First 5 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
Write-Output "=== 附魔/数据包/注册表报错（应为空）==="
$bad = Select-String -Path $log -Pattern `
    'Couldn''t parse|Failed to parse|Failed to load|Error while loading|Unknown enchantment|Unknown component|Unknown condition|not a valid|Failed to deserialize|Invalid enchantment|Non \[a-z0-9|Missing enchantment' `
    -ErrorAction SilentlyContinue
if ($bad) {
    $bad | Select-Object -First 25 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) }
} else { Write-Output "  （无）" }

Write-Output ""
if ($inWorld -and -not $bad) {
    Write-Output "结果: 通过 —— 已进入世界，注册表与数据包无报错"
    exit 0
} else {
    Write-Output ("结果: 失败 —— 进入世界={0}  报错数={1}" -f $inWorld, $(if($bad){$bad.Count}else{0}))
    exit 1
}
