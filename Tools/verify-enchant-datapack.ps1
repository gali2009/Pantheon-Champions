# 在专用服务器中验证附魔数据包确实被解析。
#
# 为什么必须用服务端，而不能只看客户端标题界面：
#   附魔在 1.21 是**数据包注册表**（datapack registry），
#   它在**服务器启动**时构建。客户端停在标题界面时只加载了资源包
#   （ResourceManager），数据包注册表还没构建——所以那时「无报错」
#   并不能证明附魔 JSON 是对的。JSON schema 写错只会在服务端启动时暴露。
#
# 做法：启动 runServer（--nogui，无界面），等它打印 "Done"，
# 然后扫描日志里的注册表解析报错，最后杀掉进程。

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
$log  = Join-Path $root "run\logs\latest.log"

if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue

# 服务端首次启动要生成世界，可能较慢。
Write-Output "启动 runServer（最多等 10 分钟）..."
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runServer", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddMinutes(10)
$done = $false

while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        # 服务端就绪标志
        if ($t -and $t -match 'Done \([\d.]+s\)! For help') {
            $done = $true
            Start-Sleep -Seconds 5
            break
        }
    }
    if ($proc.HasExited -and -not $done) { break }
}

Write-Output "关闭服务端..."
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

Write-Output "=== 服务端是否就绪 ==="
Select-String -Path $log -Pattern 'Done \([\d.]+s\)! For help|Starting minecraft server version' -ErrorAction SilentlyContinue |
    Select-Object -First 4 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
Write-Output "=== 数据包/注册表解析报错（应为空）==="
# 这些模式是**照着实际报错文案**写的，不是猜的。
# 用一个故意写坏的附魔（minecraft:damage_TYPO）跑出来的真实报错长这样：
#   > Errors in registry minecraft:enchantment:
#   >> Errors in element pantheon_champions:champion_breaker:
#   java.lang.IllegalStateException: Failed to parse
#       pantheon_champions:enchantment/champion_breaker.json from pack mod/pantheon_champions
#   Caused by: ... Not a valid resource location: minecraft:damage_TYPO ...
# 注意关键是 "Failed to parse ... from pack"，我第一版写的
# 'Failed to parse enchantment' 匹配不到它（中间夹着路径）。
#
# 同时刻意**不用**宽泛的 'Failed to load'：首次启动时
#   "Failed to load properties from file: server.properties"
# 是正常现象（配置文件尚未生成），会误报成失败（实际踩过一次）。
$patterns = @(
    'Errors in registry',
    'Errors in element',
    'from pack mod/pantheon_champions',
    'Failed to load registries',
    'Couldn''t parse enchantment',
    'Unknown enchantment',
    'Unknown enchantment effect',
    'Failed to deserialize enchantment',
    'Missing enchantment',
    'Failed to parse pantheon_champions',
    'Not a valid resource location',
    'missed input:'
)
$bad = $null
foreach ($p in $patterns) {
    $hits = Select-String -Path $log -Pattern $p -ErrorAction SilentlyContinue
    if ($hits) { $bad += $hits }
}
if ($bad) {
    $bad | Select-Object -First 30 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) }
} else { Write-Output "  （无）" }

Write-Output ""
Write-Output "=== 附注：良性信息（不作为失败判据）==="
$benign = Select-String -Path $log -Pattern 'Failed to load properties from file' -ErrorAction SilentlyContinue
if ($benign) {
    Write-Output "  server.properties 首次生成，属正常："
    $benign | Select-Object -First 2 | ForEach-Object { Write-Output ("    " + $_.Line.Trim()) }
} else { Write-Output "  （无）" }

Write-Output ""
Write-Output "=== 我们的数据包是否被加载 ==="
Select-String -Path $log -Pattern 'pantheon_champions' -ErrorAction SilentlyContinue |
    Select-Object -First 8 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
if ($done -and -not $bad) {
    Write-Output "结果: 通过 —— 服务端启动完成，附魔数据包解析无报错"
    exit 0
} else {
    Write-Output ("结果: 失败 —— 服务端就绪={0}  报错数={1}" -f $done, $(if($bad){$bad.Count}else{0}))
    exit 1
}
