# 验证声音资源在真实运行时被游戏加载。
#
# 为什么必须单独做：`gradlew build` 只会把 assets 打进 jar，不证明游戏
# 解析得了 sounds.json、也不证明注册的 SoundEvent 与资源对得上。
# 资源命名错一位（少了 assets/<ns>/ 前缀、事件名拼错）时，build 一样成功，
# 只有游戏日志里才会出现 "Unable to play unknown soundEvent" 之类的报错。
#
# 做法：启动 runClient，等资源管理器重载完成，然后扫描日志里的声音相关报错。

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
            # 资源重载后再等一会，让资源管理器把 sounds.json 解析完。
            Start-Sleep -Seconds 12
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

$t = Get-Content $log -Raw

Write-Output "=== 资源重载 ==="
Select-String -Path $log -Pattern 'Reloading ResourceManager' |
    Select-Object -First 2 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
Write-Output "=== 声音相关报错（应为空）==="
$bad = Select-String -Path $log -Pattern 'Unable to play unknown soundEvent|File .*stun.* does not exist|Failed to load sound|Could not parse sounds\.json|Non [a-z0-9_.-]* character' -ErrorAction SilentlyContinue
if ($bad) {
    $bad | Select-Object -First 15 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) }
} else {
    Write-Output "  （无）"
}

Write-Output ""
Write-Output "=== 我们的声音文件是否出现在日志中 ==="
$hit = Select-String -Path $log -Pattern 'stun1|stun2' -ErrorAction SilentlyContinue
if ($hit) {
    $hit | Select-Object -First 10 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
} else {
    Write-Output "  （日志未提及 stun1/stun2 —— 正常，除非触发播放）"
}

Write-Output ""
if ($reloaded -and -not $bad) {
    Write-Output "结果: 通过 —— 资源重载完成，无声音加载报错"
    exit 0
} else {
    Write-Output ("结果: 失败 —— 重载={0}  报错数={1}" -f $reloaded, $(if($bad){$bad.Count}else{0}))
    exit 1
}
