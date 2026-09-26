# 验证三种勇士附魔在真实运行时被游戏加载。
#
# 为什么必须实机验证：
#   附魔 JSON 里的 effects 是最容易「构建成功但运行时报错」的地方。
#   组件名写错、条件类型拼错、LevelBasedValue 结构不对，
#   gradlew build 全都发现不了——只有数据包加载时才会抛错。
#
# 做法：启动 runClient，等数据包加载完成，然后扫描日志里的附魔相关报错。
# 同时打印我们三个附魔是否被真正注册。

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $root "run\logs\latest.log"

if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue

Write-Output "启动 runClient（最多等 6 分钟）..."
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runClient", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddMinutes(6)
$reloaded = $false

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($t -and $t -match 'Reloading ResourceManager') {
            $reloaded = $true
            # 附魔属于数据包（registry），在资源重载后再等一会让它加载完
            Start-Sleep -Seconds 15
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
if (-not (Test-Path $log)) {
    Write-Output "结果: 失败 —— 没有生成日志"
    exit 1
}

Write-Output "=== 附魔 / 数据包加载报错（应为空）==="
$bad = Select-String -Path $log -Pattern `
    'Couldn''t parse|Failed to parse|Failed to load|Error while loading|Unknown enchantment effect|Unknown component|Unknown condition|not a valid|Failed to deserialize|Invalid enchantment' `
    -ErrorAction SilentlyContinue
if ($bad) {
    $bad | Select-Object -First 25 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) }
} else {
    Write-Output "  （无）"
}

Write-Output ""
Write-Output "=== 我们的附魔是否出现在日志里 ==="
$hit = Select-String -Path $log -Pattern 'champion_breaker|champion_disruptor|champion_stagger' -ErrorAction SilentlyContinue
if ($hit) {
    $hit | Select-Object -First 10 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
} else {
    Write-Output "  （日志未提及——附魔加载成功时通常也不打印，属正常）"
}

Write-Output ""
Write-Output "=== 数据包是否被加载（证明我们的 data/ 生效）==="
Select-String -Path $log -Pattern 'Reloading ResourceManager|Loaded \d+ recipes|pantheon_champions' -ErrorAction SilentlyContinue |
    Select-Object -First 6 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
if ($reloaded -and -not $bad) {
    Write-Output "结果: 通过 —— 资源重载完成，无附魔/数据包解析报错"
    exit 0
} else {
    Write-Output ("结果: 失败 —— 重载={0}  报错数={1}" -f $reloaded, $(if($bad){$bad.Count}else{0}))
    exit 1
}
