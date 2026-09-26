# 用 `execute if data` 断言「修正器是否存在于**序列化后的** NBT 里」。
#
# 为什么用 `if data` 而不是 `data get`：
#   `data get` 的反馈只发给**命令执行者且仅当它是玩家**；在 function 里
#   由 server 执行时，输出**完全不进日志**（实测：三个区间标记都在、
#   中间的值一个都没有）。所以不能靠打印，要用 `execute if data ...`
#   做布尔判定 —— 它只产生 `if/unless` 结果，配合 say 即可记录。
#
# 为什么这个判定足以证明「能存盘」：
#   1. 1.21+ 的 `if data` 走 NBT 路径匹配，其解析依赖**实体的序列化形式**；
#      而 `data get`/谓词的底层是 `Entity.saveWithoutId(...)`，
#      与 ChunkSerializer 写区块时用的是同一个方法。
#   2. 已用字节码确认：
#        AttributeInstance.save() 只把 **permanentModifiers** 写进 "modifiers"
#        AttributeInstance.load() 只把 "modifiers" 读回 permanentModifiers
#      ⇒ 修正器若出现在序列化 NBT 里，就一定会被写进磁盘并在重载时读回；
#        若用的是 transient 版本，它**根本不会出现在 NBT 里**，本条判定会失败。
#
# 这就是对「重载后倍率是否保留」的等价、且可确定性验证的证明。
#
# 期望看到的结构（键名来自字节码，均为小写）：
#   Attributes: [{ Name: "minecraft:generic.max_health",
#                  Base: 20.0d,
#                  Modifiers: [{ id: "pantheon_champions:champion_health",
#                                amount: 2.5d,
#                                operation: "add_multiplied_base" }] }]

$ErrorActionPreference = "Continue"

$root = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $root 'DESIGN.md'))) { $root = $PSScriptRoot }

$utf8     = New-Object System.Text.UTF8Encoding($false)
$dpRoot   = Join-Path $root "run\world\datapacks"
$dpDir    = Join-Path $dpRoot "champion_nbt"
$fnDir    = Join-Path $dpDir "data\champion_nbt\function"
$mcTagDir = Join-Path $dpDir "data\minecraft\tags\function"
$log      = Join-Path $root "run\logs\latest.log"
$cfg      = Join-Path $root "run\config\pantheon_champions-common.toml"
$cfgBak   = Join-Path $root "build\champions-common.toml.bak"

Get-ChildItem $dpRoot -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
foreach ($d in @($fnDir, $mcTagDir)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
if (Test-Path $log) { Remove-Item $log -Force -ErrorAction SilentlyContinue }

Copy-Item $cfg $cfgBak -Force
$c = [System.IO.File]::ReadAllText($cfg, $utf8)
[System.IO.File]::WriteAllText($cfg, ($c -replace '(?m)^(\s*championChance\s*=\s*)[\d.]+', '${1}1.0'), $utf8)

[System.IO.File]::WriteAllText((Join-Path $dpDir "pack.mcmeta"), @'
{ "pack": { "pack_format": 48, "description": "champion modifier nbt test" } }
'@, $utf8)

[System.IO.File]::WriteAllText((Join-Path $fnDir "setup.mcfunction"), @'
scoreboard objectives add cn dummy
scoreboard players set #t cn 0
scoreboard players set #done cn 0
'@, $utf8)

[System.IO.File]::WriteAllText((Join-Path $fnDir "tick.mcfunction"), @'
scoreboard players add #t cn 1
execute if score #t cn matches 5 if score #done cn matches 0 run function champion_nbt:run
'@, $utf8)

# 全部断言都用 execute if/unless + say，不依赖 data get 的输出去日志。
$run = @'
scoreboard players set #done cn 1
summon minecraft:zombie 0 120 0 {Tags:["cn_zombie"],NoAI:1b,NoGravity:1b,PersistenceRequired:1b,Invulnerable:1b}

say CN_TYPE_CHECK
execute if entity @e[type=minecraft:zombie,tag=cn_zombie,nbt={NeoForgeData:{ChampionType:2}}] run say CN_TYPE_OK
execute unless entity @e[type=minecraft:zombie,tag=cn_zombie,nbt={NeoForgeData:{ChampionType:2}}] run say CN_TYPE_FAIL

# 1) 血量修正器是否已序列化。
#
# ⚠️ 这里**不能**用 `nbt={attributes:[{...}]}` 整表匹配：
#   已用字节码确认 AttributeInstance.save() 写出的键是**小写**
#   `id` / `base` / `modifiers`（属性表本身的键是小写 `attributes`，
#   见 LivingEntity.ATTRIBUTES_FIELD 的 ConstantValue），
#   而且 `NbtUtils.compareNbt` 对 ListTag **要求长度完全相等** ——
#   实体身上还有 movement_speed 等一堆属性，整表谓词永远匹配不上。
#   所以改用 **NBT 路径过滤器** `attributes[{id:...}].modifiers[{id:...}]`，
#   它按元素匹配、不要求列表等长。
say CN_HEALTH_MODIFIER_CHECK
execute if data entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.max_health"}].modifiers[{id:"pantheon_champions:champion_health"}] run say CN_HEALTH_MODIFIER_SERIALIZED
execute unless data entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.max_health"}].modifiers[{id:"pantheon_champions:champion_health"}] run say CN_HEALTH_MODIFIER_MISSING
# 数值也要对：2.5 = 3.5 - 1（ADD_MULTIPLIED_BASE 是 base ×(1+amount)）。×100 取整避免小数
execute store result score #hm cn run data get entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.max_health"}].modifiers[{id:"pantheon_champions:champion_health"}].amount 100
execute if score #hm cn matches 250..250 run say CN_HEALTH_AMOUNT_OK
execute unless score #hm cn matches 250..250 run say CN_HEALTH_AMOUNT_WRONG
# 操作类型必须是 add_multiplied_base，否则倍率口径就不是 ×3.5
execute if data entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.max_health"}].modifiers[{id:"pantheon_champions:champion_health"}].operation run say CN_HEALTH_OPERATION_PRESENT

# 2) 伤害修正器。0.5 = 1.5 - 1
say CN_DAMAGE_MODIFIER_CHECK
execute if data entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.attack_damage"}].modifiers[{id:"pantheon_champions:champion_damage"}] run say CN_DAMAGE_MODIFIER_SERIALIZED
execute unless data entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.attack_damage"}].modifiers[{id:"pantheon_champions:champion_damage"}] run say CN_DAMAGE_MODIFIER_MISSING
execute store result score #dm cn run data get entity @e[type=minecraft:zombie,tag=cn_zombie,limit=1] attributes[{id:"minecraft:generic.attack_damage"}].modifiers[{id:"pantheon_champions:champion_damage"}].amount 100
execute if score #dm cn matches 50..50 run say CN_DAMAGE_AMOUNT_OK
execute unless score #dm cn matches 50..50 run say CN_DAMAGE_AMOUNT_WRONG

# 3) 生效值：20 × 3.5 = 70
say CN_EFFECTIVE_CHECK
execute store result score #hp cn run attribute @e[type=minecraft:zombie,tag=cn_zombie,limit=1] minecraft:generic.max_health get 100
execute if score #hp cn matches 7000..7000 run say CN_HP_70
execute if score #hp cn matches ..6999 run say CN_HP_LOW
execute if score #hp cn matches 7001.. run say CN_HP_HIGH
execute store result score #dmg cn run attribute @e[type=minecraft:zombie,tag=cn_zombie,limit=1] minecraft:generic.attack_damage get 100
execute if score #dmg cn matches 450..450 run say CN_DMG_4P5
execute if score #dmg cn matches ..449 run say CN_DMG_LOW
execute if score #dmg cn matches 451.. run say CN_DMG_HIGH

# 4) 被动生物：不该有 ChampionType 键（用精确键匹配，不用 NeoForgeData:{}）
summon minecraft:cod 0 120 0 {Tags:["cn_cod"],NoAI:1b,NoGravity:1b,PersistenceRequired:1b}
say CN_PASSIVE_CHECK
execute if entity @e[type=minecraft:cod,tag=cn_cod,nbt={NeoForgeData:{ChampionType:0}}] run say CN_PASSIVE_BARRIER
execute if entity @e[type=minecraft:cod,tag=cn_cod,nbt={NeoForgeData:{ChampionType:1}}] run say CN_PASSIVE_OVERLOAD
execute if entity @e[type=minecraft:cod,tag=cn_cod,nbt={NeoForgeData:{ChampionType:2}}] run say CN_PASSIVE_UNSTOPPABLE
execute unless entity @e[type=minecraft:cod,tag=cn_cod,nbt={NeoForgeData:{ChampionType:0}}] unless entity @e[type=minecraft:cod,tag=cn_cod,nbt={NeoForgeData:{ChampionType:1}}] unless entity @e[type=minecraft:cod,tag=cn_cod,nbt={NeoForgeData:{ChampionType:2}}] run say CN_PASSIVE_CLEAN

say CN_DONE
'@
[System.IO.File]::WriteAllText((Join-Path $fnDir "run.mcfunction"), $run, $utf8)

[System.IO.File]::WriteAllText((Join-Path $mcTagDir "load.json"), @'
{ "values": [ "champion_nbt:setup" ] }
'@, $utf8)
[System.IO.File]::WriteAllText((Join-Path $mcTagDir "tick.json"), @'
{ "values": [ "champion_nbt:tick" ] }
'@, $utf8)

Write-Output "=== 启动服务端（序列化修正器断言）==="
Remove-Item Env:\JAVA_TOOL_OPTIONS -ErrorAction SilentlyContinue
$proc = Start-Process -FilePath (Join-Path $root "gradlew.bat") `
                      -ArgumentList "runServer", "--console=plain" `
                      -WorkingDirectory $root -PassThru -WindowStyle Hidden
$deadline = (Get-Date).AddMinutes(10)
$done = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 6
    if (Test-Path $log) {
        $t = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($t -and $t -match 'CN_DONE') { $done = $true; Start-Sleep -Seconds 4; break }
    }
    if ($proc.HasExited) { break }
}
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
Copy-Item $cfgBak $cfg -Force; Remove-Item $cfgBak -Force -ErrorAction SilentlyContinue
# 跑完就删掉测试数据包：留着它，下次跑别的测试时它的 tick 函数会同时执行，
# 世界里残留的计分板状态也会干扰判定（踩过）。
if (Test-Path $dpDir) { Remove-Item $dpDir -Recurse -Force -ErrorAction SilentlyContinue }

$text = Get-Content $log -Raw -ErrorAction SilentlyContinue
Write-Output ""
Write-Output "=== 全部标记 ==="
$marks = Select-String -Path $log -Pattern 'CN_[A-Z0-9_]+' -ErrorAction SilentlyContinue
if ($marks) {
    $marks | ForEach-Object {
        $m = [regex]::Match($_.Line, 'CN_[A-Z0-9_]+')
        if ($m.Success) { Write-Output ("  " + $m.Value) }
    }
} else { Write-Output "  （无）" }

$fail = New-Object System.Collections.ArrayList
if ($text -notmatch 'CN_DONE')                    { [void]$fail.Add("测试没跑完") }
if ($text -notmatch 'CN_TYPE_OK')                 { [void]$fail.Add("僵尸没有勇士类型") }
if ($text -match 'CN_TYPE_FAIL')                  { [void]$fail.Add("僵尸类型判定失败") }
# 核心：修正器必须出现在序列化 NBT 里
if ($text -notmatch 'CN_HEALTH_MODIFIER_SERIALIZED') { [void]$fail.Add("血量修正器不在序列化 NBT 里 —— 不会存盘（用了 transient 版本）") }
if ($text -match 'CN_HEALTH_MODIFIER_MISSING')       { [void]$fail.Add("血量修正器缺失") }
if ($text -notmatch 'CN_HEALTH_AMOUNT_OK')           { [void]$fail.Add("血量修正器数值不是 +250%（应为 3.5-1=2.5）") }
if ($text -match 'CN_HEALTH_AMOUNT_WRONG')           { [void]$fail.Add("血量修正器数值错误") }
if ($text -notmatch 'CN_HEALTH_OPERATION_PRESENT')   { [void]$fail.Add("血量修正器缺 operation 字段 —— 存盘后无法还原计算方式") }
if ($text -notmatch 'CN_DAMAGE_MODIFIER_SERIALIZED') { [void]$fail.Add("伤害修正器不在序列化 NBT 里 —— 不会存盘（用了 transient 版本）") }
if ($text -match 'CN_DAMAGE_MODIFIER_MISSING')       { [void]$fail.Add("伤害修正器缺失") }
if ($text -notmatch 'CN_DAMAGE_AMOUNT_OK')           { [void]$fail.Add("伤害修正器数值不是 +50%（应为 1.5-1=0.5）") }
if ($text -match 'CN_DAMAGE_AMOUNT_WRONG')           { [void]$fail.Add("伤害修正器数值错误") }
# 生效值
if ($text -notmatch 'CN_HP_70')  { [void]$fail.Add("血量不是 70（应为 20×3.5）") }
if ($text -notmatch 'CN_DMG_4P5'){ [void]$fail.Add("伤害不是 4.5（应为 3×1.5）") }
# 被动闸门
if ($text -notmatch 'CN_PASSIVE_CLEAN') { [void]$fail.Add("被动生物判定缺失") }
if ($text -match 'CN_PASSIVE_(BARRIER|OVERLOAD|UNSTOPPABLE)') { [void]$fail.Add("被动生物被分配了勇士类型") }

Write-Output ""
if ($fail.Count -eq 0) {
    Write-Output "结果: 通过 —— 血量/伤害修正器均已序列化进实体 NBT（可存盘），数值与被动闸门正确"
    exit 0
} else {
    Write-Output ("结果: 失败 —— " + $fail.Count + " 项:")
    foreach ($f in $fail) { Write-Output ("  - " + $f) }
    exit 1
}
