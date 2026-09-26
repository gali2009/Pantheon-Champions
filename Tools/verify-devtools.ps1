# 验证 JEI 与 Jade 在开发环境中真的被 NeoForge 装载。
#
# 为什么必须单独验证：
#   `gradlew dependencies` 解析成功只证明**能下到 jar**，
#   不证明游戏启动时它们作为 mod 被装载。两者失败方式完全不同：
#   仓库/坐标错 -> 解析期失败；mods.toml 不兼容、依赖缺失
#   -> 启动期失败。所以这里启动 runClient 实测。
#
# 做法：启动 runClient，等 mod 列表打印，扫描日志里的装载情况与报错。

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
        # 资源重载出现说明 mod 列表与注册都已就绪
        if ($t -and $t -match 'Reloading ResourceManager') { $ready = $true; Start-Sleep -Seconds 15; break }
    }
    if ($proc.HasExited) { break }
}

Write-Output "关闭游戏..."
if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

Write-Output ""
if (-not (Test-Path $log)) { Write-Output "结果: 失败 —— 无日志"; exit 1 }

Write-Output "=== JEI 装载情况 ==="
$jei = Select-String -Path $log -Pattern 'Just Enough Items|modId="jei"|\bjei\b' -ErrorAction SilentlyContinue
if ($jei) {
    $jei | Select-Object -First 6 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
} else { Write-Output "  （日志未提及 JEI）" }

Write-Output ""
Write-Output "=== Jade 装载情况 ==="
$jade = Select-String -Path $log -Pattern 'Jade|modId="jade"' -ErrorAction SilentlyContinue
if ($jade) {
    $jade | Select-Object -First 6 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
} else { Write-Output "  （日志未提及 Jade）" }

Write-Output ""
Write-Output "=== 资源重载列表（应包含 jei / jade）==="
Select-String -Path $log -Pattern 'Reloading ResourceManager' -ErrorAction SilentlyContinue |
    Select-Object -First 2 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
Write-Output "=== 装载报错（应为空）==="
$bad = Select-String -Path $log -Pattern `
    'Missing or unsupported mandatory dependencies|Incompatible mods found|Mod file.*is missing|Failed to create mod file|ModResolutionException'
if ($bad) {
    $bad | Select-Object -First 15 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) }
} else { Write-Output "  （无）" }

Write-Output ""
# 判定：资源重载完成 + 无装载报错 + 日志确实提到两者
$sawJei  = ($jei  -ne $null)
$sawJade = ($jade -ne $null)
if ($ready -and -not $bad -and $sawJei -and $sawJade) {
    Write-Output "结果: 通过 —— JEI 与 Jade 均已在开发环境中装载"
    exit 0
} else {
    Write-Output ("结果: 失败 —— 重载={0}  JEI={1}  Jade={2}  报错数={3}" -f `
        $ready, $sawJei, $sawJade, $(if($bad){$bad.Count}else{0}))
    exit 1
}
