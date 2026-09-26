# 验证创造标签页在真实客户端里能构建出物品。
#
# 为什么必须实机验证：
#   displayItems 里的代码（查附魔注册表、enchanted book 组装）
#   **只在客户端打开创造模式物品栏时才执行**。服务端启动、gradlew build
#   都不会跑它。所以「编译通过」和「服务端无报错」都不能证明标签页能用——
#   附魔键写错、注册表查不到，都只会在客户端这一刻炸出来。
#
# 做法：启动 runClient，等资源重载完成，扫描日志里该标签页相关的报错。
# 注意：不打开创造物品栏的话 displayItems 可能不被调用，所以本脚本
# 至少能抓「注册标签页本身」的失败（重复注册、注册表键错等）。

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $root "run\logs\latest.log"

if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue

Write-Output "启动 runClient（最多等 7 分钟）..."
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runClient", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddMinutes(7)
$ready = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($t -and $t -match 'Reloading ResourceManager') {
            $ready = $true
            Start-Sleep -Seconds 20
            break
        }
    }
    if ($proc.HasExited) { break }
}

Write-Output "关闭游戏..."
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Output ""
if (-not (Test-Path $log)) { Write-Output "结果: 失败 —— 无日志"; exit 1 }

Write-Output "=== 标签页 / 注册相关报错（应为空）==="
$patterns = @(
    'itemGroup\.pantheon_champions',
    'CreativeModeTab',
    'Duplicate.*tab',
    'Unknown enchantment',
    'Errors in registry',
    'Failed to parse',
    'Unknown recipe|IllegalArgumentException'
)
$bad = $null
foreach ($p in $patterns) {
    $hits = Select-String -Path $log -Pattern $p -ErrorAction SilentlyContinue |
            Where-Object { $_.Line -match 'ERROR|WARN|Exception' }
    if ($hits) { $bad += $hits }
}
if ($bad) {
    $bad | Select-Object -First 20 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) }
} else { Write-Output "  （无）" }

Write-Output ""
Write-Output "=== 确认 mod 与资源重载 ==="
Select-String -Path $log -Pattern 'Pantheon: Champions|Reloading ResourceManager' -ErrorAction SilentlyContinue |
    Select-Object -First 4 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
if ($ready -and -not $bad) {
    Write-Output "结果: 通过 —— 客户端资源重载完成，标签页注册无报错"
    Write-Output "注意: displayItems 只在打开创造物品栏时执行，"
    Write-Output "      若需确认三本书真的出现，请在游戏里打开该标签页目视检查。"
    exit 0
} else {
    Write-Output ("结果: 失败 —— 重载={0}  报错数={1}" -f $ready, $(if($bad){$bad.Count}else{0}))
    exit 1
}
