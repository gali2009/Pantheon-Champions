# 在真实服务端里验证「生成时分配勇士类型 + 属性倍率」确实生效。
#
# 为什么必须进世界跑，而不能只静态检查：
#   1. EntityJoinLevelEvent 有没有被触发、我们的 handler 有没有被订阅 ——
#      静态检查只能证明代码存在，证明不了它被挂上总线。
#   2. 属性修正器有没有真的挂上去、数值对不对，只有在实体存在时读出来才算数。
#   3. 被动生物闸门是否真的挡住了鱼 —— 标签里确实有鱼，只有运行才知道拦没拦住。
#
# **确定性地测**：把 run/config 里的 championChance 临时改成 1.0，
#   这样每只符合条件的怪必然是勇士，不需要靠概率碰运气。
#   测试结束再还原配置。
#
# 做法：往世界 datapack 塞 function；服务端启动 → 进世界 → 执行 → 结果进日志。

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'DESIGN.md'))) { $root = $PSScriptRoot }

$utf8     = New-Object System.Text.UTF8Encoding($false)
$worldDir = Join-Path $root "run\world"
$dpDir    = Join-Path $worldDir "datapacks\champion_runtime_test"
$fnDir    = Join-Path $dpDir "data\champion_test\function"
$mcTagDir = Join-Path $dpDir "data\minecraft\tags\function"
$log      = Join-Path $root "run\logs\latest.log"
$cfg      = Join-Path $root "run\config\pantheon_champions-common.toml"
$cfgBak   = Join-Path $root "build\champions-common.toml.bak"

if (Test-Path $dpDir) { Remove-Item $dpDir -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $log)   { Remove-Item $log -Force -ErrorAction SilentlyContinue }
foreach ($d in @($fnDir, $mcTagDir)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }

Write-Output "=== 1. 临时把 championChance 改成 1.0（保证确定性）==="
$restoreCfg = $false
if (Test-Path $cfg) {
    New-Item -ItemType Directory -Path (Split-Path $cfgBak) -Force | Out-Null
    Copy-Item $cfg $cfgBak -Force
    $c = [System.IO.File]::ReadAllText($cfg, $utf8)
    $c2 = $c -replace '(?m)^(\s*championChance\s*=\s*)[\d.]+', '${1}1.0'
    [System.IO.File]::WriteAllText($cfg, $c2, $utf8)
    $restoreCfg = $true
    Select-String -Path $cfg -Pattern 'championChance' | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }
} else {
    Write-Output "  !! run/config 下没有配置文件，先跑一次服务端再测"
    exit 1
}

Write-Output "=== 2. 准备测试 datapack ==="
[System.IO.File]::WriteAllText((Join-Path $dpDir "pack.mcmeta"), @'
{
  "pack": {
    "pack_format": 48,
    "description": "champion runtime test"
  }
}
'@, $utf8)

# 只在第一次 tick 执行（用计分板当闸门），避免每 tick 重复召唤。
# ⚠️ 必须建**两个**目标：`champ_test` 当闸门，`cd` 用来接属性读数。
# 属性那段用的是 `execute store result score #zhp cd ...`，
# 而 `cd` 若不存在，`execute store` 会整条失败（日志里只留一句
# "Unknown scoreboard objective"，不会让 function 停下来），
# 表现就是所有 `CT_*_CHECK` 标记都在、但没有任何判定结果 —— 踩过。
[System.IO.File]::WriteAllText((Join-Path $fnDir "setup.mcfunction"), @'
scoreboard objectives add champ_test dummy
scoreboard objectives add cd dummy
scoreboard players set #done champ_test 0
'@, $utf8)

[System.IO.File]::WriteAllText((Join-Path $fnDir "tick.mcfunction"), @'
execute if score #done champ_test matches 0 run function champion_test:run
'@, $utf8)

# 测试本体。
$testFn = @'
scoreboard players set #done champ_test 1

# 抬高到空中，免得它们立刻打起来 / 掉进岩浆。
summon minecraft:zombie 0 120 0 {Tags:["ct_zombie"],NoAI:1b,PersistenceRequired:1b}
summon minecraft:cod 0 120 0 {Tags:["ct_cod"],NoAI:1b,PersistenceRequired:1b}
summon minecraft:giant 0 120 0 {Tags:["ct_giant"],NoAI:1b,PersistenceRequired:1b}
summon minecraft:skeleton 0 120 0 {Tags:["ct_skeleton"],NoAI:1b,PersistenceRequired:1b}

# --- 标记 1：僵尸 → 势不可挡（僵尸族）---
execute if entity @e[type=minecraft:zombie,tag=ct_zombie,nbt={NeoForgeData:{ChampionType:2}}] run say CT_ZOMBIE_UNSTOPPABLE_OK
execute unless entity @e[type=minecraft:zombie,tag=ct_zombie,nbt={NeoForgeData:{ChampionType:2}}] run say CT_ZOMBIE_FAIL
# 反向：僵尸不该是屏障或过载
execute if entity @e[type=minecraft:zombie,tag=ct_zombie,nbt={NeoForgeData:{ChampionType:0}}] run say CT_ZOMBIE_WRONG_BARRIER
execute if entity @e[type=minecraft:zombie,tag=ct_zombie,nbt={NeoForgeData:{ChampionType:1}}] run say CT_ZOMBIE_WRONG_OVERLOAD

# --- 标记 2：骷髅 → 屏障（骷髅族）---
execute if entity @e[type=minecraft:skeleton,tag=ct_skeleton,nbt={NeoForgeData:{ChampionType:0}}] run say CT_SKELETON_BARRIER_OK
execute unless entity @e[type=minecraft:skeleton,tag=ct_skeleton,nbt={NeoForgeData:{ChampionType:0}}] run say CT_SKELETON_FAIL

# --- 标记 3：被动生物（鳕鱼在 aquatic 标签里，但不是 Enemy）不该有类型 ---
# ⚠️ 判据必须是「有没有 ChampionType 这个键」，**绝不能**写 nbt={NeoForgeData:{}}。
# 那种写法匹配的是「NeoForgeData 存在且为空」，而 getPersistentData() 是
# **惰性创建**的——只要有任何路径碰过它，实体就带一个空标签。
# 第一版就是这么误报的：鳕鱼和巨人双双被判成「变成勇士」。
execute if entity @e[type=minecraft:cod,tag=ct_cod,nbt={NeoForgeData:{ChampionType:0}}] run say CT_PASSIVE_GOT_BARRIER
execute if entity @e[type=minecraft:cod,tag=ct_cod,nbt={NeoForgeData:{ChampionType:1}}] run say CT_PASSIVE_GOT_OVERLOAD
execute if entity @e[type=minecraft:cod,tag=ct_cod,nbt={NeoForgeData:{ChampionType:2}}] run say CT_PASSIVE_GOT_UNSTOPPABLE
execute unless entity @e[type=minecraft:cod,tag=ct_cod,nbt={NeoForgeData:{ChampionType:0}}] unless entity @e[type=minecraft:cod,tag=ct_cod,nbt={NeoForgeData:{ChampionType:1}}] unless entity @e[type=minecraft:cod,tag=ct_cod,nbt={NeoForgeData:{ChampionType:2}}] run say CT_PASSIVE_CLEAN

# --- 标记 4：巨人被排除 ---
execute if entity @e[type=minecraft:giant,tag=ct_giant,nbt={NeoForgeData:{ChampionType:0}}] run say CT_GIANT_GOT_BARRIER
execute if entity @e[type=minecraft:giant,tag=ct_giant,nbt={NeoForgeData:{ChampionType:1}}] run say CT_GIANT_GOT_OVERLOAD
execute if entity @e[type=minecraft:giant,tag=ct_giant,nbt={NeoForgeData:{ChampionType:2}}] run say CT_GIANT_GOT_UNSTOPPABLE
execute unless entity @e[type=minecraft:giant,tag=ct_giant,nbt={NeoForgeData:{ChampionType:0}}] unless entity @e[type=minecraft:giant,tag=ct_giant,nbt={NeoForgeData:{ChampionType:1}}] unless entity @e[type=minecraft:giant,tag=ct_giant,nbt={NeoForgeData:{ChampionType:2}}] run say CT_GIANT_CLEAN

# --- 标记 5：属性倍率 ---
# ⚠️ 第一版用 `execute as <生物> run attribute @s ... get`，结果日志里
# **一条属性输出都没有**。原因是 `attribute get` / `data get` 的反馈发给
# **命令执行者**，而执行者是生物（非玩家）时反馈被直接丢弃。
# 正确做法：用 `execute store result score` 把值接进计分板，
# 再用 say 播报——这样日志里必然看得到。
#
# `attribute get` 的第二个数字参数是 **scale**（乘数），
# 用它读出 ×100 的值就能保住两位小数（计分板只支持整数）。
# 僵尸基础血量 20 → 期望 70（×3.5）
execute store result score #zhp cd run attribute @e[type=minecraft:zombie,tag=ct_zombie,limit=1] minecraft:generic.max_health get 100
# 僵尸基础攻击 3 → 期望 4.5（×1.5）
execute store result score #zdmg cd run attribute @e[type=minecraft:zombie,tag=ct_zombie,limit=1] minecraft:generic.attack_damage get 100
# 骷髅基础血量 20 → 期望 70（×3.5），作为第二种生物的对照
execute store result score #shp cd run attribute @e[type=minecraft:skeleton,tag=ct_skeleton,limit=1] minecraft:generic.max_health get 100

say CT_HP_CHECK
execute if score #zhp cd matches 7000..7000 run say CT_HP_70_OK
execute if score #zhp cd matches ..6999 run say CT_HP_TOO_LOW
execute if score #zhp cd matches 7001.. run say CT_HP_TOO_HIGH

say CT_DMG_CHECK
execute if score #zdmg cd matches 450..450 run say CT_DMG_4P5_OK
execute if score #zdmg cd matches ..449 run say CT_DMG_TOO_LOW
execute if score #zdmg cd matches 451.. run say CT_DMG_TOO_HIGH

say CT_SKEL_HP_CHECK
execute if score #shp cd matches 7000..7000 run say CT_SKEL_HP_70_OK
execute if score #shp cd matches ..6999 run say CT_SKEL_HP_WRONG

# 原始属性 NBT：改成由 server 执行（不加 `as`），反馈才不会被丢弃。
# ⚠️ 注意键名是**小写** `attributes`（`LivingEntity.ATTRIBUTES_FIELD`）。
# 这条只作参考：由 server 执行时反馈仍然不进日志，所以别指望它有输出，
# 真正的判定在上面用 `execute if data` + `say` 完成。
say CT_RAW_ATTRS
data get entity @e[type=minecraft:zombie,tag=ct_zombie,limit=1] attributes

say CT_DONE
'@
[System.IO.File]::WriteAllText((Join-Path $fnDir "run.mcfunction"), $testFn, $utf8)

[System.IO.File]::WriteAllText((Join-Path $mcTagDir "load.json"), @'
{
  "values": [
    "champion_test:setup"
  ]
}
'@, $utf8)
[System.IO.File]::WriteAllText((Join-Path $mcTagDir "tick.json"), @'
{
  "values": [
    "champion_test:tick"
  ]
}
'@, $utf8)

Write-Output ("  datapack 就绪: " + $dpDir)
Write-Output ""
Write-Output "=== 3. 启动 runServer（最多等 10 分钟）==="

Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runServer", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddMinutes(10)
$done = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 10
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        # 等到测试跑完（CT_DONE 是最后一行标记）或超时
        if ($t -and $t -match 'CT_DONE') { $done = $true; Start-Sleep -Seconds 6; break }
    }
    if ($proc.HasExited) { break }
}

Write-Output "=== 4. 关闭服务端并还原配置 ==="
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
if ($restoreCfg -and (Test-Path $cfgBak)) {
    Copy-Item $cfgBak $cfg -Force
    Remove-Item $cfgBak -Force
    Write-Output "  配置已还原"
}
# 跑完就把测试数据包删掉：留着它的话，下次跑别的测试时它的 tick 函数
# 会**同时**执行，互相干扰（世界里残留的计分板状态也会影响判定）。踩过。
if (Test-Path $dpDir) { Remove-Item $dpDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output "  测试数据包已清理"

if (-not (Test-Path $log)) { Write-Output "结果: 失败 —— 无日志"; exit 1 }

Write-Output ""
Write-Output "=== 5. 服务端是否就绪 ==="
Select-String -Path $log -Pattern 'Done \([\d.]+s\)! For help' -ErrorAction SilentlyContinue |
    Select-Object -First 2 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
Write-Output "=== 6. 我们的标记 ==="
$marks = Select-String -Path $log -Pattern 'CT_[A-Z_]+' -ErrorAction SilentlyContinue
if ($marks) { $marks | Select-Object -First 25 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) } }
else { Write-Output "  （无 —— function 没跑起来）" }

Write-Output ""
Write-Output "=== 7. 属性读数 ==="
$attr = Select-String -Path $log -Pattern 'Attribute .* is .*|has the following entity data' -ErrorAction SilentlyContinue
if ($attr) { $attr | Select-Object -First 12 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) } }
else { Write-Output "  （无属性输出）" }

Write-Output ""
Write-Output "=== 8. 数据包加载 ==="
Select-String -Path $log -Pattern 'champion_runtime_test|champion_test' -ErrorAction SilentlyContinue |
    Select-Object -First 5 | ForEach-Object { Write-Output ("  " + $_.Line.Trim()) }

Write-Output ""
Write-Output "=== 9. 报错（应为空）==="
$bad = Select-String -Path $log -Pattern 'Failed to parse|Unknown function|Errors in|Unknown or incomplete command' -ErrorAction SilentlyContinue
if ($bad) { $bad | Select-Object -First 15 | ForEach-Object { Write-Output ("  !! " + $_.Line.Trim()) } }
else { Write-Output "  （无）" }

# ---- 断言 ----
$fail = New-Object System.Collections.ArrayList
$text = Get-Content $log -Raw -ErrorAction SilentlyContinue

if (-not $done) { [void]$fail.Add("服务端未跑出测试标记") }

# 测试自身的完整性：属性读数依赖 `cd` 计分板目标存在。
# 少了它，`execute store` 会静默失败，日志里只剩 CT_*_CHECK 而无数值判定 ——
# 那看起来像「模组没问题」，其实什么都没测到。所以单独抓这个报错。
if ($text -match 'Unknown scoreboard objective') { [void]$fail.Add("计分板目标缺失（cd）—— 属性读数整段静默失败，测试无效") }

# 类型分配
if ($text -notmatch 'CT_ZOMBIE_UNSTOPPABLE_OK') { [void]$fail.Add("僵尸没有被分配为「势不可挡」——概率分配或 EntityJoinLevelEvent 订阅未生效") }
if ($text -match 'CT_ZOMBIE_WRONG_BARRIER')    { [void]$fail.Add("僵尸被错分成「屏障」") }
if ($text -match 'CT_ZOMBIE_WRONG_OVERLOAD')   { [void]$fail.Add("僵尸被错分成「过载」") }
if ($text -notmatch 'CT_SKELETON_BARRIER_OK')  { [void]$fail.Add("骷髅没有被分配为「屏障」") }

# 被动生物闸门（鳕鱼在 aquatic 标签里，但不是 Enemy）
if ($text -notmatch 'CT_PASSIVE_CLEAN')          { [void]$fail.Add("无法确认被动生物被挡住") }
if ($text -match 'CT_PASSIVE_GOT_BARRIER')       { [void]$fail.Add("被动生物（鳕鱼）被分配为「屏障」—— Enemy 闸门失效") }
if ($text -match 'CT_PASSIVE_GOT_OVERLOAD')      { [void]$fail.Add("被动生物（鳕鱼）被分配为「过载」—— Enemy 闸门失效") }
if ($text -match 'CT_PASSIVE_GOT_UNSTOPPABLE')   { [void]$fail.Add("被动生物（鳕鱼）被分配为「势不可挡」—— Enemy 闸门失效") }

# 巨人排除
if ($text -notmatch 'CT_GIANT_CLEAN')            { [void]$fail.Add("无法确认巨人被排除") }
if ($text -match 'CT_GIANT_GOT_\w+')             { [void]$fail.Add("巨人被分配了勇士类型 —— 排除名单失效") }

# 血量：僵尸 20 → 70（×3.5）
if ($text -match 'CT_HP_70_OK')            { }
elseif ($text -match 'CT_HP_TOO_LOW')      { [void]$fail.Add("勇士血量低于 70 —— 生命倍率没生效") }
elseif ($text -match 'CT_HP_TOO_HIGH')     { [void]$fail.Add("勇士血量高于 70 —— 倍率被重复施加（可能不是幂等的）") }
else { [void]$fail.Add("没有拿到血量判定结果") }

# 伤害：僵尸 3 → 4.5（×1.5）
if ($text -match 'CT_DMG_4P5_OK')          { }
elseif ($text -match 'CT_DMG_TOO_LOW')     { [void]$fail.Add("勇士攻击伤害低于 4.5 —— 伤害倍率没生效") }
elseif ($text -match 'CT_DMG_TOO_HIGH')    { [void]$fail.Add("勇士攻击伤害高于 4.5 —— 倍率被重复施加") }
else { [void]$fail.Add("没有拿到伤害判定结果") }

# 骷髅对照：同为 20 基础血，也应为 70（证明不是只对僵尸生效）
if ($text -notmatch 'CT_SKEL_HP_70_OK')    { [void]$fail.Add("骷髅的血量不是 70 —— 倍率对第二种生物没生效") }

# 测试完整性：function 必须跑完
if ($text -notmatch 'CT_DONE')             { [void]$fail.Add("测试 function 没跑完（缺 CT_DONE）") }

Write-Output ""
if ($fail.Count -eq 0) {
    Write-Output "结果: 通过 —— 类型分配 / 被动闸门 / 血量×3.5 / 伤害×1.5 均已在真实服务端验证"
    exit 0
} else {
    Write-Output ("结果: 失败 —— " + $fail.Count + " 项:")
    foreach ($f in $fail) { Write-Output ("  - " + $f) }
    exit 1
}
